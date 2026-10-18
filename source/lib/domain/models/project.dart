import 'dart:math' as math;

import 'clip.dart';
import 'media_item.dart';
import 'timeline_marker.dart';
import 'timeline_transition.dart';
import 'track.dart';

const _defaultImageClipDuration = Duration(seconds: 5);
const _defaultTextClipDuration = Duration(seconds: 5);
const _defaultTimelineTransitionDuration = Duration(milliseconds: 900);
const _minimumTimelineTransitionDuration = Duration(milliseconds: 200);
const _maximumTimelineTransitionDuration = Duration(seconds: 2);
const _minimumTextClipDuration = Duration(seconds: 1);
const _minimumImageClipDuration = Duration(seconds: 1);
const _minimumMediaTrimTimelineDuration = Duration(milliseconds: 100);
const _minimumImageOverlayScale = 0.35;
const _maximumImageOverlayScale = 8.0;
const _defaultTextFontFamily = 'Arial';
const _minimumTextFontSize = 12.0;
const _maximumTextFontSize = 160.0;
const _maximumAudioNoiseReductionDb = 30.0;
const _minimumPlaybackSpeed = 0.25;
const _maximumPlaybackSpeed = 4.0;
const _minimumVideoBrightness = -1.0;
const _maximumVideoBrightness = 1.0;
const _minimumVideoContrast = 0.0;
const _maximumVideoContrast = 3.0;
const _minimumVideoSaturation = 0.0;
const _maximumVideoSaturation = 3.0;
const _minimumVideoExposure = -1.0;
const _maximumVideoExposure = 1.0;
const _minimumVideoHue = -180.0;
const _maximumVideoHue = 180.0;
const _minimumVideoColorBalance = -1.0;
const _maximumVideoColorBalance = 1.0;
const _minimumChromaKeySimilarity = 0.0;
const _maximumChromaKeySimilarity = 1.0;
const _minimumChromaKeyBlend = 0.0;
const _maximumChromaKeyBlend = 1.0;

int _nextGroupId = 0;
int _nextClipId = 0;
int _nextImageTrackId = 0;
int _nextTextTrackId = 0;
int _nextManualVideoTrackId = 0;
int _nextManualAudioTrackId = 0;
int _nextMarkerId = 0;
int _nextTransitionId = 0;
int _nextKeyframeId = 0;

enum WatermarkPosition { topLeft, topRight, bottomLeft, bottomRight, custom }

class ProjectWatermark {
  const ProjectWatermark({
    this.enabled = false,
    this.imagePath = '',
    this.position = WatermarkPosition.bottomRight,
    this.x = 0.92,
    this.y = 0.92,
    this.scale = 1.0,
    this.opacity = 0.75,
  });

  final bool enabled;
  final String imagePath;
  final WatermarkPosition position;
  final double x;
  final double y;
  final double scale;
  final double opacity;

  ProjectWatermark copyWith({
    bool? enabled,
    String? imagePath,
    WatermarkPosition? position,
    double? x,
    double? y,
    double? scale,
    double? opacity,
  }) {
    return ProjectWatermark(
      enabled: enabled ?? this.enabled,
      imagePath: imagePath ?? this.imagePath,
      position: position ?? this.position,
      x: x ?? this.x,
      y: y ?? this.y,
      scale: scale ?? this.scale,
      opacity: opacity ?? this.opacity,
    );
  }
}

class _NormalizedCropInsets {
  const _NormalizedCropInsets({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;
}

class _NormalizedKenBurnsTiming {
  const _NormalizedKenBurnsTiming({required this.start, required this.end});

  final double start;
  final double end;
}

class TgiProject {
  TgiProject({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    List<MediaItem> mediaPool = const [],
    List<Track> tracks = const [],
    List<TimelineMarker> markers = const [],
    List<TimelineTransition> transitions = const [],
    this.watermark = const ProjectWatermark(),
  }) : mediaPool = List.unmodifiable(mediaPool),
       tracks = List.unmodifiable(tracks),
       markers = List.unmodifiable(markers),
       transitions = List.unmodifiable(transitions);
  static const String defaultImageTrackId = 'track_default_image_overlay';
  static const String defaultTextTrackId = 'track_default_text_overlay';
  static const String defaultVideoTrackId = 'track_default_video';
  static const String defaultAudioTrackId = 'track_default_audio_volume';

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<MediaItem> mediaPool;
  final List<Track> tracks;
  final List<TimelineMarker> markers;
  final List<TimelineTransition> transitions;
  final ProjectWatermark watermark;

  bool get hasTimelineClips {
    return tracks.any((track) => track.clips.isNotEmpty);
  }

  Duration get timelineDuration {
    var duration = Duration.zero;
    for (final track in tracks) {
      for (final clip in track.clips) {
        if (clip.timelineEnd > duration) {
          duration = clip.timelineEnd;
        }
      }
    }
    for (final marker in markers) {
      if (marker.position > duration) {
        duration = marker.position;
      }
    }
    for (final transition in transitions) {
      if (transition.timelineEnd > duration) {
        duration = transition.timelineEnd;
      }
    }
    return duration;
  }

  factory TgiProject.empty({required String name}) {
    final now = DateTime.now();
    return TgiProject(
      id: 'project_${now.microsecondsSinceEpoch}',
      name: name,
      createdAt: now,
      updatedAt: now,
    );
  }

  static void syncIdCounters(TgiProject project) {
    var maxGroupId = _nextGroupId;
    var maxClipId = _nextClipId;
    var maxImageTrackId = _nextImageTrackId;
    var maxTextTrackId = _nextTextTrackId;
    var maxManualVideoTrackId = _nextManualVideoTrackId;
    var maxManualAudioTrackId = _nextManualAudioTrackId;
    var maxMarkerId = _nextMarkerId;
    var maxTransitionId = _nextTransitionId;
    var maxKeyframeId = _nextKeyframeId;

    for (final track in project.tracks) {
      maxImageTrackId = _maxIdAfterPrefix(
        maxImageTrackId,
        track.id,
        'track_image_overlay_',
      );
      maxTextTrackId = _maxIdAfterPrefix(
        maxTextTrackId,
        track.id,
        'track_text_overlay_',
      );
      maxManualVideoTrackId = _maxIdAfterPrefix(
        maxManualVideoTrackId,
        track.id,
        'track_video_manual_',
      );
      maxManualAudioTrackId = _maxIdAfterPrefix(
        maxManualAudioTrackId,
        track.id,
        'track_audio_manual_',
      );
      for (final clip in track.clips) {
        maxClipId = _maxIdAfterPrefix(maxClipId, clip.id, 'clip_');
        maxGroupId = _maxIdAfterPrefix(
          maxGroupId,
          clip.timelineGroupId,
          'group_',
        );
        for (final keyframe in clip.keyframes) {
          maxKeyframeId = _maxIdAfterPrefix(
            maxKeyframeId,
            keyframe.id,
            'keyframe_',
          );
        }
      }
    }

    for (final marker in project.markers) {
      maxMarkerId = _maxIdAfterPrefix(maxMarkerId, marker.id, 'marker_');
    }
    for (final transition in project.transitions) {
      maxTransitionId = _maxIdAfterPrefix(
        maxTransitionId,
        transition.id,
        'transition_',
      );
    }

    _nextGroupId = maxGroupId;
    _nextClipId = maxClipId;
    _nextImageTrackId = maxImageTrackId;
    _nextTextTrackId = maxTextTrackId;
    _nextManualVideoTrackId = maxManualVideoTrackId;
    _nextManualAudioTrackId = maxManualAudioTrackId;
    _nextMarkerId = maxMarkerId;
    _nextTransitionId = maxTransitionId;
    _nextKeyframeId = maxKeyframeId;
  }

  TgiProject copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<MediaItem>? mediaPool,
    List<Track>? tracks,
    List<TimelineMarker>? markers,
    List<TimelineTransition>? transitions,
    ProjectWatermark? watermark,
  }) {
    return TgiProject(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      mediaPool: mediaPool ?? this.mediaPool,
      tracks: tracks ?? this.tracks,
      markers: markers ?? this.markers,
      transitions: transitions ?? this.transitions,
      watermark: watermark ?? this.watermark,
    );
  }

