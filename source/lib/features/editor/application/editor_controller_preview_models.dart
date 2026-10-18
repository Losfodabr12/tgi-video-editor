part of 'editor_controller.dart';

class TimelineAudioPreviewClip {
  const TimelineAudioPreviewClip({
    required this.clipId,
    required this.mediaItem,
    required this.sourcePosition,
    required this.volume,
    required this.playbackSpeed,
  });

  final String clipId;
  final MediaItem mediaItem;
  final Duration sourcePosition;
  final double volume;
  final double playbackSpeed;
}

class TimelineVideoPreviewClip {
  const TimelineVideoPreviewClip({
    required this.clipId,
    required this.mediaItem,
    required this.sourcePosition,
    required this.timelineStart,
    required this.playbackSpeed,
  });

  final String clipId;
  final MediaItem mediaItem;
  final Duration sourcePosition;
  final Duration timelineStart;
  final double playbackSpeed;
}

class TimelineVideoOverlayPreviewClip {
  const TimelineVideoOverlayPreviewClip({
    required this.clip,
    required this.mediaItem,
    required this.sourcePosition,
    required this.opacity,
    required this.isActive,
  });

  final domain.Clip clip;
  final MediaItem mediaItem;
  final Duration sourcePosition;
  final double opacity;
  final bool isActive;
}
