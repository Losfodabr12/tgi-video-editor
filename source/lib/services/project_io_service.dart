import 'dart:convert';
import 'dart:io';

import '../domain/models/clip.dart';
import '../domain/models/media_item.dart';
import '../domain/models/project.dart';
import '../domain/models/timeline_marker.dart';
import '../domain/models/timeline_transition.dart';
import '../domain/models/track.dart';
import 'ffmpeg_export_settings.dart';
import 'project_file_storage.dart';

class ProjectSaveData {
  const ProjectSaveData({
    required this.projectName,
    required this.tracks,
    required this.mediaPool,
    this.markers = const [],
    this.transitions = const [],
  });
  final String projectName;
  final List<Map<String, dynamic>> tracks;
  final List<Map<String, dynamic>> mediaPool;
  final List<Map<String, dynamic>> markers;
  final List<Map<String, dynamic>> transitions;
  Map<String, dynamic> toJson() => {
    'projectName': projectName,
    'tracks': tracks,
    'mediaPool': mediaPool,
    'markers': markers,
    'transitions': transitions,
    'version': 14,
  };
}

class ProjectLoadResult {
  const ProjectLoadResult({
    required this.project,
    required this.missingMediaItems,
    required this.serializedData,
    required this.exportSettings,
  });
  final TgiProject project;
  final List<Map<String, dynamic>> missingMediaItems;
  final Map<String, dynamic> serializedData;
  final FfmpegExportSettings? exportSettings;
}

class MediaRelinkResult {
  const MediaRelinkResult({
    required this.mediaItemId,
    required this.originalFilename,
    required this.newPath,
  });
  final String mediaItemId;
  final String originalFilename;
  final String newPath;
}

class ProjectIOService {
  static const _projectFormatVersion = 14;
  static const _mediaPoolKey = 'mediaPool';
  static const _tracksKey = 'tracks';
  static const _markersKey = 'markers';
  static const _transitionsKey = 'transitions';
  static const _watermarkKey = 'watermark';
  static const _projectNameKey = 'projectName';
  static const _projectIdKey = 'id';
  static const _projectCreatedAtKey = 'createdAt';
  static const _projectUpdatedAtKey = 'updatedAt';
  static const _versionKey = 'version';
  static const _exportSettingsKey = 'exportSettings';

  Map<String, dynamic> serializeProject(
    TgiProject project, {
    FfmpegExportSettings? exportSettings,
  }) {
    final mediaPool = project.mediaPool.map(_serializeMediaItem).toList();
    final tracks = project.tracks.map(_serializeTrack).toList();
    final markers = project.markers.map(_serializeMarker).toList();
    final transitions = project.transitions
        .map(_serializeTimelineTransition)
        .toList();
    return {
      _projectIdKey: project.id,
      _projectNameKey: project.name,
      _projectCreatedAtKey: project.createdAt.toIso8601String(),
      _projectUpdatedAtKey: project.updatedAt.toIso8601String(),
      _tracksKey: tracks,
      _markersKey: markers,
      _transitionsKey: transitions,
      _watermarkKey: _serializeWatermark(project.watermark),
      _mediaPoolKey: mediaPool,
      if (exportSettings != null) _exportSettingsKey: exportSettings.toJson(),
      _versionKey: _projectFormatVersion,
    };
  }

