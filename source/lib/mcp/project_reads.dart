import '../core/commands/editor_command.dart';
import '../domain/models/clip.dart';
import '../domain/models/project.dart';

double seconds(Duration value) => value.inMicroseconds / 1e6;
Map<String, Object?> clipSummary(TgiProject project, Clip c) => {
  'id': c.id,
  'media_id': c.mediaItemId,
  'track_id': project.clipTrackById(c.id)?.id,
  'group_id': c.timelineGroupId,
  'type': c.trackType.name,
  'timeline_start': seconds(c.timelineStart),
  'duration': seconds(c.duration),
  'source_start': seconds(c.sourceStart),
  'source_duration': seconds(c.effectiveSourceDuration),
  'speed': c.playbackSpeed,
  'volume': c.volume,
  if (c.textContent.isNotEmpty) 'text': c.textContent,
  'is_caption': c.isCaption,
};

Map<String, Object?> projectSummary(
  TgiProject p,
  int revision, {
  int offset = 0,
  int limit = 50,
}) {
  if (offset < 0 || limit < 1 || limit > 100) {
    throw const CommandError(
      'invalid_page',
      'Use offset >= 0 e limit entre 1 e 100.',
    );
  }
  final clips = p.tracks.expand((t) => t.clips).toList();
  if (offset > clips.length) {
    throw CommandError('invalid_page', 'Página além do fim.', {
      'total': clips.length,
    });
  }
  return {
    'project_id': p.id,
    'name': p.name,
    'revision': revision,
    'format_version': 14,
    'duration': seconds(p.timelineDuration),
    'media_count': p.mediaPool.length,
    'clip_count': clips.length,
    'tracks': [
      for (final t in p.tracks)
        {
          'id': t.id,
          'name': t.name,
          'type': t.type.name,
          'locked': t.isLocked,
          'hidden': t.isHidden,
          'muted': t.isMuted,
          'clip_count': t.clips.length,
        },
    ],
    'clips': clips
        .skip(offset)
        .take(limit)
        .map((c) => clipSummary(p, c))
        .toList(),
    'markers': [
      for (final m in p.markers.take(100))
        {'id': m.id, 'name': m.name, 'at': seconds(m.position)},
    ],
    'marker_count': p.markers.length,
    'transition_count': p.transitions.length,
    'offset': offset,
    'limit': limit,
    'next_cursor': offset + limit < clips.length
        ? '$revision:${offset + limit}'
        : null,
  };
}
