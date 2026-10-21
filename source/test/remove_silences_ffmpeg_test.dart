import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/domain/models/media_item.dart';
import 'package:tgi_video_editor/domain/models/track.dart';
import 'package:tgi_video_editor/features/editor/application/editor_controller.dart';
import 'package:tgi_video_editor/mcp/editor_mcp_server.dart';
import 'package:tgi_video_editor/mcp/editor_plans.dart';
import 'package:tgi_video_editor/mcp/editor_read_service.dart';
import 'package:tgi_video_editor/mcp/mcp_path_policy.dart';
import 'package:tgi_video_editor/mcp/mcp_tool_router.dart';
import 'package:tgi_video_editor/services/media_import_service.dart';
import 'package:tgi_video_editor/services/project_io_service.dart';
import 'support/mcp_test_client.dart';
import 'support/render_fixture.dart';
import 'support/silence_project.dart';

void main() {
  test(
    'native silence analysis -> MCP preview/apply -> FFmpeg duration -> exact undo',
    () async {
      HttpOverrides.global = null;
      final fixture = RenderFixture();
      await fixture.open();
      addTearDown(fixture.close);
      final source = '${fixture.directory.path}/speech.mp4';
      await fixture.run([
        '-y',
        '-v',
        'error',
        '-f',
        'lavfi',
        '-i',
        'color=blue:s=160x90:r=20:d=6',
        '-f',
        'lavfi',
        '-i',
        r'aevalsrc=if(between(t\,1\,2)+between(t\,4\,6)\,0.3*sin(2*PI*440*t)\,0):s=48000:d=6',
        '-c:v',
        'libx264',
        '-pix_fmt',
        'yuv420p',
        '-c:a',
        'aac',
        '-shortest',
        source,
      ]);
      final base = silenceProject(duration: 6);
      final media = MediaItem(
        id: 'speech',
        name: 'speech.mp4',
        filePath: source,
        importedAt: DateTime.utc(2026),
        type: MediaType.video,
        duration: silenceTime(6),
        width: 160,
        height: 90,
        hasAudio: true,
      );
      final project = base.copyWith(
        mediaPool: [media],
        tracks: [
          Track(
            id: 'captions',
            name: 'Captions',
            clips: [
              silenceCaption('spoken', 1.1, .6),
              silenceCaption('crossing', 1.8, 2.4),
              silenceCaption('end', 4.3, 1.5),
            ],
          ),
          ...base.tracks,
        ],
      );
      final c = EditorController(
        mediaImportService: MediaImportService(ffmpegService: fixture.service),
        initialProject: project,
      );
      c.synchronizeCommandExportSettings(RenderFixture.settings);
      final baseRevision = c.projectRevision;
      final policy = McpPathPolicy(
        projectDirectory: fixture.directory.path,
        exportDirectory: fixture.directory.path,
      );
      await policy.trustProject(project);
      final reads = EditorReadService(
        c,
        ffmpeg: fixture.service,
        checkMedia: policy.authorizeMedia,
      );
      final plans = EditorPlans(c, reads)..requireApproval = false;
      final server = EditorMcpServer(
        McpToolRouter(
          reads,
          plans,
          resolveExport: policy.resolveExport,
          authorizeExport: (p, path) async {
            await policy.authorizeProject(p);
            await policy.authorizeExport(path);
          },
        ),
        token: randomMcpToken(),
        port: 0,
      );
      await server.start();
      final client = McpTestClient(server.boundPort, server.token);
      addTearDown(() async {
        client.close();
        await server.stop();
        await reads.dispose();
        c.dispose();
      });
      await client.initialize();
      String snapshot() => jsonEncode(
        ProjectIOService().serializeProject(
          c.project,
          exportSettings: c.commandExportSettings,
        ),
      );
      final before = snapshot();
      Future<Map<String, dynamic>> finish(String id) async {
        final deadline = DateTime.now().add(const Duration(seconds: 60));
        while (!reads.jobs.get(id).finished &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        final result = await client.call('get_job', {'job_id': id});
        final job = result['structuredContent'] as Map<String, dynamic>;
        expect(job['status'], 'completed', reason: job.toString());
        return job;
      }

      final start = await client.call('preview_plan', {
        'macro': 'remove_silences',
        'arguments': {
          'clip_id': 'video',
          'threshold_db': -35,
          'minimum': .5,
          'padding': 0,
        },
        'base_revision': baseRevision,
      });
      expect(start['isError'], false, reason: start.toString());
      expect(start['structuredContent']['analysis_pending'], true);
      final jobId = start['structuredContent']['job_id'] as String;
      final analysis = await finish(jobId);
      expect(analysis['result']['intervals'], hasLength(2));
      final preview = await client.call('preview_plan', {
        'macro': 'remove_silences',
        'arguments': {
          'clip_id': 'video',
          'job_id': jobId,
          'threshold_db': -35,
          'minimum': .5,
          'padding': 0,
        },
        'base_revision': baseRevision,
      });
      expect(preview['isError'], false, reason: preview.toString());
      expect(snapshot(), before);
      final plan = preview['structuredContent'] as Map;
      expect(
        (await client.call('apply_plan', {
          'plan_id': plan['plan_id'],
          'base_revision': baseRevision,
        }))['isError'],
        false,
      );
      final expected = c.project.timelineDuration.inMicroseconds / 1e6;
      expect(expected, closeTo(3, 1 / 20));
      expect(
        expected,
        closeTo(6 - (plan['time_map']['removed_duration'] as num), 1e-6),
      );
      final exported = await client.call('export', {
        'filename': 'remapped.mp4',
        'base_revision': baseRevision + 1,
      });
      expect(exported['isError'], false, reason: exported.toString());
      await finish(exported['structuredContent']['job_id'] as String);
      final toolchain = await fixture.service.resolveToolchain();
      final probe = await Process.run(toolchain.ffprobePath, [
        '-v',
        'error',
        '-show_entries',
        'format=duration:stream=codec_type,duration',
        '-of',
        'json',
        '${fixture.directory.path}/remapped.mp4',
      ]);
      expect(probe.exitCode, 0, reason: probe.stderr.toString());
      final details = jsonDecode(probe.stdout as String) as Map;
      final actual = double.parse(details['format']['duration'] as String);
      final streams = details['streams'] as List;
      final video = double.parse(
        streams.firstWhere((s) => s['codec_type'] == 'video')['duration']
            as String,
      );
      expect(video, closeTo(expected, 1 / 20 + 1e-6));
      expect(actual, closeTo(expected, 1 / 20 + 1e-6));
      expect(
        (await client.call('undo', {
          'base_revision': baseRevision + 1,
        }))['isError'],
        false,
      );
      expect(snapshot(), before);
      final report = {
        'fixture':
            'generated 6-second A/V source with known silence intervals; no speech transcription',
        'transport': 'Streamable HTTP MCP',
        'detected_intervals': analysis['result']['intervals'],
        'original_duration': 6.0,
        'removed_duration': plan['time_map']['removed_duration'],
        'expected_duration': expected,
        'ffprobe_video_duration': video,
        'ffprobe_container_duration': actual,
        'frames_per_second': 20,
        'tolerance_seconds': 1 / 20,
        'preview_dry_run': true,
        'apply_single_transaction': true,
        'undo_exact': snapshot() == before,
        'format_version': 14,
      };
      final reportPath = Platform.environment['MCP_SILENCE_NATIVE_REPORT'];
      if (reportPath != null) {
        await File(reportPath).writeAsString(
          '${const JsonEncoder.withIndent('  ').convert(report)}\n',
        );
      }
    },
    skip: !const bool.fromEnvironment('TGI_RUN_FFMPEG_INTEGRATION_TESTS'),
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
