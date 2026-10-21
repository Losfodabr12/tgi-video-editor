import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/core/commands/timeline_time_map.dart';
import 'package:tgi_video_editor/mcp/cut_plan_summary.dart';
import 'support/silence_project.dart';

void main() {
  test(
    'summary measures effective cuts, complete durations, timestamped first ten and active audio fade',
    () {
      final p = silenceProject(duration: 30);
      final map = TimelineTimeMap([
        for (var i = 0; i < 12; i++)
          (1000000 + i * 2000000, 1500000 + i * 2000000),
      ], end: 30000000);
      final result = const TimelineRemapper().apply(
        p,
        p.clipById('video')!,
        map,
        joinFadeMs: 8,
      );
      final summary = cutPlanSummary(
        result,
        durationBeforeUs: 30000000,
        joinFadeMs: 8,
        wordProtection: true,
      );
      expect(summary, containsPair('cut_count', 12));
      expect(summary, containsPair('seconds_removed', 6.0));
      expect(summary, containsPair('duration_before', 30.0));
      expect(summary, containsPair('duration_after', 24.0));
      expect(summary, containsPair('shortest_keep_seconds', 1.0));
      expect(summary, containsPair('longest_keep_seconds', 6.5));
      expect(summary, containsPair('join_fade_active', true));
      expect(summary, containsPair('word_protection_active', true));
      expect(summary['first_cuts'], hasLength(10));
      final first = (summary['first_cuts'] as List).first as Map;
      expect(first['old_start_timestamp'], '00:00:01.000');
      expect(first['old_end_timestamp'], '00:00:01.500');
      expect(first['new_time'], 1.0);
      expect(cutTimestamp(3723123456), '01:02:03.123');
    },
  );
  test('no-op and video-only plans do not claim an active audio fade', () {
    final p = silenceProject(audio: false);
    final result = const TimelineRemapper().apply(
      p,
      p.clipById('video')!,
      TimelineTimeMap([], end: 10000000),
      joinFadeMs: 8,
    );
    final summary = cutPlanSummary(
      result,
      durationBeforeUs: 10000000,
      joinFadeMs: 8,
      wordProtection: false,
    );
    expect(summary['cut_count'], 0);
    expect(summary['first_cuts'], isEmpty);
    expect(summary['join_fade_active'], false);
    expect(summary['shortest_keep_seconds'], 10.0);
  });
}