  MediaItem? mediaItemById(String id) {
    for (final item in mediaPool) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  Track? trackById(String id) {
    for (final track in tracks) {
      if (track.id == id) {
        return track;
      }
    }
    return null;
  }

  bool mediaItemIsUsed(String id) {
    for (final track in tracks) {
      for (final clip in track.clips) {
        if (clip.mediaItemId == id) {
          return true;
        }
      }
    }
    return false;
  }

  Clip? clipAt(Duration timelinePosition, {TrackType? trackType}) {
    final position = _normalizeTimelineStart(timelinePosition);
    Clip? activeClip;
    for (final track in tracks) {
      if (track.isHidden) {
        continue;
      }
      if (trackType != null && track.type != trackType) {
        continue;
      }
      for (final clip in track.clips) {
        if (clip.timelineStart <= position && position < clip.timelineEnd) {
          if (activeClip == null ||
              clip.timelineStart > activeClip.timelineStart) {
            activeClip = clip;
          }
        }
      }
    }
    return activeClip;
  }

  List<Clip> allClipsAt(Duration timelinePosition, {TrackType? trackType}) {
    final position = _normalizeTimelineStart(timelinePosition);
    final result = <Clip>[];
    for (final track in tracks) {
      if (track.isHidden) {
        continue;
      }
      if (trackType != null && track.type != trackType) {
        continue;
      }
      for (final clip in track.clips) {
        if (clip.timelineStart <= position && position < clip.timelineEnd) {
          result.add(clip);
        }
      }
    }
    return result;
  }

  TgiProject addMediaItem(MediaItem item) {
    final alreadyExists = mediaPool.any((m) => m.id == item.id);
    if (alreadyExists) {
      return this;
    }
    return copyWith(mediaPool: [...mediaPool, item], updatedAt: DateTime.now());
  }

  TgiProject removeMediaItem(String mediaItemId) {
    if (mediaItemIsUsed(mediaItemId)) {
      return this;
    }
    final updatedMediaPool = mediaPool
        .where((item) => item.id != mediaItemId)
        .toList();
    if (updatedMediaPool.length == mediaPool.length) {
      return this;
    }
    return copyWith(mediaPool: updatedMediaPool, updatedAt: DateTime.now());
  }

  TgiProject updateMediaItemPreviewProxy(
    String mediaItemId, {
    required String previewProxyPath,
  }) {
    final index = mediaPool.indexWhere((item) => item.id == mediaItemId);
    if (index < 0) {
      return this;
    }

    final updatedMediaPool = List<MediaItem>.from(mediaPool);
    updatedMediaPool[index] = updatedMediaPool[index].copyWith(
      previewProxyPath: previewProxyPath,
    );
    return copyWith(mediaPool: updatedMediaPool, updatedAt: DateTime.now());
  }

  TgiProject addMediaItemToTimeline(
    MediaItem item, {
    required Duration timelineStart,
    String? targetTrackId,
    bool forceNewVideoTrack = false,
    bool forceNewAudioTrack = false,
    ImageClipFit imageFit = ImageClipFit.overlay,
    double overlayX = 1,
    double overlayY = 0,
    double overlayScale = 1,
    Duration? clipDurationOverride,
  }) {
    final start = _normalizeTimelineStart(timelineStart);
    final groupId = 'group_${++_nextGroupId}';
    final imageDuration =
        clipDurationOverride == null || clipDurationOverride <= Duration.zero
        ? _defaultImageClipDuration
        : clipDurationOverride;
    final clipDuration = item.type == MediaType.image
        ? imageDuration
        : item.duration;
    var updated = List<Track>.from(tracks);
    final targetTrack = _trackById(updated, targetTrackId);
    if (item.type == MediaType.video) {
      final trackPair = forceNewVideoTrack
          ? _newVideoAudioTrackPair(updated)
          : _videoAudioTrackPairForDrop(updated, targetTrack);
      final videoClip = Clip(
        id: 'clip_${++_nextClipId}_v',
        mediaItemId: item.id,
        timelineGroupId: groupId,
        trackType: TrackType.video,
        timelineStart: start,
        sourceStart: Duration.zero,
        duration: clipDuration,
        sourceDuration: clipDuration,
        overlayX: _clampUnit(overlayX),
        overlayY: _clampUnit(overlayY),
        overlayScale: _clampImageOverlayScale(overlayScale),
      );
      final audioClip = Clip(
        id: 'clip_${++_nextClipId}_a',
        mediaItemId: item.id,
        timelineGroupId: groupId,
        trackType: TrackType.audio,
        timelineStart: start,
        sourceStart: Duration.zero,
        duration: clipDuration,
        sourceDuration: clipDuration,
        volume: 1,
      );
      updated = _upsertTrack(
        updated,
        trackPair.videoTrackId,
        TrackType.video,
        trackPair.videoTrackName,
        videoClip,
      );
      updated = _upsertTrack(
        updated,
        trackPair.audioTrackId,
        TrackType.audio,
        trackPair.audioTrackName,
        audioClip,
      );
    } else if (item.type == MediaType.image) {
      final clip = Clip(
        id: 'clip_${++_nextClipId}_img',
        mediaItemId: item.id,
        timelineGroupId: groupId,
        trackType: TrackType.image,
        timelineStart: start,
        sourceStart: Duration.zero,
        duration: clipDuration,
        overlayX: _clampUnit(overlayX),
        overlayY: _clampUnit(overlayY),
        overlayScale: _clampImageOverlayScale(overlayScale),
        imageFit: imageFit,
      );
      if (targetTrack?.type == TrackType.image) {
        updated = _upsertTrack(
          updated,
          targetTrack!.id,
          TrackType.image,
          targetTrack.name,
          clip,
        );
      } else {
        final imageTrackCount = updated
            .where((track) => track.type == TrackType.image)
            .length;
        updated = _insertImageTrack(
          updated,
          imageTrackCount == 0
              ? TgiProject.defaultImageTrackId
              : 'track_image_overlay_${++_nextImageTrackId}',
          'Imagem ${imageTrackCount + 1}',
          clip,
        );
      }
    } else if (item.type == MediaType.audio) {
      if (targetTrackId != null && targetTrack?.type != TrackType.audio) {
        return this;
      }
      final clip = Clip(
        id: 'clip_${++_nextClipId}_a',
        mediaItemId: item.id,
        timelineGroupId: groupId,
        trackType: TrackType.audio,
        timelineStart: start,
        sourceStart: Duration.zero,
        duration: clipDuration,
        sourceDuration: clipDuration,
        volume: 1,
      );
      final audioTrack = forceNewAudioTrack
          ? null
          : targetTrack?.type == TrackType.audio
          ? targetTrack
          : _firstTrackOfType(updated, TrackType.audio);
      final audioTrackCount = _trackCount(updated, TrackType.audio);
      final useDefaultId =
          audioTrackCount == 0 &&
          !updated.any((track) => track.id == TgiProject.defaultAudioTrackId);
      final trackId =
          audioTrack?.id ??
          (useDefaultId
              ? TgiProject.defaultAudioTrackId
              : 'track_audio_manual_${++_nextManualAudioTrackId}');
      final trackName =
          audioTrack?.name ?? _audioTrackName(audioTrackCount + 1);
      updated = _upsertTrack(
        updated,
        trackId,
        TrackType.audio,
        trackName,
        clip,
      );
    }
    return copyWith(tracks: updated, updatedAt: DateTime.now());
  }

  TgiProject addTextClipToTimeline({
    required String text,
    required Duration timelineStart,
    String? targetTrackId,
    Duration duration = _defaultTextClipDuration,
    String fontFamily = _defaultTextFontFamily,
    bool isCaption = false,
    double fontSize = 48,
    int textColor = 0xFFFFFFFF,
    int backgroundColor = 0x99000000,
    double opacity = 1,
    TextClipAnimation textAnimation = TextClipAnimation.none,
  }) {
    final content = text.trim();
    if (content.isEmpty) {
      return this;
    }

    final start = _normalizeTimelineStart(timelineStart);
    final groupId = 'group_${++_nextGroupId}';
    final clipId = 'clip_${++_nextClipId}_txt';
    final clipDuration = duration < _minimumTextClipDuration
        ? _minimumTextClipDuration
        : duration;
    var updated = List<Track>.from(tracks);
    final targetTrack = _trackById(updated, targetTrackId);
    final textTrack = targetTrack?.type == TrackType.text
        ? targetTrack
        : _firstTrackOfType(updated, TrackType.text);
    final textTrackCount = _trackCount(updated, TrackType.text);
    final useDefaultId =
        textTrackCount == 0 &&
        !updated.any((track) => track.id == TgiProject.defaultTextTrackId);
    final trackId =
        textTrack?.id ??
        (useDefaultId
            ? TgiProject.defaultTextTrackId
            : 'track_text_overlay_${++_nextTextTrackId}');
    final trackName = textTrack?.name ?? _textTrackName(textTrackCount + 1);
    final clip = Clip(
      id: clipId,
      mediaItemId: clipId,
      timelineGroupId: groupId,
      trackType: TrackType.text,
      timelineStart: start,
      sourceStart: Duration.zero,
      duration: clipDuration,
      overlayX: 0.5,
      overlayY: 0.78,
      textContent: content,
      isCaption: isCaption,
      fontFamily: _normalizedTextFontFamily(fontFamily),
      fontSize: _clampTextFontSize(fontSize),
      textColor: textColor,
      backgroundColor: backgroundColor,
      opacity: _clampOpacity(opacity),
      textAnimation: textAnimation,
    );

    updated = _upsertTrack(updated, trackId, TrackType.text, trackName, clip);
    return copyWith(tracks: updated, updatedAt: DateTime.now());
  }

  TgiProject addTimelineTrack(TrackType type) {
    final updated = List<Track>.from(tracks);
    if (type == TrackType.video) {
      final videoCount = _trackCount(updated, TrackType.video);
      final audioCount = _trackCount(updated, TrackType.audio);
      final useDefaultIds =
          videoCount == 0 &&
          !updated.any((track) => track.id == TgiProject.defaultVideoTrackId);
      final trackIndex = videoCount + 1;
      final videoTrackId = useDefaultIds
          ? TgiProject.defaultVideoTrackId
          : 'track_video_manual_${++_nextManualVideoTrackId}';
      final audioTrackId = useDefaultIds
          ? TgiProject.defaultAudioTrackId
          : _pairedAudioTrackIdForVideoTrack(videoTrackId);

      updated.add(
        Track(
          id: videoTrackId,
          name: _videoTrackName(trackIndex),
          type: TrackType.video,
        ),
      );
      updated.add(
        Track(
          id: audioTrackId,
          name: _audioTrackName(audioCount + 1),
          type: TrackType.audio,
        ),
      );
    } else if (type == TrackType.image) {
      final imageCount = _trackCount(updated, TrackType.image);
      final useDefaultId =
          imageCount == 0 &&
          !updated.any((track) => track.id == TgiProject.defaultImageTrackId);
      updated.insert(
        0,
        Track(
          id: useDefaultId
              ? TgiProject.defaultImageTrackId
              : 'track_image_overlay_${++_nextImageTrackId}',
          name: 'Imagem ${imageCount + 1}',
          type: TrackType.image,
        ),
      );
    } else if (type == TrackType.text) {
      final textCount = _trackCount(updated, TrackType.text);
      final useDefaultId =
          textCount == 0 &&
          !updated.any((track) => track.id == TgiProject.defaultTextTrackId);
      updated.insert(
        0,
        Track(
          id: useDefaultId
              ? TgiProject.defaultTextTrackId
              : 'track_text_overlay_${++_nextTextTrackId}',
          name: _textTrackName(textCount + 1),
          type: TrackType.text,
        ),
      );
    } else if (type == TrackType.audio) {
      final audioCount = _trackCount(updated, TrackType.audio);
      final useDefaultId =
          audioCount == 0 &&
          !updated.any((track) => track.id == TgiProject.defaultAudioTrackId);
      updated.add(
        Track(
          id: useDefaultId
              ? TgiProject.defaultAudioTrackId
              : 'track_audio_manual_${++_nextManualAudioTrackId}',
          name: _audioTrackName(audioCount + 1),
          type: TrackType.audio,
        ),
      );
    }
    return copyWith(tracks: updated, updatedAt: DateTime.now());
  }

  TgiProject renameTimelineTrack(String trackId, String name) {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      return this;
    }
    return _updateTimelineTrack(
      trackId,
      (track) =>
          track.name == normalized ? track : track.copyWith(name: normalized),
    );
  }

  TgiProject setTimelineTrackLocked(String trackId, bool isLocked) {
    return _updateTimelineTrack(
      trackId,
      (track) => track.isLocked == isLocked
          ? track
          : track.copyWith(isLocked: isLocked),
    );
  }

  TgiProject setTimelineTrackHidden(String trackId, bool isHidden) {
    return _updateTimelineTrack(
      trackId,
      (track) => track.isHidden == isHidden
          ? track
          : track.copyWith(isHidden: isHidden),
    );
  }

  TgiProject setTimelineTrackMuted(String trackId, bool isMuted) {
    return _updateTimelineTrack(
      trackId,
      (track) => track.type != TrackType.audio || track.isMuted == isMuted
          ? track
          : track.copyWith(isMuted: isMuted),
    );
  }

  TgiProject setTimelineTrackSolo(String trackId, bool isSolo) {
    return _updateTimelineTrack(
      trackId,
      (track) => track.type != TrackType.audio || track.isSolo == isSolo
          ? track
          : track.copyWith(isSolo: isSolo),
    );
  }

  TgiProject setTimelineTrackVolume(String trackId, double volume) {
    final clamped = volume.isFinite ? volume.clamp(0.0, 2.0).toDouble() : 1.0;
    return _updateTimelineTrack(
      trackId,
      (track) => track.type != TrackType.audio || track.volume == clamped
          ? track
          : track.copyWith(volume: clamped),
    );
  }

  TgiProject _updateTimelineTrack(
    String trackId,
    Track Function(Track track) update,
  ) {
    var changed = false;
    final updated = <Track>[];
    for (final track in tracks) {
      if (track.id != trackId) {
        updated.add(track);
        continue;
      }
      final nextTrack = update(track);
      updated.add(nextTrack);
      changed = changed || !identical(nextTrack, track);
    }
    if (!changed) {
      return this;
    }
    return copyWith(tracks: updated, updatedAt: DateTime.now());
  }

  TgiProject addTimelineMarker({
    required Duration position,
    String? name,
    int color = 0xFFFFD166,
  }) {
    final markerNumber = markers.length + 1;
    final marker = TimelineMarker(
      id: 'marker_${++_nextMarkerId}',
      name: (name == null || name.trim().isEmpty)
          ? 'Marcador $markerNumber'
          : name.trim(),
      position: _normalizeTimelineStart(position),
      color: color,
    );
    return copyWith(
      markers: _sortMarkers([...markers, marker]),
      updatedAt: DateTime.now(),
    );
  }

  TgiProject updateTimelineMarker(
    String markerId, {
    String? name,
    Duration? position,
    int? color,
  }) {
    var changed = false;
    final updated = <TimelineMarker>[];
    for (final marker in markers) {
      if (marker.id != markerId) {
        updated.add(marker);
        continue;
      }
      final normalizedName = name?.trim();
      final nextMarker = marker.copyWith(
        name: normalizedName == null || normalizedName.isEmpty
            ? marker.name
            : normalizedName,
        position: position == null
            ? marker.position
            : _normalizeTimelineStart(position),
        color: color,
      );
      updated.add(nextMarker);
      changed =
          changed ||
          nextMarker.name != marker.name ||
          nextMarker.position != marker.position ||
          nextMarker.color != marker.color;
    }
    if (!changed) {
      return this;
    }
    return copyWith(markers: _sortMarkers(updated), updatedAt: DateTime.now());
  }

  TgiProject deleteTimelineMarker(String markerId) {
    final updated = markers.where((marker) => marker.id != markerId).toList();
    if (updated.length == markers.length) {
      return this;
    }
    return copyWith(markers: updated, updatedAt: DateTime.now());
  }

  TgiProject upsertTimelineTransition({
    String filePath = '',
    required String name,
    required Duration timelinePosition,
    Duration duration = _defaultTimelineTransitionDuration,
    TimelineTransitionBlendMode blendMode = TimelineTransitionBlendMode.screen,
    TimelineTransitionPlacement placement =
        TimelineTransitionPlacement.centered,
    TimelineTransitionPreset? preset,
    TimelineTransitionDirection direction =
        TimelineTransitionDirection.leftToRight,
    int color = 0xFF000000,
    double intensity = 1,
  }) {
    final cleanPath = filePath.trim();
    if (preset == null && cleanPath.isEmpty) {
      return this;
    }
    final cleanName = name.trim().isEmpty ? 'Transicao' : name.trim();
    final position = _normalizeTimelineStart(timelinePosition);
    final normalizedDuration = _normalizeTimelineTransitionDuration(duration);
    final existingIndex = transitions.indexWhere(
      (transition) => transition.timelinePosition == position,
    );
    final updated = List<TimelineTransition>.from(transitions);
    final transition = TimelineTransition(
      id: existingIndex >= 0
          ? transitions[existingIndex].id
          : 'transition_${++_nextTransitionId}',
      name: cleanName,
      filePath: cleanPath,
      timelinePosition: position,
      duration: normalizedDuration,
      blendMode: blendMode,
      placement: placement,
      preset: preset,
      direction: direction,
      color: color,
      intensity: _normalizeTimelineTransitionIntensity(intensity),
    );
    if (existingIndex >= 0) {
      updated[existingIndex] = transition;
    } else {
      updated.add(transition);
    }
    return copyWith(
      transitions: _sortTransitions(updated),
      updatedAt: DateTime.now(),
    );
  }

  TgiProject updateTimelineTransition(
    String transitionId, {
    String? filePath,
    String? name,
    Duration? timelinePosition,
    Duration? duration,
    TimelineTransitionBlendMode? blendMode,
    TimelineTransitionPlacement? placement,
    TimelineTransitionPreset? preset,
    TimelineTransitionDirection? direction,
    int? color,
    double? intensity,
  }) {
    final index = transitions.indexWhere(
      (transition) => transition.id == transitionId,
    );
    if (index < 0) {
      return this;
    }

    final current = transitions[index];
    final nextPreset = preset ?? current.preset;
    final cleanPath = filePath == null ? current.filePath : filePath.trim();
    if (nextPreset == null && cleanPath.isEmpty) {
      return this;
    }
    final cleanName = name == null || name.trim().isEmpty
        ? current.name
        : name.trim();
    final next = current.copyWith(
      filePath: cleanPath,
      name: cleanName,
      timelinePosition: timelinePosition == null
          ? current.timelinePosition
          : _normalizeTimelineStart(timelinePosition),
      duration: duration == null
          ? current.duration
          : _normalizeTimelineTransitionDuration(duration),
      blendMode: blendMode,
      placement: placement,
      preset: nextPreset,
      direction: direction,
      color: color,
      intensity: intensity == null
          ? current.intensity
          : _normalizeTimelineTransitionIntensity(intensity),
    );
    if (next.filePath == current.filePath &&
        next.name == current.name &&
        next.timelinePosition == current.timelinePosition &&
        next.duration == current.duration &&
        next.blendMode == current.blendMode &&
        next.placement == current.placement &&
        next.preset == current.preset &&
        next.direction == current.direction &&
        next.color == current.color &&
        next.intensity == current.intensity) {
      return this;
    }

    final updated = List<TimelineTransition>.from(transitions);
    updated[index] = next;
    return copyWith(
      transitions: _sortTransitions(updated),
      updatedAt: DateTime.now(),
    );
  }

