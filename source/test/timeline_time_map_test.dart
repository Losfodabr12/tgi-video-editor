import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/core/commands/timeline_time_map.dart';
import 'package:tgi_video_editor/domain/models/clip.dart';
import 'package:tgi_video_editor/domain/models/track.dart';
import 'command_engine_test.dart' show commandFixture;

void main() {
  test(
    'time map merges cuts, is continuous and monotone, and keeps exact duration',
    () {
      final map = TimelineTimeMap([
        (2000000, 4000000),
        (3500000, 5000000),
        (7000000, 8000000),
      ], end: 10000000);
      expect(map.removedDuration, 4000000);
      expect(map.map(10000000), 6000000);
      expect(map.map(3000000), map.map(5000000));
      var previous = -1;
      for (var t = 0; t <= 10000000; t += 1000) {
        final value = map.map(t);
        expect(value, greaterThanOrEqualTo(previous));
        previous = value;
      }
    },
  );
  test(
    'all tracks remap together instead of creating caption ripple overlaps',
    () {
      var project = commandFixture();
      final video = project.tracks.expand((t) => t.clips).first;
      Clip caption(String id, int start, int duration) => Clip(
        id: id,
        mediaItemId: id,
        timelineGroupId: id,
        trackType: TrackType.text,
        timelineStart: Duration(seconds: start),
        sourceStart: Duration.zero,
        duration: Duration(seconds: duration),
        isCaption: true,
        textContent: id,
      );
      project = project.copyWith(
        tracks: [
          Track(
            id: 'captions',
            name: 'Captions',
            type: TrackType.text,
            clips: [
              caption('left', 1, 2),
              caption('inside', 3, 1),
              caption('right', 4, 2),
            ],
          ),
          ...project.tracks,
        ],
      );
      final map = TimelineTimeMap([(2000000, 4000000)], end: 10000000);
      final after = const TimelineRemapper().apply(project, video, map).project;
      expect(after.timelineDuration, const Duration(seconds: 8));
      expect(after.clipById('inside'), isNull);
      expect(after.clipById('left')!.timelineEnd, const Duration(seconds: 2));
      expect(
        after.clipById('right')!.timelineStart,
        const Duration(seconds: 2),
      );
      expect(
        after.tracks
            .where((t) => t.clips.any((c) => c.trackType == TrackType.video))
            .single
            .clips,
        hasLength(2),
      );
      expect(project.timelineDuration, const Duration(seconds: 10));
    },
  );
}
