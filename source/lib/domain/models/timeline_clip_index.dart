import 'clip.dart';

/// Immutable interval index. Prefix maxima also support overlapping legacy
/// clips; binary searches do not assume that all old projects are collision free.
class TimelineClipIndex {
  TimelineClipIndex(Iterable<Clip> source) {
    clips = List.unmodifiable(
      source.toList()
        ..sort((a, b) => a.timelineStart.compareTo(b.timelineStart)),
    );
    var maximum = 0;
    for (final clip in clips) {
      if (clip.timelineEnd.inMicroseconds > maximum) {
        maximum = clip.timelineEnd.inMicroseconds;
      }
      _maximumEnds.add(maximum);
      _groups.putIfAbsent(clip.timelineGroupId, () => []).add(clip);
    }
  }

  late final List<Clip> clips;
  final _maximumEnds = <int>[];
  final _groups = <String, List<Clip>>{};

  Iterable<Clip> group(String id) => _groups[id] ?? const [];

  Iterable<Clip> intersecting(Duration start, Duration end) sync* {
    if (end <= start || clips.isEmpty) return;
    final lower = start.inMicroseconds;
    final upper = end.inMicroseconds;
    var left = 0;
    var right = clips.length;
    while (left < right) {
      final middle = (left + right) >> 1;
      if (_maximumEnds[middle] <= lower) {
        left = middle + 1;
      } else {
        right = middle;
      }
    }
    for (var index = left; index < clips.length; index++) {
      final clip = clips[index];
      if (clip.timelineStart.inMicroseconds >= upper) break;
      if (clip.timelineEnd.inMicroseconds > lower) yield clip;
    }
  }
}