  TgiProject insertTimelineSpace({
    required Duration timelineStart,
    required Duration duration,
  }) {
    if (duration <= Duration.zero) {
      return this;
    }
    final start = _normalizeTimelineStart(timelineStart);
    var changed = false;

    final updatedTracks = <Track>[];
    for (final track in tracks) {
      var trackChanged = false;
      final updatedClips = <Clip>[];
      for (final clip in track.clips) {
        if (clip.timelineStart < start) {
          updatedClips.add(clip);
          continue;
        }
        updatedClips.add(
          clip.copyWith(timelineStart: clip.timelineStart + duration),
        );
        trackChanged = true;
        changed = true;
      }
      updatedTracks.add(
        trackChanged ? track.copyWith(clips: _sortClips(updatedClips)) : track,
      );
    }

    final updatedMarkers = <TimelineMarker>[];
    for (final marker in markers) {
      if (marker.position < start) {
        updatedMarkers.add(marker);
        continue;
      }
      updatedMarkers.add(marker.copyWith(position: marker.position + duration));
      changed = true;
    }

    final updatedTransitions = <TimelineTransition>[];
    for (final transition in transitions) {
      if (transition.timelinePosition < start) {
        updatedTransitions.add(transition);
        continue;
      }
      updatedTransitions.add(
        transition.copyWith(
          timelinePosition: transition.timelinePosition + duration,
        ),
      );
      changed = true;
    }

    if (!changed) {
      return this;
    }
    return copyWith(
      tracks: updatedTracks,
      markers: _sortMarkers(updatedMarkers),
      transitions: _sortTransitions(updatedTransitions),
      updatedAt: DateTime.now(),
    );
  }

  TgiProject deleteTimelineTransition(String transitionId) {
    final updated = transitions
        .where((transition) => transition.id != transitionId)
        .toList();
    if (updated.length == transitions.length) {
      return this;
    }
    return copyWith(transitions: updated, updatedAt: DateTime.now());
  }

  List<Track> _insertImageTrack(
    List<Track> tracks,
    String trackId,
    String name,
    Clip clip,
  ) {
    tracks.insert(
      0,
      Track(id: trackId, name: name, type: TrackType.image, clips: [clip]),
    );
    return tracks;
  }

  List<Track> _upsertTrack(
    List<Track> tracks,
    String trackId,
    TrackType type,
    String name,
    Clip clip,
  ) {
    final index = tracks.indexWhere((t) => t.id == trackId);
    if (index >= 0) {
      final track = tracks[index];
      tracks[index] = track.copyWith(clips: _sortClips([...track.clips, clip]));
      return tracks;
    }
    if (type == TrackType.image || type == TrackType.text) {
      tracks.insert(
        0,
        Track(id: trackId, name: name, type: type, clips: _sortClips([clip])),
      );
    } else {
      tracks.add(
        Track(id: trackId, name: name, type: type, clips: _sortClips([clip])),
      );
    }
    return tracks;
  }

  Clip? _findClipById(String clipId) {
    for (final track in tracks) {
      for (final clip in track.clips) {
        if (clip.id == clipId) return clip;
      }
    }
    return null;
  }

  Track? _trackById(List<Track> tracks, String? trackId) {
    if (trackId == null) {
      return null;
    }
    for (final track in tracks) {
      if (track.id == trackId) {
        return track;
      }
    }
    return null;
  }

  _VideoAudioTrackPair _videoAudioTrackPairForDrop(
    List<Track> tracks,
    Track? targetTrack,
  ) {
    var videoTrackId = TgiProject.defaultVideoTrackId;
    var audioTrackId = TgiProject.defaultAudioTrackId;

    if (targetTrack?.type == TrackType.video) {
      videoTrackId = targetTrack!.id;
      audioTrackId = _pairedAudioTrackIdForVideoTrack(videoTrackId);
    } else if (targetTrack?.type == TrackType.audio) {
      audioTrackId = targetTrack!.id;
      videoTrackId = _pairedVideoTrackIdForAudioTrack(audioTrackId);
    }

    return _VideoAudioTrackPair(
      videoTrackId: videoTrackId,
      audioTrackId: audioTrackId,
      videoTrackName:
          _trackById(tracks, videoTrackId)?.name ??
          _videoTrackName(_trackCount(tracks, TrackType.video) + 1),
      audioTrackName:
          _trackById(tracks, audioTrackId)?.name ??
          _audioTrackName(_trackCount(tracks, TrackType.audio) + 1),
    );
  }

  _VideoAudioTrackPair _newVideoAudioTrackPair(List<Track> tracks) {
    final videoCount = _trackCount(tracks, TrackType.video);
    final audioCount = _trackCount(tracks, TrackType.audio);
    final useDefaultIds =
        videoCount == 0 &&
        !tracks.any((track) => track.id == TgiProject.defaultVideoTrackId);
    final videoTrackId = useDefaultIds
        ? TgiProject.defaultVideoTrackId
        : 'track_video_manual_${++_nextManualVideoTrackId}';
    final audioTrackId = useDefaultIds
        ? TgiProject.defaultAudioTrackId
        : _pairedAudioTrackIdForVideoTrack(videoTrackId);
    return _VideoAudioTrackPair(
      videoTrackId: videoTrackId,
      audioTrackId: audioTrackId,
      videoTrackName: _videoTrackName(videoCount + 1),
      audioTrackName: _audioTrackName(audioCount + 1),
    );
  }

  String _pairedAudioTrackIdForVideoTrack(String videoTrackId) {
    if (videoTrackId == TgiProject.defaultVideoTrackId) {
      return TgiProject.defaultAudioTrackId;
    }
    return videoTrackId.replaceFirst('track_video_', 'track_audio_');
  }

  String _pairedVideoTrackIdForAudioTrack(String audioTrackId) {
    if (audioTrackId == TgiProject.defaultAudioTrackId) {
      return TgiProject.defaultVideoTrackId;
    }
    return audioTrackId.replaceFirst('track_audio_', 'track_video_');
  }

  int _trackCount(List<Track> tracks, TrackType type) {
    return tracks.where((track) => track.type == type).length;
  }

  String _videoTrackName(int index) {
    return index <= 1 ? 'V\u00EDdeo' : 'V\u00EDdeo $index';
  }

  String _audioTrackName(int index) {
    return index <= 1 ? '\u00C1udio/Volume' : '\u00C1udio/Volume $index';
  }

  String _textTrackName(int index) {
    return index <= 1 ? 'Texto' : 'Texto $index';
  }

  Track? _firstTrackOfType(List<Track> tracks, TrackType type) {
    for (final track in tracks) {
      if (track.type == type) {
        return track;
      }
    }
    return null;
  }

  bool _timelineGroupHasTrackType(String timelineGroupId, TrackType type) {
    for (final track in tracks) {
      if (track.type != type) {
        continue;
      }
      if (track.clips.any((clip) => clip.timelineGroupId == timelineGroupId)) {
        return true;
      }
    }
    return false;
  }

  TgiProject moveTimelineClipGroup(
    String timelineGroupId, {
    required Duration timelineStart,
  }) {
    final start = _normalizeTimelineStart(timelineStart);
    final updatedTracks = <Track>[];
    for (final track in tracks) {
      final groupClips = track.clips
          .where((c) => c.timelineGroupId == timelineGroupId)
          .toList();
      if (groupClips.isEmpty) {
        updatedTracks.add(track);
        continue;
      }
      final delta = start - groupClips.first.timelineStart;
      final updatedClips = track.clips.map((c) {
        if (c.timelineGroupId == timelineGroupId) {
          return c.copyWith(timelineStart: c.timelineStart + delta);
        }
        return c;
      }).toList();
      updatedTracks.add(track.copyWith(clips: updatedClips));
    }
    return copyWith(tracks: updatedTracks, updatedAt: DateTime.now());
  }

  TgiProject unlinkAudioFromTimelineGroup(String timelineGroupId) {
    if (!_timelineGroupHasTrackType(timelineGroupId, TrackType.video) ||
        !_timelineGroupHasTrackType(timelineGroupId, TrackType.audio)) {
      return this;
    }

    final newAudioGroupId = 'group_${++_nextGroupId}';
    var changed = false;
    final updatedTracks = <Track>[];
    for (final track in tracks) {
      if (track.type != TrackType.audio) {
        updatedTracks.add(track);
        continue;
      }

      final updatedClips = <Clip>[];
      var trackChanged = false;
      for (final clip in track.clips) {
        if (clip.timelineGroupId != timelineGroupId) {
          updatedClips.add(clip);
          continue;
        }
        updatedClips.add(clip.copyWith(timelineGroupId: newAudioGroupId));
        trackChanged = true;
        changed = true;
      }
      updatedTracks.add(
        trackChanged ? track.copyWith(clips: updatedClips) : track,
      );
    }

    if (!changed) {
      return this;
    }
    return copyWith(tracks: updatedTracks, updatedAt: DateTime.now());
  }

  TgiProject linkAudioTimelineGroupToVideoGroup({
    required String audioTimelineGroupId,
    required String videoTimelineGroupId,
  }) {
    if (audioTimelineGroupId == videoTimelineGroupId ||
        !_timelineGroupHasTrackType(audioTimelineGroupId, TrackType.audio) ||
        _timelineGroupHasTrackType(audioTimelineGroupId, TrackType.video) ||
        !_timelineGroupHasTrackType(videoTimelineGroupId, TrackType.video) ||
        _timelineGroupHasTrackType(videoTimelineGroupId, TrackType.audio)) {
      return this;
    }

    var changed = false;
    final updatedTracks = tracks.map((track) {
      if (track.type != TrackType.audio) {
        return track;
      }
      var trackChanged = false;
      final updatedClips = track.clips.map((clip) {
        if (clip.timelineGroupId != audioTimelineGroupId) {
          return clip;
        }
        changed = true;
        trackChanged = true;
        return clip.copyWith(timelineGroupId: videoTimelineGroupId);
      }).toList();
      return trackChanged ? track.copyWith(clips: updatedClips) : track;
    }).toList();

    if (!changed) {
      return this;
    }
    return copyWith(tracks: updatedTracks, updatedAt: DateTime.now());
  }

  TgiProject moveTimelineClipGroupsByDelta(
    Set<String> timelineGroupIds, {
    required Duration delta,
  }) {
    if (timelineGroupIds.isEmpty || delta == Duration.zero) {
      return this;
    }

    Duration? earliestStart;
    for (final track in tracks) {
      for (final clip in track.clips) {
        if (!timelineGroupIds.contains(clip.timelineGroupId)) {
          continue;
        }
        if (earliestStart == null || clip.timelineStart < earliestStart) {
          earliestStart = clip.timelineStart;
        }
      }
    }
    if (earliestStart == null) {
      return this;
    }

    var adjustedDelta = delta;
    if (earliestStart + adjustedDelta < Duration.zero) {
      adjustedDelta = Duration(microseconds: -earliestStart.inMicroseconds);
    }
    if (adjustedDelta == Duration.zero) {
      return this;
    }

    var changed = false;
    final updatedTracks = <Track>[];
    for (final track in tracks) {
      var trackChanged = false;
      final updatedClips = <Clip>[];
      for (final clip in track.clips) {
        if (!timelineGroupIds.contains(clip.timelineGroupId)) {
          updatedClips.add(clip);
          continue;
        }
        updatedClips.add(
          clip.copyWith(timelineStart: clip.timelineStart + adjustedDelta),
        );
        trackChanged = true;
        changed = true;
      }
      updatedTracks.add(
        trackChanged ? track.copyWith(clips: _sortClips(updatedClips)) : track,
      );
    }

    if (!changed) {
      return this;
    }
    return copyWith(tracks: updatedTracks, updatedAt: DateTime.now());
  }

  TgiProject moveClipToTrack(
    String clipId, {
    required String targetTrackId,
    required Duration timelineStart,
  }) {
    final targetTrack = _trackById(tracks, targetTrackId);
    if (targetTrack == null) {
      return this;
    }

    Clip? sourceClip;
    String? sourceTrackId;
    for (final track in tracks) {
      for (final clip in track.clips) {
        if (clip.id == clipId) {
          sourceClip = clip;
          sourceTrackId = track.id;
          break;
        }
      }
      if (sourceClip != null) {
        break;
      }
    }

    final clip = sourceClip;
    if (clip == null || sourceTrackId == null) {
      return this;
    }
    if (targetTrack.type != clip.trackType ||
        clip.trackType == TrackType.video ||
        (clip.trackType == TrackType.audio &&
            _timelineGroupHasTrackType(
              clip.timelineGroupId,
              TrackType.video,
            ))) {
      return this;
    }

    final movedClip = clip.copyWith(
      timelineStart: _normalizeTimelineStart(timelineStart),
    );
    final updatedTracks = <Track>[];
    for (final track in tracks) {
      if (track.id == sourceTrackId && track.id == targetTrackId) {
        updatedTracks.add(
          track.copyWith(
            clips: _sortClips(
              track.clips
                  .map(
                    (candidate) =>
                        candidate.id == clipId ? movedClip : candidate,
                  )
                  .toList(),
            ),
          ),
        );
      } else if (track.id == sourceTrackId) {
        updatedTracks.add(
          track.copyWith(
            clips: track.clips
                .where((candidate) => candidate.id != clipId)
                .toList(),
          ),
        );
      } else if (track.id == targetTrackId) {
        updatedTracks.add(
          track.copyWith(clips: _sortClips([...track.clips, movedClip])),
        );
      } else {
        updatedTracks.add(track);
      }
    }

    return copyWith(tracks: updatedTracks, updatedAt: DateTime.now());
  }

