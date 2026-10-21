import 'editor_command.dart';
import 'timeline_time_map.dart';

class SilenceOptions {
  SilenceOptions(Map<String, Object?> args) {
    mode = args['mode'] as String? ?? 'normal';
    final preset = presets[mode];
    if (preset == null) {
      throw CommandError(
        'invalid_argument',
        'mode deve ser suave|normal|agressivo.',
        {'valid_modes': presets.keys.toList()},
      );
    }
    thresholdDb = (args['threshold_db'] as num?)?.toDouble() ?? preset.$1;
    minimum = (args['minimum'] as num?)?.toDouble() ?? preset.$2;
    padding = (args['padding'] as num?)?.toDouble() ?? preset.$3;
    minKeepMs = args['min_keep_ms'] as int? ?? 250;
    if (!thresholdDb.isFinite ||
        thresholdDb < -80 ||
        thresholdDb > 0 ||
        !minimum.isFinite ||
        minimum < .1 ||
        minimum > 10 ||
        !padding.isFinite ||
        padding < 0 ||
        padding > 1 ||
        minKeepMs < 0 ||
        minKeepMs > 10000) {
      throw const CommandError(
        'out_of_range',
        'Use threshold_db -80..0, minimum 0.1..10, padding 0..1 e min_keep_ms 0..10000.',
      );
    }
  }
  static const presets = <String, (double, double, double)>{
    'suave': (-40, .7, .14),
    'normal': (-35, .5, .08),
    'agressivo': (-30, .3, .04),
  };
  late final String mode;
  late final double thresholdDb, minimum, padding;
  late final int minKeepMs;
  Map<String, Object?> toJson() => {
    'mode': mode,
    'threshold_db': thresholdDb,
    'minimum': minimum,
    'padding': padding,
    'min_keep_ms': minKeepMs,
  };
}

/// Rejoins a tiny keep to its nearest neighbour by restoring the intervening
/// removal, never by deleting speech. Ties prefer the preceding neighbour.
TimelineTimeMap mergeShortKeeps(TimelineTimeMap map, int minimumUs) {
  if (minimumUs <= 0) return map;
  while (map.removed.isNotEmpty) {
    final short = map.retained.indexWhere((r) => r.$2 - r.$1 < minimumUs);
    if (short < 0) break;
    final keep = map.retained[short];
    final left = map.removed.indexWhere((r) => r.$2 == keep.$1);
    final right = map.removed.indexWhere((r) => r.$1 == keep.$2);
    if (left < 0 && right < 0) break;
    final remove = left < 0
        ? right
        : right < 0
        ? left
        : (map.removed[left].$2 - map.removed[left].$1 <=
                  map.removed[right].$2 - map.removed[right].$1
              ? left
              : right);
    map = TimelineTimeMap([
      for (var i = 0; i < map.removed.length; i++)
        if (i != remove) map.removed[i],
    ], end: map.end);
  }
  return map;
}
