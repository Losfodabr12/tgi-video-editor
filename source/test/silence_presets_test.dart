import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/core/commands/silence_options.dart';
import 'package:tgi_video_editor/core/commands/timeline_time_map.dart';
import 'package:tgi_video_editor/core/commands/cut_range_policy.dart';
import 'package:tgi_video_editor/domain/models/track.dart';
import 'support/silence_project.dart';

void main() {
  test(
    'normal preserves previous detection defaults and explicit values override presets',
    () {
      final normal = SilenceOptions({});
      expect(
        (normal.thresholdDb, normal.minimum, normal.padding),
        (-35, .5, .08),
      );
      expect(normal.minKeepMs, 250);
      final explicit = SilenceOptions({
        'mode': 'suave',
        'threshold_db': -32,
        'minimum': .9,
        'padding': .2,
      });
      expect(
        (explicit.thresholdDb, explicit.minimum, explicit.padding),
        (-32, .9, .2),
      );
    },
  );
  test(
    'tiny keeps merge by restoring the nearest gap, including edges and a sole keep',
    () {
      final original = TimelineTimeMap([
        (1000000, 2000000),
        (2100000, 3000000),
      ], end: 4000000);
      expect(mergeShortKeeps(original, 250000).removed, [(1000000, 2000000)]);
      expect(identical(mergeShortKeeps(original, 0), original), true);
      final edge = TimelineTimeMap([(100000, 1000000)], end: 2000000);
      expect(mergeShortKeeps(edge, 250000).removed, isEmpty);
      final sole = TimelineTimeMap([
        (0, 1000000),
        (1100000, 2000000),
      ], end: 2000000);
      expect(
        mergeShortKeeps(
          sole,
          250000,
        ).retained.every((r) => r.$2 - r.$1 >= 250000),
        true,
      );
    },
  );
  for (final mode in SilenceOptions.presets.keys) {
    test(
      '$mode: 132 clips, words, captions, overlaps, duration and minimum-keep invariants',
      () {
        final p = layeredSilenceProject();
        final options = SilenceOptions({'mode': mode});
        final captions = p.tracks
            .expand((t) => t.clips)
            .where((c) => c.isCaption)
            .toList();
        final words = [
          for (final c in captions)
            (
              (c.timelineStart.inMicroseconds + 400000) / 1e6,
              (c.timelineStart.inMicroseconds + 700000) / 1e6,
            ),
        ];
        final ranges = protectCutRanges([
          for (final r in fixtureSilences)
            (r.$1 / 1e6 + options.padding, r.$2 / 1e6 - options.padding),
        ], words);
        final map = mergeShortKeeps(
          TimelineTimeMap([
            for (final r in ranges)
              ((r.$1 * 1e6).round(), (r.$2 * 1e6).round()),
          ], end: p.timelineDuration.inMicroseconds),
          options.minKeepMs * 1000,
        );
        final after = const TimelineRemapper()
            .apply(p, p.clipById('video')!, map, joinFadeMs: 8)
            .project;
        expect(
          after.timelineDuration.inMicroseconds,
          p.timelineDuration.inMicroseconds - map.removedDuration,
        );
        expect(map.retained.every((r) => r.$2 - r.$1 >= 250000), true);
        for (final track in after.tracks) {
          for (var i = 1; i < track.clips.length; i++) {
            expect(
              track.clips[i].timelineStart,
              greaterThanOrEqualTo(track.clips[i - 1].timelineEnd),
            );
          }
        }
        for (var i = 0; i < captions.length; i++) {
          final old = captions[i], next = after.clipById(old.id)!;
          final wordStart = map.map((words[i].$1 * 1e6).round());
          final wordEnd = map.map((words[i].$2 * 1e6).round());
          expect(
            wordEnd - wordStart,
            300000,
            reason: 'word duration remains intact',
          );
          expect(
            next.timelineStart.inMicroseconds,
            lessThanOrEqualTo(wordStart),
          );
          expect(
            next.timelineEnd.inMicroseconds,
            greaterThanOrEqualTo(wordEnd),
          );
          expect(
            (next.timelineStart.inMicroseconds -
                    map.map(old.timelineStart.inMicroseconds))
                .abs(),
            lessThanOrEqualTo(1000000 ~/ 30),
          );
        }
        final audio = after.tracks
            .expand((t) => t.clips)
            .where((c) => c.trackType == TrackType.audio);
        expect(audio.length, after.trackById('main')!.clips.length);
      },
    );
  }
}
