import 'dart:math' as math;

/// Interval subtraction in source seconds, before speed/reverse time mapping.
/// Protected ranges are retained, including words that straddle silence borders.
List<(double, double)> protectCutRanges(
  Iterable<(double, double)> ranges,
  Iterable<(double, double)> words, {
  double margin = .05,
}) {
  var result = ranges.where((r) => r.$2 > r.$1).toList();
  for (final word in words) {
    final a = word.$1 - margin, b = word.$2 + margin;
    result = [
      for (final range in result)
        if (range.$2 <= a || range.$1 >= b)
          range
        else ...[
          if (range.$1 < a) (range.$1, math.min(a, range.$2)),
          if (range.$2 > b) (math.max(b, range.$1), range.$2),
        ],
    ];
  }
  return result;
}
