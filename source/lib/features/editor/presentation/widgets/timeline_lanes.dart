part of 'timeline_panel.dart';

class _TimelineLanes extends StatelessWidget {
  const _TimelineLanes({
    required this.project,
    required this.horizontalScrollController,
    required this.viewportWidth,
    required this.audioWaveforms,
    required this.duration,
    required this.width,
    required this.scrollController,
    required this.viewportKey,
    required this.activeTimelineGroupId,
    required this.selectedTimelineGroupId,
    required this.selectedTimelineGroupIds,
    required this.playheadPosition,
    required this.cutMode,
    required this.editMode,
    required this.snappingEnabled,
    required this.onClipMoved,
    required this.onClipResized,
    required this.onClipCut,
    required this.onClipSelected,
    required this.onTextClipEdit,
    required this.onClipVolumeChanged,
    required this.onClipFadeChanged,
    required this.onClipTrimPreview,
    required this.onClipTrimmed,
    required this.onClipTrimCanceled,
    required this.onMediaDropped,
    required this.onClipMovedToTrack,
    required this.onClipMovedToNewTrack,
    required this.onClipSlipped,
    required this.onClipSlid,
    required this.onClipDragHover,
  });

  final TgiProject project;
  final ScrollController horizontalScrollController;
  final double viewportWidth;
  final Map<String, AudioWaveform> audioWaveforms;
  final Duration duration;
  final double width;
  final ScrollController scrollController;
  final GlobalKey viewportKey;
  final String? activeTimelineGroupId;
  final String? selectedTimelineGroupId;
  final Set<String> selectedTimelineGroupIds;
  final Duration playheadPosition;
  final bool cutMode;
  final TimelineEditMode editMode;
  final bool snappingEnabled;
  final void Function(String timelineGroupId, Duration timelineStart)
  onClipMoved;
  final void Function(String clipId, Duration timelineStart, Duration duration)?
  onClipResized;
  final void Function(String clipId, Duration timelinePosition)? onClipCut;
  final TimelineClipSelectionCallback? onClipSelected;
  final void Function(domain.Clip clip)? onTextClipEdit;
  final void Function(String clipId, double volume)? onClipVolumeChanged;
  final TimelineClipFadeCallback? onClipFadeChanged;
  final TimelineClipTrimCallback? onClipTrimPreview;
  final TimelineClipTrimCallback? onClipTrimmed;
  final VoidCallback? onClipTrimCanceled;
  final TimelineMediaDropCallback onMediaDropped;
  final TimelineClipTrackMoveCallback? onClipMovedToTrack;
  final TimelineClipNewTrackMoveCallback? onClipMovedToNewTrack;
  final TimelineClipDeltaCallback? onClipSlipped;
  final TimelineClipDeltaCallback? onClipSlid;
  final TimelineDragHoverCallback onClipDragHover;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: horizontalScrollController,
      builder: (context, _) => ListView.builder(
        key: viewportKey,
        controller: scrollController,
        itemCount: project.tracks.length + 1,
        itemBuilder: (context, row) {
          if (row == 0) {
            return const SizedBox(
              key: ValueKey('timeline-new-track-drop-zone'),
              height: _newLaneExtent,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: 12),
                  child: Text(
                    '+ Solte aqui para criar uma camada',
                    style: TextStyle(fontSize: 10, color: TgiColors.textMuted),
                  ),
                ),
              ),
            );
          }
          final index = row - 1;
          final track = project.tracks[index];
          return SizedBox(
            height: track.height,
            child: _TimelineLane(
              key: ValueKey(track.id),
              viewportStart: horizontalScrollController.hasClients
                  ? horizontalScrollController.offset
                  : 0,
              viewportWidth: viewportWidth,
              track: track,
              tracks: project.tracks,
              markers: project.markers,
              trackIndex: index,
              project: project,
              audioWaveforms: audioWaveforms,
              duration: duration,
              width: width,
              activeTimelineGroupId: activeTimelineGroupId,
              selectedTimelineGroupId: selectedTimelineGroupId,
              selectedTimelineGroupIds: selectedTimelineGroupIds,
              playheadPosition: playheadPosition,
              cutMode: cutMode,
              editMode: editMode,
              snappingEnabled: snappingEnabled,
              onClipMoved: onClipMoved,
              onClipResized: onClipResized,
              onClipCut: onClipCut,
              onClipSelected: onClipSelected,
              onTextClipEdit: onTextClipEdit,
              onClipVolumeChanged: onClipVolumeChanged,
              onClipFadeChanged: onClipFadeChanged,
              onClipTrimPreview: onClipTrimPreview,
              onClipTrimmed: onClipTrimmed,
              onClipTrimCanceled: onClipTrimCanceled,
              onMediaDropped: onMediaDropped,
              onClipMovedToTrack: onClipMovedToTrack,
              onClipMovedToNewTrack: onClipMovedToNewTrack,
              onClipSlipped: onClipSlipped,
              onClipSlid: onClipSlid,
              onClipDragHover: onClipDragHover,
              trackDropTargetFromGlobalPosition:
                  _trackDropTargetFromGlobalPosition,
            ),
          );
        },
      ),
    );
  }

  _TimelineTrackDropTarget _trackDropTargetFromGlobalPosition(
    Offset globalPosition,
    TrackType trackType,
  ) {
    final context = viewportKey.currentContext;
    final renderObject = context?.findRenderObject();
    if (renderObject is! RenderBox || tracksAreEmpty) {
      return _TimelineTrackDropTarget(isBelowTracks: tracksAreEmpty);
    }

    final localY = renderObject.globalToLocal(globalPosition).dy;
    final scrollOffset = scrollController.hasClients
        ? scrollController.offset
        : 0.0;
    final absoluteY = scrollOffset + localY;
    if (localY < 0) return const _TimelineTrackDropTarget(invalid: true);
    final targetIndex = _trackAtY(project.tracks, absoluteY);
    if (targetIndex < 0) {
      return const _TimelineTrackDropTarget(isBelowTracks: true);
    }
    final target = project.tracks[targetIndex];
    return _TimelineTrackDropTarget(
      trackId: target.accepts(trackType) && !target.isLocked ? target.id : null,
      invalid: !target.accepts(trackType) || target.isLocked,
    );
  }

  bool get tracksAreEmpty => project.tracks.isEmpty;
}

