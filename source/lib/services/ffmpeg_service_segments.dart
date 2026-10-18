part of 'ffmpeg_service.dart';

class _ExportWindow {
  const _ExportWindow({
    required this.timelineStart,
    required this.outputStart,
    required this.duration,
  });

  final Duration timelineStart;
  final Duration outputStart;
  final Duration duration;

  Duration get timelineEnd => timelineStart + duration;
}

class _ExportSegment {
  const _ExportSegment({
    required this.filePath,
    required this.timelineGroupId,
    required this.timelineStart,
    required this.outputStart,
    required this.videoSourceStart,
    required this.audioSourceStart,
    required this.videoSourceDuration,
    required this.audioSourceDuration,
    required this.duration,
    required this.playbackSpeed,
    required this.volume,
    required this.audioNoiseReductionDb,
    required this.hasSourceAudio,
    required this.videoFadeIn,
    required this.videoFadeOut,
    required this.audioFadeIn,
    required this.audioFadeOut,
    required this.brightness,
    required this.contrast,
    required this.saturation,
    required this.exposure,
    required this.hue,
    required this.temperature,
    required this.tint,
    required this.shadows,
    required this.highlights,
    required this.curveShadows,
    required this.curveMidtones,
    required this.curveHighlights,
    required this.filterPreset,
    required this.reverseVideo,
    required this.overlayX,
    required this.overlayY,
    required this.overlayScale,
    required this.opacity,
    required this.startOverlayX,
    required this.startOverlayY,
    required this.startOverlayScale,
    required this.kenBurnsEnabled,
    required this.kenBurnsStart,
    required this.kenBurnsEnd,
    required this.chromaKeyEnabled,
    required this.chromaKeyColor,
    required this.chromaKeySimilarity,
    required this.chromaKeyBlend,
    required this.maskEnabled,
    required this.maskShape,
    required this.maskEffect,
    required this.maskX,
    required this.maskY,
    required this.maskWidth,
    required this.maskHeight,
    required this.maskFeather,
    required this.maskIntensity,
    required this.maskInverted,
    required this.cropLeft,
    required this.cropTop,
    required this.cropRight,
    required this.cropBottom,
    required this.transformOffsetX,
    required this.transformOffsetY,
    required this.transformScale,
    required this.rotationDegrees,
    required this.flipHorizontal,
    required this.flipVertical,
    required this.videoKeyframes,
    required this.audioKeyframes,
  });

  const _ExportSegment.gap({
    required this.timelineStart,
    required this.outputStart,
    required this.duration,
  }) : filePath = null,
       timelineGroupId = null,
       videoSourceStart = Duration.zero,
       audioSourceStart = Duration.zero,
       videoSourceDuration = Duration.zero,
       audioSourceDuration = Duration.zero,
       playbackSpeed = 1,
       volume = 0,
       audioNoiseReductionDb = 0,
       hasSourceAudio = false,
       videoFadeIn = Duration.zero,
       videoFadeOut = Duration.zero,
       audioFadeIn = Duration.zero,
       audioFadeOut = Duration.zero,
       brightness = 0,
       contrast = 1,
       saturation = 1,
       exposure = 0,
       hue = 0,
       temperature = 0,
       tint = 0,
       shadows = 0,
       highlights = 0,
       curveShadows = 0,
       curveMidtones = 0,
       curveHighlights = 0,
       filterPreset = VideoFilterPreset.none,
       reverseVideo = false,
       overlayX = 0.5,
       overlayY = 0.5,
       overlayScale = 1,
       opacity = 1,
       startOverlayX = 0.5,
       startOverlayY = 0.5,
       startOverlayScale = 1,
       kenBurnsEnabled = false,
       kenBurnsStart = 0,
       kenBurnsEnd = 1,
       chromaKeyEnabled = false,
       chromaKeyColor = 0xFF00FF00,
       chromaKeySimilarity = 0.3,
       chromaKeyBlend = 0.1,
       maskEnabled = false,
       maskShape = VideoMaskShape.ellipse,
       maskEffect = VideoMaskEffect.blur,
       maskX = 0.5,
       maskY = 0.5,
       maskWidth = 0.32,
       maskHeight = 0.32,
       maskFeather = 0.08,
       maskIntensity = 0.7,
       maskInverted = false,
       cropLeft = 0,
       cropTop = 0,
       cropRight = 0,
       cropBottom = 0,
       transformOffsetX = 0,
       transformOffsetY = 0,
       transformScale = 1,
       rotationDegrees = 0,
       flipHorizontal = false,
       flipVertical = false,
       videoKeyframes = const [],
       audioKeyframes = const [];

