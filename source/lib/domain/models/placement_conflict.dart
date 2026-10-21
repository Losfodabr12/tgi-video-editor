enum PlacementConflictCause {
  overlap('overlap'),
  incompatibleTrack('incompatible_track'),
  lockedTrack('locked_track'),
  lockedClip('locked_clip'),
  linkedGroup('linked_group');

  const PlacementConflictCause(this.code);
  final String code;
}

/// Runtime validation data; never serialized into the v14 project document.
class PlacementConflict {
  const PlacementConflict({
    required this.cause,
    required this.clipIds,
    required this.trackIds,
    required this.start,
    required this.end,
    required this.suggestion,
    this.groupIds = const [],
  });
  final PlacementConflictCause cause;
  final List<String> clipIds, trackIds, groupIds;
  final Duration start, end;
  final String suggestion;

  Map<String, Object?> toJson() => {
    'cause': cause.code,
    'clip_ids': clipIds,
    'track_ids': trackIds,
    'group_ids': groupIds,
    'interval': {
      'start': start.inMicroseconds / 1e6,
      'end': end.inMicroseconds / 1e6,
    },
    'suggestion': suggestion,
  };
}

typedef PlacementConflictHandler = void Function(PlacementConflict conflict);
