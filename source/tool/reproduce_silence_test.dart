import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/core/commands/editor_command.dart';
import 'package:tgi_video_editor/features/editor/application/editor_controller.dart';
import 'package:tgi_video_editor/mcp/editor_plans.dart';
import 'package:tgi_video_editor/mcp/editor_read_service.dart';
import 'package:tgi_video_editor/mcp/editor_mcp_server.dart';
import 'package:tgi_video_editor/mcp/mcp_tool_router.dart';
import 'package:tgi_video_editor/services/ffmpeg_service.dart';
import 'package:tgi_video_editor/services/media_import_service.dart';
import 'package:tgi_video_editor/services/project_io_service.dart';
import '../test/support/mcp_test_client.dart';

/// Opt-in local reproduction. The private project never becomes a fixture.
void main() {
  test(
    'reproduce captured silence analysis on a copy of the real project',
    () async {
      HttpOverrides.global = null;
      final projectFile = Platform.environment['MCP_REPRO_PROJECT'];
      final analysisFile = Platform.environment['MCP_REPRO_ANALYSIS'];
      final outputFile = Platform.environment['MCP_REPRO_OUTPUT'];
      expect(projectFile, isNotNull);
      expect(analysisFile, isNotNull);
      expect(outputFile, isNotNull);
      final io = ProjectIOService();
      final loaded = io.deserializeProject(
        jsonDecode(await File(projectFile!).readAsString())
            as Map<String, dynamic>,
      );
      final captured =
          jsonDecode(await File(analysisFile!).readAsString())
              as Map<String, dynamic>;
      final controller = EditorController(
        mediaImportService: MediaImportService(ffmpegService: FfmpegService()),
        initialProject: loaded.project,
      );
      final reads = EditorReadService(controller);
      addTearDown(() async {
        await reads.dispose();
        controller.dispose();
      });
      final plans = EditorPlans(controller, reads);
      final before = jsonEncode(io.serializeProject(controller.project));
      final job = reads.jobs.start(
        'detect_silence',
        0,
        controller.project.id,
        (_) async => captured['analysis'],
      );
      while (!job.finished) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(job.status, 'completed');
      final arguments = Map<String, Object?>.from(captured['arguments'] as Map)
        ..remove('base_revision');
      arguments['job_id'] = job.id;
      final report = <String, Object?>{
        'fixture': 'private real project copy; not committed',
        'clip_count': controller.project.tracks.expand((t) => t.clips).length,
        'track_count': controller.project.tracks.length,
        'analysis_interval_count':
            (captured['analysis']['intervals'] as List).length,
        'padding': arguments['padding'],
        'format_version': 14,
      };
      try {
        final plan = plans.previewMacro(
          'remove_silences',
          arguments,
          baseRevision: 0,
        );
        report['success'] = true;
        report['duration_before'] =
            plan.before.timelineDuration.inMicroseconds / 1e6;
        report['duration_after'] =
            plan.after.timelineDuration.inMicroseconds / 1e6;
        report['plan'] = {
          'change_count': plan.toJson()['change_count'],
          'command_count': plan.commands.length,
        };
        report['removed_duration'] = plan.toJson()['time_map'] is Map
            ? (plan.toJson()['time_map'] as Map)['removed_duration']
            : null;
        plans.approve(plan.id);
        plans.apply(plan.id, baseRevision: 0);
        controller.undo();
        report['undo_exact'] =
            jsonEncode(io.serializeProject(controller.project)) == before;
        plans.requireApproval = false;
        final server = EditorMcpServer(
          McpToolRouter(reads, plans),
          token: randomMcpToken(),
          port: 0,
        );
        await server.start();
        final client = McpTestClient(server.boundPort, server.token);
        addTearDown(() async {
          client.close();
          await server.stop();
        });
        await client.initialize();
        final revision = controller.projectRevision;
        final freshJob = reads.jobs.start(
          'detect_silence',
          revision,
          controller.project.id,
          (_) async => captured['analysis'],
        );
        while (!freshJob.finished) {
          await Future<void>.delayed(Duration.zero);
        }
        final preview = await client.call('preview_plan', {
          'macro': 'remove_silences',
          'arguments': {...arguments, 'job_id': freshJob.id},
          'base_revision': revision,
        });
        expect(preview['isError'], false, reason: preview.toString());
        expect(jsonEncode(io.serializeProject(controller.project)), before);
        final applied = await client.call('apply_plan', {
          'plan_id': preview['structuredContent']['plan_id'],
          'base_revision': revision,
        });
        expect(applied['isError'], false, reason: applied.toString());
        final exportFile = Platform.environment['MCP_REPRO_EXPORT'];
        if (exportFile != null) {
          const settings = FfmpegExportSettings(
            resolution: FfmpegExportResolution(
              id: 'repro',
              label: 'Reproduction',
              width: 320,
              height: 180,
            ),
            framesPerSecond: 30,
            quality: FfmpegExportQuality.maximum,
            rangeStart: Duration.zero,
            rangeEnd: Duration(seconds: 5),
          );
          await reads.ffmpeg.exportProject(
            controller.project,
            exportFile,
            settings: settings,
          );
          final toolchain = await reads.ffmpeg.resolveToolchain();
          final probe = await Process.run(toolchain.ffprobePath, [
            '-v',
            'error',
            '-show_entries',
            'format=duration',
            '-of',
            'json',
            exportFile,
          ]);
          expect(probe.exitCode, 0, reason: probe.stderr.toString());
          final duration = double.parse(
            (jsonDecode(probe.stdout as String) as Map)['format']['duration']
                as String,
          );
          expect(duration, closeTo(5, 1 / 30));
          report['real_media_export'] = {
            'range_seconds': 5,
            'ffprobe_duration': duration,
            'frames_per_second': 30,
            'tolerance_seconds': 1 / 30,
          };
        }
        expect(
          (await client.call('undo', {
            'base_revision': controller.projectRevision,
          }))['isError'],
          false,
        );
        report['mcp_transport'] = 'Streamable HTTP loopback';
        report['mcp_sequence'] = ['preview_plan', 'apply_plan', 'undo'];
        report['mcp_undo_exact'] =
            jsonEncode(io.serializeProject(controller.project)) == before;
      } on CommandError catch (error) {
        report['success'] = false;
        report['error'] = error.toJson();
      }
      report['original_unchanged'] =
          jsonEncode(io.serializeProject(controller.project)) == before;
      await File(outputFile!).writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
      expect(report['original_unchanged'], true);
      if (Platform.environment['MCP_REPRO_EXPECT_SUCCESS'] == '1') {
        expect(report['success'], true, reason: jsonEncode(report));
        expect(report['undo_exact'], true);
        expect(report['mcp_undo_exact'], true);
      } else {
        expect(report['success'], false);
        final error = report['error'] as Map;
        expect(error['code'], 'placement_conflict');
        expect((error['details'] as Map)['cause'], 'overlap');
      }
    },
  );
}
