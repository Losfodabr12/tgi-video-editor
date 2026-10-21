import 'dart:math' as math;
import '../core/commands/timeline_time_map.dart';
import '../domain/models/track.dart';

String cutTimestamp(int us) {
  final ms = us ~/ 1000;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(ms ~/ 3600000)}:${two(ms ~/ 60000 % 60)}:${two(ms ~/ 1000 % 60)}.${(ms % 1000).toString().padLeft(3, '0')}';
}

Map<String, Object?> cutPlanSummary(
  TimelineRemapResult result, {
  required int durationBeforeUs,
  required int joinFadeMs,
  required bool wordProtection,
}) {
  final map = result.timeMap;
  final lengths = map.retained.map((r) => r.$2 - r.$1).toList();
  final joins = map.removed
      .where((r) => r.$1 > 0 && r.$2 < map.end)
      .map((r) => map.map(r.$1))
      .toSet();
  final audio = result.project.tracks
      .where((t) => result.selection.tracks.contains(t.id))
      .expand((t) => t.clips)
      .where((c) => c.trackType == TrackType.audio);
  final faded = joins
      .where(
        (at) => audio.any(
          (c) =>
              (c.timelineStart.inMicroseconds == at &&
                  c.fadeIn > Duration.zero) ||
              (c.timelineEnd.inMicroseconds == at && c.fadeOut > Duration.zero),
        ),
      )
      .length;
  return {
    'cut_count': map.removed.length,
    'internal_join_count': joins.length,
    'seconds_removed': map.removedDuration / 1e6,
    'duration_before': durationBeforeUs / 1e6,
    'duration_after': result.project.timelineDuration.inMicroseconds / 1e6,
    'retained_segment_count': lengths.length,
    'shortest_keep_seconds': lengths.isEmpty
        ? 0.0
        : lengths.reduce(math.min) / 1e6,
    'longest_keep_seconds': lengths.isEmpty
        ? 0.0
        : lengths.reduce(math.max) / 1e6,
    'first_cuts': [
      for (final r in map.removed.take(10))
        {
          'old_start': r.$1 / 1e6,
          'old_end': r.$2 / 1e6,
          'new_time': map.map(r.$1) / 1e6,
          'old_start_timestamp': cutTimestamp(r.$1),
          'old_end_timestamp': cutTimestamp(r.$2),
          'new_timestamp': cutTimestamp(map.map(r.$1)),
        },
    ],
    'word_protection_active': wordProtection,
    'join_fade_ms': joinFadeMs,
    'join_fade_active': joinFadeMs > 0 && faded > 0,
    'faded_audio_join_count': joinFadeMs > 0 ? faded : 0,
  };
}