  final String? filePath;
  final String? timelineGroupId;
  final Duration timelineStart;
  final Duration outputStart;
  final Duration videoSourceStart;
  final Duration audioSourceStart;
  final Duration videoSourceDuration;
  final Duration audioSourceDuration;
  final Duration duration;
  final double playbackSpeed;
  final double volume;
  final double audioNoiseReductionDb;
  final bool hasSourceAudio;
  final Duration videoFadeIn;
  final Duration videoFadeOut;
  final Duration audioFadeIn;
  final Duration audioFadeOut;
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
  final double overlayX;
  final double overlayY;
  final double overlayScale;
  final double opacity;
  final double startOverlayX;
  final double startOverlayY;
  final double startOverlayScale;
  final bool kenBurnsEnabled;
  final double kenBurnsStart;
  final double kenBurnsEnd;
  final bool chromaKeyEnabled;
  final int chromaKeyColor;
  final double chromaKeySimilarity;
  final double chromaKeyBlend;
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
  final List<ClipKeyframe> videoKeyframes;
  final List<ClipKeyframe> audioKeyframes;

  bool get isGap => filePath == null;

  bool get usesSourceAudio =>
      !isGap &&
      hasSourceAudio &&
      audioSourceDuration > Duration.zero &&
      volume > 0;

  Duration get timelineEnd => timelineStart + duration;
}

class _VideoOverlaySegment {
  const _VideoOverlaySegment({
    required this.filePath,
    required this.outputStart,
    required this.sourceStart,
    required this.sourceDuration,
    required this.duration,
    required this.playbackSpeed,
    required this.overlayX,
    required this.overlayY,
    required this.overlayScale,
    required this.opacity,
    required this.brightness,
    required this.contrast,
    required this.saturation,
    required this.exposure,
    required this.hue,
    required this.temperature,
    required this.tint,
    required this.shadows,
    required this.highlights,
    required this.curveShadows,
    required this.curveMidtones,
    required this.curveHighlights,
    required this.filterPreset,
    required this.reverseVideo,
    required this.chromaKeyEnabled,
    required this.chromaKeyColor,
    required this.chromaKeySimilarity,
    required this.chromaKeyBlend,
    required this.maskEnabled,
    required this.maskShape,
    required this.maskEffect,
    required this.maskX,
    required this.maskY,
    required this.maskWidth,
    required this.maskHeight,
    required this.maskFeather,
    required this.maskIntensity,
    required this.maskInverted,
    required this.cropLeft,
    required this.cropTop,
    required this.cropRight,
    required this.cropBottom,
    required this.transformOffsetX,
    required this.transformOffsetY,
    required this.transformScale,
    required this.rotationDegrees,
    required this.flipHorizontal,
    required this.flipVertical,
    required this.startOverlayX,
    required this.startOverlayY,
    required this.startOverlayScale,
    required this.kenBurnsEnabled,
    required this.kenBurnsStart,
    required this.kenBurnsEnd,
    required this.keyframes,
  });