  TgiProject moveClipToNewTrack(
    String clipId, {
    required Duration timelineStart,
  }) {
    Clip? sourceClip;
    String? sourceTrackId;
    for (final track in tracks) {
      for (final clip in track.clips) {
        if (clip.id == clipId) {
          sourceClip = clip;
          sourceTrackId = track.id;
          break;
        }
      }
      if (sourceClip != null) {
        break;
      }
    }

    final clip = sourceClip;
    if (clip == null || sourceTrackId == null) {
      return this;
    }
    if (clip.trackType != TrackType.audio ||
        _timelineGroupHasTrackType(clip.timelineGroupId, TrackType.video)) {
      return this;
    }

    final audioTrackCount = _trackCount(tracks, TrackType.audio);
    final newTrack = Track(
      id: 'track_audio_manual_${++_nextManualAudioTrackId}',
      name: _audioTrackName(audioTrackCount + 1),
      type: TrackType.audio,
      clips: [
        clip.copyWith(timelineStart: _normalizeTimelineStart(timelineStart)),
      ],
    );
    final updatedTracks = <Track>[];
    for (final track in tracks) {
      if (track.id == sourceTrackId) {
        updatedTracks.add(
          track.copyWith(
            clips: track.clips
                .where((candidate) => candidate.id != clipId)
                .toList(),
          ),
        );
      } else {
        updatedTracks.add(track);
      }
    }
    updatedTracks.add(newTrack);

    return copyWith(tracks: updatedTracks, updatedAt: DateTime.now());
  }

  TgiProject moveImageClipToTrack(
    String clipId, {
    required String targetTrackId,
    required Duration timelineStart,
  }) {
    return moveClipToTrack(
      clipId,
      targetTrackId: targetTrackId,
      timelineStart: timelineStart,
    );
  }

  TgiProject updateImageClipOverlayPosition(
    String clipId, {
    required double overlayX,
    required double overlayY,
  }) {
    final updatedTracks = <Track>[];
    for (final track in tracks) {
      final clipIndex = track.clips.indexWhere((c) => c.id == clipId);
      if (clipIndex < 0) {
        updatedTracks.add(track);
        continue;
      }
      final updatedClips = List<Clip>.from(track.clips);
      updatedClips[clipIndex] = updatedClips[clipIndex].copyWith(
        overlayX: overlayX,
        overlayY: overlayY,
      );
      updatedTracks.add(track.copyWith(clips: updatedClips));
    }
    return copyWith(tracks: updatedTracks, updatedAt: DateTime.now());
  }

  TgiProject updateTextClipContent(String clipId, {required String text}) {
    return updateTextClipProperties(clipId, text: text);
  }

  TgiProject updateTextClipProperties(
    String clipId, {
    required String text,
    String? fontFamily,
    double? fontSize,
    int? textColor,
    int? backgroundColor,
    double? opacity,
    TextClipAnimation? textAnimation,
  }) {
    final content = text.trim();
    if (content.isEmpty) {
      return this;
    }

    var changed = false;
    final updatedTracks = <Track>[];
    for (final track in tracks) {
      final clipIndex = track.clips.indexWhere((c) => c.id == clipId);
      if (clipIndex < 0 || track.clips[clipIndex].trackType != TrackType.text) {
        updatedTracks.add(track);
        continue;
      }
      final currentClip = track.clips[clipIndex];
      final updatedClip = currentClip.copyWith(
        textContent: content,
        fontFamily: fontFamily == null
            ? currentClip.fontFamily
            : _normalizedTextFontFamily(fontFamily),
        fontSize: fontSize == null
            ? currentClip.fontSize
            : _clampTextFontSize(fontSize),
        textColor: textColor ?? currentClip.textColor,
        backgroundColor: backgroundColor ?? currentClip.backgroundColor,
        opacity: opacity == null ? currentClip.opacity : _clampOpacity(opacity),
        textAnimation: textAnimation ?? currentClip.textAnimation,
      );
      if (_sameTextStyleClip(currentClip, updatedClip)) {
        updatedTracks.add(track);
        continue;
      }
      final updatedClips = List<Clip>.from(track.clips);
      updatedClips[clipIndex] = updatedClip;
      updatedTracks.add(track.copyWith(clips: updatedClips));
      changed = true;
    }

    if (!changed) {
      return this;
    }
    return copyWith(tracks: updatedTracks, updatedAt: DateTime.now());
  }

  TgiProject updateTextClipOverlayPosition(
    String clipId, {
    required double overlayX,
    required double overlayY,
  }) {
    var changed = false;
    final updatedTracks = <Track>[];
    for (final track in tracks) {
      final clipIndex = track.clips.indexWhere((c) => c.id == clipId);
      if (clipIndex < 0 || track.clips[clipIndex].trackType != TrackType.text) {
        updatedTracks.add(track);
        continue;
      }
      final updatedClips = List<Clip>.from(track.clips);
      updatedClips[clipIndex] = updatedClips[clipIndex].copyWith(
        overlayX: overlayX,
        overlayY: overlayY,
      );
      updatedTracks.add(track.copyWith(clips: updatedClips));
      changed = true;
    }

    if (!changed) {
      return this;
    }
    return copyWith(tracks: updatedTracks, updatedAt: DateTime.now());
  }

  TgiProject updateImageClipOverlayScale(
    String clipId, {
    required double overlayScale,
  }) {
    final clamped = _clampImageOverlayScale(overlayScale);
    final updatedTracks = <Track>[];
    for (final track in tracks) {
      final clipIndex = track.clips.indexWhere((c) => c.id == clipId);
      if (clipIndex < 0) {
        updatedTracks.add(track);
        continue;
      }
      final updatedClips = List<Clip>.from(track.clips);
      updatedClips[clipIndex] = updatedClips[clipIndex].copyWith(
        overlayScale: clamped,
      );
      updatedTracks.add(track.copyWith(clips: updatedClips));
    }
    return copyWith(tracks: updatedTracks, updatedAt: DateTime.now());
  }

  TgiProject updateImageClipFit(
    String clipId, {
    required ImageClipFit imageFit,
    double? overlayX,
    double? overlayY,
    double? overlayScale,
  }) {
    var changed = false;
    final updatedTracks = <Track>[];
    for (final track in tracks) {
      final clipIndex = track.clips.indexWhere((c) => c.id == clipId);
      if (clipIndex < 0 ||
          track.clips[clipIndex].trackType != TrackType.image) {
        updatedTracks.add(track);
        continue;
      }
      final current = track.clips[clipIndex];
      final updatedClips = List<Clip>.from(track.clips);
      updatedClips[clipIndex] = current.copyWith(
        imageFit: imageFit,
        overlayX: overlayX == null ? current.overlayX : _clampUnit(overlayX),
        overlayY: overlayY == null ? current.overlayY : _clampUnit(overlayY),
        overlayScale: overlayScale == null
            ? current.overlayScale
            : _clampImageOverlayScale(overlayScale),
      );
      updatedTracks.add(track.copyWith(clips: updatedClips));
      changed = true;
    }
    if (!changed) {
      return this;
    }
    return copyWith(tracks: updatedTracks, updatedAt: DateTime.now());
  }

  TgiProject resizeImageClip(
    String clipId, {
    required Duration timelineStart,
    required Duration duration,
  }) {
    final clampedDuration = duration < _minimumImageClipDuration
        ? _minimumTextClipDuration
        : duration;
    final start = _normalizeTimelineStart(timelineStart);
    final updatedTracks = <Track>[];
    for (final track in tracks) {
      final clipIndex = track.clips.indexWhere((c) => c.id == clipId);
      if (clipIndex < 0) {
        updatedTracks.add(track);
        continue;
      }
      final updatedClips = List<Clip>.from(track.clips);
      updatedClips[clipIndex] = updatedClips[clipIndex].copyWith(
        timelineStart: start,
        duration: clampedDuration,
      );
      updatedTracks.add(track.copyWith(clips: updatedClips));
    }
    return copyWith(tracks: updatedTracks, updatedAt: DateTime.now());
  }

  TgiProject trimTimelineClipGroup(
    String clipId, {
    required Duration sourceStart,
    required Duration sourceDuration,
  }) {
    final referenceClip = _findClipById(clipId);
    if (referenceClip == null ||
        (referenceClip.trackType != TrackType.video &&
            referenceClip.trackType != TrackType.audio)) {
      return this;
    }

    var changed = false;
    final updatedTracks = <Track>[];
    for (final track in tracks) {
      var trackChanged = false;
      final updatedClips = <Clip>[];
      for (final clip in track.clips) {
        if (clip.timelineGroupId != referenceClip.timelineGroupId ||
            (clip.trackType != TrackType.video &&
                clip.trackType != TrackType.audio)) {
          updatedClips.add(clip);
          continue;
        }

        final mediaDuration =
            mediaItemById(clip.mediaItemId)?.duration ?? clip.sourceEnd;
        if (mediaDuration <= Duration.zero) {
          updatedClips.add(clip);
          continue;
        }

        final minimumSourceDuration = _sourceDurationForTimeline(
          _minimumMediaTrimTimelineDuration,
          clip.playbackSpeed,
        );
        final effectiveMinimumSourceDuration =
            mediaDuration < minimumSourceDuration
            ? mediaDuration
            : minimumSourceDuration;
        final maxStart = mediaDuration - effectiveMinimumSourceDuration;
        final nextSourceStart = _clampDuration(
          sourceStart,
          Duration.zero,
          maxStart < Duration.zero ? Duration.zero : maxStart,
        );
        final maxSourceDuration = mediaDuration - nextSourceStart;
        final nextSourceDuration = _clampDuration(
          sourceDuration,
          effectiveMinimumSourceDuration,
          maxSourceDuration < effectiveMinimumSourceDuration
              ? effectiveMinimumSourceDuration
              : maxSourceDuration,
        );
        final nextTimelineDuration = _timelineDurationForSource(
          nextSourceDuration,
          clip.playbackSpeed,
        );
        final maxFade = Duration(
          microseconds: (nextTimelineDuration.inMicroseconds / 2).floor(),
        );
        final nextClip = clip.copyWith(
          sourceStart: nextSourceStart,
          sourceDuration: nextSourceDuration,
          duration: nextTimelineDuration,
          fadeIn: _clampDuration(clip.fadeIn, Duration.zero, maxFade),
          fadeOut: _clampDuration(clip.fadeOut, Duration.zero, maxFade),
        );
        updatedClips.add(nextClip);
        if (nextClip.sourceStart != clip.sourceStart ||
            nextClip.sourceDuration != clip.sourceDuration ||
            nextClip.duration != clip.duration ||
            nextClip.fadeIn != clip.fadeIn ||
            nextClip.fadeOut != clip.fadeOut) {
          trackChanged = true;
          changed = true;
        }
      }
      updatedTracks.add(
        trackChanged ? track.copyWith(clips: _sortClips(updatedClips)) : track,
      );
    }

    if (!changed) {
      return this;
    }
    return copyWith(tracks: updatedTracks, updatedAt: DateTime.now());
  }

  TgiProject updateClipVolume(String clipId, {required double volume}) {
    final clamped = volume.clamp(0.0, 2.0);
    final updatedTracks = <Track>[];
    for (final track in tracks) {
      final clipIndex = track.clips.indexWhere((c) => c.id == clipId);
      if (clipIndex < 0) {
        updatedTracks.add(track);
        continue;
      }
      final updatedClips = List<Clip>.from(track.clips);
      updatedClips[clipIndex] = updatedClips[clipIndex].copyWith(
        volume: clamped,
      );
      updatedTracks.add(track.copyWith(clips: updatedClips));
    }
    return copyWith(tracks: updatedTracks, updatedAt: DateTime.now());
  }

  TgiProject updateClipAudioNoiseReduction(
    String clipId, {
    required double noiseReductionDb,
  }) {
    final clamped = _clampAudioNoiseReduction(noiseReductionDb);
    var changed = false;
    final updatedTracks = <Track>[];
    for (final track in tracks) {
      final clipIndex = track.clips.indexWhere((c) => c.id == clipId);
      if (clipIndex < 0 ||
          track.clips[clipIndex].trackType != TrackType.audio) {
        updatedTracks.add(track);
        continue;
      }
      final currentClip = track.clips[clipIndex];
      if (currentClip.audioNoiseReductionDb == clamped) {
        updatedTracks.add(track);
        continue;
      }
      final updatedClips = List<Clip>.from(track.clips);
      updatedClips[clipIndex] = currentClip.copyWith(
        audioNoiseReductionDb: clamped,
      );
      updatedTracks.add(track.copyWith(clips: updatedClips));
      changed = true;
    }
    if (!changed) {
      return this;
    }
    return copyWith(tracks: updatedTracks, updatedAt: DateTime.now());
  }

