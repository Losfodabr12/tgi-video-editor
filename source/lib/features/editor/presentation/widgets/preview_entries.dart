import '../../../../domain/models/clip.dart';
import '../../../../domain/models/media_item.dart';
import '../../../../domain/models/timeline_transition.dart';

class ImageOverlayEntry {
  const ImageOverlayEntry({
    required this.item,
    required this.clipId,
    required this.overlayX,
    required this.overlayY,
    required this.overlayScale,
    required this.imageFit,
    required this.opacity,
    required this.isActive,
    required this.timelineGroupId,
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
  });

  final MediaItem item;
  final String clipId;
  final double overlayX;
  final double overlayY;
  final double overlayScale;
  final ImageClipFit imageFit;
  final double opacity;
  final bool isActive;
  final String timelineGroupId;
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
}

class VideoOverlayEntry {
  const VideoOverlayEntry({
    required this.item,
    required this.clipId,
    required this.timelineGroupId,
    required this.sourcePosition,
    required this.playbackSpeed,
    required this.overlayX,
    required this.overlayY,
    required this.overlayScale,
    required this.opacity,
    required this.isActive,
    required this.visualAdjustments,
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
    this.maskToolActive = false,
  });

  final MediaItem item;
  final String clipId;
  final String timelineGroupId;
  final Duration sourcePosition;
  final double playbackSpeed;
  final double overlayX;
  final double overlayY;
  final double overlayScale;
  final double opacity;
  final bool isActive;
  final VideoPreviewVisualAdjustments visualAdjustments;
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
  final bool maskToolActive;
}

class TextOverlayEntry {
  const TextOverlayEntry({
    required this.clipId,
    required this.timelineGroupId,
    required this.text,
    required this.fontFamily,
    required this.overlayX,
    required this.overlayY,
    required this.fontSize,
    required this.textColor,
    required this.backgroundColor,
    required this.opacity,
    required this.animation,
    required this.animationProgress,
    required this.isActive,
  });

  final String clipId;
  final String timelineGroupId;
  final String text;
  final String fontFamily;
  final double overlayX;
  final double overlayY;
  final double fontSize;
  final int textColor;
  final int backgroundColor;
  final double opacity;
  final TextClipAnimation animation;
  final double animationProgress;
  final bool isActive;
}

class AudioPreviewEntry {
  const AudioPreviewEntry({
    required this.clipId,
    required this.item,
    required this.sourcePosition,
    required this.volume,
    required this.playbackSpeed,
  });

  final String clipId;
  final MediaItem item;
  final Duration sourcePosition;
  final double volume;
  final double playbackSpeed;
}

class VideoPreviewPreloadEntry {
  const VideoPreviewPreloadEntry({
    required this.clipId,
    required this.item,
    required this.sourcePosition,
    required this.timelineStart,
    required this.playbackSpeed,
  });

  final String clipId;
  final MediaItem item;
  final Duration sourcePosition;
  final Duration timelineStart;
  final double playbackSpeed;
}

class VideoColorAnalysis {
  const VideoColorAnalysis({
    required this.luma,
    required this.red,
    required this.green,
    required this.blue,
    required this.averageColor,
  });

  final List<double> luma;
  final List<double> red;
  final List<double> green;
  final List<double> blue;
  final int averageColor;
}

class VideoPreviewVisualAdjustments {
  const VideoPreviewVisualAdjustments({
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
    this.kenBurnsEnabled = false,
    this.kenBurnsStart = 0,
    this.kenBurnsEnd = 1,
    this.startOverlayX = 0.5,
    this.startOverlayY = 0.5,
    this.startOverlayScale = 1,
    this.endOverlayX = 0.5,
    this.endOverlayY = 0.5,
    this.endOverlayScale = 1,
    this.timelineStart = Duration.zero,
    this.duration = Duration.zero,
  });

