part of 'timeline_panel.dart';

// Tracks and projects are immutable snapshots. Expando releases indexes along
// with snapshots, including discarded undo history, without a global cache leak.
final _trackIndexes = Expando<_TimelineTrackIndex>();
final _mediaIndexes = Expando<Map<String, MediaItem>>();

_TimelineTrackIndex _trackIndexFor(List<Track> tracks) =>
    _trackIndexes[tracks] ??= _TimelineTrackIndex(tracks);

class _TimelineTrackIndex {
  _TimelineTrackIndex(List<Track> tracks) {
    for (var index = 0; index < tracks.length; index++) {
      final track = tracks[index];
      for (final clip in track.clips) {
        groupTracks.putIfAbsent((
          clip.timelineGroupId,
          clip.trackType,
        ), () => index);
        for (final boundary in [clip.timelineStart, clip.timelineEnd]) {
          boundaryGroups
              .putIfAbsent(boundary, () => <String>{})
              .add(clip.timelineGroupId);
        }
      }
    }
  }

  final groupTracks = <(String, TrackType), int>{};
  final boundaryGroups = <Duration, Set<String>>{};

  Iterable<Duration> snapCandidates({
    required List<TimelineMarker> markers,
    required Duration playhead,
    required Duration duration,
    String? ignoredGroup,
  }) sync* {
    yield Duration.zero;
    yield _clampDuration(playhead, Duration.zero, duration);
    for (final entry in boundaryGroups.entries) {
      // Preserve a shared boundary even when one of its owners is dragged.
      if (ignoredGroup != null &&
          entry.value.length == 1 &&
          entry.value.contains(ignoredGroup)) {
        continue;
      }
      yield _clampDuration(entry.key, Duration.zero, duration);
    }
    for (final marker in markers) {
      yield _clampDuration(marker.position, Duration.zero, duration);
    }
  }
}