  TgiProject updateVideoClipLook(
    String clipId, {
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
    bool? stabilizationEnabled,
  }) {
    var changed = false;
    final updatedTracks = <Track>[];
    for (final track in tracks) {
      final clipIndex = track.clips.indexWhere((c) => c.id == clipId);
      if (clipIndex < 0 ||
          track.clips[clipIndex].trackType != TrackType.video) {
        updatedTracks.add(track);
        continue;
      }

      final current = track.clips[clipIndex];
      final next = current.copyWith(
        brightness: brightness == null
            ? current.brightness
            : _clampVideoBrightness(brightness),
        contrast: contrast == null
            ? current.contrast
            : _clampVideoContrast(contrast),
        saturation: saturation == null
            ? current.saturation
            : _clampVideoSaturation(saturation),
        exposure: exposure == null
            ? current.exposure
            : _clampVideoExposure(exposure),
        hue: hue == null ? current.hue : _clampVideoHue(hue),
        temperature: temperature == null
            ? current.temperature
            : _clampVideoColorBalance(temperature),
        tint: tint == null ? current.tint : _clampVideoColorBalance(tint),
        shadows: shadows == null
            ? current.shadows
            : _clampVideoColorBalance(shadows),
        highlights: highlights == null
            ? current.highlights
            : _clampVideoColorBalance(highlights),
        curveShadows: curveShadows == null
            ? current.curveShadows
            : _clampVideoColorBalance(curveShadows),
        curveMidtones: curveMidtones == null
            ? current.curveMidtones
            : _clampVideoColorBalance(curveMidtones),
        curveHighlights: curveHighlights == null
            ? current.curveHighlights
            : _clampVideoColorBalance(curveHighlights),
        filterPreset: filterPreset ?? current.filterPreset,
        reverseVideo: reverseVideo ?? current.reverseVideo,
        chromaKeyEnabled: chromaKeyEnabled ?? current.chromaKeyEnabled,
        chromaKeyColor: chromaKeyColor ?? current.chromaKeyColor,
        chromaKeySimilarity: chromaKeySimilarity == null
            ? current.chromaKeySimilarity
            : _clampChromaKeySimilarity(chromaKeySimilarity),
        chromaKeyBlend: chromaKeyBlend == null
            ? current.chromaKeyBlend
            : _clampChromaKeyBlend(chromaKeyBlend),
        stabilizationEnabled:
            stabilizationEnabled ?? current.stabilizationEnabled,
      );
      if (_sameVideoLookClip(current, next)) {
        updatedTracks.add(track);
        continue;
      }

      final updatedClips = List<Clip>.from(track.clips);
      updatedClips[clipIndex] = next;
      updatedTracks.add(track.copyWith(clips: updatedClips));
      changed = true;
    }

    if (!changed) {
      return this;
    }
    return copyWith(tracks: updatedTracks, updatedAt: DateTime.now());
  }

  TgiProject updateVideoClipMask(
    String clipId, {
    bool? enabled,
    VideoMaskShape? shape,
    VideoMaskEffect? effect,
    double? x,
    double? y,
    double? width,
    double? height,
    double? feather,
    double? intensity,
    bool? inverted,
  }) {
    var changed = false;
    final updatedTracks = <Track>[];
    for (final track in tracks) {
      final clipIndex = track.clips.indexWhere((clip) => clip.id == clipId);
      if (clipIndex < 0 ||
          track.clips[clipIndex].trackType != TrackType.video) {
        updatedTracks.add(track);
        continue;
      }
      final current = track.clips[clipIndex];
      final next = current.copyWith(
        maskEnabled: enabled ?? current.maskEnabled,
        maskShape: shape ?? current.maskShape,
        maskEffect: effect ?? current.maskEffect,
        maskX: x == null ? current.maskX : _clampUnit(x),
        maskY: y == null ? current.maskY : _clampUnit(y),
        maskWidth: width == null
            ? current.maskWidth
            : width.clamp(0.04, 1.0).toDouble(),
        maskHeight: height == null
            ? current.maskHeight
            : height.clamp(0.04, 1.0).toDouble(),
        maskFeather: feather == null
            ? current.maskFeather
            : feather.clamp(0.0, 0.5).toDouble(),
        maskIntensity: intensity == null
            ? current.maskIntensity
            : intensity.clamp(0.05, 1.0).toDouble(),
        maskInverted: inverted ?? current.maskInverted,
      );
      if (_sameMaskClip(current, next)) {
        updatedTracks.add(track);
        continue;
      }
      final clips = List<Clip>.from(track.clips)..[clipIndex] = next;
      updatedTracks.add(track.copyWith(clips: clips));
      changed = true;
    }
    if (!changed) return this;
    return copyWith(tracks: updatedTracks, updatedAt: DateTime.now());
  }

  TgiProject updateClipCrop(
    String clipId, {
    double? cropLeft,
    double? cropTop,
    double? cropRight,
    double? cropBottom,
  }) {
    var changed = false;
    final updatedTracks = <Track>[];
    for (final track in tracks) {
      final clipIndex = track.clips.indexWhere((c) => c.id == clipId);
      if (clipIndex < 0 ||
          (track.clips[clipIndex].trackType != TrackType.video &&
              track.clips[clipIndex].trackType != TrackType.image)) {
        updatedTracks.add(track);
        continue;
      }

      final current = track.clips[clipIndex];
      final normalized = _normalizeCropInsets(
        left: cropLeft ?? current.cropLeft,
        top: cropTop ?? current.cropTop,
        right: cropRight ?? current.cropRight,
        bottom: cropBottom ?? current.cropBottom,
      );
      final next = current.copyWith(
        cropLeft: normalized.left,
        cropTop: normalized.top,
        cropRight: normalized.right,
        cropBottom: normalized.bottom,
      );
      if (_sameCropClip(current, next)) {
        updatedTracks.add(track);
        continue;
      }

      final updatedClips = List<Clip>.from(track.clips);
      updatedClips[clipIndex] = next;
      updatedTracks.add(track.copyWith(clips: updatedClips));
      changed = true;
    }

    if (!changed) {
      return this;
    }
    return copyWith(tracks: updatedTracks, updatedAt: DateTime.now());
  }

  TgiProject updateClipTransform(
    String clipId, {
    double? offsetX,
    double? offsetY,
    double? scale,
    double? rotationDegrees,
    bool? flipHorizontal,
    bool? flipVertical,
  }) {
    var changed = false;
    final updatedTracks = <Track>[];
    for (final track in tracks) {
      final clipIndex = track.clips.indexWhere((clip) => clip.id == clipId);
      if (clipIndex < 0 ||
          (track.clips[clipIndex].trackType != TrackType.video &&
              track.clips[clipIndex].trackType != TrackType.image)) {
        updatedTracks.add(track);
        continue;
      }
      final current = track.clips[clipIndex];
      final next = current.copyWith(
        transformOffsetX: offsetX == null
            ? current.transformOffsetX
            : _clampTransformOffset(offsetX),
        transformOffsetY: offsetY == null
            ? current.transformOffsetY
            : _clampTransformOffset(offsetY),
        transformScale: scale == null
            ? current.transformScale
            : _clampTransformScale(scale),
        rotationDegrees: rotationDegrees == null
            ? current.rotationDegrees
            : _normalizeRotation(rotationDegrees),
        flipHorizontal: flipHorizontal ?? current.flipHorizontal,
        flipVertical: flipVertical ?? current.flipVertical,
      );
      if (_sameTransformClip(current, next)) {
        updatedTracks.add(track);
        continue;
      }
      final clips = List<Clip>.from(track.clips)..[clipIndex] = next;
      updatedTracks.add(track.copyWith(clips: clips));
      changed = true;
    }
    if (!changed) {
      return this;
    }
    return copyWith(tracks: updatedTracks, updatedAt: DateTime.now());
  }

  TgiProject updateClipKenBurns(
    String clipId, {
    bool? enabled,
    double? startOverlayX,
    double? startOverlayY,
    double? startOverlayScale,
    double? endOverlayX,
    double? endOverlayY,
    double? endOverlayScale,
    double? kenBurnsStart,
    double? kenBurnsEnd,
  }) {
    var changed = false;
    final updatedTracks = <Track>[];
    for (final track in tracks) {
      final clipIndex = track.clips.indexWhere((c) => c.id == clipId);
      if (clipIndex < 0 ||
          (track.clips[clipIndex].trackType != TrackType.image &&
              track.clips[clipIndex].trackType != TrackType.video)) {
        updatedTracks.add(track);
        continue;
      }

      final current = track.clips[clipIndex];
      final timing = _normalizeKenBurnsTiming(
        start: kenBurnsStart ?? current.kenBurnsStart,
        end: kenBurnsEnd ?? current.kenBurnsEnd,
      );
      final next = current.copyWith(
        kenBurnsEnabled: enabled ?? current.kenBurnsEnabled,
        startOverlayX: startOverlayX == null
            ? current.startOverlayX
            : _clampUnit(startOverlayX),
        startOverlayY: startOverlayY == null
            ? current.startOverlayY
            : _clampUnit(startOverlayY),
        startOverlayScale: startOverlayScale == null
            ? current.startOverlayScale
            : _clampImageOverlayScale(startOverlayScale),
        overlayX: endOverlayX == null
            ? current.overlayX
            : _clampUnit(endOverlayX),
        overlayY: endOverlayY == null
            ? current.overlayY
            : _clampUnit(endOverlayY),
        overlayScale: endOverlayScale == null
            ? current.overlayScale
            : _clampImageOverlayScale(endOverlayScale),
        kenBurnsStart: timing.start,
        kenBurnsEnd: timing.end,
      );
      if (_sameKenBurnsClip(current, next)) {
        updatedTracks.add(track);
        continue;
      }

      final updatedClips = List<Clip>.from(track.clips);
      updatedClips[clipIndex] = next;
      updatedTracks.add(track.copyWith(clips: updatedClips));
      changed = true;
    }

    if (!changed) {
      return this;
    }
    return copyWith(tracks: updatedTracks, updatedAt: DateTime.now());
  }

  TgiProject upsertClipKeyframe(
    String clipId, {
    required ClipKeyframeProperty property,
    required double time,
    required double value,
  }) {
    var changed = false;
    final updatedTracks = <Track>[];
    for (final track in tracks) {
      final clipIndex = track.clips.indexWhere((c) => c.id == clipId);
      if (clipIndex < 0) {
        updatedTracks.add(track);
        continue;
      }

      final current = track.clips[clipIndex];
      final safeTime = _clampUnit(time);
      final safeValue = _clampKeyframeValue(property: property, value: value);
      final keyframes = List<ClipKeyframe>.from(current.keyframes);
      final existingIndex = keyframes.indexWhere(
        (keyframe) =>
            keyframe.property == property &&
            (keyframe.time - safeTime).abs() <= 0.005,
      );
      if (existingIndex >= 0) {
        final existing = keyframes[existingIndex];
        final next = existing.copyWith(time: safeTime, value: safeValue);
        if (existing.time == next.time && existing.value == next.value) {
          updatedTracks.add(track);
          continue;
        }
        keyframes[existingIndex] = next;
      } else {
        keyframes.add(
          ClipKeyframe(
            id: 'keyframe_${++_nextKeyframeId}',
            property: property,
            time: safeTime,
            value: safeValue,
          ),
        );
      }

      final updatedClips = List<Clip>.from(track.clips);
      updatedClips[clipIndex] = current.copyWith(
        keyframes: _sortKeyframes(keyframes),
      );
      updatedTracks.add(track.copyWith(clips: updatedClips));
      changed = true;
    }

    if (!changed) {
      return this;
    }
    return copyWith(tracks: updatedTracks, updatedAt: DateTime.now());
  }

  TgiProject removeClipKeyframe(String clipId, String keyframeId) {
    var changed = false;
    final updatedTracks = <Track>[];
    for (final track in tracks) {
      final clipIndex = track.clips.indexWhere((c) => c.id == clipId);
      if (clipIndex < 0) {
        updatedTracks.add(track);
        continue;
      }
      final current = track.clips[clipIndex];
      final keyframes = [
        for (final keyframe in current.keyframes)
          if (keyframe.id != keyframeId) keyframe,
      ];
      if (keyframes.length == current.keyframes.length) {
        updatedTracks.add(track);
        continue;
      }
      final updatedClips = List<Clip>.from(track.clips);
      updatedClips[clipIndex] = current.copyWith(keyframes: keyframes);
      updatedTracks.add(track.copyWith(clips: updatedClips));
      changed = true;
    }

    if (!changed) {
      return this;
    }
    return copyWith(tracks: updatedTracks, updatedAt: DateTime.now());
  }

  TgiProject removeClipKeyframeNear(
    String clipId, {
    required ClipKeyframeProperty property,
    required double time,
  }) {
    final clip = _findClipById(clipId);
    if (clip == null) {
      return this;
    }
    final safeTime = _clampUnit(time);
    ClipKeyframe? nearest;
    var nearestDistance = double.infinity;
    for (final keyframe in clip.keyframesFor(property)) {
      final distance = (keyframe.time - safeTime).abs();
      if (distance < nearestDistance) {
        nearest = keyframe;
        nearestDistance = distance;
      }
    }
    if (nearest == null || nearestDistance > 0.02) {
      return this;
    }
    return removeClipKeyframe(clipId, nearest.id);
  }

  TgiProject clearClipKeyframes(
    String clipId, {
    ClipKeyframeProperty? property,
  }) {
    var changed = false;
    final updatedTracks = <Track>[];
    for (final track in tracks) {
      final clipIndex = track.clips.indexWhere((c) => c.id == clipId);
      if (clipIndex < 0) {
        updatedTracks.add(track);
        continue;
      }
      final current = track.clips[clipIndex];
      final keyframes = property == null
          ? <ClipKeyframe>[]
          : [
              for (final keyframe in current.keyframes)
                if (keyframe.property != property) keyframe,
            ];
      if (keyframes.length == current.keyframes.length) {
        updatedTracks.add(track);
        continue;
      }
      final updatedClips = List<Clip>.from(track.clips);
      updatedClips[clipIndex] = current.copyWith(keyframes: keyframes);
      updatedTracks.add(track.copyWith(clips: updatedClips));
      changed = true;
    }

    if (!changed) {
      return this;
    }
    return copyWith(tracks: updatedTracks, updatedAt: DateTime.now());
  }

  TgiProject updateWatermark(
    ProjectWatermark Function(ProjectWatermark) update,
  ) {
    final next = _normalizeWatermark(update(watermark));
    if (_sameWatermark(watermark, next)) {
      return this;
    }
    return copyWith(watermark: next, updatedAt: DateTime.now());
  }

