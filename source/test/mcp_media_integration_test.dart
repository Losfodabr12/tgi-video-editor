import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:tgi_video_editor/core/commands/command_engine.dart';
import 'package:tgi_video_editor/domain/models/media_item.dart';
import 'package:tgi_video_editor/domain/models/project.dart';
import 'package:tgi_video_editor/features/editor/application/editor_controller.dart';
import 'package:tgi_video_editor/mcp/editor_jobs.dart';
import 'package:tgi_video_editor/mcp/editor_read_service.dart';
import 'package:tgi_video_editor/mcp/editor_plans.dart';
import 'package:tgi_video_editor/mcp/editor_mcp_server.dart';
import 'package:tgi_video_editor/mcp/mcp_tool_router.dart';
import 'package:tgi_video_editor/mcp/mcp_path_policy.dart';
import 'package:tgi_video_editor/services/media_import_service.dart';
import 'package:tgi_video_editor/services/ffmpeg_service.dart';
import 'package:tgi_video_editor/services/auto_caption_service.dart';
import 'support/mcp_test_client.dart';
import 'support/render_fixture.dart';
import 'command_engine_test.dart' show commandFixture;

class _Captions implements AutoCaptionService {
  @override
  Future<List<CaptionCue>> generateCaptionsForMedia(
    MediaItem item, {
    String? languageCode,
    String modelName = '',
    int maxCharsPerCue = 44,
    AutoCaptionProgressCallback? onProgress,
  }) async => const [
    CaptionCue(
      start: Duration(seconds: 1),
      end: Duration(seconds: 3),
      text: 'Teste de legenda',
    ),
  ];
}

