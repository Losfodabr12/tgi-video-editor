import 'dart:math' as math;
import 'dart:typed_data';

import 'ffmpeg_service.dart';

class MotionMaskTrackPoint {
  const MotionMaskTrackPoint({
    required this.time,
    required this.x,
    required this.y,
    required this.confidence,
  });

  final double time;
  final double x;
  final double y;
  final double confidence;
}

class MotionMaskTracker {
  const MotionMaskTracker();

  List<MotionMaskTrackPoint> track({
    required FfmpegGrayFrameBatch batch,
    required double seedTime,
    required double seedX,
    required double seedY,
    required double maskWidth,
    required double maskHeight,
    void Function(double progress)? onProgress,
  }) {
    final frames = batch.frames;
    if (frames.length < 2) return const [];
    final seedIndex = (seedTime.clamp(0.0, 1.0) * (frames.length - 1))
        .round()
        .clamp(0, frames.length - 1);
    final patchWidth = (batch.width * maskWidth.clamp(0.04, 0.8))
        .round()
        .clamp(10, math.max(10, batch.width ~/ 2))
        .toInt();
    final patchHeight = (batch.height * maskHeight.clamp(0.04, 0.8))
        .round()
        .clamp(8, math.max(8, batch.height ~/ 2))
        .toInt();
    final centers = List<({double x, double y, double confidence})?>.filled(
      frames.length,
      null,
    );
    centers[seedIndex] = (
      x: seedX.clamp(0.0, 1.0).toDouble(),
      y: seedY.clamp(0.0, 1.0).toDouble(),
      confidence: 1,
    );

    var completed = 0;
    final total = math.max(1, frames.length - 1);
    void trackDirection(int start, int end, int step) {
      var previousIndex = start;
      for (var index = start + step; index != end; index += step) {
        final previous = centers[previousIndex]!;
        final match = _matchNext(
          reference: frames[previousIndex],
          target: frames[index],
          frameWidth: batch.width,
          frameHeight: batch.height,
          centerX: previous.x,
          centerY: previous.y,
          patchWidth: patchWidth,
          patchHeight: patchHeight,
        );
        centers[index] = match;
        previousIndex = index;
        completed++;
        onProgress?.call(completed / total);
      }
    }

    trackDirection(seedIndex, frames.length, 1);
    trackDirection(seedIndex, -1, -1);
    onProgress?.call(1);
    return [
      for (var index = 0; index < centers.length; index++)
        if (centers[index] case final center?)
          MotionMaskTrackPoint(
            time: index / (centers.length - 1),
            x: center.x,
            y: center.y,
            confidence: center.confidence,
          ),
    ];
  }

  List<MotionMaskTrackPoint> simplify(
    List<MotionMaskTrackPoint> points, {
    int maximumPoints = 24,
    double tolerance = 0.006,
  }) {
    if (points.length <= 2) return points;
    final kept = <int>{0, points.length - 1};
    void simplifyRange(int start, int end) {
      if (end <= start + 1) return;
      final first = points[start];
      final last = points[end];
      var bestDistance = 0.0;
      var bestIndex = -1;
      for (var index = start + 1; index < end; index++) {
        final point = points[index];
        final span = last.time - first.time;
        final progress = span.abs() < 0.000001
            ? 0.0
            : (point.time - first.time) / span;
        final expectedX = first.x + (last.x - first.x) * progress;
        final expectedY = first.y + (last.y - first.y) * progress;
        final distance = math.sqrt(
          math.pow(point.x - expectedX, 2) + math.pow(point.y - expectedY, 2),
        );
        if (distance > bestDistance) {
          bestDistance = distance;
          bestIndex = index;
        }
      }
      if (bestIndex >= 0 && bestDistance > tolerance) {
        kept.add(bestIndex);
        simplifyRange(start, bestIndex);
        simplifyRange(bestIndex, end);
      }
    }

    simplifyRange(0, points.length - 1);
    var result = [for (final index in kept) points[index]]
      ..sort((a, b) => a.time.compareTo(b.time));
    if (result.length <= maximumPoints) return result;
    final reduced = <MotionMaskTrackPoint>[];
    for (var index = 0; index < maximumPoints; index++) {
      final sourceIndex = (index * (result.length - 1) / (maximumPoints - 1))
          .round();
      reduced.add(result[sourceIndex]);
    }
    return reduced;
  }

  ({double x, double y, double confidence}) _matchNext({
    required Uint8List reference,
    required Uint8List target,
    required int frameWidth,
    required int frameHeight,
    required double centerX,
    required double centerY,
    required int patchWidth,
    required int patchHeight,
  }) {
    final referenceX = (centerX * frameWidth).round();
    final referenceY = (centerY * frameHeight).round();
    final radius = math.max(8, math.min(22, math.min(patchWidth, patchHeight)));
    final sampleStep = math.max(1, math.max(patchWidth, patchHeight) ~/ 24);
    var bestScore = double.infinity;
    var bestX = referenceX;
    var bestY = referenceY;
    var sampleCount = 1;
    for (var dy = -radius; dy <= radius; dy += 2) {
      for (var dx = -radius; dx <= radius; dx += 2) {
        final candidateX = (referenceX + dx).clamp(
          patchWidth ~/ 2,
          frameWidth - (patchWidth + 1) ~/ 2,
        );
        final candidateY = (referenceY + dy).clamp(
          patchHeight ~/ 2,
          frameHeight - (patchHeight + 1) ~/ 2,
        );
        var score = 0.0;
        var samples = 0;
        for (
          var py = -patchHeight ~/ 2;
          py < patchHeight ~/ 2;
          py += sampleStep
        ) {
          final referenceRow = (referenceY + py).clamp(0, frameHeight - 1);
          final targetRow = (candidateY + py).clamp(0, frameHeight - 1);
          for (
            var px = -patchWidth ~/ 2;
            px < patchWidth ~/ 2;
            px += sampleStep
          ) {
            final referenceColumn = (referenceX + px).clamp(0, frameWidth - 1);
            final targetColumn = (candidateX + px).clamp(0, frameWidth - 1);
            score +=
                (reference[referenceRow * frameWidth + referenceColumn] -
                        target[targetRow * frameWidth + targetColumn])
                    .abs();
            samples++;
          }
        }
        if (score < bestScore) {
          bestScore = score;
          bestX = candidateX;
          bestY = candidateY;
          sampleCount = math.max(1, samples);
        }
      }
    }
    final confidence = (1 - bestScore / (sampleCount * 255))
        .clamp(0.0, 1.0)
        .toDouble();
    return (
      x: (bestX / frameWidth).clamp(0.0, 1.0).toDouble(),
      y: (bestY / frameHeight).clamp(0.0, 1.0).toDouble(),
      confidence: confidence,
    );
  }
}
