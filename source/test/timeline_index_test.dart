import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/domain/models/clip.dart';
import 'package:tgi_video_editor/domain/models/track.dart';
import 'package:tgi_video_editor/domain/models/timeline_clip_index.dart';

Clip clip(int n, {int? duration}) => Clip(
  id: 'clip_$n',
  mediaItemId: 'm',
  timelineGroupId: 'group_$n',
  trackType: TrackType.text,
  timelineStart: Duration(milliseconds: n * 2000),
  sourceStart: Duration.zero,
  duration: Duration(milliseconds: duration ?? 1000),
);

void main() {
  test(
    'interval lookup preserves overlapping legacy clips and exclusive ends',
    () {
      final index = TimelineClipIndex([
        clip(0, duration: 20000),
        clip(1),
        clip(2),
        clip(3),
      ]);
      expect(
        index
            .intersecting(
              const Duration(seconds: 5),
              const Duration(seconds: 6),
            )
            .map((c) => c.id),
        ['clip_0'],
      );
      expect(
        index
            .intersecting(
              const Duration(seconds: 6),
              const Duration(seconds: 7),
            )
            .map((c) => c.id),
        ['clip_0', 'clip_3'],
      );
      expect(
        index.intersecting(
          const Duration(seconds: 20),
          const Duration(seconds: 21),
        ),
        isEmpty,
      );
    },
  );

  for (final size in [20, 20000]) {
    test(
      'measure linear and indexed queries over $size clips with equal results',
      () {
        final clips = [for (var n = 0; n < size; n++) clip(n)];
        final build = Stopwatch()..start();
        final index = TimelineClipIndex(clips);
        build.stop();
        final times = [for (var n = 0; n < 300; n++) (n * 997) % size];
        final linear = Stopwatch()..start();
        final expected = [
          for (final time in times)
            clips
                .where(
                  (clip) =>
                      clip.timelineStart < Duration(seconds: time * 2 + 12) &&
                      clip.timelineEnd > Duration(seconds: time * 2),
                )
                .map((clip) => clip.id)
                .toList(),
        ];
        linear.stop();
        final indexed = Stopwatch()..start();
        final actual = [
          for (final time in times)
            index
                .intersecting(
                  Duration(seconds: time * 2),
                  Duration(seconds: time * 2 + 12),
                )
                .map((clip) => clip.id)
                .toList(),
        ];
        indexed.stop();
        expect(actual, expected);
        // Measurements are recorded, never used as hardware-dependent pass/fail thresholds.
        // ignore: avoid_print
        print(
          'TIMELINE_MEASUREMENT clips=$size queries=300 build_us=${build.elapsedMicroseconds} '
          'linear_us=${linear.elapsedMicroseconds} indexed_us=${indexed.elapsedMicroseconds}',
        );
      },
    );
  }
}