Future<void> _finish(EditorJob job) async {
  for (var i = 0; i < 750 && !job.finished; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(job.status, 'completed', reason: job.error.toString());
}

class _DelayedFfmpeg extends FfmpegService {
  final started = Completer<void>(), launch = Completer<FfmpegCommandProcess>();
  @override
  Future<FfmpegCommandProcess> startCommand(
    List<String> arguments, {
    bool useFfprobe = false,
  }) async {
    started.complete();
    return launch.future;
  }
}

class _Handle implements MediaProcessHandle {
  final out = StreamController<List<int>>(),
      err = StreamController<List<int>>();
  final exit = Completer<int>();
  bool cancelled = false;
  @override
  int get pid => 999;
  @override
  Stream<List<int>> get stdout => out.stream;
  @override
  Stream<List<int>> get stderr => err.stream;
  @override
  Future<int> get exitCode => exit.future;
  @override
  Future<bool> cancel() async {
    cancelled = true;
    if (!exit.isCompleted) {
      exit.complete(-9);
      unawaited(out.close());
      unawaited(err.close());
    }
    return true;
  }
}

void main() {
  test(
    'real FFmpeg tools return scene/silence/loudness, PNG frames and a playable export over MCP',
    () async {
      HttpOverrides.global = null;
      final fixture = RenderFixture();
      await fixture.open();
      addTearDown(fixture.close);
      final path = '${fixture.directory.path}/mcp.mp4';
      await fixture.run([
        '-y',
        '-v',
        'error',
        '-f',
        'lavfi',
        '-i',
        'color=red:s=160x90:r=10:d=1.5',
        '-f',
        'lavfi',
        '-i',
        'color=blue:s=160x90:r=10:d=1.5',
        '-f',
        'lavfi',
        '-i',
        r'aevalsrc=if(lt(t\,1)\,0\,0.3*sin(2*PI*440*t)):s=16000:d=3',
        '-filter_complex',
        '[0:v][1:v]concat=n=2:v=1:a=0[v]',
        '-map',
        '[v]',
        '-map',
        '2:a',
        '-c:v',
        'libx264',
        '-pix_fmt',
        'yuv420p',
        '-c:a',
        'aac',
        path,
      ]);
      final media = MediaItem(
        id: 'media',
        filePath: path,
        name: 'mcp.mp4',
        type: MediaType.video,
        duration: const Duration(seconds: 3),
        importedAt: DateTime.utc(2026),
        width: 160,
        height: 90,
      );
      final project = TgiProject.empty(name: 'MCP integration')
          .addMediaItem(media)
          .addMediaItemToTimeline(media, timelineStart: Duration.zero);
      final c = EditorController(
        mediaImportService: MediaImportService(ffmpegService: fixture.service),
        initialProject: project,
      );
      c.synchronizeCommandExportSettings(RenderFixture.settings);
      final policy = McpPathPolicy(
        projectDirectory: fixture.directory.path,
        exportDirectory: fixture.directory.path,
      );
      await policy.trustProject(project);
      final reads = EditorReadService(
        c,
        ffmpeg: fixture.service,
        captions: _Captions(),
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
      final loudness = await client.call('get_loudness', {'media_id': 'media'});
      expect(loudness['isError'], isFalse, reason: loudness.toString());
      expect(loudness['structuredContent']['integrated_lufs'], isA<num>());
      final frames = await client.call('get_frames', {
        'media_id': 'media',
        'times': [0.5, 2.5],
      });
      expect(frames['isError'], isFalse, reason: frames.toString());
      final images = (frames['content'] as List)
          .where((c) => c['type'] == 'image')
          .toList();
      expect(images.length, 2);
      final first = image
          .decodePng(
            Uint8List.fromList(base64Decode(images[0]['data'] as String)),
          )!
          .getPixel(20, 20);
      final last = image
          .decodePng(
            Uint8List.fromList(base64Decode(images[1]['data'] as String)),
          )!
          .getPixel(20, 20);
      expect(first.r, greaterThan(200));
      expect(last.b, greaterThan(200));
      final videoId = c.project.tracks.expand((t) => t.clips).first.id;
      c.executeCommands([
        EditorCommand('apply_effect', {'clip_id': videoId, 'reverse': true}),
        EditorCommand('split_clip', {'clip_id': videoId, 'at': 1}),
      ], baseRevision: c.projectRevision);
      final silent = await client.call('detect_silence', {
        'media_id': 'media',
        'minimum': 0.3,
      });
      final silenceJob = reads.jobs.get(
        silent['structuredContent']['job_id'] as String,
      );
      await _finish(silenceJob);
      final intervals = (silenceJob.result as Map)['intervals'] as List;
      expect(intervals, isNotEmpty);
      expect(intervals.first['end'], closeTo(1, 0.1));
      final scenes = await client.call('detect_scenes', {
        'media_id': 'media',
        'threshold': 0.1,
      });
      final sceneJob = reads.jobs.get(
        scenes['structuredContent']['job_id'] as String,
      );
      await _finish(sceneJob);
      expect((sceneJob.result as Map)['times'], contains(closeTo(1.5, 0.2)));
      final transcript = await client.call('transcribe', {'media_id': 'media'});
      await _finish(
        reads.jobs.get(transcript['structuredContent']['job_id'] as String),
      );
      expect(
        (await client.call('get_transcript', {
          'media_id': 'media',
        }))['structuredContent']['total'],
        1,
      );
      final export = await client.call('export', {
        'filename': 'result.mp4',
        'base_revision': c.projectRevision,
      });
      expect(export['isError'], isFalse, reason: export.toString());
      await _finish(
        reads.jobs.get(export['structuredContent']['job_id'] as String),
      );
      expect(
        await File('${fixture.directory.path}/result.mp4').length(),
        greaterThan(1000),
      );
      final probe = await fixture.service.runCommand([
        '-v',
        'error',
        '-show_entries',
        'format=duration',
        '-of',
        'json',
        '${fixture.directory.path}/result.mp4',
      ], useFfprobe: true);
      expect(
        double.parse(
          (jsonDecode(probe.stdout as String) as Map)['format']['duration']
              as String,
        ),
        closeTo(3, 0.1),
      );
      final firstReversed = await fixture.pixel(
        '${fixture.directory.path}/result.mp4',
        0.25,
      );
      final lastReversed = await fixture.pixel(
        '${fixture.directory.path}/result.mp4',
        2.75,
      );
      expect(firstReversed[2], greaterThan(200));
      expect(lastReversed[0], greaterThan(200));
    },
  );
  test(
    'emergency cancellation also kills a native process that finishes starting later',
    () async {
      final c = EditorController(
        mediaImportService: MediaImportService(ffmpegService: FfmpegService()),
        initialProject: commandFixture(),
      );
      final ffmpeg = _DelayedFfmpeg(), handle = _Handle();
      final reads = EditorReadService(
        c,
        ffmpeg: ffmpeg,
        checkMedia: (m) async => m.filePath,
      );
      addTearDown(() async {
        await reads.dispose();
        c.dispose();
      });
      final pending = reads.getLoudness('media');
      await ffmpeg.started.future;
      final rejected = expectLater(
        pending,
        throwsA(isA<CommandError>().having((e) => e.code, 'code', 'cancelled')),
      );
      await reads.cancelAll();
      ffmpeg.launch.complete(FfmpegCommandProcess(handle));
      await rejected;
      expect(handle.cancelled, isTrue);
    },
  );
}