  final String filePath;
  final Duration outputStart;
  final Duration sourceStart;
  final Duration sourceDuration;
  final Duration duration;
  final double playbackSpeed;
  final double overlayX;
  final double overlayY;
  final double overlayScale;
  final double opacity;
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
  final double startOverlayX;
  final double startOverlayY;
  final double startOverlayScale;
  final bool kenBurnsEnabled;
  final double kenBurnsStart;
  final double kenBurnsEnd;
  final List<ClipKeyframe> keyframes;
}

class _AudioMixSegment {
  const _AudioMixSegment({
    required this.filePath,
    required this.timelineStart,
    required this.sourceStart,
    required this.sourceDuration,
    required this.duration,
    required this.playbackSpeed,
    required this.volume,
    required this.noiseReductionDb,
    required this.fadeIn,
    required this.fadeOut,
    required this.reverseAudio,
    required this.keyframes,
  });

  final String filePath;
  final Duration timelineStart;
  final Duration sourceStart;
  final Duration sourceDuration;
  final Duration duration;
  final double playbackSpeed;
  final double volume;
  final double noiseReductionDb;
  final Duration fadeIn;
  final Duration fadeOut;
  final bool reverseAudio;
  final List<ClipKeyframe> keyframes;
}

class _TextOverlaySegment {
  const _TextOverlaySegment({
    required this.text,
    required this.outputStart,
    required this.duration,
    required this.overlayX,
    required this.overlayY,
    required this.fontFamily,
    required this.fontSize,
    required this.textColor,
    required this.backgroundColor,
    required this.opacity,
    required this.animation,
    required this.keyframes,
  });

  final String text;
  final Duration outputStart;
  final Duration duration;
  final double overlayX;
  final double overlayY;
  final String fontFamily;
  final double fontSize;
  final int textColor;
  final int backgroundColor;
  final double opacity;
  final TextClipAnimation animation;
  final List<ClipKeyframe> keyframes;
}

class _TransitionOverlaySegment {
  const _TransitionOverlaySegment({
    required this.filePath,
    required this.outputStart,
    required this.sourceStart,
    required this.duration,
    required this.blendMode,
    required this.placement,
    this.preset,
    this.direction = TimelineTransitionDirection.leftToRight,
    this.color = 0xFF000000,
    this.intensity = 1,
  });

  final String filePath;
  final Duration outputStart;
  final Duration sourceStart;
  final Duration duration;
  final TimelineTransitionBlendMode blendMode;
  final TimelineTransitionPlacement placement;
  final TimelineTransitionPreset? preset;
  final TimelineTransitionDirection direction;
  final int color;
  final double intensity;
}

class _ImageOverlaySegment {
  const _ImageOverlaySegment({
    required this.filePath,
    required this.outputStart,
    required this.duration,
    required this.overlayX,
    required this.overlayY,
    required this.overlayScale,
    required this.opacity,
    required this.fadeIn,
    required this.fadeOut,
    required this.imageFit,
    required this.cropLeft,
    required this.cropTop,
    required this.cropRight,
    required this.cropBottom,
    required this.transformOffsetX,
    required this.transformOffsetY,
    required this.transformScale,
    required this.rotationDegrees,
    required this.flipHorizontal,
    required this.flipVertical,
    required this.startOverlayX,
    required this.startOverlayY,
    required this.startOverlayScale,
    required this.kenBurnsEnabled,
    required this.kenBurnsStart,
    required this.kenBurnsEnd,
    required this.keyframes,
  });

  final String filePath;
  final Duration outputStart;
  final Duration duration;
  final double overlayX;
  final double overlayY;
  final double overlayScale;
  final double opacity;
  final ImageClipFit imageFit;
  final Duration fadeIn;
  final Duration fadeOut;
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
  final double startOverlayX;
  final double startOverlayY;
  final double startOverlayScale;
  final bool kenBurnsEnabled;
  final double kenBurnsStart;
  final double kenBurnsEnd;
  final List<ClipKeyframe> keyframes;
}
