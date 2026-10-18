import 'dart:math' as math;
import '../domain/models/clip.dart';

class SpeechInterval {
  const SpeechInterval(this.start, this.end);
  final Duration start;
  final Duration end;
}

List<ClipKeyframe> buildDuckingKeyframes(
  Clip music,
  List<SpeechInterval> speech, {
  double reductionDb = 12,
  Duration attack = const Duration(milliseconds: 150),
  Duration release = const Duration(milliseconds: 350),
}) {
  if (music.duration <= Duration.zero) return music.keyframes;
  final length = music.duration.inMicroseconds.toDouble();
  final attenuation = math.pow(10, -reductionDb.clamp(0, 36) / 20).toDouble();
  final merged = <SpeechInterval>[];
  final sorted = List<SpeechInterval>.of(speech)
    ..sort((a, b) => a.start.compareTo(b.start));
  for (final interval in sorted) {
    if (interval.end <= interval.start) continue;
    if (merged.isNotEmpty &&
        interval.start <= merged.last.end + const Duration(milliseconds: 300)) {
      final previous = merged.removeLast();
      merged.add(
        SpeechInterval(
          previous.start,
          interval.end > previous.end ? interval.end : previous.end,
        ),
      );
    } else {
      merged.add(interval);
    }
  }
  double normalized(Duration position) =>
      ((position - music.timelineStart).inMicroseconds / length).clamp(
        0.0,
        1.0,
      );
  final times = <double>{
    0,
    1,
    for (final k in music.keyframesFor(ClipKeyframeProperty.volume)) k.time,
    for (final interval in merged) ...[
      normalized(interval.start - attack),
      normalized(interval.start),
      normalized(interval.end),
      normalized(interval.end + release),
    ],
  }.toList()..sort();
  double duck(double t) {
    final position =
        music.timelineStart + Duration(microseconds: (t * length).round());
    var factor = 1.0;
    for (final interval in merged) {
      var strength = 0.0;
      if (position >= interval.start && position <= interval.end) {
        strength = 1;
      } else if (position < interval.start && attack > Duration.zero) {
        strength =
            (1 -
                    (interval.start - position).inMicroseconds /
                        attack.inMicroseconds)
                .clamp(0.0, 1.0);
      } else if (position > interval.end && release > Duration.zero) {
        strength =
            (1 -
                    (position - interval.end).inMicroseconds /
                        release.inMicroseconds)
                .clamp(0.0, 1.0);
      }
      factor = math.min(factor, 1 - strength * (1 - attenuation));
    }
    return factor;
  }

  return [
    for (final key in music.keyframes)
      if (key.property != ClipKeyframeProperty.volume) key,
    for (var i = 0; i < times.length; i++)
      ClipKeyframe(
        id: '${music.id}_duck_$i',
        property: ClipKeyframeProperty.volume,
        time: times[i],
        value:
            music.keyframedValue(ClipKeyframeProperty.volume, times[i]) *
            duck(times[i]),
      ),
  ];
}