class _TimelineLane extends StatefulWidget {
  const _TimelineLane({
    super.key,
    required this.viewportStart,
    required this.viewportWidth,
    required this.track,
    required this.tracks,
    required this.markers,
    required this.trackIndex,
    required this.project,
    required this.audioWaveforms,
    required this.duration,
    required this.width,
    required this.activeTimelineGroupId,
    required this.selectedTimelineGroupId,
    required this.selectedTimelineGroupIds,
    required this.playheadPosition,
    required this.cutMode,
    required this.editMode,
    required this.snappingEnabled,
    required this.onClipMoved,
    required this.onClipResized,
    required this.onClipCut,
    required this.onClipSelected,
    required this.onTextClipEdit,
    required this.onClipVolumeChanged,
    required this.onClipFadeChanged,
    required this.onClipTrimPreview,
    required this.onClipTrimmed,
    required this.onClipTrimCanceled,
    required this.onMediaDropped,
    required this.onClipMovedToTrack,
    required this.onClipMovedToNewTrack,
    required this.onClipSlipped,
    required this.onClipSlid,
    required this.onClipDragHover,
    required this.trackDropTargetFromGlobalPosition,
  });

  final Track track;
  final double viewportStart;
  final double viewportWidth;
  final List<Track> tracks;
  final List<TimelineMarker> markers;
  final int trackIndex;
  final TgiProject project;
  final Map<String, AudioWaveform> audioWaveforms;
  final Duration duration;
  final double width;
  final String? activeTimelineGroupId;
  final String? selectedTimelineGroupId;
  final Set<String> selectedTimelineGroupIds;
  final Duration playheadPosition;
  final bool cutMode;
  final TimelineEditMode editMode;
  final bool snappingEnabled;
  final void Function(String timelineGroupId, Duration timelineStart)
  onClipMoved;
  final void Function(String clipId, Duration timelineStart, Duration duration)?
  onClipResized;
  final void Function(String clipId, Duration timelinePosition)? onClipCut;
  final TimelineClipSelectionCallback? onClipSelected;
  final void Function(domain.Clip clip)? onTextClipEdit;
  final void Function(String clipId, double volume)? onClipVolumeChanged;
  final TimelineClipFadeCallback? onClipFadeChanged;
  final TimelineClipTrimCallback? onClipTrimPreview;
  final TimelineClipTrimCallback? onClipTrimmed;
  final VoidCallback? onClipTrimCanceled;
  final TimelineMediaDropCallback onMediaDropped;
  final TimelineClipTrackMoveCallback? onClipMovedToTrack;
  final TimelineClipNewTrackMoveCallback? onClipMovedToNewTrack;
  final TimelineClipDeltaCallback? onClipSlipped;
  final TimelineClipDeltaCallback? onClipSlid;
  final TimelineDragHoverCallback onClipDragHover;
  final _TimelineTrackDropTargetAtOffset trackDropTargetFromGlobalPosition;

  @override
  State<_TimelineLane> createState() => _TimelineLaneState();

  Widget buildLane(
    BuildContext context,
    GlobalKey laneKey, {
    Duration? dropPreview,
    required ValueChanged<Duration?> onDropHover,
  }) {
    return DragTarget<MediaItem>(
      hitTestBehavior: HitTestBehavior.opaque,
      onWillAcceptWithDetails: (details) =>
          !track.isLocked && _canDropMediaOnTrack(details.data, track),
      onMove: (details) {
        final box = laneKey.currentContext?.findRenderObject();
        if (box is! RenderBox) return;
        onDropHover(
          _snapMediaDropPosition(
            item: details.data,
            project: project,
            targetTrack: track,
            proposedStart: _positionFromDx(
              box.globalToLocal(details.offset).dx,
              duration,
              width,
            ),
            playheadPosition: playheadPosition,
            duration: duration,
            width: width,
            enabled: snappingEnabled,
          ),
        );
      },
      onLeave: (_) => onDropHover(null),
      onAcceptWithDetails: (details) {
        onDropHover(null);
        if (track.isLocked) {
          return;
        }
        final renderObject = laneKey.currentContext?.findRenderObject();
        final localDx = renderObject is RenderBox
            ? renderObject.globalToLocal(details.offset).dx
            : 0.0;
        final rawTimelineStart = _positionFromDx(localDx, duration, width);
        final timelineStart = _snapMediaDropPosition(
          item: details.data,
          project: project,
          targetTrack: track,
          proposedStart: rawTimelineStart,
          playheadPosition: playheadPosition,
          duration: duration,
          width: width,
          enabled: snappingEnabled,
        );
        onMediaDropped(
          details.data,
          timelineStart,
          targetTrackId: track.id,
          forceNewVideoTrack: _shouldCreateVideoTrackForDroppedMedia(
            details.data,
            project,
            track,
            timelineStart,
            isEmptyLaneArea: false,
          ),
          forceNewAudioTrack: false,
        );
      },
      builder: (context, candidateData, rejectedData) {
        final accepting = candidateData.isNotEmpty;
        final laneColor = _timelineLaneFillFor(trackIndex, track);
        final accentColor = _trackAccentFor(track.type);
        return AnimatedContainer(
          key: laneKey,
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: accepting ? _timelineDropBackground : laneColor,
            border: const Border(
              bottom: BorderSide(color: TgiColors.borderSubtle),
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 2,
                  color: accentColor.withValues(
                    alpha: track.isHidden ? 0.12 : 0.34,
                  ),
                ),
              ),
              _TimelineGrid(duration: duration),
              if (accepting && dropPreview != null)
                Positioned(
                  key: ValueKey('media-drop-preview-${track.id}'),
                  left: _leftFor(dropPreview, duration, width),
                  top: 3,
                  bottom: 3,
                  width: _widthFor(
                    candidateData.first!.type == MediaType.image
                        ? const Duration(seconds: 5)
                        : candidateData.first!.duration,
                    duration,
                    width,
                  ),
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: TgiColors.accent.withValues(alpha: .16),
                        border: Border.all(
                          color:
                              _trackHasClipOverlap(
                                track,
                                dropPreview,
                                candidateData.first!.type == MediaType.image
                                    ? const Duration(seconds: 5)
                                    : candidateData.first!.duration,
                              )
                              ? TgiColors.danger
                              : TgiColors.accent,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Text(
                          formatDuration(dropPreview),
                          style: const TextStyle(
                            fontSize: 10,
                            color: TgiColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              for (final clip in _visibleClips())
                _PositionedClip(
                  key: ValueKey(clip.id),
                  clip: clip,
                  mediaItem: _findMediaItem(project, clip.mediaItemId),
                  audioWaveform: audioWaveforms[clip.mediaItemId],
                  duration: duration,
                  width: width,
                  active: clip.timelineGroupId == activeTimelineGroupId,
                  selected:
                      selectedTimelineGroupIds.contains(clip.timelineGroupId) ||
                      clip.timelineGroupId == selectedTimelineGroupId,
                  trackLocked: track.isLocked,
                  trackHidden: track.isHidden,
                  playheadPosition: playheadPosition,
                  cutMode: cutMode,
                  editMode: editMode,
                  snappingEnabled: snappingEnabled,
                  onClipMoved: onClipMoved,
                  onClipResized: onClipResized,
                  onClipCut: onClipCut,
                  onClipSelected: onClipSelected,
                  onTextClipEdit: onTextClipEdit,
                  onClipVolumeChanged: onClipVolumeChanged,
                  onClipFadeChanged: onClipFadeChanged,
                  onClipTrimPreview: onClipTrimPreview,
                  onClipTrimmed: onClipTrimmed,
                  onClipTrimCanceled: onClipTrimCanceled,
                  tracks: tracks,
                  markers: markers,
                  trackIndex: trackIndex,
                  onClipMovedToTrack: onClipMovedToTrack,
                  onClipMovedToNewTrack: onClipMovedToNewTrack,
                  onClipSlipped: onClipSlipped,
                  onClipSlid: onClipSlid,
                  onClipDragHover: onClipDragHover,
                  trackDropTargetFromGlobalPosition:
                      trackDropTargetFromGlobalPosition,
                ),
            ],
          ),
        );
      },
    );
  }

  Iterable<domain.Clip> _visibleClips() sync* {
    const overscan = 160.0;
    final start = _positionFromDx(
      math.max(0, viewportStart - overscan),
      duration,
      width,
    );
    final end = _positionFromDx(
      viewportStart + viewportWidth + overscan,
      duration,
      width,
    );
    final seen = <String>{};
    for (final clip in track.clipIndex.intersecting(start, end)) {
      seen.add(clip.id);
      yield clip;
    }
    for (final group in {
      ...selectedTimelineGroupIds,
      ?selectedTimelineGroupId,
    }) {
      for (final clip in track.clipIndex.group(group)) {
        if (seen.add(clip.id)) yield clip;
      }
    }
  }
}

class _TimelineLaneState extends State<_TimelineLane> {
  final _laneKey = GlobalKey();
  Duration? _dropPreview;

