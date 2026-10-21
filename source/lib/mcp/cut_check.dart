import 'dart:math' as math;
import '../core/commands/editor_command.dart';
import '../core/commands/timeline_time_map.dart';
import '../domain/models/project.dart';
import '../domain/models/track.dart';
import 'editor_plans.dart';

class CutCheck {
  const CutCheck(this.project, this.windows, this.cutCount);
  final TgiProject project;
  final List<(int, int)> windows;
  final int cutCount;
}

/// Composition of the simulated snapshot. Original plan/project stay immutable.
/// Overlapping one-second windows merge, so close cuts aren't repeated.
CutCheck buildCutCheck(EditorPlan plan) {
  final summary = plan.effects['cut_summary'];
  if (summary is! Map ||
      summary['first_cuts'] is! List ||
      (summary['first_cuts'] as List).isEmpty) {
    throw const CommandError(
      'no_cuts',
      'Gere um plano de corte com emendas antes de export_cut_check.',
    );
  }
  final end = plan.after.timelineDuration.inMicroseconds;
  final raw = <(int, int)>[
    for (final cut in (summary['first_cuts'] as List).take(10))
      (
        math.max(0, ((cut['new_time'] as num) * 1e6).round() - 500000),
        math.min(end, ((cut['new_time'] as num) * 1e6).round() + 500000),
      ),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  final windows = <(int, int)>[];
  for (final r in raw.where((r) => r.$2 > r.$1)) {
    if (windows.isNotEmpty && r.$1 <= windows.last.$2) {
      windows[windows.length - 1] = (
        windows.last.$1,
        math.max(windows.last.$2, r.$2),
      );
    } else {
      windows.add(r);
    }
  }
  final anchor = plan.after.tracks
      .expand((t) => t.clips)
      .where(
        (c) => c.trackType == TrackType.video || c.trackType == TrackType.audio,
      )
      .firstOrNull;
  if (windows.isEmpty || anchor == null) {
    throw const CommandError(
      'no_cuts',
      'Não há mídia restante para ouvir os cortes.',
    );
  }
  final removed = <(int, int)>[];
  var cursor = 0;
  for (final w in windows) {
    if (w.$1 > cursor) removed.add((cursor, w.$1));
    cursor = w.$2;
  }
  if (cursor < end) removed.add((cursor, end));
  final snapshot = const TimelineRemapper()
      .apply(
        plan.after,
        anchor,
        TimelineTimeMap(removed, end: end),
        lockedTracks: 'unlock',
      )
      .project;
  return CutCheck(snapshot, List.unmodifiable(windows), raw.length);
}
