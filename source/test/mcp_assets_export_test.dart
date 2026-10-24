import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:tgi_video_editor/domain/models/project.dart';
import 'package:tgi_video_editor/domain/models/track.dart';
import 'package:tgi_video_editor/features/editor/application/editor_controller.dart';
import 'package:tgi_video_editor/mcp/editor_mcp_server.dart';
import 'package:tgi_video_editor/mcp/editor_plans.dart';
import 'package:tgi_video_editor/mcp/editor_read_service.dart';
import 'package:tgi_video_editor/mcp/mcp_import_paths.dart';
import 'package:tgi_video_editor/mcp/mcp_media_import.dart';
import 'package:tgi_video_editor/mcp/mcp_path_policy.dart';
import 'package:tgi_video_editor/mcp/mcp_tool_router.dart';
import 'package:tgi_video_editor/services/media_import_service.dart';
import 'package:tgi_video_editor/services/project_io_service.dart';
import 'support/mcp_test_client.dart';
import 'support/render_fixture.dart';

void main() {
  test(
    'wire import + clip + alpha/image/video fades export and undo as one v14 transaction',
    () async {
      HttpOverrides.global = null;
      final fixture = RenderFixture();
      await fixture.open();
      addTearDown(fixture.close);
      final blue = await fixture.color('blue', seconds: 4);
      final red = await fixture.color('red', seconds: 2, audio: '660');
      final rgba = image.Image(width: 64, height: 64, numChannels: 4);
      for (var y = 16; y < 48; y++) {
        for (var x = 16; x < 48; x++) {
          rgba.setPixelRgba(x, y, 255, 0, 0, 128);
        }
      }
      for (var y = 24; y < 40; y++) {
        for (var x = 24; x < 40; x++) {
          rgba.setPixelRgba(x, y, 0, 255, 0, 255);
        }
      }
      final png = await File(
        '${fixture.directory.path}/alpha.png',
      ).writeAsBytes(image.encodePng(rgba));
      final pngHash = sha256.convert(await png.readAsBytes()).toString();
      final initial = TgiProject.empty(
        name: 'MCP assets',
      ).addDynamicTrack(TrackType.video).addDynamicTrack(TrackType.audio);
      final c = EditorController(
        initialProject: initial,
        mediaImportService: MediaImportService(ffmpegService: fixture.service),
      );
      c.synchronizeCommandExportSettings(RenderFixture.settings);
      final revision = c.projectRevision;
      final reads = EditorReadService(c, ffmpeg: fixture.service);
      final plans = EditorPlans(c, reads);
      final paths = McpImportPaths(directories: [fixture.directory.path]);
      final policy = McpPathPolicy(exportDirectory: fixture.directory.path);
      final server = EditorMcpServer(
        McpToolRouter(
          reads,
          plans,
          imports: McpMediaImport(paths, fixture.service),
          resolveExport: policy.resolveExport,
          authorizeExport: (project, path) async {
            await policy.trustProject(c.project);
            await policy.authorizeProject(project);
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
      Future<Map> call(String tool, Map<String, Object?> args) async {
        final result = await client.call(tool, args);
        expect(result['isError'], false, reason: result.toString());
        return result['structuredContent'] as Map;
      }

      final inputs = [blue.filePath, png.path, red.filePath];
      final importPreview = await call('import_media', {
        'paths': inputs,
        'base_revision': revision,
      });
      final ids = (importPreview['imported_media'] as List)
          .map((m) => (m as Map)['media_id'] as String)
          .toList();
      Map<String, Object?> overlay(String id, double x, double y) => {
        'media_id': id,
        'at': 1,
        'duration': 2,
        'position': {'x': x, 'y': y},
        'scale': .5,
        'fade_in_ms': 500,
        'fade_out_ms': 500,
      };
      final commands = [
        {
          'tool': 'import_media',
          'arguments': {'paths': inputs},
        },
        {
          'tool': 'add_clip',
          'arguments': {
            'media_id': ids[0],
            'track': TgiProject.defaultVideoTrackId,
            'at': 0,
            'in': 0,
            'out': 4,
          },
        },
        {'tool': 'add_image_overlay', 'arguments': overlay(ids[1], 0, 0)},
        {
          'tool': 'add_video_overlay',
          'arguments': {...overlay(ids[2], 1, 1), 'volume': .25},
        },
      ];
      final io = ProjectIOService();
      final before = jsonEncode(io.serializeProject(c.project));
      final preview = await call('preview_plan', {
        'commands': commands,
        'base_revision': revision,
        'label': 'IA: assets e overlays',
      });
      expect(jsonEncode(io.serializeProject(c.project)), before);
      plans.approve(preview['plan_id'] as String);
      await call('apply_plan', {
        'plan_id': preview['plan_id'],
        'base_revision': revision,
      });
      expect(c.projectRevision, revision + 1);
      expect(c.project.mediaPool.length, 3);
      final serialized = io.serializeProject(c.project);
      expect(serialized['version'], 14);
      final roundTrip = io.deserializeProject(serialized).project;
      expect(
        jsonEncode(io.serializeProject(roundTrip)),
        jsonEncode(serialized),
      );
      final export = await call('export', {
        'filename': 'assets.mp4',
        'base_revision': revision + 1,
      });
      final job = reads.jobs.get(export['job_id'] as String);
      for (var i = 0; i < 600 && !job.finished; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      final result = await call('get_job', {'job_id': job.id});
      expect(result['status'], 'completed', reason: result.toString());
      final output = '${fixture.directory.path}/assets.mp4';
      final transparent = await fixture.pixel(output, 2, x: 2, y: 2);
      expect(transparent[2], greaterThan(190));
      expect(transparent[0], lessThan(45));
      final semi = await fixture.pixel(output, 2, x: 14, y: 14);
      expect(semi[0], inInclusiveRange(70, 190));
      expect(semi[2], inInclusiveRange(70, 190));
      final opaque = await fixture.pixel(output, 2, x: 22, y: 22);
      expect(opaque[1], greaterThan(180));
      expect(opaque[2], lessThan(55));
      for (final t in [.75, 3.25]) {
        final p = await fixture.pixel(output, t, x: 22, y: 22);
        expect(p[2], greaterThan(190));
        expect(p[1], lessThan(45));
      }
      for (final t in [1.05, 2.95]) {
        final p = await fixture.pixel(output, t, x: 22, y: 22);
        expect(p[1], lessThan(110));
        expect(p[2], greaterThan(120));
      }
      final pip = await fixture.pixel(output, 2, x: 140, y: 70);
      expect(pip[0], greaterThan(180));
      expect(pip[2], lessThan(55));
      for (final t in [1.05, 2.95]) {
        final p = await fixture.pixel(output, t, x: 140, y: 70);
        expect(p[0], lessThan(110));
        expect(p[2], greaterThan(120));
      }
      final audio = await fixture.service.runCommand([
        '-v',
        'info',
        '-ss',
        '1.7',
        '-t',
        '0.2',
        '-i',
        output,
        '-af',
        'volumedetect',
        '-vn',
        '-f',
        'null',
        '-',
      ]);
      expect(audio.exitCode, 0);
      final mean = double.parse(
        RegExp(
          r'mean_volume: (-?[0-9.]+) dB',
        ).firstMatch('${audio.stderr}')!.group(1)!,
      );
      expect(
        mean,
        inInclusiveRange(-45, -24),
        reason: 'Overlay audio gain .25 must reach the export.',
      );
      expect(sha256.convert(await png.readAsBytes()).toString(), pngHash);
      final undo = await call('undo', {'base_revision': revision + 1});
      plans.approve(undo['plan_id'] as String);
      await call('apply_plan', {
        'plan_id': undo['plan_id'],
        'base_revision': revision + 1,
      });
      expect(jsonEncode(io.serializeProject(c.project)), before);
    },
  );
}
