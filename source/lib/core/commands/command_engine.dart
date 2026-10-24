import '../../domain/models/clip.dart';
import '../../domain/models/placement_conflict.dart';
import '../../domain/models/project.dart';
import '../../domain/models/track.dart';
import '../../domain/models/timeline_transition.dart';
import 'command_catalog.dart';
import 'timeline_time_map.dart';
import 'editor_command.dart';
import 'prepared_media_import.dart';
import 'media_commands.dart';

export 'command_catalog.dart';
export 'editor_command.dart';

/// Pure transformations. No disk, processes, widgets, history or global project.
class CommandEngine {
  const CommandEngine();
  TgiProject apply(TgiProject project, EditorCommand command, {int? revision}) {
    final definition = commandCatalog[command.name];
    if (definition == null) {
      throw CommandError('unknown_command', 'Comando desconhecido.', {
        'valid_commands': commandCatalog.keys.toList(),
      });
    }
    if (revision != null) checkRevision(command.baseRevision, revision);
    validateArguments(command.arguments, definition.schema);
    final a = command.arguments;
    double n(String key) => (a[key] as num).toDouble();
    Duration time(String key) =>
        Duration(microseconds: (n(key) * 1000000).round());
    Clip? clip;
    if (a.containsKey('clip_id')) {
      clip = project.clipById(a['clip_id'] as String);
      if (clip == null) {
        throw CommandError(
          'clip_not_found',
          'Clipe não encontrado. Leia get_project.',
          {
            'clip_id': a['clip_id'],
            'valid_clip_ids': [
              for (final t in project.tracks)
                for (final c in t.clips) c.id,
            ],
          },
        );
      }
      if (command.name != 'remap_timeline' &&
          project.groupsAreLocked({clip.timelineGroupId})) {
        throw CommandError(
          'track_locked',
          'Destrave as pistas vinculadas antes de editar.',
          {
            ..._lockedGroupConflict(project, {clip.timelineGroupId}).toJson(),
            'clip_id': clip.id,
            'locked_track_ids': [
              for (final t in project.tracks)
                if (t.isLocked) t.id,
            ],
          },
        );
      }
    }
    final before = project;
    switch (command.name) {
      case 'add_clip':
        project = MediaCommands.addClip(project, a);
      case 'add_clips_sequence':
        project = MediaCommands.sequence(project, a);
      case 'import_media':
        if (command is! PreparedMediaImport) {
          throw const CommandError(
            'import_preflight_required',
            'Importação exige validação de caminhos e ffprobe pelo MCP.',
          );
        }
        for (final media in command.media) {
          project = project.addMediaItem(media);
        }
      case 'remap_timeline':
        final ranges = <(int, int)>[];
        for (final raw in a['removed_ranges'] as List) {
          final r = raw as Map;
          final start = ((r['start'] as num) * 1e6).round(),
              end = ((r['end'] as num) * 1e6).round();
          if (end <= start || end > project.timelineDuration.inMicroseconds) {
            throw CommandError(
              'out_of_range',
              'Intervalo de remoção deve ser positivo e estar dentro da timeline.',
              {
                'start': start / 1e6,
                'end': end / 1e6,
                'maximum': project.timelineDuration.inMicroseconds / 1e6,
              },
            );
          }
          ranges.add((start, end));
        }
        return const TimelineRemapper()
            .apply(
              project,
              clip!,
              TimelineTimeMap(
                ranges,
                end: project.timelineDuration.inMicroseconds,
              ),
              scope: a['scope'] as String? ?? 'all_tracks',
              lockedTracks: a['locked_tracks'] as String? ?? 'fail',
              joinFadeMs: a['join_fade_ms'] as int? ?? 0,
            )
            .project;
      case 'split_clip':
        final at = time('at');
        if (at <= clip!.timelineStart || at >= clip.timelineEnd) {
          throw CommandError(
            'out_of_range',
            'O corte precisa estar dentro do clipe.',
            {
              'exclusive_min': clip.timelineStart.inMicroseconds / 1e6,
              'exclusive_max': clip.timelineEnd.inMicroseconds / 1e6,
            },
          );
        }
        project = project.splitTimelineClipGroupAt(
          clip.id,
          timelinePosition: at,
        );
      case 'trim_clip':
        if (clip!.trackType != TrackType.video &&
            clip.trackType != TrackType.audio) {
          throw const CommandError(
            'unsupported_clip_type',
            'Trim requer vídeo ou áudio.',
            {
              'valid_types': ['video', 'audio'],
            },
          );
        }
        final start = time('source_start'), duration = time('source_duration');
        final maximum =
            project.mediaItemById(clip.mediaItemId)?.duration ?? clip.sourceEnd;
        if (start + duration > maximum ||
            duration.inMicroseconds / clip.playbackSpeed < 100000) {
          throw CommandError(
            'out_of_range',
            'Trim excede a fonte ou tem menos de 0.1s na timeline.',
            {
              'source_duration_max': maximum.inMicroseconds / 1e6,
              'minimum_timeline_duration': 0.1,
            },
          );
        }
        project = project.trimTimelineClipGroup(
          clip.id,
          sourceStart: start,
          sourceDuration: duration,
          onConflict: (conflict) => _throwConflict(before, conflict),
        );
        if (identical(project, before) &&
            (clip.sourceStart != start ||
                clip.effectiveSourceDuration != duration)) {
          _placementError(before, clip: clip);
        }
      case 'delete_clip':
        project = a['ripple'] == true
            ? deleteGroups(project, {clip!.timelineGroupId}, ripple: true)
            : deleteGroups(project, {clip!.timelineGroupId});
      case 'move_clip':
        final trackId = a['track_id'] as String?;
        if (trackId != null && project.trackById(trackId) == null) {
          throw CommandError('track_not_found', 'Pista não encontrada.', {
            'valid_track_ids': project.tracks.map((t) => t.id).toList(),
          });
        }
        final groups = (a['group_ids'] as List?)?.cast<String>().toSet();
        final validGroups = project.tracks
            .expand((t) => t.clips)
            .map((c) => c.timelineGroupId)
            .toSet();
        if (groups != null &&
            (!groups.contains(clip!.timelineGroupId) ||
                !validGroups.containsAll(groups))) {
          throw CommandError(
            'invalid_groups',
            'Inclua o grupo do clipe de referência e apenas grupos existentes.',
            {'valid_group_ids': validGroups.toList()},
          );
        }
        if (groups != null && project.groupsAreLocked(groups)) {
          _throwConflict(project, _lockedGroupConflict(project, groups));
        }
        project = project.placeClipGroups(
          clip!.id,
          targetTrackId: trackId,
          timelineStart: time('timeline_start'),
          selectedGroups: groups,
          onConflict: (conflict) => _throwConflict(before, conflict),
        );
        if (identical(project, before) &&
            (clip.timelineStart != time('timeline_start') ||
                (trackId != null &&
                    before.clipTrackById(clip.id)?.id != trackId))) {
          _placementError(before, clip: clip);
        }
      case 'set_clip_speed':
        if (clip!.trackType != TrackType.video &&
            clip.trackType != TrackType.audio) {
          throw const CommandError(
            'unsupported_clip_type',
            'Velocidade requer vídeo ou áudio.',
            {
              'valid_types': ['video', 'audio'],
            },
          );
        }
        final linkedVideo = project.tracks
            .expand((t) => t.clips)
            .any(
              (c) =>
                  c.timelineGroupId == clip!.timelineGroupId &&
                  c.trackType == TrackType.video,
            );
        project = linkedVideo
            ? project.updateClipGroupPlaybackSpeed(
                clip.timelineGroupId,
                playbackSpeed: n('speed'),
                onConflict: (conflict) => _throwConflict(before, conflict),
              )
            : project.changeAudioSpeed(
                clip.timelineGroupId,
                n('speed'),
                onConflict: (conflict) => _throwConflict(before, conflict),
              );
        if (identical(project, before) && clip.playbackSpeed != n('speed')) {
          _placementError(before, clip: clip);
        }
      case 'add_text':
        project = project.addTextClipToTimeline(
          text: (a['text'] as String).trim(),
          timelineStart: time('timeline_start'),
          duration: time('duration'),
          isCaption: a['is_caption'] as bool? ?? false,
          fontFamily: a['font_family'] as String? ?? 'Arial',
          fontSize: (a['font_size'] as num?)?.toDouble() ?? 48,
          textColor: a['text_color'] as int? ?? 0xFFFFFFFF,
          backgroundColor: a['background_color'] as int? ?? 0,
          opacity: (a['opacity'] as num?)?.toDouble() ?? 1,
          textAnimation: TextClipAnimation.values.byName(
            a['animation'] as String? ?? 'none',
          ),
        );
      case 'set_caption_style':
        if (clip!.trackType != TrackType.text) {
          throw const CommandError(
            'unsupported_clip_type',
            'Estilo requer texto/legenda.',
            {
              'valid_types': ['text'],
            },
          );
        }
        project = project.updateTextClipProperties(
          clip.id,
          text: a['text'] as String? ?? clip.textContent,
          fontFamily: a['font_family'] as String?,
          fontSize: (a['font_size'] as num?)?.toDouble(),
          textColor: a['text_color'] as int?,
          backgroundColor: a['background_color'] as int?,
          opacity: (a['opacity'] as num?)?.toDouble(),
          textAnimation: a['animation'] == null
              ? null
              : TextClipAnimation.values.byName(a['animation'] as String),
        );
      case 'apply_effect':
        if (clip!.trackType != TrackType.video &&
            clip.trackType != TrackType.image) {
          throw const CommandError(
            'unsupported_clip_type',
            'Efeito requer vídeo/imagem.',
            {
              'valid_types': ['video', 'image'],
            },
          );
        }
        final color = [
          'brightness',
          'contrast',
          'saturation',
          'exposure',
          'hue',
          'temperature',
          'tint',
          'shadows',
          'highlights',
          'curve_shadows',
          'curve_midtones',
          'curve_highlights',
          'reverse',
          'chroma_key_enabled',
          'chroma_key_color',
          'chroma_key_similarity',
          'chroma_key_blend',
          'stabilization',
          'filter',
        ].any(a.containsKey);
        if (color && clip.trackType != TrackType.video) {
          throw const CommandError(
            'unsupported_clip_type',
            'Cor e filtro requerem vídeo.',
            {
              'valid_types': ['video'],
            },
          );
        }
        if (color) {
          project = project.updateVideoClipLook(
            clip.id,
            brightness: (a['brightness'] as num?)?.toDouble(),
            contrast: (a['contrast'] as num?)?.toDouble(),
            saturation: (a['saturation'] as num?)?.toDouble(),
            exposure: (a['exposure'] as num?)?.toDouble(),
            hue: (a['hue'] as num?)?.toDouble(),
            temperature: (a['temperature'] as num?)?.toDouble(),
            tint: (a['tint'] as num?)?.toDouble(),
            shadows: (a['shadows'] as num?)?.toDouble(),
            highlights: (a['highlights'] as num?)?.toDouble(),
            curveShadows: (a['curve_shadows'] as num?)?.toDouble(),
            curveMidtones: (a['curve_midtones'] as num?)?.toDouble(),
            curveHighlights: (a['curve_highlights'] as num?)?.toDouble(),
            reverseVideo: a['reverse'] as bool?,
            chromaKeyEnabled: a['chroma_key_enabled'] as bool?,
            chromaKeyColor: a['chroma_key_color'] as int?,
            chromaKeySimilarity: (a['chroma_key_similarity'] as num?)
                ?.toDouble(),
            chromaKeyBlend: (a['chroma_key_blend'] as num?)?.toDouble(),
            stabilizationEnabled: a['stabilization'] as bool?,
            filterPreset: a['filter'] == null
                ? null
                : VideoFilterPreset.values.byName(a['filter'] as String),
          );
        }
        if ([
          'crop_left',
          'crop_right',
          'crop_top',
          'crop_bottom',
        ].any(a.containsKey)) {
          final l = (a['crop_left'] as num?)?.toDouble() ?? clip.cropLeft,
              r = (a['crop_right'] as num?)?.toDouble() ?? clip.cropRight;
          final t = (a['crop_top'] as num?)?.toDouble() ?? clip.cropTop,
              b = (a['crop_bottom'] as num?)?.toDouble() ?? clip.cropBottom;
          if (l + r >= 0.98 || t + b >= 0.98) {
            throw const CommandError(
              'out_of_range',
              'Crop precisa preservar pelo menos 2% da imagem.',
              {'maximum_sum': 0.98},
            );
          }
          project = project.updateClipCrop(
            clip.id,
            cropLeft: l,
            cropRight: r,
            cropTop: t,
            cropBottom: b,
          );
        }
      case 'set_keyframe':
        final property = ClipKeyframeProperty.values.byName(
          a['property'] as String,
        );
        final range = keyframeRange(property);
        if (n('value') < range.$1 || n('value') > range.$2) {
          throw CommandError(
            'out_of_range',
            'Valor inválido para ${property.name}.',
            {'minimum': range.$1, 'maximum': range.$2},
          );
        }
        project = project.upsertClipKeyframe(
          clip!.id,
          property: property,
          time: n('time'),
          value: n('value'),
        );
      case 'add_transition':
        if (time('at') > project.timelineDuration) {
          throw CommandError('out_of_range', 'Transição fora da timeline.', {
            'maximum': project.timelineDuration.inMicroseconds / 1e6,
          });
        }
        project = project.upsertTimelineTransition(
          name: a['name'] as String? ?? a['preset'] as String,
          filePath: '',
          timelinePosition: time('at'),
          duration: time('duration'),
          placement: TimelineTransitionPlacement.values.byName(
            a['placement'] as String? ?? 'centered',
          ),
          direction: TimelineTransitionDirection.values.byName(
            a['direction'] as String? ?? 'leftToRight',
          ),
          color: a['color'] as int? ?? 0xFF000000,
          intensity: (a['intensity'] as num?)?.toDouble() ?? 1,
          preset: TimelineTransitionPreset.values.byName(a['preset'] as String),
        );
      case 'set_volume':
        project = project.updateClipVolume(clip!.id, volume: n('volume'));
      case 'add_marker':
        project = project.addTimelineMarker(
          position: time('at'),
          name: a['name'] as String,
        );
      case 'undo':
      case 'redo':
        throw const CommandError(
          'history_required',
          'Use o dispatcher com o histórico do editor.',
        );
    }
    final validated = project.validatedAgainst(
      before,
      onConflict: (conflict) => _throwConflict(before, conflict),
    );
    if (!identical(project, before) && identical(validated, before)) {
      _placementError(before, clip: clip);
    }
    return validated;
  }

