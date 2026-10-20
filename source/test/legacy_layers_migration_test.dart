import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/domain/models/clip.dart';
import 'package:tgi_video_editor/domain/models/project.dart';
import 'package:tgi_video_editor/domain/models/track.dart';
import 'package:tgi_video_editor/services/project_io_service.dart';

void main() {
  for (final version in [13, 14]) {
    test(
      'format $version overlaps migrate without losing payload and remain stable',
      () {
        final clips = List.generate(
          3,
          (i) => Clip(
            id: 'c$i',
            mediaItemId: 'm$i',
            timelineGroupId: 'g$i',
            trackType: TrackType.video,
            timelineStart: Duration(seconds: i),
            sourceStart: const Duration(seconds: 4),
            duration: const Duration(seconds: 3),
            opacity: .7,
            keyframes: const [
              ClipKeyframe(
                id: 'key',
                property: ClipKeyframeProperty.opacity,
                time: .5,
                value: .2,
              ),
            ],
          ),
        );
        final audio = clips[0].copyWith(
          id: 'audio',
          trackType: TrackType.audio,
        );
        final original = TgiProject.empty(name: 'Old').copyWith(
          tracks: [
            Track(
              id: 'video',
              name: 'Original',
              clips: clips,
              isLocked: true,
              height: 88,
            ),
            Track(
              id: 'video_layer_2',
              name: 'Existing ID',
              kind: TrackKind.audio,
              clips: [audio],
            ),
          ],
        );
        final io = ProjectIOService();
        final data = io.serializeProject(original)..['version'] = version;
        final migrated = io.deserializeProject(data).project;
        final visual = migrated.tracks
            .where((t) => t.kind == TrackKind.visual)
            .toList();
        expect(visual.length, 3);
        expect(
          migrated.tracks.map((t) => t.id).toSet().length,
          migrated.tracks.length,
        );
        for (final track in visual) {
          expect(track.isLocked, isTrue);
          expect(track.height, 88);
          expect(track.clips.length, 1);
        }
        for (final clip in clips) {
          final next = migrated.clipById(clip.id)!;
          expect(next.timelineStart, clip.timelineStart);
          expect(next.sourceStart, clip.sourceStart);
          expect(next.duration, clip.duration);
          expect(next.timelineGroupId, clip.timelineGroupId);
          expect(next.keyframes.single.value, .2);
          expect(next.opacity, .7);
        }
        expect(migrated.clipById('audio')!.timelineGroupId, 'g0');
        final serialized = io.serializeProject(migrated);
        expect(serialized['version'], 14);
        final reopened = io.deserializeProject(serialized).project;
        expect(io.serializeProject(reopened), serialized);
        expect(original.tracks.first.clips.length, 3);
      },
    );
  }
}