  TgiProject updateClipTransition(
    String clipId, {
    required Duration fadeIn,
    required Duration fadeOut,
  }) {
    final normalizedFadeIn = _normalizeTransitionDuration(fadeIn);
    final normalizedFadeOut = _normalizeTransitionDuration(fadeOut);
    var changed = false;
    final updatedTracks = <Track>[];
    for (final track in tracks) {
      final clipIndex = track.clips.indexWhere((clip) => clip.id == clipId);
      if (clipIndex < 0) {
        updatedTracks.add(track);
        continue;
      }
      final updatedClips = List<Clip>.from(track.clips);
      final clip = updatedClips[clipIndex];
      final maxFade = Duration(
        microseconds: (clip.duration.inMicroseconds / 2).floor(),
      );
      final nextClip = clip.copyWith(
        fadeIn: _clampDuration(normalizedFadeIn, Duration.zero, maxFade),
        fadeOut: _clampDuration(normalizedFadeOut, Duration.zero, maxFade),
      );
      updatedClips[clipIndex] = nextClip;
      updatedTracks.add(track.copyWith(clips: updatedClips));
      if (nextClip.fadeIn != clip.fadeIn || nextClip.fadeOut != clip.fadeOut) {
        changed = true;
      }
    }

    if (!changed) {
      return this;
    }
    return copyWith(tracks: updatedTracks, updatedAt: DateTime.now());
  }

  TgiProject updateClipGroupTransition(
    String timelineGroupId, {
    required Duration fadeIn,
    required Duration fadeOut,
  }) {
    final normalizedFadeIn = _normalizeTransitionDuration(fadeIn);
    final normalizedFadeOut = _normalizeTransitionDuration(fadeOut);
    var changed = false;
    final updatedTracks = <Track>[];
    for (final track in tracks) {
      var trackChanged = false;
      final updatedClips = <Clip>[];
      for (final clip in track.clips) {
        if (clip.timelineGroupId != timelineGroupId) {
          updatedClips.add(clip);
          continue;
        }
        final maxFade = Duration(
          microseconds: (clip.duration.inMicroseconds / 2).floor(),
        );
        final nextClip = clip.copyWith(
          fadeIn: _clampDuration(normalizedFadeIn, Duration.zero, maxFade),
          fadeOut: _clampDuration(normalizedFadeOut, Duration.zero, maxFade),
        );
        updatedClips.add(nextClip);
        if (nextClip.fadeIn != clip.fadeIn ||
            nextClip.fadeOut != clip.fadeOut) {
          trackChanged = true;
          changed = true;
        }
      }
      updatedTracks.add(
        trackChanged ? track.copyWith(clips: updatedClips) : track,
      );
    }

    if (!changed) {
      return this;
    }
    return copyWith(tracks: updatedTracks, updatedAt: DateTime.now());
  }

  TgiProject updateClipGroupPlaybackSpeed(
    String timelineGroupId, {
    required double playbackSpeed,
  }) {
    final speed = _clampPlaybackSpeed(playbackSpeed);
    Clip? referenceClip;
    for (final track in tracks) {
      if (track.type != TrackType.video) continue;
      for (final clip in track.clips) {
        if (clip.timelineGroupId == timelineGroupId) {
          referenceClip = clip;
          break;
        }
      }
      if (referenceClip != null) break;
    }
    final reference = referenceClip;
    if (reference == null) return this;
    final oldEnd = reference.timelineEnd;
    final nextReferenceDuration = _timelineDurationForSource(
      reference.effectiveSourceDuration,
      speed,
    );
    final timelineDelta = nextReferenceDuration - reference.duration;
    var changed = false;
    final updatedTracks = <Track>[];
    for (final track in tracks) {
      var trackChanged = false;
      final updatedClips = <Clip>[];
      for (final clip in track.clips) {
        if (clip.timelineGroupId != timelineGroupId) {
          final shouldRipple =
              timelineDelta != Duration.zero && clip.timelineStart >= oldEnd;
          updatedClips.add(
            shouldRipple
                ? clip.copyWith(
                    timelineStart: _normalizeTimelineStart(
                      clip.timelineStart + timelineDelta,
                    ),
                  )
                : clip,
          );
          trackChanged = trackChanged || shouldRipple;
          changed = changed || shouldRipple;
          continue;
        }

        if (track.type != TrackType.video && track.type != TrackType.audio) {
          updatedClips.add(clip);
          continue;
        }

        final sourceDuration = clip.effectiveSourceDuration;
        final timelineDuration = _timelineDurationForSource(
          sourceDuration,
          speed,
        );
        final updatedClip = clip.copyWith(
          duration: timelineDuration,
          sourceDuration: sourceDuration,
          playbackSpeed: speed,
        );
        updatedClips.add(updatedClip);
        if (clip.duration != updatedClip.duration ||
            clip.sourceDuration != updatedClip.sourceDuration ||
            clip.playbackSpeed != updatedClip.playbackSpeed) {
          trackChanged = true;
          changed = true;
        }
      }

      updatedTracks.add(
        trackChanged ? track.copyWith(clips: _sortClips(updatedClips)) : track,
      );
    }

    if (!changed) {
      return this;
    }
    final updatedMarkers = [
      for (final marker in markers)
        timelineDelta != Duration.zero && marker.position >= oldEnd
            ? marker.copyWith(
                position: _normalizeTimelineStart(
                  marker.position + timelineDelta,
                ),
              )
            : marker,
    ];
    final updatedTransitions = [
      for (final transition in transitions)
        timelineDelta != Duration.zero && transition.timelinePosition >= oldEnd
            ? transition.copyWith(
                timelinePosition: _normalizeTimelineStart(
                  transition.timelinePosition + timelineDelta,
                ),
              )
            : transition,
    ];
    return copyWith(
      tracks: updatedTracks,
      markers: _sortMarkers(updatedMarkers),
      transitions: _sortTransitions(updatedTransitions),
      updatedAt: DateTime.now(),
    );
  }

  TgiProject slipTimelineClipGroup(
    String timelineGroupId, {
    required Duration sourceDelta,
  }) {
    if (sourceDelta == Duration.zero) return this;
    final groupClips = <Clip>[];
    for (final track in tracks) {
      if (track.type != TrackType.video && track.type != TrackType.audio) {
        continue;
      }
      groupClips.addAll(
        track.clips.where((clip) => clip.timelineGroupId == timelineGroupId),
      );
    }
    if (groupClips.isEmpty) return this;

    var minimumDeltaUs = -0x7fffffffffffffff;
    var maximumDeltaUs = 0x7fffffffffffffff;
    for (final clip in groupClips) {
      final media = mediaItemById(clip.mediaItemId);
      if (media == null) return this;
      minimumDeltaUs = math.max(
        minimumDeltaUs,
        -clip.sourceStart.inMicroseconds,
      );
      maximumDeltaUs = math.min(
        maximumDeltaUs,
        (media.duration - clip.sourceEnd).inMicroseconds,
      );
    }
    final deltaUs = sourceDelta.inMicroseconds.clamp(
      minimumDeltaUs,
      maximumDeltaUs,
    );
    if (deltaUs == 0) return this;
    final delta = Duration(microseconds: deltaUs);
    final updatedTracks = [
      for (final track in tracks)
        track.copyWith(
          clips: [
            for (final clip in track.clips)
              clip.timelineGroupId == timelineGroupId &&
                      (track.type == TrackType.video ||
                          track.type == TrackType.audio)
                  ? clip.copyWith(sourceStart: clip.sourceStart + delta)
                  : clip,
          ],
        ),
    ];
    return copyWith(tracks: updatedTracks, updatedAt: DateTime.now());
  }

  TgiProject slideTimelineClipGroup(
    String timelineGroupId, {
    required Duration timelineDelta,
  }) {
    if (timelineDelta == Duration.zero) return this;
    Track? referenceTrack;
    Clip? selected;
    for (final track in tracks) {
      if (track.type != TrackType.video) continue;
      for (final clip in track.clips) {
        if (clip.timelineGroupId == timelineGroupId) {
          referenceTrack = track;
          selected = clip;
          break;
        }
      }
      if (selected != null) break;
    }
    final current = selected;
    final videoTrack = referenceTrack;
    if (current == null || videoTrack == null) return this;
    final ordered = _sortClips(videoTrack.clips);
    final selectedIndex = ordered.indexWhere((clip) => clip.id == current.id);
    if (selectedIndex <= 0 || selectedIndex >= ordered.length - 1) return this;
    final previous = ordered[selectedIndex - 1];
    final next = ordered[selectedIndex + 1];
    const tolerance = Duration(milliseconds: 3);
    if ((previous.timelineEnd - current.timelineStart).abs() > tolerance ||
        (next.timelineStart - current.timelineEnd).abs() > tolerance) {
      return this;
    }

    const minimumClipDuration = Duration(milliseconds: 100);
    var minimumDeltaUs = math.max(
      -current.timelineStart.inMicroseconds,
      (minimumClipDuration - previous.duration).inMicroseconds,
    );
    var maximumDeltaUs = (next.duration - minimumClipDuration).inMicroseconds;
    final previousMedia = mediaItemById(previous.mediaItemId);
    final nextMedia = mediaItemById(next.mediaItemId);
    if (previousMedia == null || nextMedia == null) return this;
    final previousExpansion = Duration(
      microseconds:
          ((previousMedia.duration - previous.sourceEnd).inMicroseconds /
                  previous.playbackSpeed)
              .floor(),
    );
    final nextBackwardExpansion = Duration(
      microseconds: (next.sourceStart.inMicroseconds / next.playbackSpeed)
          .floor(),
    );
    maximumDeltaUs = math.min(maximumDeltaUs, previousExpansion.inMicroseconds);
    minimumDeltaUs = math.max(
      minimumDeltaUs,
      -nextBackwardExpansion.inMicroseconds,
    );
    final deltaUs = timelineDelta.inMicroseconds.clamp(
      minimumDeltaUs,
      maximumDeltaUs,
    );
    if (deltaUs == 0) return this;
    final delta = Duration(microseconds: deltaUs);
    final affectedGroups = {
      previous.timelineGroupId,
      current.timelineGroupId,
      next.timelineGroupId,
    };

    final updatedTracks = <Track>[];
    for (final track in tracks) {
      final updatedClips = <Clip>[];
      for (final clip in track.clips) {
        if (!affectedGroups.contains(clip.timelineGroupId)) {
          updatedClips.add(clip);
          continue;
        }
        if (clip.timelineGroupId == current.timelineGroupId) {
          updatedClips.add(
            clip.copyWith(timelineStart: clip.timelineStart + delta),
          );
          continue;
        }
        final sourceDelta = _sourceDurationForTimeline(
          delta.abs(),
          clip.playbackSpeed,
        );
        if (clip.timelineGroupId == previous.timelineGroupId) {
          updatedClips.add(
            clip.copyWith(
              duration: clip.duration + delta,
              sourceDuration:
                  clip.effectiveSourceDuration +
                  (delta.isNegative ? -sourceDelta : sourceDelta),
            ),
          );
        } else {
          final signedSourceDelta = delta.isNegative
              ? -sourceDelta
              : sourceDelta;
          updatedClips.add(
            clip.copyWith(
              timelineStart: clip.timelineStart + delta,
              duration: clip.duration - delta,
              sourceStart: clip.sourceStart + signedSourceDelta,
              sourceDuration: clip.effectiveSourceDuration - signedSourceDelta,
            ),
          );
        }
      }
      updatedTracks.add(track.copyWith(clips: _sortClips(updatedClips)));
    }
    final updatedTransitions = [
      for (final transition in transitions)
        ((transition.timelinePosition - current.timelineStart).abs() <=
                    tolerance ||
                (transition.timelinePosition - current.timelineEnd).abs() <=
                    tolerance)
            ? transition.copyWith(
                timelinePosition: transition.timelinePosition + delta,
              )
            : transition,
    ];
    return copyWith(
      tracks: updatedTracks,
      transitions: _sortTransitions(updatedTransitions),
      updatedAt: DateTime.now(),
    );
  }

