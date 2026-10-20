import 'dart:math' as math;

import 'duration_formatter.dart';

class TimelineRulerTick {
  const TimelineRulerTick(this.position, {required this.major});
  final Duration position;
  final bool major;
}

/// Chooses time intervals from pixel density, independent of project length.
/// Generates only the visible portion, including one label of overscan.
class TimelineRulerScale {
  TimelineRulerScale({required this.duration, required this.contentWidth}) {
    final targetMs = duration.inMilliseconds / math.max(1, contentWidth) * 96;
    final interval = _intervals.firstWhere(
      (pair) => pair.$1 >= targetMs,
      orElse: () => _intervals.last,
    );
    majorMilliseconds = interval.$1;
    minorMilliseconds = interval.$2;
    while (majorMilliseconds < targetMs) {
      majorMilliseconds *= 2;
      minorMilliseconds *= 2;
    }
  }

  final Duration duration;
  final double contentWidth;
  late int majorMilliseconds;
  late int minorMilliseconds;

  static const _intervals = <(int, int)>[
    (50, 10),
    (100, 20),
    (200, 50),
    (500, 100),
    (1000, 200),
    (2000, 500),
    (5000, 1000),
    (10000, 2000),
    (15000, 5000),
    (30000, 5000),
    (60000, 15000),
    (120000, 30000),
    (300000, 60000),
    (600000, 120000),
    (900000, 300000),
    (1800000, 300000),
    (3600000, 900000),
    (7200000, 1800000),
  ];

  List<TimelineRulerTick> visibleTicks({
    required double scrollOffset,
    required double viewportWidth,
  }) {
    if (duration <= Duration.zero || contentWidth <= 0 || viewportWidth <= 0) {
      return const [];
    }
    final millisecondsPerPixel = duration.inMilliseconds / contentWidth;
    final start = math.max(0.0, scrollOffset - 96) * millisecondsPerPixel;
    final end = math.min(
      duration.inMilliseconds.toDouble(),
      (scrollOffset + viewportWidth + 96) * millisecondsPerPixel,
    );
    final first = (start / minorMilliseconds).floor() * minorMilliseconds;
    return [
      for (var ms = first; ms <= end; ms += minorMilliseconds)
        TimelineRulerTick(
          Duration(milliseconds: ms),
          major: ms % majorMilliseconds == 0,
        ),
    ];
  }

  String label(Duration position) {
    final whole = formatDuration(position);
    if (majorMilliseconds >= 1000) return whole;
    final fraction = position.inMilliseconds
        .remainder(1000)
        .toString()
        .padLeft(3, '0');
    return '$whole.$fraction';
  }
}