  @override
  Widget build(BuildContext context) => widget.buildLane(
    context,
    _laneKey,
    dropPreview: _dropPreview,
    onDropHover: (value) {
      if (mounted && value != _dropPreview) {
        setState(() => _dropPreview = value);
      }
    },
  );
}

class _TimelineGrid extends StatelessWidget {
  const _TimelineGrid({required this.duration});

  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              for (final seconds in _tickSeconds(duration))
                Positioned(
                  left: _leftFor(
                    Duration(seconds: seconds),
                    duration,
                    constraints.maxWidth,
                  ),
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: seconds % 5 == 0 ? 1.2 : 1,
                    color:
                        (seconds % 5 == 0
                                ? TgiColors.borderStrong
                                : TgiColors.timelineGrid)
                            .withValues(alpha: seconds % 5 == 0 ? 0.62 : 0.38),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PositionedClip extends StatefulWidget {
  const _PositionedClip({
    super.key,
    required this.clip,
    required this.mediaItem,
    required this.audioWaveform,
    required this.duration,
    required this.width,
    required this.active,
    required this.selected,
    required this.trackLocked,
    required this.trackHidden,
    required this.playheadPosition,
    required this.cutMode,
    required this.editMode,
    required this.snappingEnabled,
    required this.onClipMoved,
    required this.onClipResized,
    required this.onClipCut,
    required this.onClipSelected,
    required this.onTextClipEdit,
    required this.onClipVolumeChanged,
    required this.onClipFadeChanged,
    required this.onClipTrimPreview,
    required this.onClipTrimmed,
    required this.onClipTrimCanceled,
    required this.tracks,
    required this.markers,
    required this.trackIndex,
    required this.onClipMovedToTrack,
    required this.onClipMovedToNewTrack,
    required this.onClipSlipped,
    required this.onClipSlid,
    required this.onClipDragHover,
    required this.trackDropTargetFromGlobalPosition,
  });

  final domain.Clip clip;
  final MediaItem? mediaItem;
  final AudioWaveform? audioWaveform;
  final Duration duration;
  final double width;
  final bool active;
  final bool selected;
  final bool trackLocked;
  final bool trackHidden;
  final Duration playheadPosition;
  final bool cutMode;
  final TimelineEditMode editMode;
  final bool snappingEnabled;
  final void Function(String timelineGroupId, Duration timelineStart)
  onClipMoved;
  final void Function(String clipId, Duration timelineStart, Duration duration)?
  onClipResized;
  final void Function(String clipId, Duration timelinePosition)? onClipCut;
  final TimelineClipSelectionCallback? onClipSelected;
  final void Function(domain.Clip clip)? onTextClipEdit;
  final void Function(String clipId, double volume)? onClipVolumeChanged;
  final TimelineClipFadeCallback? onClipFadeChanged;
  final TimelineClipTrimCallback? onClipTrimPreview;
  final TimelineClipTrimCallback? onClipTrimmed;
  final VoidCallback? onClipTrimCanceled;
  final List<Track> tracks;
  final List<TimelineMarker> markers;
  final int trackIndex;
  final TimelineClipTrackMoveCallback? onClipMovedToTrack;
  final TimelineClipNewTrackMoveCallback? onClipMovedToNewTrack;
  final TimelineClipDeltaCallback? onClipSlipped;
  final TimelineClipDeltaCallback? onClipSlid;
  final TimelineDragHoverCallback onClipDragHover;
  final _TimelineTrackDropTargetAtOffset trackDropTargetFromGlobalPosition;

  @override
  State<_PositionedClip> createState() => _PositionedClipState();
}

enum _ClipResizeEdge { left, right }

enum _AudioClipDragMode { pending, moving, volume }

class _ClipFadeValues {
  const _ClipFadeValues({required this.fadeIn, required this.fadeOut});

  final Duration fadeIn;
  final Duration fadeOut;
}

class _PositionedClipState extends State<_PositionedClip> {
  bool _hovering = false;
  bool _dragging = false;
  double _dragDelta = 0;
  double _dragVerticalDelta = 0;
  int? _rawDragPointer;
  Offset? _rawDragStartGlobalPosition;
  bool _rawDragStartedOnVolumeLine = false;
  _AudioClipDragMode? _rawAudioDragMode;
  double? _rawAudioVolume;
  bool _resizing = false;
  _ClipResizeEdge? _resizeEdge;
  double _resizeDelta = 0;
  bool _trimming = false;
  _ClipResizeEdge? _trimEdge;
  double _trimDelta = 0;
  domain.Clip? _trimBaseClip;
  bool _adjustingFade = false;
  _ClipResizeEdge? _fadeEdge;
  double _fadeDelta = 0;
  Offset? _lastDragGlobalPosition;

  @override
  void dispose() {
    if (_dragging) {
      widget.onClipDragHover(null);
    }
    if (_trimming) {
      _scheduleClipTrimCanceled(requireMounted: false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapCandidates = widget.snappingEnabled
        ? _snapCandidatesForTimeline(
            tracks: widget.tracks,
            markers: widget.markers,
            playheadPosition: widget.playheadPosition,
            timelineDuration: widget.duration,
            ignoredTimelineGroupId: widget.clip.timelineGroupId,
          )
        : const <Duration>[];
    final resizeResult = _resizing && _resizeEdge != null
        ? _resizeForDragDelta(
            widget.clip,
            _resizeEdge!,
            _resizeDelta,
            widget.duration,
            widget.width,
            snapCandidates: snapCandidates,
          )
        : null;
    final trimResult = _trimming && _trimEdge != null
        ? _trimForDragDelta(
            _trimBaseClip ?? widget.clip,
            widget.mediaItem,
            _trimEdge!,
            _trimDelta,
            widget.duration,
            widget.width,
          )
        : null;
    final fadeResult = _adjustingFade && _fadeEdge != null
        ? _fadeForDragDelta(
            widget.clip,
            _fadeEdge!,
            _fadeDelta,
            widget.duration,
            widget.width,
          )
        : null;
    final clipForDisplay = _trimBaseClip ?? widget.clip;
    final displayedStart =
        trimResult?.timelineStart ??
        resizeResult?.timelineStart ??
        (_dragging && widget.editMode != TimelineEditMode.slip
            ? _startForDragDelta(
                clipForDisplay,
                _dragDelta,
                widget.duration,
                widget.width,
                snapCandidates: widget.editMode == TimelineEditMode.move
                    ? snapCandidates
                    : const <Duration>[],
              )
            : widget.clip.timelineStart);
    final slippedSourceStart =
        _dragging && widget.editMode == TimelineEditMode.slip
        ? _sourceStartForSlipDrag(
            clipForDisplay,
            widget.mediaItem,
            _dragDelta,
            widget.duration,
            widget.width,
          )
        : clipForDisplay.sourceStart;
    final displayedDuration =
        trimResult?.timelineDuration ??
        resizeResult?.duration ??
        widget.clip.duration;
    final displayedClip = clipForDisplay.copyWith(
      timelineStart: displayedStart,
      duration: displayedDuration,
      sourceStart: trimResult?.sourceStart ?? slippedSourceStart,
      sourceDuration:
          trimResult?.sourceDuration ?? clipForDisplay.sourceDuration,
      volume: widget.clip.trackType == TrackType.audio
          ? _rawAudioVolume ?? widget.clip.volume
          : widget.clip.volume,
      fadeIn: fadeResult?.fadeIn ?? widget.clip.fadeIn,
      fadeOut: fadeResult?.fadeOut ?? widget.clip.fadeOut,
    );
    final snappedEdges = (_dragging || _resizing) && widget.snappingEnabled
        ? snapCandidates
              .where(
                (candidate) =>
                    candidate == displayedStart ||
                    candidate == displayedStart + displayedDuration,
              )
              .toList()
        : const <Duration>[];
    final left = _leftFor(displayedStart, widget.duration, widget.width);
    final rawWidth = _widthFor(
      displayedDuration,
      widget.duration,
      widget.width,
    );
    final availableWidth = math.max(
      _minimumTimelineClipWidth,
      widget.width - left,
    );
    final clipWidth = math.min(
      math.max(rawWidth, _minimumTimelineClipWidth),
      availableWidth,
    );
    final canResize =
        (widget.clip.trackType == TrackType.image ||
            widget.clip.trackType == TrackType.text) &&
        !widget.trackLocked &&
        !widget.cutMode &&
        widget.editMode == TimelineEditMode.move &&
        widget.onClipResized != null;
    final canTrim =
        widget.clip.trackType == TrackType.video &&
        !widget.trackLocked &&
        !widget.cutMode &&
        widget.editMode == TimelineEditMode.move &&
        widget.mediaItem != null &&
        widget.onClipTrimmed != null;
    final linkedAudioClip =
        widget.clip.trackType == TrackType.audio &&
        _timelineGroupHasTrackType(
          widget.tracks,
          widget.clip.timelineGroupId,
          TrackType.video,
        );
    final canDragClip =
        !widget.trackLocked &&
        !widget.cutMode &&
        (widget.editMode == TimelineEditMode.move ||
            (widget.editMode == TimelineEditMode.slip &&
                widget.onClipSlipped != null &&
                widget.mediaItem != null) ||
            (widget.editMode == TimelineEditMode.slide &&
                widget.onClipSlid != null &&
                widget.clip.trackType == TrackType.video)) &&
        !_resizing &&
        !_trimming &&
        !_adjustingFade;
    final canAdjustFade =
        widget.onClipFadeChanged != null &&
        !widget.trackLocked &&
        !widget.cutMode &&
        !_trimming &&
        widget.clip.duration > Duration.zero;
    final fadeEnabled =
        widget.clip.fadeIn > Duration.zero ||
        widget.clip.fadeOut > Duration.zero;
    final hasRoomForEdgeHandles = clipWidth >= _clipTrimHandleWidth * 2;
    final showFadeHandles =
        canAdjustFade &&
        fadeEnabled &&
        (widget.selected || widget.active) &&
        hasRoomForEdgeHandles;
    final showTrimHandles = canTrim && hasRoomForEdgeHandles;
    final useRawAudioDrag =
        widget.editMode == TimelineEditMode.move &&
        widget.clip.trackType == TrackType.audio &&
        (_canMoveRawAudioClip() || _canAdjustRawAudioVolume());
    final linkedCompanionTrackIndex = switch (widget.clip.trackType) {
      TrackType.video => _timelineGroupTrackIndex(
        widget.tracks,
        widget.clip.timelineGroupId,
        TrackType.audio,
      ),
      TrackType.audio => _timelineGroupTrackIndex(
        widget.tracks,
        widget.clip.timelineGroupId,
        TrackType.video,
      ),
      TrackType.image || TrackType.text => null,
    };
    final connectedAbove = linkedCompanionTrackIndex == widget.trackIndex - 1;
    final connectedBelow = linkedCompanionTrackIndex == widget.trackIndex + 1;
    final topInset = connectedAbove ? 0.0 : 7.0;
    final bottomInset = connectedBelow ? 0.0 : 7.0;

    return Positioned(
      left: left,
      top: topInset,
      width: clipWidth,
      height: widget.tracks[widget.trackIndex].height - topInset - bottomInset,
      child: MouseRegion(
        onEnter: (_) {
          if (!_hovering) {
            setState(() => _hovering = true);
          }
        },
        onExit: (_) {
          if (_hovering && !_trimming) {
            setState(() => _hovering = false);
          }
        },
        child: Transform.translate(
          offset: Offset(
            0,
            _dragging &&
                    widget.editMode == TimelineEditMode.move &&
                    _canMoveClipBetweenTracks()
                ? _dragVerticalDelta
                : 0,
          ),
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: useRawAudioDrag
                ? _startRawAudioDrag
                : (event) {
                    if (widget.cutMode ||
                        (event.buttons & kPrimaryMouseButton) == 0) {
                      return;
                    }
                    widget.onClipSelected?.call(
                      widget.clip.timelineGroupId,
                      clipId: widget.clip.id,
                      additive: _additiveSelectPressed(),
                      toggle: _toggleSelectPressed(),
                    );
                  },
            onPointerMove: useRawAudioDrag
                ? (event) => _updateRawAudioDrag(event, snapCandidates)
                : null,
            onPointerUp: useRawAudioDrag
                ? (event) => _finishRawAudioDrag(event, snapCandidates)
                : null,
            onPointerCancel: useRawAudioDrag ? _cancelRawAudioDrag : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_dragging)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            width: 2,
                            color: _trackDropTargetForDrag().invalid
                                ? TgiColors.danger
                                : TgiColors.accent,
                          ),
                        ),
                      ),
                    ),
                  ),
                GestureDetector(
                  key: ValueKey('timeline-clip-body-${widget.clip.id}'),
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    if (widget.cutMode && !widget.trackLocked) {
                      final timelinePosition = _positionFromDx(
                        left + details.localPosition.dx,
                        widget.duration,
                        widget.width,
                      );
                      if (widget.clip.timelineStart < timelinePosition &&
                          timelinePosition < widget.clip.timelineEnd) {
                        widget.onClipCut?.call(
                          widget.clip.id,
                          timelinePosition,
                        );
                      }
                      return;
                    }
                  },
                  onDoubleTap:
                      widget.clip.trackType == TrackType.text &&
                          !widget.cutMode &&
                          !widget.trackLocked
                      ? () {
                          widget.onClipSelected?.call(
                            widget.clip.timelineGroupId,
                            clipId: widget.clip.id,
                          );
                          widget.onTextClipEdit?.call(widget.clip);
                        }
                      : null,
                  onPanStart: !canDragClip || useRawAudioDrag
                      ? null
                      : (details) {
                          setState(() {
                            _dragging = true;
                            _dragDelta = 0;
                            _dragVerticalDelta = 0;
                            _lastDragGlobalPosition = details.globalPosition;
                          });
                          widget.onClipDragHover(details.globalPosition);
                        },
                  onPanUpdate: !canDragClip || useRawAudioDrag
                      ? null
                      : (details) {
                          setState(() {
                            _dragDelta += details.delta.dx;
                            _dragVerticalDelta += details.delta.dy;
                            _lastDragGlobalPosition = details.globalPosition;
                          });
                          widget.onClipDragHover(details.globalPosition);
                        },
                  onPanCancel: !canDragClip || useRawAudioDrag
                      ? null
                      : () {
                          setState(() {
                            _dragging = false;
                            _dragDelta = 0;
                            _dragVerticalDelta = 0;
                            _lastDragGlobalPosition = null;
                          });
                          widget.onClipDragHover(null);
                        },
                  onPanEnd: !canDragClip || useRawAudioDrag
                      ? null
                      : (_) {
                          _finishClipDrag(snapCandidates);
                        },
                  child: MouseRegion(
                    cursor: widget.cutMode
                        ? SystemMouseCursors.precise
                        : linkedAudioClip
                        ? SystemMouseCursors.basic
                        : widget.editMode == TimelineEditMode.slip
                        ? SystemMouseCursors.resizeLeftRight
                        : widget.editMode == TimelineEditMode.slide
                        ? SystemMouseCursors.grab
                        : SystemMouseCursors.move,
                    child: _TimelineClip(
                      clip: displayedClip,
                      mediaItem: widget.mediaItem,
                      audioWaveform: widget.audioWaveform,
                      dragging: _dragging || _resizing || _trimming,
                      active: widget.active,
                      selected: widget.selected,
                      locked: widget.trackLocked,
                      hidden: widget.trackHidden,
                      cutMode: widget.cutMode,
                      connectedAbove: connectedAbove,
                      connectedBelow: connectedBelow,
                      onVolumeChanged: widget.onClipVolumeChanged,
                    ),
                  ),
                ),
                if (snappedEdges.isNotEmpty)
                  Positioned(
                    key: ValueKey('snap-guide-${widget.clip.id}'),
                    left: snappedEdges.contains(displayedStart) ? 0 : null,
                    right: snappedEdges.contains(displayedStart) ? null : 0,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.symmetric(
                            vertical: BorderSide(
                              color: TgiColors.accent,
                              width: 2,
                            ),
                          ),
                        ),
                        alignment: Alignment.topCenter,
                        child: const ColoredBox(
                          color: TgiColors.primary,
                          child: Padding(
                            padding: EdgeInsets.all(4),
                            child: Text(
                              'SNAP',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: TgiColors.backgroundDeep,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (widget.clip.trackType == TrackType.audio)
                  _AudioVolumeLineLayer(
                    clipId: widget.clip.id,
                    volume: displayedClip.volume,
                    enabled:
                        widget.onClipVolumeChanged != null &&
                        !widget.trackLocked &&
                        !widget.cutMode,
                  ),
                if (showFadeHandles) ...[
                  _ClipFadeHandle(
                    edge: _ClipResizeEdge.left,
                    onDragStart: () =>
                        _startFadeAdjustment(_ClipResizeEdge.left),
                    onDragUpdate: _updateFadeAdjustment,
                    onDragCancel: _cancelFadeAdjustment,
                    onDragEnd: _finishFadeAdjustment,
                  ),
                  _ClipFadeHandle(
                    edge: _ClipResizeEdge.right,
                    onDragStart: () =>
                        _startFadeAdjustment(_ClipResizeEdge.right),
                    onDragUpdate: _updateFadeAdjustment,
                    onDragCancel: _cancelFadeAdjustment,
                    onDragEnd: _finishFadeAdjustment,
                  ),
                ],
                if (canResize) ...[
                  _ClipResizeHandle(
                    edge: _ClipResizeEdge.left,
                    onDragStart: () => _startResize(_ClipResizeEdge.left),
                    onDragUpdate: _updateResize,
                    onDragCancel: _cancelResize,
                    onDragEnd: _finishResize,
                  ),
                  _ClipResizeHandle(
                    edge: _ClipResizeEdge.right,
                    onDragStart: () => _startResize(_ClipResizeEdge.right),
                    onDragUpdate: _updateResize,
                    onDragCancel: _cancelResize,
                    onDragEnd: _finishResize,
                  ),
                ],
                if (showTrimHandles) ...[
                  _ClipTrimHandle(
                    edge: _ClipResizeEdge.left,
                    onDragStart: () => _startTrim(_ClipResizeEdge.left),
                    onDragUpdate: _updateTrim,
                    onDragCancel: _cancelTrim,
                    onDragEnd: _finishTrim,
                  ),
                  _ClipTrimHandle(
                    edge: _ClipResizeEdge.right,
                    onDragStart: () => _startTrim(_ClipResizeEdge.right),
                    onDragUpdate: _updateTrim,
                    onDragCancel: _cancelTrim,
                    onDragEnd: _finishTrim,
                  ),
                ],
                if (trimResult != null)
                  _ClipTrimPreviewBubble(
                    mediaItem: widget.mediaItem,
                    sourcePosition: trimResult.previewSourcePosition,
                    edge: _trimEdge ?? _ClipResizeEdge.left,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _startRawAudioDrag(PointerDownEvent event) {
    final size = context.size;
    if (size == null) {
      return;
    }
    widget.onClipSelected?.call(
      widget.clip.timelineGroupId,
      clipId: widget.clip.id,
      additive: _additiveSelectPressed(),
      toggle: _toggleSelectPressed(),
    );
    _rawDragPointer = event.pointer;
    _rawDragStartGlobalPosition = event.position;
    _rawDragStartedOnVolumeLine = _audioVolumeLineContains(
      event.localPosition,
      size,
    );
    _rawAudioDragMode = _AudioClipDragMode.pending;
    _lastDragGlobalPosition = event.position;
    _dragDelta = 0;
    _dragVerticalDelta = 0;
  }

  void _updateRawAudioDrag(
    PointerMoveEvent event,
    Iterable<Duration> snapCandidates,
  ) {
    if (_rawDragPointer != event.pointer) {
      return;
    }
    final start = _rawDragStartGlobalPosition;
    if (start == null) {
      return;
    }
    final delta = event.position - start;
    if (!_dragging && delta.distance < _clipDragStartThreshold) {
      return;
    }
    if (_rawAudioDragMode == _AudioClipDragMode.pending) {
      if (_rawDragStartedOnVolumeLine &&
          HardwareKeyboard.instance.isAltPressed &&
          delta.dy.abs() > delta.dx.abs() &&
          _canAdjustRawAudioVolume()) {
        _rawAudioDragMode = _AudioClipDragMode.volume;
        _updateRawAudioVolume(event.localPosition);
      } else if (_canMoveRawAudioClip()) {
        _rawAudioDragMode = _AudioClipDragMode.moving;
      } else {
        _clearRawAudioDrag();
        return;
      }
    }
    if (_rawAudioDragMode == _AudioClipDragMode.volume) {
      _updateRawAudioVolume(event.localPosition);
      return;
    }
    setState(() {
      _dragging = true;
      _dragDelta = delta.dx;
      _dragVerticalDelta = delta.dy;
      _lastDragGlobalPosition = event.position;
    });
    widget.onClipDragHover(event.position);
  }

  void _finishRawAudioDrag(
    PointerUpEvent event,
    Iterable<Duration> snapCandidates,
  ) {
    if (_rawDragPointer != event.pointer) {
      return;
    }
    if (!_dragging) {
      if (_rawAudioDragMode == _AudioClipDragMode.volume) {
        _commitRawAudioVolume(event.localPosition);
      }
      _clearRawAudioDrag();
      return;
    }
    _lastDragGlobalPosition = event.position;
    _finishClipDrag(snapCandidates);
    _clearRawAudioDrag();
  }

  void _cancelRawAudioDrag(PointerCancelEvent event) {
    if (_rawDragPointer != event.pointer) {
      return;
    }
    if (_dragging) {
      widget.onClipDragHover(null);
    }
    setState(() {
      _dragging = false;
      _dragDelta = 0;
      _dragVerticalDelta = 0;
      _lastDragGlobalPosition = null;
    });
    _clearRawAudioDrag();
  }

  void _clearRawAudioDrag() {
    _rawDragPointer = null;
    _rawDragStartGlobalPosition = null;
    _rawDragStartedOnVolumeLine = false;
    _rawAudioDragMode = null;
    _rawAudioVolume = null;
  }

  bool _audioVolumeLineContains(Offset localPosition, Size size) {
    if (widget.clip.trackType != TrackType.audio || size.height <= 0) {
      return false;
    }
    final lineY = _volumeLineY(widget.clip.volume, size.height);
    return localPosition.dx >= 0 &&
        localPosition.dx <= size.width &&
        (localPosition.dy - lineY).abs() <= _audioVolumeLineHitRadius;
  }

  bool _canMoveRawAudioClip() {
    return widget.clip.trackType == TrackType.audio &&
        !widget.trackLocked &&
        !widget.cutMode &&
        !_resizing;
  }

  bool _canAdjustRawAudioVolume() {
    return widget.clip.trackType == TrackType.audio &&
        widget.onClipVolumeChanged != null &&
        !widget.trackLocked &&
        !widget.cutMode;
  }

  void _updateRawAudioVolume(Offset localPosition) {
    final size = context.size;
    if (size == null || size.height <= 0) {
      return;
    }
    setState(() {
      _rawAudioVolume = _volumeFromLocalY(localPosition.dy, size.height);
    });
  }

  void _commitRawAudioVolume(Offset localPosition) {
    final size = context.size;
    if (size == null || size.height <= 0) {
      return;
    }
    final nextVolume = _volumeFromLocalY(localPosition.dy, size.height);
    widget.onClipVolumeChanged?.call(widget.clip.id, nextVolume);
  }

  void _finishClipDrag(Iterable<Duration> snapCandidates) {
    final rawTimelineDelta = Duration(
      microseconds: (_dragDelta / widget.width * widget.duration.inMicroseconds)
          .round(),
    );
    if (widget.editMode == TimelineEditMode.slip) {
      final sourceDelta = Duration(
        microseconds:
            (rawTimelineDelta.inMicroseconds * widget.clip.playbackSpeed)
                .round(),
      );
      widget.onClipDragHover(null);
      _resetClipDragState();
      widget.onClipSlipped?.call(widget.clip.id, sourceDelta);
      return;
    }
    if (widget.editMode == TimelineEditMode.slide) {
      widget.onClipDragHover(null);
      _resetClipDragState();
      widget.onClipSlid?.call(widget.clip.id, rawTimelineDelta);
      return;
    }
    final nextStart = _startForDragDelta(
      widget.clip,
      _dragDelta,
      widget.duration,
      widget.width,
      snapCandidates: snapCandidates,
    );
    final target = _trackDropTargetForDrag();
    widget.onClipDragHover(null);
    _resetClipDragState();
    if (target.invalid) return;
    if (target.trackId != null && widget.onClipMovedToTrack != null) {
      widget.onClipMovedToTrack!(widget.clip.id, target.trackId!, nextStart);
    } else if (_shouldMoveClipToNewTrack(target) &&
        widget.onClipMovedToNewTrack != null) {
      widget.onClipMovedToNewTrack!(widget.clip.id, nextStart);
    } else {
      widget.onClipMoved(widget.clip.timelineGroupId, nextStart);
    }
  }

  void _resetClipDragState() {
    setState(() {
      _dragging = false;
      _dragDelta = 0;
      _dragVerticalDelta = 0;
      _lastDragGlobalPosition = null;
    });
  }

  _TimelineTrackDropTarget _trackDropTargetForDrag() {
    if (!_canMoveClipBetweenTracks() || widget.tracks.isEmpty) {
      return const _TimelineTrackDropTarget();
    }

    final globalPosition = _lastDragGlobalPosition;
    if (globalPosition != null) {
      return widget.trackDropTargetFromGlobalPosition(
        globalPosition,
        widget.clip.trackType,
      );
    }

    final targetIndex =
        widget.trackIndex +
        (_dragVerticalDelta / widget.tracks[widget.trackIndex].height).round();
    if (targetIndex >= widget.tracks.length) {
      return const _TimelineTrackDropTarget(isBelowTracks: true);
    }
    if (targetIndex < 0) {
      return const _TimelineTrackDropTarget(isBelowTracks: true);
    }
    final targetTrack = widget.tracks[targetIndex];
    return _TimelineTrackDropTarget(
      trackId:
          targetTrack.accepts(widget.clip.trackType) && !targetTrack.isLocked
          ? targetTrack.id
          : null,
      invalid:
          !targetTrack.accepts(widget.clip.trackType) || targetTrack.isLocked,
    );
  }

  bool _shouldMoveClipToNewTrack(_TimelineTrackDropTarget target) =>
      target.isBelowTracks;

  bool _canMoveClipBetweenTracks() => !widget.trackLocked && !widget.cutMode;

  void _startFadeAdjustment(_ClipResizeEdge edge) {
    widget.onClipSelected?.call(
      widget.clip.timelineGroupId,
      clipId: widget.clip.id,
    );
    _clearRawAudioDrag();
    setState(() {
      _dragging = false;
      _dragDelta = 0;
      _adjustingFade = true;
      _fadeEdge = edge;
      _fadeDelta = 0;
    });
  }

  void _updateFadeAdjustment(DragUpdateDetails details) {
    setState(() {
      _fadeDelta += details.primaryDelta ?? 0;
    });
  }

  void _cancelFadeAdjustment() {
    setState(() {
      _adjustingFade = false;
      _fadeEdge = null;
      _fadeDelta = 0;
    });
  }

  void _finishFadeAdjustment() {
    final edge = _fadeEdge;
    if (edge == null) {
      _cancelFadeAdjustment();
      return;
    }
    final next = _fadeForDragDelta(
      widget.clip,
      edge,
      _fadeDelta,
      widget.duration,
      widget.width,
    );
    setState(() {
      _adjustingFade = false;
      _fadeEdge = null;
      _fadeDelta = 0;
    });
    widget.onClipFadeChanged?.call(
      widget.clip.id,
      fadeIn: next.fadeIn,
      fadeOut: next.fadeOut,
    );
  }

  void _startTrim(_ClipResizeEdge edge) {
    _clearRawAudioDrag();
    setState(() {
      _hovering = true;
      _dragging = false;
      _dragDelta = 0;
      _resizing = false;
      _resizeEdge = null;
      _resizeDelta = 0;
      _adjustingFade = false;
      _trimming = true;
      _trimEdge = edge;
      _trimDelta = 0;
      _trimBaseClip = widget.clip;
    });
    final next = _trimForDragDelta(
      widget.clip,
      widget.mediaItem,
      edge,
      0,
      widget.duration,
      widget.width,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _logTrim(
        'start edge=${edge.name} clip=${widget.clip.id} '
        'timelineStart=${widget.clip.timelineStart.inMilliseconds}ms '
        'duration=${widget.clip.duration.inMilliseconds}ms',
      );
      widget.onClipSelected?.call(
        widget.clip.timelineGroupId,
        clipId: widget.clip.id,
      );
      _logTrim(
        'start-preview edge=${edge.name} clip=${widget.clip.id} '
        'sourceStart=${next.sourceStart.inMilliseconds}ms '
        'sourceDuration=${next.sourceDuration.inMilliseconds}ms '
        'timelinePosition=${next.previewTimelinePosition.inMilliseconds}ms',
      );
      _previewTrim(next);
    });
  }

  void _updateTrim(double delta) {
    _logTrim('update clip=${widget.clip.id} delta=${delta.toStringAsFixed(2)}');
    setState(() {
      _trimDelta += delta;
    });
    final next = _currentTrimResult();
    if (next != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _logTrim(
          'update-preview clip=${widget.clip.id} '
          'trimDelta=${_trimDelta.toStringAsFixed(2)} '
          'sourceStart=${next.sourceStart.inMilliseconds}ms '
          'sourceDuration=${next.sourceDuration.inMilliseconds}ms '
          'timelinePosition=${next.previewTimelinePosition.inMilliseconds}ms',
        );
        _previewTrim(next);
      });
    }
  }

  void _scheduleClipTrimCanceled({bool requireMounted = true}) {
    final onClipTrimCanceled = widget.onClipTrimCanceled;
    if (onClipTrimCanceled == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (requireMounted && !mounted) {
        return;
      }
      onClipTrimCanceled();
    });
  }

  void _cancelTrim() {
    _logTrim('cancel clip=${widget.clip.id}');
    setState(() {
      _trimming = false;
      _trimEdge = null;
      _trimDelta = 0;
      _trimBaseClip = null;
    });
    _scheduleClipTrimCanceled();
  }

  void _finishTrim() {
    final next = _currentTrimResult();
    _logTrim(
      'finish clip=${widget.clip.id} '
      'trimDelta=${_trimDelta.toStringAsFixed(2)} '
      'hasResult=${next != null}',
    );
    setState(() {
      _trimming = false;
      _trimEdge = null;
      _trimDelta = 0;
      _trimBaseClip = null;
    });
    if (next == null) {
      _scheduleClipTrimCanceled();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.onClipTrimmed?.call(
        widget.clip.id,
        sourceStart: next.sourceStart,
        sourceDuration: next.sourceDuration,
        previewTimelinePosition: next.previewTimelinePosition,
      );
    });
  }