  TgiProject deleteGroups(
    TgiProject project,
    Set<String> groups, {
    bool ripple = false,
  }) {
    if (project.groupsAreLocked(groups)) {
      _throwConflict(project, _lockedGroupConflict(project, groups));
    }
    final next = ripple
        ? project.rippleDeleteTimelineClipGroups(
            groups,
            onConflict: (conflict) => _throwConflict(project, conflict),
          )
        : project.deleteTimelineClipGroups(groups);
    if (identical(next, project) && groups.isNotEmpty) {
      _placementError(project, groups: groups);
    }
    return next;
  }

  PlacementConflict _lockedGroupConflict(
    TgiProject project,
    Set<String> groups,
  ) {
    final tracks = project.tracks
        .where(
          (t) =>
              t.isLocked &&
              t.clips.any((c) => groups.contains(c.timelineGroupId)),
        )
        .toList();
    final clips = tracks
        .expand((t) => t.clips)
        .where((c) => groups.contains(c.timelineGroupId))
        .toList();
    return PlacementConflict(
      cause: PlacementConflictCause.lockedTrack,
      clipIds: clips.map((c) => c.id).toList(),
      trackIds: tracks.map((t) => t.id).toList(),
      groupIds: groups.toList(),
      start: clips.isEmpty
          ? Duration.zero
          : clips.map((c) => c.timelineStart).reduce((a, b) => a < b ? a : b),
      end: clips.isEmpty
          ? Duration.zero
          : clips.map((c) => c.timelineEnd).reduce((a, b) => a > b ? a : b),
      suggestion:
          'Desbloqueie as camadas vinculadas ${tracks.map((t) => t.id).join(", ")} antes de editar.',
    );
  }

