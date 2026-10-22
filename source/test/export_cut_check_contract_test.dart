import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/domain/models/project.dart';
import 'package:tgi_video_editor/features/editor/application/editor_controller.dart';
import 'package:tgi_video_editor/mcp/editor_mcp_server.dart';
import 'package:tgi_video_editor/mcp/editor_plans.dart';
import 'package:tgi_video_editor/mcp/editor_read_service.dart';
import 'package:tgi_video_editor/mcp/mcp_path_policy.dart';
import 'package:tgi_video_editor/mcp/mcp_tool_router.dart';
import 'package:tgi_video_editor/services/ffmpeg_service.dart';
import 'package:tgi_video_editor/services/media_import_service.dart';
import 'package:tgi_video_editor/services/project_io_service.dart';
import 'support/mcp_test_client.dart';
import 'support/render_fixture.dart';
import 'support/silence_project.dart';

class _RecordingExport extends FfmpegService {
  @override
  Future<void> exportProject(
    TgiProject project,
    String outputPath, {
    FfmpegExportSettings settings = FfmpegExportSettings.defaultSettings,
    FfmpegExportProgressCallback? onProgress,
  }) async {
    await File(outputPath).writeAsBytes([1, 2, 3]);
  }
}

void main() {
  for (final native in [false, true]) {
    test(
      'MCP export_cut_check native=$native: discovery, safe preview render, apply/undo and stale rejection',
      () async {
        HttpOverrides.global = null;
        final f = RenderFixture();
        await f.open();
        addTearDown(f.close);
        final base = silenceProject(duration: 6);
        final media = native
            ? await f.color('blue', seconds: 6, audio: '437')
            : base.mediaPool.single.copyWith(
                filePath: '${f.directory.path}/source.mp4',
              );
        if (!native) {
          await File(media.filePath).writeAsBytes([0]);
        }
        final p = base.copyWith(mediaPool: [media.copyWith(id: 'speech')]);
        final service = native ? f.service : _RecordingExport();
        final c = EditorController(
          mediaImportService: MediaImportService(ffmpegService: service),
          initialProject: p,
        );
        c.synchronizeCommandExportSettings(RenderFixture.settings);
        final policy = McpPathPolicy(
          projectDirectory: f.directory.path,
          exportDirectory: f.directory.path,
        );
        await policy.trustProject(p);
        final reads = EditorReadService(
          c,
          ffmpeg: service,
          checkMedia: policy.authorizeMedia,
        );
        final plans = EditorPlans(c, reads);
        final server = EditorMcpServer(
          McpToolRouter(
            reads,
            plans,
            resolveExport: policy.resolveExport,
            authorizeExport: (project, path) async {
              await policy.authorizeProject(project);
              await policy.authorizeExport(path);
            },
          ),
          token: randomMcpToken(),
          port: 0,
        );
        await server.start();
        final client = McpTestClient(server.boundPort, server.token);
        await client.initialize();
        addTearDown(() async {
          client.close();
          await server.stop();
          await reads.dispose();
          c.dispose();
        });
        String snapshot() => jsonEncode(
          ProjectIOService().serializeProject(
            c.project,
            exportSettings: c.commandExportSettings,
          ),
        );
        final original = snapshot(), revision = c.projectRevision;
        final tools =
            (await client.request('tools/list', {})).$2['result']['tools']
                as List;
        expect(tools, hasLength(34));
        final definition =
            tools.singleWhere((t) => t['name'] == 'export_cut_check') as Map;
        expect(definition['annotations']['readOnlyHint'], true);
        expect(definition['annotations']['idempotentHint'], false);
        expect(
          tools.indexOf(definition),
          greaterThan(tools.indexWhere((t) => t['name'] == 'cancel_job')),
        );
        expect(
          tools.indexOf(definition),
          lessThan(tools.indexWhere((t) => t['name'] == 'export')),
        );
        final analysis = reads.jobs.start(
          'detect_silence',
          revision,
          p.id,
          (_) async => {
            'media_id': 'speech',
            'threshold_db': -35,
            'minimum': .5,
            'intervals': [
              {'start': .8, 'end': 1.2},
              {'start': 3.0, 'end': 4.0},
            ],
          },
        );
        while (!analysis.finished) {
          await Future<void>.delayed(Duration.zero);
        }
        final preview = await client.call('preview_plan', {
          'macro': 'remove_silences',
          'arguments': {
            'clip_id': 'video',
            'job_id': analysis.id,
            'padding': 0,
          },
          'base_revision': revision,
        });
        expect(preview['isError'], false, reason: '$preview');
        final plan = preview['structuredContent'] as Map;
        final args = {
          'plan_id': plan['plan_id'],
          'filename': 'check.wav',
          'base_revision': revision,
        };
        final unsafe = await client.call('export_cut_check', {
          ...args,
          'filename': '../outside.wav',
        });
        expect(
          unsafe['structuredContent']['error']['code'],
          'path_not_allowed',
        );
        policy.exportDirectory = null;
        final noDirectory = await client.call('export_cut_check', args);
        expect(
          noDirectory['structuredContent']['error']['code'],
          'export_directory_required',
        );
        policy.exportDirectory = f.directory.path;
        final output = await client.call('export_cut_check', args);
        expect(output['isError'], false, reason: '$output');
        final job = reads.jobs.get(
          output['structuredContent']['job_id'] as String,
        );
        final deadline = DateTime.now().add(const Duration(seconds: 60));
        while (!job.finished && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        final completed =
            (await client.call('get_job', {
                  'job_id': job.id,
                }))['structuredContent']
                as Map;
        expect(completed['status'], 'completed', reason: '$completed');
        expect(completed['result']['duration'], 2.0);
        expect(completed['result']['window_count'], 2);
        expect(File('${f.directory.path}/check.wav').existsSync(), true);
        expect(snapshot(), original);
        expect(c.projectRevision, revision);
        expect(plans.get(plan['plan_id'] as String).approved, false);
        if (native) {
          final pcm =
              (await f.run([
                    '-v',
                    'error',
                    '-i',
                    '${f.directory.path}/check.wav',
                    '-ac',
                    '1',
                    '-ar',
                    '48000',
                    '-f',
                    's16le',
                    'pipe:1',
                  ])).stdout
                  as List<int>;
          expect(pcm.length / 2 / 48000, closeTo(2, 1 / 20));
        }
        final duplicate = await client.call('export_cut_check', args);
        expect(duplicate['structuredContent']['error']['code'], 'file_exists');
        final blocked = await client.call('apply_plan', {
          'plan_id': plan['plan_id'],
          'base_revision': revision,
        });
        expect(
          blocked['structuredContent']['error']['code'],
          'approval_required',
        );
        plans.approve(plan['plan_id'] as String);
        expect(
          (await client.call('apply_plan', {
            'plan_id': plan['plan_id'],
            'base_revision': revision,
          }))['isError'],
          false,
        );
        final stale = await client.call('export_cut_check', {
          ...args,
          'filename': 'stale.wav',
        });
        expect(
          stale['structuredContent']['error']['code'],
          'revision_conflict',
        );
        plans.requireApproval = false;
        expect(
          (await client.call('undo', {
            'base_revision': c.projectRevision,
          }))['isError'],
          false,
        );
        expect(snapshot(), original);
      },
      skip:
          native &&
          !const bool.fromEnvironment('TGI_RUN_FFMPEG_INTEGRATION_TESTS'),
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