  TgiProject applyClipGroupSpeedRamp(
    String timelineGroupId, {
    required List<double> speedMultipliers,
  }) {
    if (speedMultipliers.length < 2) {
      return this;
    }
    Clip? referenceClip;
    for (final track in tracks) {
      if (track.type != TrackType.video) continue;
      for (final clip in track.clips) {
        if (clip.timelineGroupId == timelineGroupId) {
          referenceClip = clip;
          break;
        }
      }
      if (referenceClip != null) break;
    }
    final reference = referenceClip;
    if (reference == null ||
        reference.effectiveSourceDuration <= Duration.zero) {
      return this;
    }

    final safeMultipliers = [
      for (final value in speedMultipliers)
        value.isFinite && value > 0 ? value.clamp(0.1, 8.0).toDouble() : 1.0,
    ];
    final inverseAverage =
        safeMultipliers.fold<double>(0, (sum, value) => sum + 1 / value) /
        safeMultipliers.length;
    final baseSpeed = _clampPlaybackSpeed(reference.playbackSpeed);
    final speeds = [
      for (final multiplier in safeMultipliers)
        _clampPlaybackSpeed(baseSpeed * multiplier * inverseAverage),
    ];
    final groupIds = <String>[
      timelineGroupId,
      for (var index = 1; index < speeds.length; index++)
        'group_${++_nextGroupId}',
    ];

    final sourceTotalUs = reference.effectiveSourceDuration.inMicroseconds;
    final sourceBoundaries = <int>[0];
    for (var index = 1; index < speeds.length; index++) {
      sourceBoundaries.add((sourceTotalUs * index / speeds.length).round());
    }
    sourceBoundaries.add(sourceTotalUs);
    final segmentDurations = <Duration>[];
    for (var index = 0; index < speeds.length; index++) {
      segmentDurations.add(
        _timelineDurationForSource(
          Duration(
            microseconds: sourceBoundaries[index + 1] - sourceBoundaries[index],
          ),
          speeds[index],
        ),
      );
    }
    final nextTotalDuration = segmentDurations.fold<Duration>(
      Duration.zero,
      (total, duration) => total + duration,
    );
    final oldEnd = reference.timelineEnd;
    final timelineDelta = nextTotalDuration - reference.duration;

    final updatedTracks = <Track>[];
    for (final track in tracks) {
      final updatedClips = <Clip>[];
      for (final clip in track.clips) {
        if (clip.timelineGroupId != timelineGroupId) {
          updatedClips.add(
            clip.timelineStart >= oldEnd && timelineDelta != Duration.zero
                ? clip.copyWith(
                    timelineStart: _normalizeTimelineStart(
                      clip.timelineStart + timelineDelta,
                    ),
                  )
                : clip,
          );
          continue;
        }

        var timelineCursor = clip.timelineStart;
        for (var index = 0; index < speeds.length; index++) {
          final sourceStartFraction = index / speeds.length;
          final sourceEndFraction = (index + 1) / speeds.length;
          final sourceOffset = Duration(microseconds: sourceBoundaries[index]);
          final sourceDuration = Duration(
            microseconds: sourceBoundaries[index + 1] - sourceBoundaries[index],
          );
          final duration = _timelineDurationForSource(
            sourceDuration,
            speeds[index],
          );
          updatedClips.add(
            clip.copyWith(
              id: 'clip_${++_nextClipId}_${_clipIdSuffix(clip.trackType)}',
              timelineGroupId: groupIds[index],
              timelineStart: timelineCursor,
              sourceStart: clip.sourceStart + sourceOffset,
              sourceDuration: sourceDuration,
              duration: duration,
              playbackSpeed: speeds[index],
              fadeIn: index == 0 ? clip.fadeIn : Duration.zero,
              fadeOut: index == speeds.length - 1
                  ? clip.fadeOut
                  : Duration.zero,
              keyframes: _sliceKeyframesForSpeedRamp(
                clip,
                sourceStartFraction,
                sourceEndFraction,
              ),
            ),
          );
          timelineCursor += duration;
        }
      }
      updatedTracks.add(track.copyWith(clips: _sortClips(updatedClips)));
    }

    final updatedMarkers = [
      for (final marker in markers)
        marker.position >= oldEnd && timelineDelta != Duration.zero
            ? marker.copyWith(
                position: _normalizeTimelineStart(
                  marker.position + timelineDelta,
                ),
              )
            : marker,
    ];
    final updatedTransitions = [
      for (final transition in transitions)
        transition.timelinePosition >= oldEnd && timelineDelta != Duration.zero
            ? transition.copyWith(
                timelinePosition: _normalizeTimelineStart(
                  transition.timelinePosition + timelineDelta,
                ),
              )
            : transition,
    ];
    return copyWith(
      tracks: updatedTracks,
      markers: _sortMarkers(updatedMarkers),
      transitions: _sortTransitions(updatedTransitions),
      updatedAt: DateTime.now(),
    );
  }

  List<ClipKeyframe> _sliceKeyframesForSpeedRamp(
    Clip clip,
    double start,
    double end,
  ) {
    if (clip.keyframes.isEmpty || end <= start) {
      return const [];
    }
    final span = end - start;
    final result = <ClipKeyframe>[];
    for (final property in ClipKeyframeProperty.values) {
      final sourceFrames = clip.keyframesFor(property);
      if (sourceFrames.isEmpty) continue;
      result.add(
        ClipKeyframe(
          id: 'keyframe_${++_nextKeyframeId}',
          property: property,
          time: 0,
          value: clip.keyframedValue(property, start),
        ),
      );
      for (final frame in sourceFrames) {
        if (frame.time <= start || frame.time >= end) continue;
        result.add(
          frame.copyWith(
            id: 'keyframe_${++_nextKeyframeId}',
            time: (frame.time - start) / span,
          ),
        );
      }
      result.add(
        ClipKeyframe(
          id: 'keyframe_${++_nextKeyframeId}',
          property: property,
          time: 1,
          value: clip.keyframedValue(property, end),
        ),
      );
    }
    return _sortKeyframes(result);
  }

  TgiProject splitTimelineClipGroupAt(
    String clipId, {
    required Duration timelinePosition,
  }) {
    final position = _normalizeTimelineStart(timelinePosition);
    final referenceClip = _findClipById(clipId);
    if (referenceClip == null) return this;
    final groupId = referenceClip.timelineGroupId;
    if (position <= referenceClip.timelineStart ||
        position >= referenceClip.timelineEnd) {
      return this;
    }
    final existingGroupIds = <String>{
      for (final track in tracks)
        for (final clip in track.clips) clip.timelineGroupId,
    };
    final existingClipIds = <String>{
      for (final track in tracks)
        for (final clip in track.clips) clip.id,
    };
    late String newGroupId;
    do {
      newGroupId = 'group_${++_nextGroupId}';
    } while (existingGroupIds.contains(newGroupId));

    String nextSplitClipId(String suffix) {
      late String id;
      do {
        id = 'clip_${++_nextClipId}_$suffix';
      } while (existingClipIds.contains(id));
      existingClipIds.add(id);
      return id;
    }

    final updatedTracks = <Track>[];
    for (final track in tracks) {
      final groupClips = track.clips
          .where((c) => c.timelineGroupId == groupId)
          .toList();
      if (groupClips.isEmpty) {
        updatedTracks.add(track);
        continue;
      }
      final updatedClips = <Clip>[];
      for (final clip in track.clips) {
        if (clip.timelineGroupId != groupId) {
          updatedClips.add(clip);
          continue;
        }
        final leftDuration = position - clip.timelineStart;
        final rightDuration = clip.timelineEnd - position;
        final keepsMediaSource =
            clip.trackType == TrackType.video ||
            clip.trackType == TrackType.audio;
        final leftSourceDuration = keepsMediaSource
            ? _clampDuration(
                _sourceDurationForTimeline(leftDuration, clip.playbackSpeed),
                Duration.zero,
                clip.effectiveSourceDuration,
              )
            : leftDuration;
        final rightSourceDuration = keepsMediaSource
            ? clip.effectiveSourceDuration - leftSourceDuration
            : rightDuration;
        final rightTimelineDuration = keepsMediaSource
            ? _timelineDurationForSource(
                rightSourceDuration,
                clip.playbackSpeed,
              )
            : rightDuration;
        final leftClip = clip.copyWith(
          id: nextSplitClipId('L'),
          duration: leftDuration,
          sourceDuration: keepsMediaSource
              ? leftSourceDuration
              : clip.sourceDuration,
        );
        final rightClip = clip.copyWith(
          id: nextSplitClipId('R'),
          timelineGroupId: newGroupId,
          timelineStart: position,
          sourceStart: clip.sourceStart + leftSourceDuration,
          duration: rightTimelineDuration,
          sourceDuration: keepsMediaSource
              ? rightSourceDuration
              : clip.sourceDuration,
        );
        updatedClips.add(leftClip);
        updatedClips.add(rightClip);
      }
      updatedTracks.add(track.copyWith(clips: updatedClips));
    }
    return copyWith(tracks: updatedTracks, updatedAt: DateTime.now());
  }

  TgiProject deleteTimelineClipGroup(String timelineGroupId) {
    return deleteTimelineClipGroups({timelineGroupId});
  }

  TgiProject deleteTimelineClipGroups(Set<String> timelineGroupIds) {
    if (timelineGroupIds.isEmpty) {
      return this;
    }
    final updatedTracks = <Track>[];
    var changed = false;
    for (final track in tracks) {
      final filteredClips = track.clips
          .where((c) => !timelineGroupIds.contains(c.timelineGroupId))
          .toList();
      changed = changed || filteredClips.length != track.clips.length;
      updatedTracks.add(track.copyWith(clips: filteredClips));
    }
    if (!changed) {
      return this;
    }
    return copyWith(tracks: updatedTracks, updatedAt: DateTime.now());
  }

  TgiProject rippleDeleteTimelineClipGroups(Set<String> timelineGroupIds) {
    if (timelineGroupIds.isEmpty) {
      return this;
    }
    Duration? gapStart;
    Duration? gapEnd;
    for (final track in tracks) {
      for (final clip in track.clips) {
        if (!timelineGroupIds.contains(clip.timelineGroupId)) continue;
        if (gapStart == null || clip.timelineStart < gapStart) {
          gapStart = clip.timelineStart;
        }
        if (gapEnd == null || clip.timelineEnd > gapEnd) {
          gapEnd = clip.timelineEnd;
        }
      }
    }
    if (gapStart == null || gapEnd == null || gapEnd <= gapStart) {
      return this;
    }
    final gapDuration = gapEnd - gapStart;
    final updatedTracks = <Track>[];
    for (final track in tracks) {
      final updatedClips = <Clip>[];
      for (final clip in track.clips) {
        if (timelineGroupIds.contains(clip.timelineGroupId)) continue;
        updatedClips.add(
          clip.timelineStart >= gapEnd
              ? clip.copyWith(timelineStart: clip.timelineStart - gapDuration)
              : clip,
        );
      }
      updatedTracks.add(track.copyWith(clips: _sortClips(updatedClips)));
    }
    final updatedMarkers = <TimelineMarker>[];
    for (final marker in markers) {
      if (marker.position >= gapStart && marker.position < gapEnd) continue;
      updatedMarkers.add(
        marker.position >= gapEnd
            ? marker.copyWith(position: marker.position - gapDuration)
            : marker,
      );
    }
    final updatedTransitions = <TimelineTransition>[];
    for (final transition in transitions) {
      if (transition.timelinePosition >= gapStart &&
          transition.timelinePosition < gapEnd) {
        continue;
      }
      updatedTransitions.add(
        transition.timelinePosition >= gapEnd
            ? transition.copyWith(
                timelinePosition: transition.timelinePosition - gapDuration,
              )
            : transition,
      );
    }
    return copyWith(
      tracks: updatedTracks,
      markers: _sortMarkers(updatedMarkers),
      transitions: _sortTransitions(updatedTransitions),
      updatedAt: DateTime.now(),
    );
  }

  TgiProject duplicateTimelineClipGroups(
    Set<String> timelineGroupIds, {
    required Duration timelineStart,
  }) {
    if (timelineGroupIds.isEmpty) {
      return this;
    }

    final sourceClips = <Clip>[];
    for (final track in tracks) {
      for (final clip in track.clips) {
        if (timelineGroupIds.contains(clip.timelineGroupId)) {
          sourceClips.add(clip);
        }
      }
    }
    if (sourceClips.isEmpty) {
      return this;
    }

    sourceClips.sort((a, b) {
      final timeCompare = a.timelineStart.compareTo(b.timelineStart);
      if (timeCompare != 0) {
        return timeCompare;
      }
      return a.id.compareTo(b.id);
    });

    final earliestStart = sourceClips.first.timelineStart;
    final targetStart = _normalizeTimelineStart(timelineStart);
    final groupIdMap = <String, String>{};
    final updatedTracks = <Track>[];
    var changed = false;

    for (final track in tracks) {
      final duplicates = <Clip>[];
      for (final clip in track.clips) {
        if (!timelineGroupIds.contains(clip.timelineGroupId)) {
          continue;
        }
        final newGroupId = groupIdMap.putIfAbsent(
          clip.timelineGroupId,
          () => 'group_${++_nextGroupId}',
        );
        final offset = clip.timelineStart - earliestStart;
        duplicates.add(
          clip.copyWith(
            id: 'clip_${++_nextClipId}_${_clipIdSuffix(clip.trackType)}',
            timelineGroupId: newGroupId,
            timelineStart: targetStart + offset,
          ),
        );
      }
      if (duplicates.isEmpty) {
        updatedTracks.add(track);
        continue;
      }
      changed = true;
      updatedTracks.add(
        track.copyWith(clips: _sortClips([...track.clips, ...duplicates])),
      );
    }

    if (!changed) {
      return this;
    }
    return copyWith(tracks: updatedTracks, updatedAt: DateTime.now());
  }

  List<Clip> _sortClips(List<Clip> clips) {
    return [...clips]
      ..sort((a, b) => a.timelineStart.compareTo(b.timelineStart));
  }

  List<TimelineMarker> _sortMarkers(List<TimelineMarker> markers) {
    return [...markers]..sort((a, b) => a.position.compareTo(b.position));
  }

  List<TimelineTransition> _sortTransitions(
    List<TimelineTransition> transitions,
  ) {
    return [...transitions]
      ..sort((a, b) => a.timelinePosition.compareTo(b.timelinePosition));
  }

  List<ClipKeyframe> _sortKeyframes(List<ClipKeyframe> keyframes) {
    return [...keyframes]..sort((a, b) {
      final property = a.property.index.compareTo(b.property.index);
      if (property != 0) {
        return property;
      }
      return a.time.compareTo(b.time);
    });
  }

  String _clipIdSuffix(TrackType type) {
    switch (type) {
      case TrackType.video:
        return 'v';
      case TrackType.audio:
        return 'a';
      case TrackType.image:
        return 'img';
      case TrackType.text:
        return 'txt';
    }
  }

  bool _sameTextStyleClip(Clip first, Clip second) {
    return first.textContent == second.textContent &&
        first.fontFamily == second.fontFamily &&
        first.fontSize == second.fontSize &&
        first.textColor == second.textColor &&
        first.backgroundColor == second.backgroundColor &&
        first.opacity == second.opacity &&
        first.textAnimation == second.textAnimation;
  }

  bool _sameVideoLookClip(Clip first, Clip second) {
    return first.brightness == second.brightness &&
        first.contrast == second.contrast &&
        first.saturation == second.saturation &&
        first.exposure == second.exposure &&
        first.hue == second.hue &&
        first.temperature == second.temperature &&
        first.tint == second.tint &&
        first.shadows == second.shadows &&
        first.highlights == second.highlights &&
        first.curveShadows == second.curveShadows &&
        first.curveMidtones == second.curveMidtones &&
        first.curveHighlights == second.curveHighlights &&
        first.filterPreset == second.filterPreset &&
        first.reverseVideo == second.reverseVideo &&
        first.chromaKeyEnabled == second.chromaKeyEnabled &&
        first.chromaKeyColor == second.chromaKeyColor &&
        first.chromaKeySimilarity == second.chromaKeySimilarity &&
        first.chromaKeyBlend == second.chromaKeyBlend &&
        first.stabilizationEnabled == second.stabilizationEnabled;
  }

