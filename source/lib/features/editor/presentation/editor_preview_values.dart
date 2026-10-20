import '../../../domain/models/clip.dart' as domain;
import 'widgets/preview_entries.dart';

/// Preview parameter evaluation, independent of widget state and lifecycle.
class EditorPreviewValues {
  const EditorPreviewValues({
    required this.position,
    required this.fadeOpacity,
  });
  final Duration position;
  final double Function(domain.Clip) fadeOpacity;
  VideoPreviewVisualAdjustments visualAdjustmentsForClip(domain.Clip? clip) {
    final base = VideoPreviewVisualAdjustments.fromClip(clip);
    if (clip == null || !clip.hasKeyframes) {
      return base;
    }
    final time = previewClipTime(clip);
    final hasCameraKeyframes =
        clip.hasKeyframesFor(domain.ClipKeyframeProperty.overlayX) ||
        clip.hasKeyframesFor(domain.ClipKeyframeProperty.overlayY) ||
        clip.hasKeyframesFor(domain.ClipKeyframeProperty.overlayScale);
    final cameraX = previewKeyframedValue(
      clip,
      domain.ClipKeyframeProperty.overlayX,
    );
    final cameraY = previewKeyframedValue(
      clip,
      domain.ClipKeyframeProperty.overlayY,
    );
    final cameraScale = previewKeyframedValue(
      clip,
      domain.ClipKeyframeProperty.overlayScale,
    );
    return base.copyWith(
      brightness: clip.keyframedValue(
        domain.ClipKeyframeProperty.brightness,
        time,
      ),
      contrast: clip.keyframedValue(domain.ClipKeyframeProperty.contrast, time),
      saturation: clip.keyframedValue(
        domain.ClipKeyframeProperty.saturation,
        time,
      ),
      exposure: clip.keyframedValue(domain.ClipKeyframeProperty.exposure, time),
      hue: clip.keyframedValue(domain.ClipKeyframeProperty.hue, time),
      cropLeft: clip.keyframedValue(domain.ClipKeyframeProperty.cropLeft, time),
      cropTop: clip.keyframedValue(domain.ClipKeyframeProperty.cropTop, time),
      cropRight: clip.keyframedValue(
        domain.ClipKeyframeProperty.cropRight,
        time,
      ),
      cropBottom: clip.keyframedValue(
        domain.ClipKeyframeProperty.cropBottom,
        time,
      ),
      kenBurnsEnabled: base.kenBurnsEnabled || hasCameraKeyframes,
      startOverlayX: hasCameraKeyframes ? cameraX : base.startOverlayX,
      startOverlayY: hasCameraKeyframes ? cameraY : base.startOverlayY,
      startOverlayScale: hasCameraKeyframes
          ? cameraScale
          : base.startOverlayScale,
      endOverlayX: hasCameraKeyframes ? cameraX : base.endOverlayX,
      endOverlayY: hasCameraKeyframes ? cameraY : base.endOverlayY,
      endOverlayScale: hasCameraKeyframes ? cameraScale : base.endOverlayScale,
    );
  }

  double previewClipTime(domain.Clip clip) {
    if (clip.duration <= Duration.zero) {
      return 0;
    }
    final value =
        (position - clip.timelineStart).inMicroseconds /
        clip.duration.inMicroseconds;
    if (value.isNaN || value.isInfinite) {
      return 0;
    }
    return value.clamp(0.0, 1.0).toDouble();
  }

  double previewKeyframedValue(
    domain.Clip clip,
    domain.ClipKeyframeProperty property,
  ) {
    return clip.keyframedValue(property, previewClipTime(clip));
  }

  double previewOpacityForClip(domain.Clip clip) {
    return fadeOpacity(clip) *
        previewKeyframedValue(clip, domain.ClipKeyframeProperty.opacity);
  }

  double previewOverlayProgress(domain.Clip clip) {
    if (!clip.kenBurnsEnabled || clip.duration <= Duration.zero) {
      return 1;
    }
    final start =
        clip.timelineStart +
        Duration(
          microseconds: (clip.duration.inMicroseconds * clip.kenBurnsStart)
              .round(),
        );
    final end =
        clip.timelineStart +
        Duration(
          microseconds: (clip.duration.inMicroseconds * clip.kenBurnsEnd)
              .round(),
        );
    final span = end - start;
    if (span <= Duration.zero) {
      return 1;
    }
    final elapsed = (position - start).inMicroseconds / span.inMicroseconds;
    if (elapsed.isNaN || elapsed.isInfinite) {
      return 1;
    }
    return elapsed.clamp(0.0, 1.0).toDouble();
  }

  double previewOverlayX(domain.Clip clip) {
    if (clip.hasKeyframesFor(domain.ClipKeyframeProperty.overlayX)) {
      return previewKeyframedValue(clip, domain.ClipKeyframeProperty.overlayX);
    }
    final progress = previewOverlayProgress(clip);
    return clip.startOverlayX + (clip.overlayX - clip.startOverlayX) * progress;
  }

  double previewOverlayY(domain.Clip clip) {
    if (clip.hasKeyframesFor(domain.ClipKeyframeProperty.overlayY)) {
      return previewKeyframedValue(clip, domain.ClipKeyframeProperty.overlayY);
    }
    final progress = previewOverlayProgress(clip);
    return clip.startOverlayY + (clip.overlayY - clip.startOverlayY) * progress;
  }

  double previewOverlayScale(domain.Clip clip) {
    if (clip.hasKeyframesFor(domain.ClipKeyframeProperty.overlayScale)) {
      return previewKeyframedValue(
        clip,
        domain.ClipKeyframeProperty.overlayScale,
      );
    }
    final progress = previewOverlayProgress(clip);
    return clip.startOverlayScale +
        (clip.overlayScale - clip.startOverlayScale) * progress;
  }
}
