enum TimelineTransitionBlendMode { normal, screen }

enum TimelineTransitionPlacement { centered, start }

enum TimelineTransitionPreset {
  fade,
  flash,
  wipe,
  dissolve,
  blur,
  glitch,
  spin,
  pixelate,
  zoom,
  lightLeak,
}

enum TimelineTransitionDirection {
  leftToRight,
  rightToLeft,
  topToBottom,
  bottomToTop,
}

class TimelineTransitionAsset {
  const TimelineTransitionAsset({
    required this.id,
    required this.name,
    this.filePath = '',
    this.fileName,
    this.downloadUrl,
    this.preset,
    this.direction = TimelineTransitionDirection.leftToRight,
    this.color = 0xFF000000,
    this.intensity = 1,
    this.duration = const Duration(milliseconds: 900),
  });

  final String id;
  final String name;
  final String filePath;
  final String? fileName;
  final String? downloadUrl;
  final TimelineTransitionPreset? preset;
  final TimelineTransitionDirection direction;
  final int color;
  final double intensity;
  final Duration duration;

  bool get isPreset => preset != null;
}

class TimelineTransition {
  const TimelineTransition({
    required this.id,
    required this.name,
    this.filePath = '',
    required this.timelinePosition,
    required this.duration,
    this.blendMode = TimelineTransitionBlendMode.screen,
    this.placement = TimelineTransitionPlacement.centered,
    this.preset,
    this.direction = TimelineTransitionDirection.leftToRight,
    this.color = 0xFF000000,
    this.intensity = 1,
  });

  final String id;
  final String name;
  final String filePath;
  final Duration timelinePosition;
  final Duration duration;
  final TimelineTransitionBlendMode blendMode;
  final TimelineTransitionPlacement placement;
  final TimelineTransitionPreset? preset;
  final TimelineTransitionDirection direction;
  final int color;
  final double intensity;

  bool get isPreset => preset != null;

  Duration get timelineStart {
    if (placement == TimelineTransitionPlacement.start) {
      return timelinePosition;
    }
    final halfDuration = Duration(
      microseconds: (duration.inMicroseconds / 2).floor(),
    );
    final start = timelinePosition - halfDuration;
    return start < Duration.zero ? Duration.zero : start;
  }

  Duration get timelineEnd => timelineStart + duration;

  TimelineTransition copyWith({
    String? id,
    String? name,
    String? filePath,
    Duration? timelinePosition,
    Duration? duration,
    TimelineTransitionBlendMode? blendMode,
    TimelineTransitionPlacement? placement,
    TimelineTransitionPreset? preset,
    TimelineTransitionDirection? direction,
    int? color,
    double? intensity,
  }) {
    return TimelineTransition(
      id: id ?? this.id,
      name: name ?? this.name,
      filePath: filePath ?? this.filePath,
      timelinePosition: timelinePosition ?? this.timelinePosition,
      duration: duration ?? this.duration,
      blendMode: blendMode ?? this.blendMode,
      placement: placement ?? this.placement,
      preset: preset ?? this.preset,
      direction: direction ?? this.direction,
      color: color ?? this.color,
      intensity: intensity ?? this.intensity,
    );
  }
}
