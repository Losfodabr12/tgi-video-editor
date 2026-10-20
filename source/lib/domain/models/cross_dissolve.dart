import 'clip.dart';
import 'project.dart';
import 'timeline_transition.dart';
import 'track.dart';

class CrossDissolve {
  const CrossDissolve({
    required this.transition,
    required this.left,
    required this.right,
    required this.duration,
  });
  final TimelineTransition transition;
  final Clip left, right;
  final Duration duration;
  Duration get boundary => right.timelineStart;
  Duration get incoming =>
      transition.placement == TimelineTransitionPlacement.start
      ? Duration.zero
      : Duration(microseconds: duration.inMicroseconds ~/ 2);
  Duration get outgoing => duration - incoming;
  Duration get start => boundary - incoming;
  Duration get end => boundary + outgoing;
  double progressAt(Duration position) =>
      ((position - start).inMicroseconds / duration.inMicroseconds).clamp(
        0.0,
        1.0,
      );

  static List<CrossDissolve> forProject(TgiProject project) {
    final result = <CrossDissolve>[];
    final used = <Duration>{};
    final transitions = [...project.transitions]
      ..sort((a, b) => a.timelinePosition.compareTo(b.timelinePosition));
    for (final transition in transitions) {
      if (transition.preset != TimelineTransitionPreset.dissolve ||
          transition.duration <= Duration.zero ||
          used.contains(transition.timelinePosition)) {
        continue;
      }
      for (final track in project.tracks.where(
        (t) => !t.isHidden && t.kind == TrackKind.visual,
      )) {
        final clips =
            track.clips
                .where(
                  (c) =>
                      c.trackType == TrackType.video &&
                      c.duration > Duration.zero,
                )
                .toList()
              ..sort((a, b) => a.timelineStart.compareTo(b.timelineStart));
        for (var i = 1; i < clips.length; i++) {
          final left = clips[i - 1], right = clips[i];
          if (left.timelineEnd != right.timelineStart ||
              right.timelineStart != transition.timelinePosition) {
            continue;
          }
          var duration = transition.duration;
          if (duration > left.duration) duration = left.duration;
          if (duration > right.duration) duration = right.duration;
          // Prevent neighboring windows from intersecting.
          if (result.isNotEmpty) {
            final space = right.timelineStart - result.last.end;
            if (duration > space) duration = space;
          }
          if (duration <= Duration.zero) continue;
          result.add(
            CrossDissolve(
              transition: transition,
              left: left,
              right: right,
              duration: duration,
            ),
          );
          used.add(right.timelineStart);
          break;
        }
        if (used.contains(transition.timelinePosition)) break;
      }
    }
    return result;
  }
}