  factory VideoPreviewVisualAdjustments.fromClip(Clip? clip) {
    if (clip == null) {
      return const VideoPreviewVisualAdjustments();
    }
    return VideoPreviewVisualAdjustments(
      brightness: clip.brightness,
      contrast: clip.contrast,
      saturation: clip.saturation,
      exposure: clip.exposure,
      hue: clip.hue,
      temperature: clip.temperature,
      tint: clip.tint,
      shadows: clip.shadows,
      highlights: clip.highlights,
      curveShadows: clip.curveShadows,
      curveMidtones: clip.curveMidtones,
      curveHighlights: clip.curveHighlights,
      filterPreset: clip.filterPreset,
      reverseVideo: clip.reverseVideo,
      chromaKeyEnabled: clip.chromaKeyEnabled,
      chromaKeyColor: clip.chromaKeyColor,
      chromaKeySimilarity: clip.chromaKeySimilarity,
      chromaKeyBlend: clip.chromaKeyBlend,
      cropLeft: clip.cropLeft,
      cropTop: clip.cropTop,
      cropRight: clip.cropRight,
      cropBottom: clip.cropBottom,
      transformOffsetX: clip.transformOffsetX,
      transformOffsetY: clip.transformOffsetY,
      transformScale: clip.transformScale,
      rotationDegrees: clip.rotationDegrees,
      flipHorizontal: clip.flipHorizontal,
      flipVertical: clip.flipVertical,
      kenBurnsEnabled: clip.kenBurnsEnabled,
      kenBurnsStart: clip.kenBurnsStart,
      kenBurnsEnd: clip.kenBurnsEnd,
      startOverlayX: clip.startOverlayX,
      startOverlayY: clip.startOverlayY,
      startOverlayScale: clip.startOverlayScale,
      endOverlayX: clip.overlayX,
      endOverlayY: clip.overlayY,
      endOverlayScale: clip.overlayScale,
      timelineStart: clip.timelineStart,
      duration: clip.duration,
    );
  }

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
  final bool kenBurnsEnabled;
  final double kenBurnsStart;
  final double kenBurnsEnd;
  final double startOverlayX;
  final double startOverlayY;
  final double startOverlayScale;
  final double endOverlayX;
  final double endOverlayY;
  final double endOverlayScale;
  final Duration timelineStart;
  final Duration duration;

  VideoPreviewVisualAdjustments copyWith({
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
    bool? kenBurnsEnabled,
    double? kenBurnsStart,
    double? kenBurnsEnd,
    double? startOverlayX,
    double? startOverlayY,
    double? startOverlayScale,
    double? endOverlayX,
    double? endOverlayY,
    double? endOverlayScale,
    Duration? timelineStart,
    Duration? duration,
  }) {
    return VideoPreviewVisualAdjustments(
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
      kenBurnsEnabled: kenBurnsEnabled ?? this.kenBurnsEnabled,
      kenBurnsStart: kenBurnsStart ?? this.kenBurnsStart,
      kenBurnsEnd: kenBurnsEnd ?? this.kenBurnsEnd,
      startOverlayX: startOverlayX ?? this.startOverlayX,
      startOverlayY: startOverlayY ?? this.startOverlayY,
      startOverlayScale: startOverlayScale ?? this.startOverlayScale,
      endOverlayX: endOverlayX ?? this.endOverlayX,
      endOverlayY: endOverlayY ?? this.endOverlayY,
      endOverlayScale: endOverlayScale ?? this.endOverlayScale,
      timelineStart: timelineStart ?? this.timelineStart,
      duration: duration ?? this.duration,
    );
  }

  bool get hasManualAdjustments =>
      brightness.abs() > 0.000001 ||
      (contrast - 1).abs() > 0.000001 ||
      (saturation - 1).abs() > 0.000001 ||
      exposure.abs() > 0.000001 ||
      hue.abs() > 0.000001 ||
      temperature.abs() > 0.000001 ||
      tint.abs() > 0.000001 ||
      shadows.abs() > 0.000001 ||
      highlights.abs() > 0.000001 ||
      curveShadows.abs() > 0.000001 ||
      curveMidtones.abs() > 0.000001 ||
      curveHighlights.abs() > 0.000001;

  bool get hasPreset => filterPreset != VideoFilterPreset.none;
  bool get hasCrop =>
      cropLeft.abs() > 0.000001 ||
      cropTop.abs() > 0.000001 ||
      cropRight.abs() > 0.000001 ||
      cropBottom.abs() > 0.000001;

  bool get hasAnyEffect =>
      hasManualAdjustments ||
      hasPreset ||
      reverseVideo ||
      chromaKeyEnabled ||
      hasCrop ||
      hasTransform ||
      kenBurnsEnabled;

  bool get hasTransform =>
      transformOffsetX.abs() > 0.000001 ||
      transformOffsetY.abs() > 0.000001 ||
      (transformScale - 1).abs() > 0.000001 ||
      rotationDegrees.abs() > 0.000001 ||
      flipHorizontal ||
      flipVertical;
}

class TransitionPreviewEntry {
  const TransitionPreviewEntry({
    required this.id,
    required this.name,
    required this.filePath,
    required this.sourcePosition,
    required this.timelinePosition,
    required this.duration,
    required this.blendMode,
    required this.placement,
    this.preset,
    this.opacityOverride,
    this.direction = TimelineTransitionDirection.leftToRight,
    this.color = 0xFF000000,
    this.intensity = 1,
  });

  final double? opacityOverride;
  final String id;
  final String name;
  final String filePath;
  final Duration sourcePosition;
  final Duration timelinePosition;
  final Duration duration;
  final TimelineTransitionBlendMode blendMode;
  final TimelineTransitionPlacement placement;
  final TimelineTransitionPreset? preset;
  final TimelineTransitionDirection direction;
  final int color;
  final double intensity;

  bool get isPreset => preset != null;
}