  Future<String> toJsonString(
    TgiProject project, {
    FfmpegExportSettings? exportSettings,
  }) async {
    final data = serializeProject(project, exportSettings: exportSettings);
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  Future<void> saveToFile(
    TgiProject project,
    String filePath, {
    FfmpegExportSettings? exportSettings,
  }) => ProjectFileStorage.write(
    filePath,
    () => toJsonString(project, exportSettings: exportSettings),
  );

  Future<void> saveSerializedToFile(
    Map<String, dynamic> data,
    String filePath,
  ) => ProjectFileStorage.write(
    filePath,
    () => const JsonEncoder.withIndent('  ').convert(data),
  );

  Future<Map<String, dynamic>> readFromFile(String filePath) async {
    final content = await ProjectFileStorage.read(filePath);
    final data = jsonDecode(content) as Map<String, dynamic>;
    if (data['portable'] == true) {
      final root = File(filePath).absolute.parent.uri;
      void resolve(Map<String, dynamic> owner, String key) {
        final value = owner[key];
        if (value is! String || value.isEmpty) return;
        final relative = value.replaceAll('\\', '/');
        final uri = root.resolve(relative).normalizePath();
        if (!uri.toString().startsWith(root.toString()) ||
            relative.startsWith('/') ||
            relative.contains(':')) {
          throw const FormatException('Caminho inválido no projeto portátil.');
        }
        owner[key] = uri.toFilePath();
      }

      final portableMedia = _objectList(data['mediaPool']);
      data['mediaPool'] = portableMedia;
      for (final item in portableMedia) {
        resolve(item, 'filePath');
      }
      final portableTransitions = _objectList(data['transitions']);
      data['transitions'] = portableTransitions;
      for (final transition in portableTransitions) {
        resolve(transition, 'filePath');
      }
      if (data['watermark'] is Map<String, dynamic>) {
        resolve(data['watermark'] as Map<String, dynamic>, 'imagePath');
      }
      // In-memory snapshots/history use resolved absolute paths.
      data.remove('portable');
    }
    return data;
  }

  ProjectLoadResult deserializeProject(Map<String, dynamic> data) {
    final version = _readVersion(data);
    if (version > _projectFormatVersion) {
      throw FormatException(
        'Projeto salvo em uma versao mais nova do TGI Video Editor '
        '(formato $version, app suporta $_projectFormatVersion).',
      );
    }
    final normalized = _normalizeLegacyProjectData(data, version);
    final name = normalized[_projectNameKey] as String? ?? 'Projeto importado';
    final mediaList = _objectList(normalized[_mediaPoolKey]);
    final tracksList = _objectList(normalized[_tracksKey]);
    final markerList = _objectList(normalized[_markersKey]);
    final transitionList = _objectList(normalized[_transitionsKey]);
    final watermarkData = normalized[_watermarkKey] is Map<String, dynamic>
        ? normalized[_watermarkKey] as Map<String, dynamic>
        : const <String, dynamic>{};
    final mediaItems = <MediaItem>[];
    final missingMediaItems = <Map<String, dynamic>>[];
    for (final mediaData in mediaList) {
      final mediaItem = _deserializeMediaItem(mediaData);
      if (mediaItem != null) {
        final filePath = mediaData['filePath'] as String? ?? '';
        if (filePath.isNotEmpty && !File(filePath).existsSync()) {
          missingMediaItems.add(mediaData);
        }
        mediaItems.add(mediaItem);
      }
    }
    final tracks = <Track>[];
    for (var i = 0; i < tracksList.length; i++) {
      tracks.add(_deserializeTrack(tracksList[i], index: i));
    }
    final markers =
        markerList.map(_deserializeMarker).whereType<TimelineMarker>().toList()
          ..sort((a, b) => a.position.compareTo(b.position));
    final transitions =
        transitionList
            .map(_deserializeTimelineTransition)
            .whereType<TimelineTransition>()
            .toList()
          ..sort((a, b) => a.timelinePosition.compareTo(b.timelinePosition));
    final createdAt = _parseDateTime(
      normalized[_projectCreatedAtKey] as String?,
    );
    final updatedAt = _parseDateTime(
      normalized[_projectUpdatedAtKey] as String?,
    );
    final now = DateTime.now();
    final project = TgiProject(
      id:
          normalized[_projectIdKey] as String? ??
          'project_${now.microsecondsSinceEpoch}',
      name: name,
      createdAt: createdAt ?? now,
      updatedAt: updatedAt ?? createdAt ?? now,
      mediaPool: mediaItems,
      tracks: _separateLegacyCaptionGroups(
        version < 14 ? _migrateLegacyTrackOrder(tracks) : tracks,
      ),
      markers: markers,
      transitions: transitions,
      watermark: _deserializeWatermark(watermarkData),
    );
    TgiProject.syncIdCounters(project);
    return ProjectLoadResult(
      project: project,
      missingMediaItems: missingMediaItems,
      serializedData: data,
      exportSettings: FfmpegExportSettings.fromJson(
        normalized[_exportSettingsKey],
      ),
    );
  }

  // Formats 1–13 rendered video lanes forward, then image/text lanes reversed.
  // Canonical order is now top-to-bottom. IDs, clips, links and timing stay intact.
  List<Track> _migrateLegacyTrackOrder(List<Track> tracks) => [
    ...tracks.where((track) => track.type == TrackType.text),
    ...tracks.where((track) => track.type == TrackType.image),
    ...tracks.where((track) => track.type == TrackType.video).toList().reversed,
    ...tracks.where((track) => track.type == TrackType.audio),
  ];

  List<Track> _separateLegacyCaptionGroups(List<Track> tracks) {
    // Older splits used the clip counter for group IDs. A later caption
    // could inherit a video/audio group and move/delete unrelated media.
    final mediaGroups = {
      for (final track in tracks)
        for (final clip in track.clips)
          if (clip.trackType != TrackType.text) clip.timelineGroupId,
    };
    final occupied = {
      for (final track in tracks)
        for (final clip in track.clips) clip.timelineGroupId,
    };
    return [
      for (final track in tracks)
        if (!track.clips.any(
          (clip) =>
              clip.trackType == TrackType.text &&
              mediaGroups.contains(clip.timelineGroupId),
        ))
          track
        else
          track.copyWith(
            clips: [
              for (final clip in track.clips)
                if (clip.trackType != TrackType.text ||
                    !mediaGroups.contains(clip.timelineGroupId))
                  clip
                else
                  clip.copyWith(
                    timelineGroupId: _recoveredCaptionGroupId(
                      clip.id,
                      occupied,
                    ),
                  ),
            ],
          ),
    ];
  }

  String _recoveredCaptionGroupId(String clipId, Set<String> occupied) {
    final base = 'group_recovered_text_$clipId';
    var candidate = base;
    var suffix = 0;
    while (!occupied.add(candidate)) {
      candidate = '${base}_${++suffix}';
    }
    return candidate;
  }

  TgiProject applyRelinkedMedia(
    TgiProject project,
    List<MediaRelinkResult> relinked,
  ) {
    final relinkMap = {
      for (final result in relinked) result.mediaItemId: result.newPath,
    };
    final updatedMediaPool = project.mediaPool.map((item) {
      final newPath = relinkMap[item.id];
      if (newPath == null) return item;
      return item.copyWith(filePath: newPath);
    }).toList();
    return project.copyWith(
      mediaPool: updatedMediaPool,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> _serializeMediaItem(MediaItem item) {
    final map = {
      'id': item.id,
      'filePath': item.filePath,
      'name': item.name,
      'type': item.type.name,
      'duration': item.duration.inMilliseconds,
      'importedAt': item.importedAt.toIso8601String(),
      'hasAudio': item.hasAudio,
      'thumbnailPath': item.thumbnailPath,
      'previewProxyPath': item.previewProxyPath,
    };
    if (item.width != null) {
      map['width'] = item.width;
    }
    if (item.height != null) {
      map['height'] = item.height;
    }
    return map;
  }

  MediaItem? _deserializeMediaItem(Map<String, dynamic> data) {
    try {
      final id = data['id'] as String?;
      if (id == null) return null;
      final type = MediaType.values.firstWhere(
        (t) => t.name == (data['type'] as String? ?? 'video'),
        orElse: () => MediaType.video,
      );
      return MediaItem(
        id: id,
        filePath: data['filePath'] as String? ?? '',
        name: data['name'] as String? ?? 'Midia desconhecida',
        type: type,
        duration: _durationFromJson(data['duration']),
        importedAt:
            DateTime.tryParse(data['importedAt'] as String? ?? '') ??
            DateTime.now(),
        hasAudio:
            data['hasAudio'] as bool? ??
            (type == MediaType.video || type == MediaType.audio),
        thumbnailPath: data['thumbnailPath'] as String?,
        previewProxyPath: data['previewProxyPath'] as String?,
        width: _intFromJson(data['width']),
        height: _intFromJson(data['height']),
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _serializeTrack(Track track) {
    return {
      'id': track.id,
      'name': track.name,
      'type': track.type.name,
      'kind': track.kind.name,
      'height': track.height,
      'isLocked': track.isLocked,
      'isHidden': track.isHidden,
      'isMuted': track.isMuted,
      'isSolo': track.isSolo,
      'volume': track.volume,
      'clips': track.clips.map(_serializeClip).toList(),
    };
  }

  Track _deserializeTrack(Map<String, dynamic> data, {required int index}) {
    final type = _trackTypeFrom(data['type']) ?? TrackType.video;
    final clips =
        _objectList(data['clips'])
            .map(
              (clipData) => _deserializeClip(clipData, fallbackTrackType: type),
            )
            .whereType<Clip>()
            .toList()
          ..sort((a, b) => a.timelineStart.compareTo(b.timelineStart));
    final trackId = data['id'] as String?;
    return Track(
      id: trackId == null || trackId.isEmpty ? 'track_${index + 1}' : trackId,
      name: data['name'] as String? ?? 'Trilha',
      type: type,
      kind: data['kind'] == 'audio'
          ? TrackKind.audio
          : data['kind'] == 'visual'
          ? TrackKind.visual
          : null,
      height: (data['height'] is num && (data['height'] as num).isFinite)
          ? (data['height'] as num).toDouble().clamp(44.0, 180.0)
          : 64,
      clips: clips,
      isLocked: data['isLocked'] as bool? ?? false,
      isHidden: data['isHidden'] as bool? ?? false,
      isMuted: data['isMuted'] as bool? ?? false,
      isSolo: data['isSolo'] as bool? ?? false,
      volume: ((data['volume'] as num?)?.toDouble() ?? 1)
          .clamp(0.0, 2.0)
          .toDouble(),
    );
  }

  Map<String, dynamic> _serializeClip(Clip clip) {
    final map = <String, dynamic>{
      'id': clip.id,
      'mediaItemId': clip.mediaItemId,
      'timelineGroupId': clip.timelineGroupId,
      'trackType': clip.trackType.name,
      'timelineStart': clip.timelineStart.inMilliseconds,
      'sourceStart': clip.sourceStart.inMilliseconds,
      'duration': clip.duration.inMilliseconds,
      'playbackSpeed': clip.playbackSpeed,
      'overlayX': clip.overlayX,
      'overlayY': clip.overlayY,
      'overlayScale': clip.overlayScale,
      'imageFit': clip.imageFit.name,
      'volume': clip.volume,
      'textContent': clip.textContent,
      'isCaption': clip.isCaption,
      'fontFamily': clip.fontFamily,
      'fontSize': clip.fontSize,
      'textColor': clip.textColor,
      'backgroundColor': clip.backgroundColor,
      'opacity': clip.opacity,
      'textAnimation': clip.textAnimation.name,
      'audioNoiseReductionDb': clip.audioNoiseReductionDb,
      'fadeIn': clip.fadeIn.inMilliseconds,
      'fadeOut': clip.fadeOut.inMilliseconds,
      'brightness': clip.brightness,
      'contrast': clip.contrast,
      'saturation': clip.saturation,
      'exposure': clip.exposure,
      'hue': clip.hue,
      'temperature': clip.temperature,
      'tint': clip.tint,
      'shadows': clip.shadows,
      'highlights': clip.highlights,
      'curveShadows': clip.curveShadows,
      'curveMidtones': clip.curveMidtones,
      'curveHighlights': clip.curveHighlights,
      'filterPreset': clip.filterPreset.name,
      'reverseVideo': clip.reverseVideo,
      'chromaKeyEnabled': clip.chromaKeyEnabled,
      'chromaKeyColor': clip.chromaKeyColor,
      'chromaKeySimilarity': clip.chromaKeySimilarity,
      'chromaKeyBlend': clip.chromaKeyBlend,
      'startOverlayX': clip.startOverlayX,
      'startOverlayY': clip.startOverlayY,
      'startOverlayScale': clip.startOverlayScale,
      'kenBurnsEnabled': clip.kenBurnsEnabled,
      'kenBurnsStart': clip.kenBurnsStart,
      'kenBurnsEnd': clip.kenBurnsEnd,
      'cropLeft': clip.cropLeft,
      'cropTop': clip.cropTop,
      'cropRight': clip.cropRight,
      'cropBottom': clip.cropBottom,
      'transformOffsetX': clip.transformOffsetX,
      'transformOffsetY': clip.transformOffsetY,
      'transformScale': clip.transformScale,
      'rotationDegrees': clip.rotationDegrees,
      'flipHorizontal': clip.flipHorizontal,
      'flipVertical': clip.flipVertical,
      'stabilizationEnabled': clip.stabilizationEnabled,
      'maskEnabled': clip.maskEnabled,
      'maskShape': clip.maskShape.name,
      'maskEffect': clip.maskEffect.name,
      'maskX': clip.maskX,
      'maskY': clip.maskY,
      'maskWidth': clip.maskWidth,
      'maskHeight': clip.maskHeight,
      'maskFeather': clip.maskFeather,
      'maskIntensity': clip.maskIntensity,
      'maskInverted': clip.maskInverted,
      'keyframes': clip.keyframes.map(_serializeClipKeyframe).toList(),
    };
    if (clip.sourceDuration != null) {
      map['sourceDuration'] = clip.sourceDuration!.inMilliseconds;
    }
    return map;
  }

  Clip? _deserializeClip(
    Map<String, dynamic> data, {
    required TrackType fallbackTrackType,
  }) {
    try {
      final id = data['id'] as String?;
      if (id == null) return null;
      final trackType = _trackTypeFrom(data['trackType']) ?? fallbackTrackType;
      final sourceDurVal = data['sourceDuration'];
      return Clip(
        id: id,
        mediaItemId: data['mediaItemId'] as String? ?? '',
        timelineGroupId: data['timelineGroupId'] as String? ?? '',
        trackType: trackType,
        timelineStart: _durationFromJson(data['timelineStart']),
        sourceStart: _durationFromJson(data['sourceStart']),
        duration: _durationFromJson(data['duration']),
        sourceDuration: sourceDurVal != null
            ? _durationFromJson(sourceDurVal)
            : null,
        playbackSpeed: (data['playbackSpeed'] as num?)?.toDouble() ?? 1,
        overlayX: (data['overlayX'] as num?)?.toDouble() ?? 1,
        overlayY: (data['overlayY'] as num?)?.toDouble() ?? 0,
        overlayScale: (data['overlayScale'] as num?)?.toDouble() ?? 1,
        imageFit: _imageClipFitFrom(data['imageFit']),
        volume: (data['volume'] as num?)?.toDouble() ?? 1,
        textContent: data['textContent'] as String? ?? '',
        isCaption: data['isCaption'] as bool? ?? false,
        fontFamily: data['fontFamily'] as String? ?? 'Arial',
        fontSize: (data['fontSize'] as num?)?.toDouble() ?? 48,
        textColor: data['textColor'] as int? ?? 0xFFFFFFFF,
        backgroundColor: data['backgroundColor'] as int? ?? 0x00000000,
        opacity: (data['opacity'] as num?)?.toDouble() ?? 1.0,
        textAnimation: _textClipAnimationFrom(data['textAnimation']),
        audioNoiseReductionDb:
            (data['audioNoiseReductionDb'] as num?)?.toDouble() ?? 0,
        fadeIn: Duration(milliseconds: data['fadeIn'] as int? ?? 0),
        fadeOut: Duration(milliseconds: data['fadeOut'] as int? ?? 0),
        brightness: (data['brightness'] as num?)?.toDouble() ?? 0,
        contrast: (data['contrast'] as num?)?.toDouble() ?? 1,
        saturation: (data['saturation'] as num?)?.toDouble() ?? 1,
        exposure: (data['exposure'] as num?)?.toDouble() ?? 0,
        hue: (data['hue'] as num?)?.toDouble() ?? 0,
        temperature: (data['temperature'] as num?)?.toDouble() ?? 0,
        tint: (data['tint'] as num?)?.toDouble() ?? 0,
        shadows: (data['shadows'] as num?)?.toDouble() ?? 0,
        highlights: (data['highlights'] as num?)?.toDouble() ?? 0,
        curveShadows: (data['curveShadows'] as num?)?.toDouble() ?? 0,
        curveMidtones: (data['curveMidtones'] as num?)?.toDouble() ?? 0,
        curveHighlights: (data['curveHighlights'] as num?)?.toDouble() ?? 0,
        filterPreset: _videoFilterPresetFrom(data['filterPreset']),
        reverseVideo: data['reverseVideo'] as bool? ?? false,
        chromaKeyEnabled: data['chromaKeyEnabled'] as bool? ?? false,
        chromaKeyColor: _intFromJson(data['chromaKeyColor']) ?? 0xFF00FF00,
        chromaKeySimilarity:
            (data['chromaKeySimilarity'] as num?)?.toDouble() ?? 0.3,
        chromaKeyBlend: (data['chromaKeyBlend'] as num?)?.toDouble() ?? 0.1,
        startOverlayX: (data['startOverlayX'] as num?)?.toDouble() ?? 1,
        startOverlayY: (data['startOverlayY'] as num?)?.toDouble() ?? 0,
        startOverlayScale: (data['startOverlayScale'] as num?)?.toDouble() ?? 1,
        kenBurnsEnabled: data['kenBurnsEnabled'] as bool? ?? false,
        kenBurnsStart: (data['kenBurnsStart'] as num?)?.toDouble() ?? 0,
        kenBurnsEnd: (data['kenBurnsEnd'] as num?)?.toDouble() ?? 1,
        cropLeft: (data['cropLeft'] as num?)?.toDouble() ?? 0,
        cropTop: (data['cropTop'] as num?)?.toDouble() ?? 0,
        cropRight: (data['cropRight'] as num?)?.toDouble() ?? 0,
        cropBottom: (data['cropBottom'] as num?)?.toDouble() ?? 0,
        transformOffsetX: (data['transformOffsetX'] as num?)?.toDouble() ?? 0,
        transformOffsetY: (data['transformOffsetY'] as num?)?.toDouble() ?? 0,
        transformScale: (data['transformScale'] as num?)?.toDouble() ?? 1,
        rotationDegrees: (data['rotationDegrees'] as num?)?.toDouble() ?? 0,
        flipHorizontal: data['flipHorizontal'] as bool? ?? false,
        flipVertical: data['flipVertical'] as bool? ?? false,
        stabilizationEnabled: data['stabilizationEnabled'] as bool? ?? false,
        maskEnabled: data['maskEnabled'] as bool? ?? false,
        maskShape: _videoMaskShapeFrom(data['maskShape']),
        maskEffect: _videoMaskEffectFrom(data['maskEffect']),
        maskX: (data['maskX'] as num?)?.toDouble() ?? 0.5,
        maskY: (data['maskY'] as num?)?.toDouble() ?? 0.5,
        maskWidth: (data['maskWidth'] as num?)?.toDouble() ?? 0.32,
        maskHeight: (data['maskHeight'] as num?)?.toDouble() ?? 0.32,
        maskFeather: (data['maskFeather'] as num?)?.toDouble() ?? 0.08,
        maskIntensity: (data['maskIntensity'] as num?)?.toDouble() ?? 0.7,
        maskInverted: data['maskInverted'] as bool? ?? false,
        keyframes: _objectList(
          data['keyframes'],
        ).map(_deserializeClipKeyframe).whereType<ClipKeyframe>().toList(),
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _serializeClipKeyframe(ClipKeyframe keyframe) {
    return {
      'id': keyframe.id,
      'property': keyframe.property.name,
      'time': keyframe.time,
      'value': keyframe.value,
    };
  }

  ClipKeyframe? _deserializeClipKeyframe(Map<String, dynamic> data) {
    try {
      final id = data['id'] as String?;
      final property = _clipKeyframePropertyFrom(data['property']);
      if (id == null || id.isEmpty || property == null) {
        return null;
      }
      return ClipKeyframe(
        id: id,
        property: property,
        time: (data['time'] as num?)?.toDouble() ?? 0,
        value: (data['value'] as num?)?.toDouble() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _serializeMarker(TimelineMarker marker) {
    return {
      'id': marker.id,
      'name': marker.name,
      'position': marker.position.inMilliseconds,
      'color': marker.color,
    };
  }

  Map<String, dynamic> _serializeTimelineTransition(
    TimelineTransition transition,
  ) {
    return {
      'id': transition.id,
      'name': transition.name,
      'filePath': transition.filePath,
      'timelinePosition': transition.timelinePosition.inMilliseconds,
      'duration': transition.duration.inMilliseconds,
      'blendMode': transition.blendMode.name,
      'placement': transition.placement.name,
      if (transition.preset != null) 'preset': transition.preset!.name,
      'direction': transition.direction.name,
      'color': transition.color,
      'intensity': transition.intensity,
    };
  }

  Map<String, dynamic> _serializeWatermark(ProjectWatermark watermark) {
    return {
      'enabled': watermark.enabled,
      'imagePath': watermark.imagePath,
      'position': watermark.position.name,
      'x': watermark.x,
      'y': watermark.y,
      'scale': watermark.scale,
      'opacity': watermark.opacity,
    };
  }

  ProjectWatermark _deserializeWatermark(Map<String, dynamic> data) {
    return ProjectWatermark(
      enabled: data['enabled'] as bool? ?? false,
      imagePath: data['imagePath'] as String? ?? '',
      position: _watermarkPositionFrom(data['position']),
      x: (data['x'] as num?)?.toDouble() ?? 0.92,
      y: (data['y'] as num?)?.toDouble() ?? 0.92,
      scale: (data['scale'] as num?)?.toDouble() ?? 1.0,
      opacity: (data['opacity'] as num?)?.toDouble() ?? 0.75,
    );
  }

  int _readVersion(Map<String, dynamic> data) {
    final rawVersion = data[_versionKey];
    if (rawVersion is int) {
      return rawVersion;
    }
    if (rawVersion is num) {
      return rawVersion.toInt();
    }
    return 0;
  }

  Map<String, dynamic> _normalizeLegacyProjectData(
    Map<String, dynamic> data,
    int version,
  ) {
    final normalized = <String, dynamic>{...data};
    normalized[_projectNameKey] =
        data[_projectNameKey] ?? data['name'] ?? 'Projeto importado';
    normalized[_mediaPoolKey] = data[_mediaPoolKey] ?? data['mediaItems'] ?? [];
    normalized[_tracksKey] = data[_tracksKey] ?? data['timeline'] ?? [];
    normalized[_markersKey] = data[_markersKey] ?? [];
    normalized[_transitionsKey] = data[_transitionsKey] ?? [];
    if (version < 2) {
      normalized.remove(_projectCreatedAtKey);
      normalized.remove(_projectUpdatedAtKey);
    }
    return normalized;
  }

  Duration _durationFromJson(Object? value) {
    if (value is int) {
      return Duration(milliseconds: value);
    }
    if (value is num) {
      return Duration(milliseconds: value.toInt());
    }
    return Duration.zero;
  }

  int? _intFromJson(Object? value) {
    if (value is int && value > 0) {
      return value;
    }
    if (value is num && value > 0) {
      return value.round();
    }
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }
    return null;
  }

  DateTime? _parseDateTime(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }

  TimelineMarker? _deserializeMarker(Map<String, dynamic> data) {
    try {
      final id = data['id'] as String?;
      if (id == null || id.isEmpty) {
        return null;
      }
      return TimelineMarker(
        id: id,
        name: data['name'] as String? ?? 'Marcador',
        position: _durationFromJson(data['position']),
        color: data['color'] as int? ?? 0xFFFFD166,
      );
    } catch (_) {
      return null;
    }
  }

  TimelineTransition? _deserializeTimelineTransition(
    Map<String, dynamic> data,
  ) {
    try {
      final id = data['id'] as String?;
      final filePath = data['filePath'] as String? ?? '';
      final preset = _timelineTransitionPresetFrom(data['preset']);
      if (id == null ||
          id.isEmpty ||
          (preset == null && filePath.trim().isEmpty)) {
        return null;
      }
      final duration = _durationFromJson(data['duration']);
      return TimelineTransition(
        id: id,
        name: data['name'] as String? ?? 'Transicao',
        filePath: filePath,
        timelinePosition: _durationFromJson(data['timelinePosition']),
        duration: duration <= Duration.zero
            ? const Duration(milliseconds: 900)
            : duration,
        blendMode: _timelineTransitionBlendModeFrom(data['blendMode']),
        placement: _timelineTransitionPlacementFrom(data['placement']),
        preset: preset,
        direction: _timelineTransitionDirectionFrom(data['direction']),
        color: data['color'] as int? ?? 0xFF000000,
        intensity: (data['intensity'] as num?)?.toDouble() ?? 1,
      );
    } catch (_) {
      return null;
    }
  }

  TimelineTransitionPlacement _timelineTransitionPlacementFrom(Object? value) {
    final name = value as String?;
    for (final placement in TimelineTransitionPlacement.values) {
      if (placement.name == name) {
        return placement;
      }
    }
    return TimelineTransitionPlacement.centered;
  }

  List<Map<String, dynamic>> _objectList(Object? value) {
    if (value is! List) {
      return const [];
    }
    return [
      for (final item in value)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
  }

  TrackType? _trackTypeFrom(Object? value) {
    final name = value as String?;
    if (name == null) {
      return null;
    }
    for (final type in TrackType.values) {
      if (type.name == name) {
        return type;
      }
    }
    return null;
  }

  ImageClipFit _imageClipFitFrom(Object? value) {
    final name = value as String?;
    if (name == null) {
      return ImageClipFit.overlay;
    }
    for (final fit in ImageClipFit.values) {
      if (fit.name == name) {
        return fit;
      }
    }
    return ImageClipFit.overlay;
  }

  TextClipAnimation _textClipAnimationFrom(Object? value) {
    final name = value as String?;
    if (name == null) {
      return TextClipAnimation.none;
    }
    for (final animation in TextClipAnimation.values) {
      if (animation.name == name) {
        return animation;
      }
    }
    return TextClipAnimation.none;
  }

  VideoFilterPreset _videoFilterPresetFrom(Object? value) {
    final name = value as String?;
    if (name == null) {
      return VideoFilterPreset.none;
    }
    for (final preset in VideoFilterPreset.values) {
      if (preset.name == name) {
        return preset;
      }
    }
    return VideoFilterPreset.none;
  }

  VideoMaskShape _videoMaskShapeFrom(Object? value) {
    final name = value as String?;
    for (final shape in VideoMaskShape.values) {
      if (shape.name == name) return shape;
    }
    return VideoMaskShape.ellipse;
  }

  VideoMaskEffect _videoMaskEffectFrom(Object? value) {
    final name = value as String?;
    for (final effect in VideoMaskEffect.values) {
      if (effect.name == name) return effect;
    }
    return VideoMaskEffect.blur;
  }

  ClipKeyframeProperty? _clipKeyframePropertyFrom(Object? value) {
    final name = value as String?;
    if (name == null) {
      return null;
    }
    for (final property in ClipKeyframeProperty.values) {
      if (property.name == name) {
        return property;
      }
    }
    return null;
  }

  WatermarkPosition _watermarkPositionFrom(Object? value) {
    final name = value as String?;
    if (name == null) {
      return WatermarkPosition.bottomRight;
    }
    for (final position in WatermarkPosition.values) {
      if (position.name == name) {
        return position;
      }
    }
    return WatermarkPosition.bottomRight;
  }

  TimelineTransitionBlendMode _timelineTransitionBlendModeFrom(Object? value) {
    final name = value as String?;
    if (name == null) {
      return TimelineTransitionBlendMode.screen;
    }
    for (final mode in TimelineTransitionBlendMode.values) {
      if (mode.name == name) {
        return mode;
      }
    }
    return TimelineTransitionBlendMode.screen;
  }

  TimelineTransitionPreset? _timelineTransitionPresetFrom(Object? value) {
    final name = value as String?;
    if (name == null || name.isEmpty) {
      return null;
    }
    for (final preset in TimelineTransitionPreset.values) {
      if (preset.name == name) {
        return preset;
      }
    }
    return null;
  }

  TimelineTransitionDirection _timelineTransitionDirectionFrom(Object? value) {
    final name = value as String?;
    if (name == null) {
      return TimelineTransitionDirection.leftToRight;
    }
    for (final direction in TimelineTransitionDirection.values) {
      if (direction.name == name) {
        return direction;
      }
    }
    return TimelineTransitionDirection.leftToRight;
  }
}
