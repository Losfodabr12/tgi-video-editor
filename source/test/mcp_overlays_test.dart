import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/domain/models/project.dart';
import 'package:tgi_video_editor/domain/models/media_item.dart';
import 'package:tgi_video_editor/domain/models/track.dart';
import 'package:tgi_video_editor/features/editor/application/editor_controller.dart';
import 'package:tgi_video_editor/mcp/editor_plans.dart';
import 'package:tgi_video_editor/mcp/editor_read_service.dart';
import 'package:tgi_video_editor/mcp/mcp_tool_router.dart';
import 'package:tgi_video_editor/services/ffmpeg_service.dart';
import 'package:tgi_video_editor/services/media_import_service.dart';
import 'package:tgi_video_editor/services/project_io_service.dart';
import 'command_engine_test.dart' show commandFixture;

void main() {
  late EditorController c;
  late EditorReadService reads;
  late EditorPlans plans;
  late McpToolRouter router;
  setUp(() {
    final image = MediaItem(
      id: 'png',
      filePath: 'alpha.png',
      name: 'alpha.png',
      type: MediaType.image,
      duration: const Duration(seconds: 5),
      hasAudio: false,
      importedAt: DateTime.utc(2026),
    );
    c = EditorController(
      initialProject: commandFixture().addMediaItem(image),
      mediaImportService: MediaImportService(ffmpegService: FfmpegService()),
    );
    reads = EditorReadService(c);
    plans = EditorPlans(c, reads)..requireApproval = false;
    router = McpToolRouter(reads, plans);
  });
  tearDown(() async {
    await reads.dispose();
    c.dispose();
  });
  Map<String, Object?> args(String id) => {
    'media_id': id,
    'at': 1,
    'duration': 3,
    'position': {'x': 1, 'y': 1},
    'scale': .18,
    'fade_in_ms': 200,
    'fade_out_ms': 200,
  };
  String snapshot() =>
      jsonEncode(ProjectIOService().serializeProject(c.project));

  test(
    'image overlay is above video, maps scale to canvas fraction and keeps source alpha untouched',
    () async {
      final before = snapshot();
      final result = await router.call('add_image_overlay', {
        ...args('png'),
        'base_revision': 0,
      });
      expect(result['isError'], false, reason: result.toString());
      final overlay = c.project.tracks.first.clips.single;
      expect(overlay.trackType, TrackType.image);
      expect(overlay.overlayScale, closeTo(.72, 1e-9));
      expect(overlay.overlayX, 1);
      expect(overlay.overlayY, 1);
      expect(overlay.fadeIn, const Duration(milliseconds: 200));
      expect(overlay.fadeOut, const Duration(milliseconds: 200));
      expect(c.project.mediaItemById('png')!.filePath, 'alpha.png');
      expect(
        c.project.tracks.indexOf(c.project.baseVideoTrack!),
        greaterThan(0),
      );
      c.undo();
      expect(snapshot(), before);
    },
  );

  test(
    'video overlay has a linked audio companion with independent configurable volume and fades',
    () async {
      final oldIds = c.project.tracks
          .expand((t) => t.clips)
          .map((c) => c.id)
          .toSet();
      final result = await router.call('add_video_overlay', {
        ...args('media'),
        'volume': .4,
        'base_revision': 0,
      });
      expect(result['isError'], false, reason: result.toString());
      final additions = c.project.tracks
          .expand((t) => t.clips)
          .where((c) => !oldIds.contains(c.id))
          .toList();
      expect(additions.length, 2);
      expect(additions.map((c) => c.timelineGroupId).toSet().length, 1);
      expect(additions.map((c) => c.volume), everyElement(.4));
      for (final clip in additions) {
        expect(clip.timelineStart, const Duration(seconds: 1));
        expect(clip.duration, const Duration(seconds: 3));
        expect(clip.sourceStart, Duration.zero);
        expect(clip.fadeIn, const Duration(milliseconds: 200));
      }
      expect(c.project.tracks.first.clips.single.trackType, TrackType.video);
      expect(
        c.project.tracks.indexOf(c.project.baseVideoTrack!),
        greaterThan(0),
      );
    },
  );

  test(
    'overlay batch is an exact preview and atomic on type, source-range, fade or position errors',
    () async {
      final before = snapshot();
      for (final changes in [
        {'duration': 11},
        {'fade_in_ms': 2000, 'fade_out_ms': 2000},
        {'scale': 0},
        {
          'position': {'x': 2, 'y': 0},
        },
      ]) {
        final result = await router.call('add_video_overlay', {
          ...args('media'),
          ...changes,
          'base_revision': 0,
        });
        expect(result['isError'], true);
        expect(snapshot(), before);
      }
      expect(
        (await router.call('add_image_overlay', {
          ...args('media'),
          'base_revision': 0,
        }))['isError'],
        true,
      );
      final draft = await router.call('preview_plan', {
        'base_revision': 0,
        'commands': [
          {'tool': 'add_image_overlay', 'arguments': args('png')},
          {'tool': 'add_video_overlay', 'arguments': args('media')},
        ],
      });
      expect(draft['isError'], false);
      expect(snapshot(), before);
      final id = (draft['structuredContent'] as Map)['plan_id'];
      expect(
        (await router.call('apply_plan', {
          'plan_id': id,
          'base_revision': 0,
        }))['isError'],
        false,
      );
      expect(c.undoLabel, startsWith('IA:'));
      c.undo();
      expect(snapshot(), before);
    },
  );
}
