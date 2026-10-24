import '../../domain/models/clip.dart';
import '../../domain/models/media_item.dart';
import '../../domain/models/project.dart';
import '../../domain/models/track.dart';
import 'editor_command.dart';

abstract final class MediaCommands {
  static MediaItem media(TgiProject project, String id) =>
      project.mediaItemById(id) ??
      (throw const CommandError(
        'media_not_found',
        'Use um media_id de list_media ou import_media.',
      ));

  static Duration seconds(num value) =>
      Duration(microseconds: (value * 1e6).round());

  static TgiProject addClip(TgiProject project, Map<String, Object?> args) {
    final item = media(project, args['media_id'] as String);
    if (item.type == MediaType.text) {
      throw const CommandError(
        'unsupported_media_type',
        'Use add_text para texto.',
      );
    }
    final lane = project.trackById(args['track'] as String);
    if (lane == null) {
      throw const CommandError('track_not_found', 'Use track de get_project.');
    }
    if (lane.isLocked) {
      throw const CommandError(
        'track_locked',
        'A pista de destino está bloqueada.',
      );
    }
    final start = seconds(args['in'] as num), end = seconds(args['out'] as num);
    final duration = end - start;
    if (start.isNegative ||
        end > item.duration ||
        duration < const Duration(milliseconds: 100)) {
      throw const CommandError(
        'out_of_range',
        'Use 0 <= in < out <= duração da fonte, com no mínimo 0.1s.',
      );
    }
    final kind = switch (item.type) {
      MediaType.video => TrackType.video,
      MediaType.audio => TrackType.audio,
      _ => TrackType.image,
    };
    if (!lane.accepts(kind)) {
      throw const CommandError(
        'incompatible_track',
        'Tipo de mídia incompatível com a pista.',
      );
    }
    final existing = project.tracks
        .expand((t) => t.clips)
        .map((c) => c.id)
        .toSet();
    final next = project.addMediaItemToTimeline(
      item.copyWith(duration: duration),
      timelineStart: seconds(args['at'] as num),
      targetTrackId: lane.id,
      clipDurationOverride: duration,
      imageFit: ImageClipFit.contain,
      overlayX: .5,
      overlayY: .5,
    );
    if (identical(next, project)) {
      throw const CommandError(
        'placement_conflict',
        'O intervalo colide com um clipe existente.',
      );
    }
    return next.copyWith(
      tracks: [
        for (final track in next.tracks)
          track.copyWith(
            clips: [
              for (final clip in track.clips)
                existing.contains(clip.id)
                    ? clip
                    : clip.copyWith(
                        sourceStart: start,
                        sourceDuration: item.type == MediaType.image
                            ? null
                            : duration,
                      ),
            ],
          ),
      ],
    );
  }

  static TgiProject sequence(TgiProject project, Map<String, Object?> args) {
    var at = seconds(args['at'] as num), next = project;
    for (final id in (args['media_ids'] as List).cast<String>()) {
      final item = media(next, id);
      next = addClip(next, {
        'media_id': id,
        'track': args['track'],
        'at': at.inMicroseconds / 1e6,
        'in': 0,
        'out': item.duration.inMicroseconds / 1e6,
      });
      at += item.duration;
    }
    return next;
  }

  static TgiProject overlay(
    TgiProject project,
    Map<String, Object?> args, {
    required bool image,
  }) {
    final item = media(project, args['media_id'] as String);
    if (item.type != (image ? MediaType.image : MediaType.video)) {
      throw const CommandError(
        'unsupported_media_type',
        'O tipo da mídia não corresponde à tool de overlay.',
      );
    }
    final duration = seconds(args['duration'] as num);
    final fadeIn = Duration(milliseconds: args['fade_in_ms'] as int? ?? 0);
    final fadeOut = Duration(milliseconds: args['fade_out_ms'] as int? ?? 0);
    if ((!image && duration > item.duration) || fadeIn + fadeOut > duration) {
      throw const CommandError(
        'out_of_range',
        'Duração deve caber no vídeo; a soma dos fades não pode exceder a duração.',
      );
    }
    final position = args['position'] as Map;
    final existing = project.tracks
        .expand((t) => t.clips)
        .map((c) => c.id)
        .toSet();
    final scale = (args['scale'] as num).toDouble() * 4;
    final placed = project.addMediaItemToTimeline(
      item.copyWith(duration: duration),
      timelineStart: seconds(args['at'] as num),
      forceNewVideoTrack: true,
      clipDurationOverride: duration,
      imageFit: ImageClipFit.overlay,
      overlayX: (position['x'] as num).toDouble(),
      overlayY: (position['y'] as num).toDouble(),
      overlayScale: scale,
    );
    return placed.copyWith(
      tracks: [
        for (final track in placed.tracks)
          track.copyWith(
            clips: [
              for (final clip in track.clips)
                existing.contains(clip.id)
                    ? clip
                    : clip.copyWith(
                        fadeIn: fadeIn,
                        fadeOut: fadeOut,
                        volume: (args['volume'] as num?)?.toDouble() ?? 0,
                      ),
            ],
          ),
      ],
    );
  }
}
