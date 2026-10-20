part of 'project.dart';

/// Timeline operations are transactional: a rejected placement returns the
/// original snapshot, including all linked companions and track metadata.
extension DynamicTimeline on TgiProject {
  /// Paste keeps source offsets and links. Occupied destinations receive a
  /// neighbouring compatible lane; a missing source lane never discards clips.
  TgiProject pasteClips(
    Map<String, List<Clip>> copiedTracks, {
    required Duration timelineStart,
  }) {
    final entries = copiedTracks.values.expand((clips) => clips).toList();
    if (entries.isEmpty) return this;
    if (copiedTracks.keys.any((id) => trackById(id)?.isLocked ?? false)) {
      return this;
    }
    final earliest = entries
        .map((clip) => clip.timelineStart)
        .reduce((a, b) => a < b ? a : b);
    final start = _normalizeTimelineStart(timelineStart);
    final groups = <String, String>{};
    var project = this;
    var missingVisualIndex = 0;
    for (final source in copiedTracks.entries) {
      if (source.value.isEmpty) continue;
      final clones = [
        for (final clip in source.value)
          clip.copyWith(
            id: 'clip_${++_nextClipId}_${_clipIdSuffix(clip.kind)}',
            timelineGroupId: groups.putIfAbsent(
              clip.timelineGroupId,
              () => 'group_${++_nextGroupId}',
            ),
            timelineStart: start + (clip.timelineStart - earliest),
          ),
      ];
      bool fits(Track track) {
        var staged = track;
        for (final clone in clones) {
          if (!project.canPlaceOnTrack(staged, clone)) return false;
          staged = staged.copyWith(clips: [...staged.clips, clone]);
        }
        return true;
      }

      var destination = project.trackById(source.key);
      if (destination == null || !fits(destination)) {
        final lane = project._newDynamicTrack(clones.first.kind);
        if (!fits(lane)) return this;
        final lanes = [...project.tracks];
        final original = lanes.indexWhere((track) => track.id == source.key);
        final index = original >= 0
            ? original + (lane.kind == TrackKind.audio ? 1 : 0)
            : lane.kind == TrackKind.audio
            ? lanes.length
            : missingVisualIndex++;
        lanes.insert(index, lane);
        project = project.copyWith(tracks: lanes);
        destination = lane;
      }
      final destinationId = destination.id;
      project = project.copyWith(
        tracks: [
          for (final track in project.tracks)
            track.id == destinationId
                ? track.copyWith(clips: _sortClips([...track.clips, ...clones]))
                : track,
        ],
      );
    }
    return project.copyWith(updatedAt: DateTime.now());
  }

  TgiProject changeAudioSpeed(String groupId, double value) {
    if (groupsAreLocked({groupId}) || !value.isFinite || value <= 0) {
      return this;
    }
    final speed = value.clamp(.25, 4.0);
    final audio = tracks
        .expand((track) => track.clips)
        .where(
          (clip) =>
              clip.timelineGroupId == groupId &&
              clip.trackType == TrackType.audio,
        );
    if (audio.isEmpty || audio.every((clip) => clip.playbackSpeed == speed)) {
      return this;
    }
    if (tracks
        .expand((track) => track.clips)
        .any(
          (clip) =>
              clip.timelineGroupId == groupId &&
              clip.trackType == TrackType.video,
        )) {
      return updateClipGroupPlaybackSpeed(groupId, playbackSpeed: speed);
    }
    return copyWith(
      tracks: tracks
          .map(
            (track) => track.copyWith(
              clips: [
                for (final clip in track.clips)
                  clip.timelineGroupId == groupId &&
                          clip.trackType == TrackType.audio
                      ? clip.copyWith(
                          playbackSpeed: speed,
                          sourceDuration: clip.effectiveSourceDuration,
                          duration: Duration(
                            microseconds:
                                (clip.effectiveSourceDuration.inMicroseconds /
                                        speed)
                                    .round(),
                          ),
                        )
                      : clip,
              ],
            ),
          )
          .toList(),
      updatedAt: DateTime.now(),
    ).validatedAgainst(this);
  }