  Never _placementError(
    TgiProject project, {
    Clip? clip,
    Set<String>? groups,
  }) => _throwConflict(
    project,
    PlacementConflict(
      cause: PlacementConflictCause.linkedGroup,
      clipIds: project.tracks
          .expand((t) => t.clips)
          .where(
            (c) =>
                c.timelineGroupId == clip?.timelineGroupId ||
                (groups?.contains(c.timelineGroupId) ?? false),
          )
          .map((c) => c.id)
          .toList(),
      trackIds: project.tracks
          .where(
            (t) => t.clips.any(
              (c) =>
                  c.timelineGroupId == clip?.timelineGroupId ||
                  (groups?.contains(c.timelineGroupId) ?? false),
            ),
          )
          .map((t) => t.id)
          .toList(),
      start: clip?.timelineStart ?? Duration.zero,
      end: clip?.timelineEnd ?? project.timelineDuration,
      suggestion:
          'Confira os vínculos A/V e use uma camada compatível para todos os membros do grupo.',
    ),
  );

  Never _throwConflict(
    TgiProject project,
    PlacementConflict conflict,
  ) => throw CommandError(
    'placement_conflict',
    'Operação bloqueada por sobreposição, pista incompatível ou conteúdo bloqueado.',
    {
      ...conflict.toJson(),
      'valid_track_ids': project.tracks
          .where((t) => !t.isLocked)
          .map((t) => t.id)
          .toList(),
      'locked_track_ids': project.tracks
          .where((t) => t.isLocked)
          .map((t) => t.id)
          .toList(),
    },
  );
}

(double, double) keyframeRange(ClipKeyframeProperty p) => switch (p) {
  ClipKeyframeProperty.overlayScale => (0.35, 8),
  ClipKeyframeProperty.volume => (0, 2),
  ClipKeyframeProperty.brightness || ClipKeyframeProperty.exposure => (-1, 1),
  ClipKeyframeProperty.contrast || ClipKeyframeProperty.saturation => (0, 3),
  ClipKeyframeProperty.hue => (-180, 180),
  _ => (0, 1),
};
