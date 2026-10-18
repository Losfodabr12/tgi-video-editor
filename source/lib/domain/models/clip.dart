import 'track.dart';

enum ImageClipFit { overlay, trackedOverlay, contain, cover }

enum TextClipAnimation { none, fade, rise, pop, slideLeft }

enum VideoFilterPreset { none, blackAndWhite, sepia, vintage, cinematic }

enum VideoMaskShape { rectangle, ellipse }

enum VideoMaskEffect { blur, pixelate, darken }

enum ClipKeyframeProperty {
  overlayX,
  overlayY,
  overlayScale,
  opacity,
  volume,
  brightness,
  contrast,
  saturation,
  exposure,
  hue,
  cropLeft,
  cropTop,
  cropRight,
  cropBottom,
  chromaKeySimilarity,
  chromaKeyBlend,
  maskX,
  maskY,
  maskWidth,
  maskHeight,
}

class ClipKeyframe {
  const ClipKeyframe({
    required this.id,
    required this.property,
    required this.time,
    required this.value,
  });

  final String id;
  final ClipKeyframeProperty property;
  final double time;
  final double value;

  ClipKeyframe copyWith({
    String? id,
    ClipKeyframeProperty? property,
    double? time,
    double? value,
  }) {
    return ClipKeyframe(
      id: id ?? this.id,
      property: property ?? this.property,
      time: time ?? this.time,
      value: value ?? this.value,
    );
  }
}

class Clip {
  const Clip({
    required this.id,
    required this.mediaItemId,
    required this.timelineGroupId,
    required this.trackType,
    required this.timelineStart,
    required this.sourceStart,
    required this.duration,
    this.sourceDuration,
    this.playbackSpeed = 1,
    this.overlayX = 1,
    this.overlayY = 0,
    this.overlayScale = 1,
    this.imageFit = ImageClipFit.overlay,
    this.volume = 1,
    this.textContent = '',
    this.isCaption = false,
    this.fontFamily = 'Arial',
    this.fontSize = 48,
    this.textColor = 0xFFFFFFFF,
    this.backgroundColor = 0x00000000,
    this.opacity = 1.0,
    this.textAnimation = TextClipAnimation.none,
    this.audioNoiseReductionDb = 0,
    this.fadeIn = Duration.zero,
    this.fadeOut = Duration.zero,
    this.brightness = 0,
    this.contrast = 1,
    this.saturation = 1,
    this.exposure = 0,
    this.hue = 0,
    this.temperature = 0,
    this.tint = 0,
    this.shadows = 0,
    this.highlights = 0,
    this.curveShadows = 0,
    this.curveMidtones = 0,
    this.curveHighlights = 0,
    this.filterPreset = VideoFilterPreset.none,
    this.reverseVideo = false,
    this.chromaKeyEnabled = false,
    this.chromaKeyColor = 0xFF00FF00,
    this.chromaKeySimilarity = 0.3,
    this.chromaKeyBlend = 0.1,
    this.startOverlayX = 1,
    this.startOverlayY = 0,
    this.startOverlayScale = 1,
    this.kenBurnsEnabled = false,
    this.kenBurnsStart = 0,
    this.kenBurnsEnd = 1,
    this.cropLeft = 0,
    this.cropTop = 0,
    this.cropRight = 0,
    this.cropBottom = 0,
    this.transformOffsetX = 0,
    this.transformOffsetY = 0,
    this.transformScale = 1,
    this.rotationDegrees = 0,
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.stabilizationEnabled = false,
    this.maskEnabled = false,
    this.maskShape = VideoMaskShape.ellipse,
    this.maskEffect = VideoMaskEffect.blur,
    this.maskX = 0.5,
    this.maskY = 0.5,
    this.maskWidth = 0.32,
    this.maskHeight = 0.32,
    this.maskFeather = 0.08,
    this.maskIntensity = 0.7,
    this.maskInverted = false,
    this.keyframes = const [],
  });

  final String id;
  final String mediaItemId;
  final String timelineGroupId;
  final TrackType trackType;
  final Duration timelineStart;
  final Duration sourceStart;
  final Duration duration;
  final Duration? sourceDuration;
  final double playbackSpeed;
  final double overlayX;
  final double overlayY;
  final double overlayScale;
  final ImageClipFit imageFit;
  final double volume;
  final String textContent;
  final bool isCaption;
  final String fontFamily;
  final double fontSize;
  final int textColor;
  final int backgroundColor;
  final double opacity;
  final TextClipAnimation textAnimation;
  final double audioNoiseReductionDb;
  final Duration fadeIn;
  final Duration fadeOut;
  final double brightness;
  final double contrast;
  final double saturation;
  final double exposure;
  final double hue;
  final double temperature;
  final double tint;
  final double shadows;
  final double highlights;
  final double curveShadows;
  final double curveMidtones;
  final double curveHighlights;
  final VideoFilterPreset filterPreset;
  final bool reverseVideo;
  final bool chromaKeyEnabled;
  final int chromaKeyColor;
  final double chromaKeySimilarity;
  final double chromaKeyBlend;
  final double startOverlayX;
  final double startOverlayY;
  final double startOverlayScale;
  final bool kenBurnsEnabled;
  final double kenBurnsStart;
  final double kenBurnsEnd;
  final double cropLeft;
  final double cropTop;
  final double cropRight;
  final double cropBottom;
  final double transformOffsetX;
  final double transformOffsetY;
  final double transformScale;
  final double rotationDegrees;
  final bool flipHorizontal;
  final bool flipVertical;
  final bool stabilizationEnabled;
  final bool maskEnabled;
  final VideoMaskShape maskShape;
  final VideoMaskEffect maskEffect;
  final double maskX;
  final double maskY;
  final double maskWidth;
  final double maskHeight;
  final double maskFeather;
  final double maskIntensity;
  final bool maskInverted;
  final List<ClipKeyframe> keyframes;