  void _logTrim(String message) {
    final line = '[trim] $message';
    if (EditorDebugLog.enabled) {
      debugPrint(line);
    }
    EditorDebugLog.write('timeline', line);
  }

  _ClipTrimResult? _currentTrimResult() {
    final edge = _trimEdge;
    final baseClip = _trimBaseClip;
    if (edge == null || baseClip == null) {
      return null;
    }
    return _trimForDragDelta(
      baseClip,
      widget.mediaItem,
      edge,
      _trimDelta,
      widget.duration,
      widget.width,
    );
  }

  void _previewTrim(_ClipTrimResult next) {
    _logTrim(
      'local-preview clip=${widget.clip.id} '
      'sourceStart=${next.sourceStart.inMilliseconds}ms '
      'sourceDuration=${next.sourceDuration.inMilliseconds}ms '
      'timelinePosition=${next.previewTimelinePosition.inMilliseconds}ms',
    );
  }

  void _startResize(_ClipResizeEdge edge) {
    widget.onClipSelected?.call(
      widget.clip.timelineGroupId,
      clipId: widget.clip.id,
    );
    setState(() {
      _dragging = false;
      _dragDelta = 0;
      _resizing = true;
      _resizeEdge = edge;
      _resizeDelta = 0;
    });
  }

  void _updateResize(DragUpdateDetails details) {
    setState(() {
      _resizeDelta += details.primaryDelta ?? 0;
    });
  }

  void _cancelResize() {
    setState(() {
      _resizing = false;
      _resizeEdge = null;
      _resizeDelta = 0;
    });
  }

  void _finishResize() {
    final edge = _resizeEdge;
    if (edge == null) {
      _cancelResize();
      return;
    }
    final next = _resizeForDragDelta(
      widget.clip,
      edge,
      _resizeDelta,
      widget.duration,
      widget.width,
      snapCandidates: _snapCandidatesForTimeline(
        tracks: widget.tracks,
        markers: widget.markers,
        playheadPosition: widget.playheadPosition,
        timelineDuration: widget.duration,
        ignoredTimelineGroupId: widget.clip.timelineGroupId,
      ),
    );
    setState(() {
      _resizing = false;
      _resizeEdge = null;
      _resizeDelta = 0;
    });
    widget.onClipResized?.call(
      widget.clip.id,
      next.timelineStart,
      next.duration,
    );
  }
}
