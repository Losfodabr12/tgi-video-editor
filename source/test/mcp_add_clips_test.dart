import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/core/commands/command_engine.dart';
import 'package:tgi_video_editor/domain/models/media_item.dart';
import 'package:tgi_video_editor/domain/models/project.dart';
import 'package:tgi_video_editor/domain/models/track.dart';
import 'package:tgi_video_editor/features/editor/application/editor_controller.dart';
import 'package:tgi_video_editor/mcp/editor_plans.dart';
import 'package:tgi_video_editor/mcp/editor_read_service.dart';
import 'package:tgi_video_editor/mcp/mcp_tool_router.dart';
import 'package:tgi_video_editor/services/ffmpeg_service.dart';
import 'package:tgi_video_editor/services/media_import_service.dart';
import 'package:tgi_video_editor/services/project_io_service.dart';

void main() {
  late EditorController c;
  late EditorReadService reads;
  late EditorPlans plans;
  late McpToolRouter router;
  setUp(() {
    var project = TgiProject.empty(name: 'Insert')
        .addDynamicTrack(TrackType.video)
        .addDynamicTrack(TrackType.audio);
    for (final id in ['a', 'b']) {
      project = project.addMediaItem(
        MediaItem(
          id: id,
          name: id,
          filePath: '$id.mp4',
          type: MediaType.video,
          duration: const Duration(seconds: 4),
          importedAt: DateTime.utc(2026),
          hasAudio: true,
        ),
      );
    }
    c = EditorController(
      initialProject: project,
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
  Map data(Map result) => result['structuredContent'] as Map;
  String snapshot() =>
      jsonEncode(ProjectIOService().serializeProject(c.project));

  test(
    'add_clip keeps video/audio trims linked and one undo restores the project',
    () async {
      final before = snapshot();
      final result = await router.call('add_clip', {
        'media_id': 'a',
        'track': TgiProject.defaultVideoTrackId,
        'at': 2,
        'in': 1,
        'out': 3,
        'base_revision': 0,
      });
      expect(result['isError'], false, reason: result.toString());
      final clips = c.project.tracks.expand((t) => t.clips).toList();
      expect(clips.length, 2);
      expect(clips.map((c) => c.timelineGroupId).toSet().length, 1);
      for (final clip in clips) {
        expect(clip.sourceStart, const Duration(seconds: 1));
        expect(clip.duration, const Duration(seconds: 2));
        expect(clip.timelineStart, const Duration(seconds: 2));
      }
      expect(c.undoLabel, 'IA: add_clip');
      c.undo();
      expect(snapshot(), before);
    },
  );

  test(
    'sequence previews all clips, has no gaps and is atomic on collision',
    () async {
      final before = snapshot();
      final result = data(
        await router.call('preview_plan', {
          'base_revision': 0,
          'commands': [
            {
              'tool': 'add_clips_sequence',
              'arguments': {
                'media_ids': ['a', 'b'],
                'track': TgiProject.defaultVideoTrackId,
                'at': 0,
              },
            },
          ],
        }),
      );
      expect(result, isNot(contains('error')), reason: result.toString());
      expect(snapshot(), before);
      expect(
        data(
          await router.call('apply_plan', {
            'plan_id': result['plan_id'],
            'base_revision': 0,
          }),
        ),
        isNot(contains('error')),
      );
      final video = c.project.tracks
          .expand((t) => t.clips)
          .where((c) => c.trackType == TrackType.video)
          .toList();
      expect(video.map((c) => c.timelineStart), [
        Duration.zero,
        const Duration(seconds: 4),
      ]);
      expect(c.project.timelineDuration, const Duration(seconds: 8));
      final populated = snapshot();
      final blocked = await router.call('add_clips_sequence', {
        'media_ids': ['a', 'b'],
        'track': TgiProject.defaultVideoTrackId,
        'at': 6,
        'base_revision': c.projectRevision,
      });
      expect((data(blocked)['error'] as Map)['code'], 'placement_conflict');
      expect(snapshot(), populated);
      c.undo();
      expect(snapshot(), before);
    },
  );

  test(
    'unknown IDs, incompatible/locked tracks and invalid source intervals fail without editing',
    () async {
      final args = {
        'media_id': 'a',
        'track': TgiProject.defaultVideoTrackId,
        'at': 0,
        'in': 0,
        'out': 4,
        'base_revision': 0,
      };
      for (final change in [
        {'media_id': 'missing'},
        {'track': 'missing'},
        {'track': TgiProject.defaultAudioTrackId},
        {'in': 3, 'out': 2},
        {'out': 5},
      ]) {
        expect(
          (await router.call('add_clip', {...args, ...change}))['isError'],
          true,
        );
        expect(c.projectRevision, 0);
      }
      final locked = c.project.copyWith(
        tracks: [for (final t in c.project.tracks) t.copyWith(isLocked: true)],
      );
      expect(
        () => const CommandEngine().apply(
          locked,
          EditorCommand('add_clip', {
            'media_id': 'a',
            'track': TgiProject.defaultVideoTrackId,
            'at': 0,
            'in': 0,
            'out': 4,
          }),
        ),
        throwsA(isA<CommandError>()),
      );
    },
  );
}