  Duration get timelineEnd => timelineStart + duration;
  Duration get effectiveSourceDuration => sourceDuration ?? duration;
  Duration get sourceEnd => sourceStart + effectiveSourceDuration;
  bool get hasKeyframes => keyframes.isNotEmpty;

  List<ClipKeyframe> keyframesFor(ClipKeyframeProperty property) {
    return [
      for (final keyframe in keyframes)
        if (keyframe.property == property) keyframe,
    ]..sort((a, b) => a.time.compareTo(b.time));
  }

  bool hasKeyframesFor(ClipKeyframeProperty property) {
    return keyframes.any((keyframe) => keyframe.property == property);
  }

  double baseValueForKeyframeProperty(ClipKeyframeProperty property) {
    switch (property) {
      case ClipKeyframeProperty.overlayX:
        return overlayX;
      case ClipKeyframeProperty.overlayY:
        return overlayY;
      case ClipKeyframeProperty.overlayScale:
        return overlayScale;
      case ClipKeyframeProperty.opacity:
        return opacity;
      case ClipKeyframeProperty.volume:
        return volume;
      case ClipKeyframeProperty.brightness:
        return brightness;
      case ClipKeyframeProperty.contrast:
        return contrast;
      case ClipKeyframeProperty.saturation:
        return saturation;
      case ClipKeyframeProperty.exposure:
        return exposure;
      case ClipKeyframeProperty.hue:
        return hue;
      case ClipKeyframeProperty.cropLeft:
        return cropLeft;
      case ClipKeyframeProperty.cropTop:
        return cropTop;
      case ClipKeyframeProperty.cropRight:
        return cropRight;
      case ClipKeyframeProperty.cropBottom:
        return cropBottom;
      case ClipKeyframeProperty.chromaKeySimilarity:
        return chromaKeySimilarity;
      case ClipKeyframeProperty.chromaKeyBlend:
        return chromaKeyBlend;
      case ClipKeyframeProperty.maskX:
        return maskX;
      case ClipKeyframeProperty.maskY:
        return maskY;
      case ClipKeyframeProperty.maskWidth:
        return maskWidth;
      case ClipKeyframeProperty.maskHeight:
        return maskHeight;
    }
  }

  double keyframedValue(ClipKeyframeProperty property, double normalizedTime) {
    final frames = keyframesFor(property);
    if (frames.isEmpty) {
      return baseValueForKeyframeProperty(property);
    }
    final safeTime = _clampUnit(normalizedTime);
    if (safeTime <= frames.first.time) {
      return frames.first.value;
    }
    if (safeTime >= frames.last.time) {
      return frames.last.value;
    }
    for (var index = 0; index < frames.length - 1; index++) {
      final start = frames[index];
      final end = frames[index + 1];
      if (safeTime < start.time || safeTime > end.time) {
        continue;
      }
      final span = end.time - start.time;
      if (span.abs() <= 0.000001) {
        return end.value;
      }
      final progress = ((safeTime - start.time) / span).clamp(0.0, 1.0);
      return start.value + (end.value - start.value) * progress;
    }
    return frames.last.value;
  }