  bool _sameMaskClip(Clip first, Clip second) {
    return first.maskEnabled == second.maskEnabled &&
        first.maskShape == second.maskShape &&
        first.maskEffect == second.maskEffect &&
        first.maskX == second.maskX &&
        first.maskY == second.maskY &&
        first.maskWidth == second.maskWidth &&
        first.maskHeight == second.maskHeight &&
        first.maskFeather == second.maskFeather &&
        first.maskIntensity == second.maskIntensity &&
        first.maskInverted == second.maskInverted;
  }

  bool _sameCropClip(Clip first, Clip second) {
    return first.cropLeft == second.cropLeft &&
        first.cropTop == second.cropTop &&
        first.cropRight == second.cropRight &&
        first.cropBottom == second.cropBottom;
  }

  bool _sameTransformClip(Clip first, Clip second) {
    return first.transformOffsetX == second.transformOffsetX &&
        first.transformOffsetY == second.transformOffsetY &&
        first.transformScale == second.transformScale &&
        first.rotationDegrees == second.rotationDegrees &&
        first.flipHorizontal == second.flipHorizontal &&
        first.flipVertical == second.flipVertical;
  }

  bool _sameKenBurnsClip(Clip first, Clip second) {
    return first.kenBurnsEnabled == second.kenBurnsEnabled &&
        first.startOverlayX == second.startOverlayX &&
        first.startOverlayY == second.startOverlayY &&
        first.startOverlayScale == second.startOverlayScale &&
        first.overlayX == second.overlayX &&
        first.overlayY == second.overlayY &&
        first.overlayScale == second.overlayScale &&
        first.kenBurnsStart == second.kenBurnsStart &&
        first.kenBurnsEnd == second.kenBurnsEnd;
  }

  bool _sameWatermark(ProjectWatermark first, ProjectWatermark second) {
    return first.enabled == second.enabled &&
        first.imagePath == second.imagePath &&
        first.position == second.position &&
        first.x == second.x &&
        first.y == second.y &&
        first.scale == second.scale &&
        first.opacity == second.opacity;
  }

  String _normalizedTextFontFamily(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? _defaultTextFontFamily : normalized;
  }

  double _clampTextFontSize(double value) {
    if (value.isNaN || value.isInfinite) {
      return 48;
    }
    return value.clamp(_minimumTextFontSize, _maximumTextFontSize).toDouble();
  }

  double _clampOpacity(double value) {
    if (value.isNaN || value.isInfinite) {
      return 1;
    }
    return value.clamp(0.0, 1.0).toDouble();
  }

  double _clampAudioNoiseReduction(double value) {
    if (value.isNaN || value.isInfinite) {
      return 0;
    }
    return value.clamp(0.0, _maximumAudioNoiseReductionDb).toDouble();
  }

  double _clampUnit(double value) {
    if (value.isNaN || value.isInfinite) {
      return 0.5;
    }
    return value.clamp(0.0, 1.0).toDouble();
  }

  double _clampImageOverlayScale(double value) {
    if (value.isNaN || value.isInfinite) {
      return 1;
    }
    return value
        .clamp(_minimumImageOverlayScale, _maximumImageOverlayScale)
        .toDouble();
  }

  double _clampChromaKeySimilarity(double value) {
    if (value.isNaN || value.isInfinite) {
      return 0.3;
    }
    return value
        .clamp(_minimumChromaKeySimilarity, _maximumChromaKeySimilarity)
        .toDouble();
  }

  double _clampChromaKeyBlend(double value) {
    if (value.isNaN || value.isInfinite) {
      return 0.1;
    }
    return value
        .clamp(_minimumChromaKeyBlend, _maximumChromaKeyBlend)
        .toDouble();
  }

  double _clampKeyframeValue({
    required ClipKeyframeProperty property,
    required double value,
  }) {
    if (value.isNaN || value.isInfinite) {
      return _keyframeFallbackValue(property);
    }
    switch (property) {
      case ClipKeyframeProperty.overlayX:
      case ClipKeyframeProperty.overlayY:
      case ClipKeyframeProperty.opacity:
      case ClipKeyframeProperty.cropLeft:
      case ClipKeyframeProperty.cropTop:
      case ClipKeyframeProperty.cropRight:
      case ClipKeyframeProperty.cropBottom:
      case ClipKeyframeProperty.chromaKeySimilarity:
      case ClipKeyframeProperty.chromaKeyBlend:
      case ClipKeyframeProperty.maskX:
      case ClipKeyframeProperty.maskY:
      case ClipKeyframeProperty.maskWidth:
      case ClipKeyframeProperty.maskHeight:
        return value.clamp(0.0, 1.0).toDouble();
      case ClipKeyframeProperty.overlayScale:
        return _clampImageOverlayScale(value);
      case ClipKeyframeProperty.volume:
        return value.clamp(0.0, 2.0).toDouble();
      case ClipKeyframeProperty.brightness:
        return value
            .clamp(_minimumVideoBrightness, _maximumVideoBrightness)
            .toDouble();
      case ClipKeyframeProperty.contrast:
        return value
            .clamp(_minimumVideoContrast, _maximumVideoContrast)
            .toDouble();
      case ClipKeyframeProperty.saturation:
        return value
            .clamp(_minimumVideoSaturation, _maximumVideoSaturation)
            .toDouble();
      case ClipKeyframeProperty.exposure:
        return value
            .clamp(_minimumVideoExposure, _maximumVideoExposure)
            .toDouble();
      case ClipKeyframeProperty.hue:
        return value.clamp(_minimumVideoHue, _maximumVideoHue).toDouble();
    }
  }

  double _keyframeFallbackValue(ClipKeyframeProperty property) {
    switch (property) {
      case ClipKeyframeProperty.overlayScale:
      case ClipKeyframeProperty.volume:
      case ClipKeyframeProperty.contrast:
      case ClipKeyframeProperty.saturation:
        return 1;
      case ClipKeyframeProperty.chromaKeySimilarity:
        return 0.3;
      case ClipKeyframeProperty.chromaKeyBlend:
        return 0.1;
      case ClipKeyframeProperty.overlayX:
      case ClipKeyframeProperty.overlayY:
      case ClipKeyframeProperty.maskX:
      case ClipKeyframeProperty.maskY:
        return 0.5;
      case ClipKeyframeProperty.maskWidth:
      case ClipKeyframeProperty.maskHeight:
        return 0.32;
      case ClipKeyframeProperty.opacity:
        return 1;
      case ClipKeyframeProperty.brightness:
      case ClipKeyframeProperty.exposure:
      case ClipKeyframeProperty.hue:
      case ClipKeyframeProperty.cropLeft:
      case ClipKeyframeProperty.cropTop:
      case ClipKeyframeProperty.cropRight:
      case ClipKeyframeProperty.cropBottom:
        return 0;
    }
  }

  _NormalizedCropInsets _normalizeCropInsets({
    required double left,
    required double top,
    required double right,
    required double bottom,
  }) {
    var normalizedLeft = _clampUnit(left);
    var normalizedTop = _clampUnit(top);
    var normalizedRight = _clampUnit(right);
    var normalizedBottom = _clampUnit(bottom);
    if (normalizedLeft + normalizedRight > 0.95) {
      final ratio = 0.95 / (normalizedLeft + normalizedRight);
      normalizedLeft *= ratio;
      normalizedRight *= ratio;
    }
    if (normalizedTop + normalizedBottom > 0.95) {
      final ratio = 0.95 / (normalizedTop + normalizedBottom);
      normalizedTop *= ratio;
      normalizedBottom *= ratio;
    }
    return _NormalizedCropInsets(
      left: normalizedLeft,
      top: normalizedTop,
      right: normalizedRight,
      bottom: normalizedBottom,
    );
  }

  ProjectWatermark _normalizeWatermark(ProjectWatermark value) {
    final cleanPath = value.imagePath.trim();
    final scale = value.scale.isNaN || value.scale.isInfinite
        ? 1.0
        : value.scale.clamp(0.1, 4.0).toDouble();
    return ProjectWatermark(
      enabled: value.enabled && cleanPath.isNotEmpty,
      imagePath: cleanPath,
      position: value.position,
      x: _clampUnit(value.x),
      y: _clampUnit(value.y),
      scale: scale,
      opacity: _clampOpacity(value.opacity),
    );
  }

  _NormalizedKenBurnsTiming _normalizeKenBurnsTiming({
    required double start,
    required double end,
  }) {
    var normalizedStart = _clampUnit(start);
    var normalizedEnd = _clampUnit(end);
    if (normalizedEnd < normalizedStart + 0.01) {
      normalizedEnd = (normalizedStart + 0.01).clamp(0.0, 1.0).toDouble();
      if (normalizedEnd <= normalizedStart) {
        normalizedStart = (normalizedEnd - 0.01).clamp(0.0, 1.0).toDouble();
      }
    }
    return _NormalizedKenBurnsTiming(
      start: normalizedStart,
      end: normalizedEnd,
    );
  }

  Duration _normalizeTransitionDuration(Duration value) {
    if (value < Duration.zero) {
      return Duration.zero;
    }
    return value > const Duration(seconds: 10)
        ? const Duration(seconds: 10)
        : value;
  }

  Duration _normalizeTimelineTransitionDuration(Duration value) {
    if (value < _minimumTimelineTransitionDuration) {
      return _minimumTimelineTransitionDuration;
    }
    if (value > _maximumTimelineTransitionDuration) {
      return _maximumTimelineTransitionDuration;
    }
    return value;
  }

  double _normalizeTimelineTransitionIntensity(double value) {
    if (value.isNaN || value.isInfinite) {
      return 1;
    }
    return value.clamp(0.0, 1.0).toDouble();
  }

  double _clampPlaybackSpeed(double value) {
    if (value.isNaN || value.isInfinite || value <= 0) {
      return 1;
    }
    return value.clamp(_minimumPlaybackSpeed, _maximumPlaybackSpeed).toDouble();
  }

  double _clampVideoBrightness(double value) {
    if (value.isNaN || value.isInfinite) {
      return 0;
    }
    return value
        .clamp(_minimumVideoBrightness, _maximumVideoBrightness)
        .toDouble();
  }

  double _clampVideoContrast(double value) {
    if (value.isNaN || value.isInfinite) {
      return 1;
    }
    return value.clamp(_minimumVideoContrast, _maximumVideoContrast).toDouble();
  }

  double _clampVideoSaturation(double value) {
    if (value.isNaN || value.isInfinite) {
      return 1;
    }
    return value
        .clamp(_minimumVideoSaturation, _maximumVideoSaturation)
        .toDouble();
  }

  double _clampVideoExposure(double value) {
    if (value.isNaN || value.isInfinite) {
      return 0;
    }
    return value.clamp(_minimumVideoExposure, _maximumVideoExposure).toDouble();
  }

  double _clampVideoHue(double value) {
    if (value.isNaN || value.isInfinite) {
      return 0;
    }
    return value.clamp(_minimumVideoHue, _maximumVideoHue).toDouble();
  }

  double _clampVideoColorBalance(double value) {
    if (!value.isFinite) {
      return 0;
    }
    return value
        .clamp(_minimumVideoColorBalance, _maximumVideoColorBalance)
        .toDouble();
  }

  double _clampTransformOffset(double value) {
    if (!value.isFinite) {
      return 0;
    }
    return value.clamp(-1.0, 1.0).toDouble();
  }

  double _clampTransformScale(double value) {
    if (!value.isFinite || value <= 0) {
      return 1;
    }
    return value.clamp(0.1, 8.0).toDouble();
  }

  double _normalizeRotation(double value) {
    if (!value.isFinite) {
      return 0;
    }
    var normalized = value % 360;
    if (normalized > 180) normalized -= 360;
    if (normalized <= -180) normalized += 360;
    return normalized.abs() < 0.000001 ? 0 : normalized;
  }

  Duration _sourceDurationForTimeline(
    Duration timelineDuration,
    double playbackSpeed,
  ) {
    if (timelineDuration <= Duration.zero) {
      return Duration.zero;
    }
    return Duration(
      microseconds:
          (timelineDuration.inMicroseconds * _clampPlaybackSpeed(playbackSpeed))
              .round(),
    );
  }

  Duration _timelineDurationForSource(
    Duration sourceDuration,
    double playbackSpeed,
  ) {
    if (sourceDuration <= Duration.zero) {
      return Duration.zero;
    }
    final microseconds =
        (sourceDuration.inMicroseconds / _clampPlaybackSpeed(playbackSpeed))
            .round();
    return Duration(microseconds: microseconds <= 0 ? 1 : microseconds);
  }

  Duration _clampDuration(Duration value, Duration min, Duration max) {
    if (value < min) {
      return min;
    }
    if (value > max) {
      return max;
    }
    return value;
  }

  Duration _normalizeTimelineStart(Duration position) {
    return position < Duration.zero ? Duration.zero : position;
  }
}

int _maxIdAfterPrefix(int current, String value, String prefix) {
  if (!value.startsWith(prefix)) {
    return current;
  }
  final match = RegExp(r'\d+').firstMatch(value.substring(prefix.length));
  if (match == null) {
    return current;
  }
  final parsed = int.tryParse(match.group(0) ?? '');
  if (parsed == null || parsed <= current) {
    return current;
  }
  return parsed;
}

class _VideoAudioTrackPair {
  const _VideoAudioTrackPair({
    required this.videoTrackId,
    required this.audioTrackId,
    required this.videoTrackName,
    required this.audioTrackName,
  });

  final String videoTrackId;
  final String audioTrackId;
  final String videoTrackName;
  final String audioTrackName;
}