  TgiProject rippleRemoveGroups(Set<String> groups) {
    if (groups.isEmpty || groupsAreLocked(groups)) return this;
    final ranges = <(Duration, Duration)>[
      for (final track in tracks)
        for (final clip in track.clips)
          if (groups.contains(clip.timelineGroupId))
            (clip.timelineStart, clip.timelineEnd),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    if (ranges.isEmpty) return this;
    final merged = <(Duration, Duration)>[];
    for (final range in ranges) {
      if (merged.isEmpty || range.$1 > merged.last.$2) {
        merged.add(range);
      } else if (range.$2 > merged.last.$2) {
        merged[merged.length - 1] = (merged.last.$1, range.$2);
      }
    }
    Duration shift(Duration time) {
      var removed = Duration.zero;
      for (final range in merged) {
        if (range.$2 <= time) removed += range.$2 - range.$1;
      }
      return time - removed;
    }

    bool removed(Duration time) =>
        merged.any((range) => time >= range.$1 && time < range.$2);
    return copyWith(
      tracks: tracks
          .map(
            (track) => track.copyWith(
              clips: [
                for (final clip in track.clips)
                  if (!groups.contains(clip.timelineGroupId))
                    shift(clip.timelineStart) == clip.timelineStart
                        ? clip
                        : clip.copyWith(
                            timelineStart: shift(clip.timelineStart),
                          ),
              ],
            ),
          )
          .toList(),
      markers: [
        for (final marker in markers)
          if (!removed(marker.position))
            marker.copyWith(position: shift(marker.position)),
      ],
      transitions: [
        for (final transition in transitions)
          if (!removed(transition.timelinePosition))
            transition.copyWith(
              timelinePosition: shift(transition.timelinePosition),
            ),
      ],
      updatedAt: DateTime.now(),
    ).validatedAgainst(this);
  }

  /// Checks only changed spans, leaving pre-existing legacy overlaps untouched.
  /// Locked companions also guard ripple/trim operations spanning other lanes.
  TgiProject validatedAgainst(TgiProject original) {
    for (final track in original.tracks.where((track) => track.isLocked)) {
      final next = trackById(track.id);
      if (next == null || next.clips.length != track.clips.length) {
        return original;
      }
      for (var index = 0; index < track.clips.length; index++) {
        if (!identical(track.clips[index], next.clips[index])) return original;
      }
    }
    for (final track in tracks) {
      for (final clip in track.clips) {
        final old = original.clipById(clip.id);
        if (old != null &&
            old.timelineStart == clip.timelineStart &&
            old.duration == clip.duration &&
            original.clipTrackById(clip.id)?.id == track.id) {
          continue;
        }
        if (!canPlaceOnTrack(
          track,
          clip,
          ignoringGroups: {clip.timelineGroupId},
        )) {
          return original;
        }
      }
    }
    return this;
  }

  /// Shift-drop inserts at an edit boundary, shifting whole linked groups.
  /// Inserting inside a clip is rejected instead of silently truncating it.
  TgiProject insertMedia(
    MediaItem item, {
    required Duration timelineStart,
    required String targetTrackId,
    ImageClipFit imageFit = ImageClipFit.overlay,
    double overlayX = 1,
    double overlayY = 0,
    double overlayScale = 1,
  }) {
    final target = trackById(targetTrackId);
    final content = item.type == MediaType.audio
        ? TrackType.audio
        : TrackType.video;
    if (target == null || target.isLocked || !target.accepts(content)) {
      return this;
    }
    final start = _normalizeTimelineStart(timelineStart);
    if (target.clips.any(
      (clip) => clip.timelineStart < start && clip.timelineEnd > start,
    )) {
      return this;
    }
    final groups = target.clips
        .where((clip) => clip.timelineStart >= start)
        .map((clip) => clip.timelineGroupId)
        .toSet();
    if (groupsAreLocked(groups)) return this;
    final duration = item.type == MediaType.image
        ? _defaultImageClipDuration
        : item.duration;
    final shifted = groups.isEmpty
        ? this
        : moveTimelineClipGroupsByDelta(groups, delta: duration);
    if (groups.isNotEmpty && identical(shifted, this)) return this;
    final placed = shifted.placeMedia(
      item,
      timelineStart: start,
      targetTrackId: targetTrackId,
      imageFit: imageFit,
      overlayX: overlayX,
      overlayY: overlayY,
      overlayScale: overlayScale,
    );
    return identical(placed, shifted) ? this : placed.validatedAgainst(this);
  }

  Track? trackForClip(String clipId) {
    return clipTrackById(clipId);
  }

  bool groupsAreLocked(Set<String> groups) => tracks.any(
    (track) =>
        track.isLocked &&
        track.clips.any((clip) => groups.contains(clip.timelineGroupId)),
  );

  /// Bottom to top, independent of selection or content type.
  List<Clip> visualClipsAt(Duration position) => [
    for (final track in tracks.reversed)
      if (track.kind == TrackKind.visual && !track.isHidden)
        for (final clip in track.clipIndex.intersecting(
          position,
          position + const Duration(microseconds: 1),
        ))
          if (clip.trackType != TrackType.audio &&
              position >= clip.timelineStart &&
              position < clip.timelineEnd)
            clip,
  ];

  Track? get baseVideoTrack {
    for (final track in tracks.reversed) {
      if (track.kind == TrackKind.visual &&
          !track.isHidden &&
          track.clips.any((clip) => clip.trackType == TrackType.video)) {
        return track;
      }
    }
    return null;
  }

  TgiProject setTrackHeight(String id, double height) => _updateTimelineTrack(
    id,
    (track) =>
        !height.isFinite || (track.height - height.clamp(44, 180)).abs() < .1
        ? track
        : track.copyWith(height: height),
  );

  TgiProject reorderTrack(String id, int targetIndex) {
    final index = tracks.indexWhere((track) => track.id == id);
    if (index < 0 || tracks[index].isLocked) return this;
    final target = targetIndex.clamp(0, tracks.length - 1);
    if (index == target) return this;
    final next = [...tracks];
    next.insert(target, next.removeAt(index));
    return copyWith(tracks: next, updatedAt: DateTime.now());
  }

  TgiProject deleteTrack(String id) {
    final target = trackById(id);
    if (target == null || target.isLocked) return this;
    // Removing a lane removes its content only, never a linked visual/audio lane.
    return copyWith(
      tracks: tracks.where((track) => track.id != id).toList(),
      updatedAt: DateTime.now(),
    );
  }

  TgiProject removeGroupAudio(String groupId) {
    if (groupsAreLocked({groupId})) return this;
    var changed = false;
    final next = tracks.map((track) {
      final clips = track.clips
          .where(
            (clip) =>
                clip.timelineGroupId != groupId ||
                clip.trackType != TrackType.audio,
          )
          .toList();
      if (clips.length == track.clips.length) return track;
      changed = true;
      return track.copyWith(clips: clips);
    }).toList();
    return changed ? copyWith(tracks: next, updatedAt: DateTime.now()) : this;
  }

  bool canPlaceOnTrack(
    Track track,
    Clip clip, {
    Set<String> ignoringGroups = const {},
  }) =>
      !track.isLocked &&
      track.accepts(clip.trackType) &&
      !track.clips.any(
        (other) =>
            !ignoringGroups.contains(other.timelineGroupId) &&
            other.id != clip.id &&
            clip.timelineStart < other.timelineEnd &&
            other.timelineStart < clip.timelineEnd,
      );

  Track _newDynamicTrack(TrackType content) {
    final audio = content == TrackType.audio;
    final defaultId = switch (content) {
      TrackType.video => TgiProject.defaultVideoTrackId,
      TrackType.audio => TgiProject.defaultAudioTrackId,
      TrackType.image => TgiProject.defaultImageTrackId,
      TrackType.text => TgiProject.defaultTextTrackId,
    };
    final id = tracks.any((track) => track.id == defaultId)
        ? audio
              ? 'track_audio_manual_${++_nextManualAudioTrackId}'
              : 'track_video_manual_${++_nextManualVideoTrackId}'
        : defaultId;
    final count =
        tracks
            .where(
              (track) =>
                  track.kind == (audio ? TrackKind.audio : TrackKind.visual),
            )
            .length +
        1;
    return Track(
      id: id,
      name: audio ? 'Áudio $count' : 'Visual $count',
      type: content,
      kind: audio ? TrackKind.audio : TrackKind.visual,
    );
  }

  TgiProject addDynamicTrack(TrackType content) {
    final lane = _newDynamicTrack(content);
    return copyWith(
      tracks: lane.kind == TrackKind.visual
          ? [lane, ...tracks]
          : [...tracks, lane],
      updatedAt: DateTime.now(),
    );
  }

  TgiProject placeMedia(
    MediaItem item, {
    required Duration timelineStart,
    String? targetTrackId,
    bool newTrack = false,
    ImageClipFit imageFit = ImageClipFit.overlay,
    double overlayX = 1,
    double overlayY = 0,
    double overlayScale = 1,
    Duration? clipDurationOverride,
  }) {
    final content = switch (item.type) {
      MediaType.video => TrackType.video,
      MediaType.image => TrackType.image,
      MediaType.text => TrackType.text,
      MediaType.audio => TrackType.audio,
    };
    final start = _normalizeTimelineStart(timelineStart);
    final duration = item.type == MediaType.image
        ? clipDurationOverride ?? _defaultImageClipDuration
        : item.duration;
    if (duration <= Duration.zero) return this;
    final group = 'group_${++_nextGroupId}';
    final clip = Clip(
      id: 'clip_${++_nextClipId}_${_clipIdSuffix(content)}',
      mediaItemId: item.id,
      timelineGroupId: group,
      trackType: content,
      timelineStart: start,
      sourceStart: Duration.zero,
      duration: duration,
      sourceDuration: item.type == MediaType.image ? null : duration,
      overlayX: _clampUnit(overlayX),
      overlayY: _clampUnit(overlayY),
      overlayScale: _clampImageOverlayScale(overlayScale),
      imageFit: imageFit,
    );
    Track? lane;
    if (targetTrackId != null && !newTrack) {
      lane = trackById(targetTrackId);
      if (lane == null || !canPlaceOnTrack(lane, clip)) return this;
    } else if (!newTrack) {
      for (final candidate in tracks.reversed) {
        if (canPlaceOnTrack(candidate, clip)) {
          lane = candidate;
          break;
        }
      }
    }
    var project = this;
    if (lane == null) {
      lane = _newDynamicTrack(content);
      project = copyWith(
        tracks: lane.kind == TrackKind.visual
            ? [lane, ...tracks]
            : [...tracks, lane],
      );
    }
    final laneId = lane.id;
    project = project.copyWith(
      tracks: project.tracks
          .map(
            (track) => track.id == laneId
                ? track.copyWith(clips: _sortClips([...track.clips, clip]))
                : track,
          )
          .toList(),
    );
    if (item.type == MediaType.video && item.hasAudio) {
      final audio = Clip(
        id: 'clip_${++_nextClipId}_a',
        mediaItemId: item.id,
        timelineGroupId: group,
        trackType: TrackType.audio,
        timelineStart: start,
        sourceStart: Duration.zero,
        duration: duration,
        sourceDuration: duration,
      );
      // Reuse an available audio lane; silent video never creates a lane.
      Track? audioLane;
      for (final candidate in project.tracks) {
        if (candidate.kind == TrackKind.audio &&
            project.canPlaceOnTrack(candidate, audio)) {
          audioLane = candidate;
          break;
        }
      }
      if (audioLane == null) {
        audioLane = project._newDynamicTrack(TrackType.audio);
        project = project.copyWith(tracks: [...project.tracks, audioLane]);
      }
      final audioId = audioLane.id;
      project = project.copyWith(
        tracks: project.tracks
            .map(
              (track) => track.id == audioId
                  ? track.copyWith(clips: _sortClips([...track.clips, audio]))
                  : track,
            )
            .toList(),
      );
    }
    return project.copyWith(updatedAt: DateTime.now());
  }

  TgiProject placeText(Clip clip, {String? targetTrackId}) {
    Track? lane;
    if (targetTrackId != null) {
      lane = trackById(targetTrackId);
      if (lane == null || !canPlaceOnTrack(lane, clip)) return this;
    } else {
      for (final candidate in tracks) {
        if (canPlaceOnTrack(candidate, clip)) {
          lane = candidate;
          break;
        }
      }
    }
    var next = this;
    if (lane == null) {
      lane = _newDynamicTrack(TrackType.text);
      next = copyWith(tracks: [lane, ...tracks]);
    }
    final id = lane.id;
    return next.copyWith(
      tracks: next.tracks
          .map(
            (track) => track.id == id
                ? track.copyWith(clips: _sortClips([...track.clips, clip]))
                : track,
          )
          .toList(),
      updatedAt: DateTime.now(),
    );
  }

  TgiProject placeClipGroups(
    String anchorClipId, {
    required Duration timelineStart,
    String? targetTrackId,
    Set<String>? selectedGroups,
  }) {
    final source = trackForClip(anchorClipId);
    if (source == null) return this;
    final anchor = source.clips.firstWhere((clip) => clip.id == anchorClipId);
    final groups =
        selectedGroups != null &&
            selectedGroups.contains(anchor.timelineGroupId)
        ? selectedGroups
        : {anchor.timelineGroupId};
    if (groupsAreLocked(groups)) return this;
    final target = targetTrackId == null ? source : trackById(targetTrackId);
    if (target == null ||
        target.isLocked ||
        !target.accepts(anchor.trackType)) {
      return this;
    }
    final compatible = tracks
        .where((track) => track.kind == source.kind)
        .toList();
    final verticalDelta =
        compatible.indexWhere((track) => track.id == target.id) -
        compatible.indexWhere((track) => track.id == source.id);
    final moving = [
      for (final track in tracks)
        for (final clip in track.clips)
          if (groups.contains(clip.timelineGroupId)) clip,
    ];
    final earliest = moving
        .map((clip) => clip.timelineStart)
        .reduce((a, b) => a < b ? a : b);
    var delta = _normalizeTimelineStart(timelineStart) - anchor.timelineStart;
    if (earliest + delta < Duration.zero) delta = -earliest;
    if (delta == Duration.zero && verticalDelta == 0) return this;
    final placements = <String, List<Clip>>{};
    for (final track in tracks) {
      final clips = track.clips
          .where((clip) => groups.contains(clip.timelineGroupId))
          .toList();
      if (clips.isEmpty) continue;
      var destination = track;
      if (track.kind == source.kind) {
        final index =
            compatible.indexWhere((candidate) => candidate.id == track.id) +
            verticalDelta;
        if (index < 0 || index >= compatible.length) return this;
        destination = compatible[index];
      }
      for (final clip in clips) {
        final moved = clip.copyWith(timelineStart: clip.timelineStart + delta);
        if (!canPlaceOnTrack(destination, moved, ignoringGroups: groups)) {
          return this;
        }
        placements.putIfAbsent(destination.id, () => []).add(moved);
      }
    }
    return copyWith(
      tracks: tracks.map((track) {
        final remaining = track.clips.where(
          (clip) => !groups.contains(clip.timelineGroupId),
        );
        final additions = placements[track.id] ?? const <Clip>[];
        if (additions.isEmpty && remaining.length == track.clips.length) {
          return track;
        }
        return track.copyWith(clips: _sortClips([...remaining, ...additions]));
      }).toList(),
      updatedAt: DateTime.now(),
    );
  }

  TgiProject placeClipOnNewTrack(
    String clipId,
    Duration start, {
    Set<String>? selectedGroups,
  }) {
    final source = trackForClip(clipId);
    if (source == null) return this;
    final clip = source.clips.firstWhere((clip) => clip.id == clipId);
    final groups =
        selectedGroups != null && selectedGroups.contains(clip.timelineGroupId)
        ? selectedGroups
        : {clip.timelineGroupId};
    if (groupsAreLocked(groups)) return this;
    final next = addDynamicTrack(clip.trackType);
    final newId = next.tracks
        .firstWhere((track) => !tracks.any((old) => old.id == track.id))
        .id;
    final result = next.placeClipGroups(
      clipId,
      timelineStart: start,
      targetTrackId: newId,
      selectedGroups: groups,
    );
    return identical(result, next) ? this : result;
  }
}