  Clip copyWith({
    String? id,
    String? mediaItemId,
    String? timelineGroupId,
    TrackType? trackType,
    Duration? timelineStart,
    Duration? sourceStart,
    Duration? duration,
    Duration? sourceDuration,
    double? playbackSpeed,
    double? overlayX,
    double? overlayY,
    double? overlayScale,
    ImageClipFit? imageFit,
    double? volume,
    String? textContent,
    bool? isCaption,
    String? fontFamily,
    double? fontSize,
    int? textColor,
    int? backgroundColor,
    double? opacity,
    TextClipAnimation? textAnimation,
    double? audioNoiseReductionDb,
    Duration? fadeIn,
    Duration? fadeOut,
    double? brightness,
    double? contrast,
    double? saturation,
    double? exposure,
    double? hue,
    double? temperature,
    double? tint,
    double? shadows,
    double? highlights,
    double? curveShadows,
    double? curveMidtones,
    double? curveHighlights,
    VideoFilterPreset? filterPreset,
    bool? reverseVideo,
    bool? chromaKeyEnabled,
    int? chromaKeyColor,
    double? chromaKeySimilarity,
    double? chromaKeyBlend,
    double? startOverlayX,
    double? startOverlayY,
    double? startOverlayScale,
    bool? kenBurnsEnabled,
    double? kenBurnsStart,
    double? kenBurnsEnd,
    double? cropLeft,
    double? cropTop,
    double? cropRight,
    double? cropBottom,
    double? transformOffsetX,
    double? transformOffsetY,
    double? transformScale,
    double? rotationDegrees,
    bool? flipHorizontal,
    bool? flipVertical,
    bool? stabilizationEnabled,
    bool? maskEnabled,
    VideoMaskShape? maskShape,
    VideoMaskEffect? maskEffect,
    double? maskX,
    double? maskY,
    double? maskWidth,
    double? maskHeight,
    double? maskFeather,
    double? maskIntensity,
    bool? maskInverted,
    List<ClipKeyframe>? keyframes,
  }) {
    return Clip(
      id: id ?? this.id,
      mediaItemId: mediaItemId ?? this.mediaItemId,
      timelineGroupId: timelineGroupId ?? this.timelineGroupId,
      trackType: trackType ?? this.trackType,
      timelineStart: timelineStart ?? this.timelineStart,
      sourceStart: sourceStart ?? this.sourceStart,
      duration: duration ?? this.duration,
      sourceDuration: sourceDuration ?? this.sourceDuration,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      overlayX: overlayX ?? this.overlayX,
      overlayY: overlayY ?? this.overlayY,
      overlayScale: overlayScale ?? this.overlayScale,
      imageFit: imageFit ?? this.imageFit,
      volume: volume ?? this.volume,
      textContent: textContent ?? this.textContent,
      isCaption: isCaption ?? this.isCaption,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      textColor: textColor ?? this.textColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      opacity: opacity ?? this.opacity,
      textAnimation: textAnimation ?? this.textAnimation,
      audioNoiseReductionDb:
          audioNoiseReductionDb ?? this.audioNoiseReductionDb,
      fadeIn: fadeIn ?? this.fadeIn,
      fadeOut: fadeOut ?? this.fadeOut,
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      exposure: exposure ?? this.exposure,
      hue: hue ?? this.hue,
      temperature: temperature ?? this.temperature,
      tint: tint ?? this.tint,
      shadows: shadows ?? this.shadows,
      highlights: highlights ?? this.highlights,
      curveShadows: curveShadows ?? this.curveShadows,
      curveMidtones: curveMidtones ?? this.curveMidtones,
      curveHighlights: curveHighlights ?? this.curveHighlights,
      filterPreset: filterPreset ?? this.filterPreset,
      reverseVideo: reverseVideo ?? this.reverseVideo,
      chromaKeyEnabled: chromaKeyEnabled ?? this.chromaKeyEnabled,
      chromaKeyColor: chromaKeyColor ?? this.chromaKeyColor,
      chromaKeySimilarity: chromaKeySimilarity ?? this.chromaKeySimilarity,
      chromaKeyBlend: chromaKeyBlend ?? this.chromaKeyBlend,
      startOverlayX: startOverlayX ?? this.startOverlayX,
      startOverlayY: startOverlayY ?? this.startOverlayY,
      startOverlayScale: startOverlayScale ?? this.startOverlayScale,
      kenBurnsEnabled: kenBurnsEnabled ?? this.kenBurnsEnabled,
      kenBurnsStart: kenBurnsStart ?? this.kenBurnsStart,
      kenBurnsEnd: kenBurnsEnd ?? this.kenBurnsEnd,
      cropLeft: cropLeft ?? this.cropLeft,
      cropTop: cropTop ?? this.cropTop,
      cropRight: cropRight ?? this.cropRight,
      cropBottom: cropBottom ?? this.cropBottom,
      transformOffsetX: transformOffsetX ?? this.transformOffsetX,
      transformOffsetY: transformOffsetY ?? this.transformOffsetY,
      transformScale: transformScale ?? this.transformScale,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      flipHorizontal: flipHorizontal ?? this.flipHorizontal,
      flipVertical: flipVertical ?? this.flipVertical,
      stabilizationEnabled: stabilizationEnabled ?? this.stabilizationEnabled,
      maskEnabled: maskEnabled ?? this.maskEnabled,
      maskShape: maskShape ?? this.maskShape,
      maskEffect: maskEffect ?? this.maskEffect,
      maskX: maskX ?? this.maskX,
      maskY: maskY ?? this.maskY,
      maskWidth: maskWidth ?? this.maskWidth,
      maskHeight: maskHeight ?? this.maskHeight,
      maskFeather: maskFeather ?? this.maskFeather,
      maskIntensity: maskIntensity ?? this.maskIntensity,
      maskInverted: maskInverted ?? this.maskInverted,
      keyframes: keyframes ?? this.keyframes,
    );
  }
}

double _clampUnit(double value) {
  if (value.isNaN || value.isInfinite) {
    return 0;
  }
  return value.clamp(0.0, 1.0).toDouble();
}
