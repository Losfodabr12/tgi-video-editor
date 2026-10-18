import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../../../app/theme/decorations.dart';
import '../../../../domain/models/audio_waveform.dart';
import '../../../../domain/models/clip.dart' as domain;
import '../../../../domain/models/media_item.dart';
import '../../../../domain/models/timeline_marker.dart';
import '../../../../domain/models/timeline_transition.dart';
import '../../../../domain/models/project.dart';
import '../../../../domain/models/track.dart';
import '../../../../services/editor_debug_log.dart';
import '../duration_formatter.dart';
import 'timeline_zoom_controls.dart';

part 'timeline_content.dart';
part 'timeline_tracks.dart';
part 'timeline_guides.dart';
part 'timeline_lanes.dart';
part 'timeline_clip_widgets.dart';
part 'timeline_index.dart';

const _trackHeaderWidth = 190.0;
const _timelineHeaderHeight = 44.0;
const _rulerHeight = 34.0;
const _trackHeight = 64.0;
const _minimumTimelineDuration = Duration(seconds: 30);
const _minimumClipResizeDuration = Duration(seconds: 1);
const _pixelsPerSecond = 76.0;
const _minimumTimelineContentWidth = 1280.0;
const _minimumTimelineZoom = 0.5;
const _maximumTimelineZoom = 4.0;
const _timelineZoomStep = 0.25;
const _timelineSnapThresholdPx = 12.0;
const _timelineAutoScrollEdgeThreshold = 50.0;
const _timelineAutoScrollMaxStep = 18.0;
const _timelineAutoScrollInterval = Duration(milliseconds: 16);
const _maxClipVolume = 2.0;
const _audioVolumeLineHitRadius = 20.0;
const _clipDragStartThreshold = 4.0;
const _clipTrimHandleWidth = 12.0;
const _minimumTimelineClipWidth = 1.0;
const _minimumClipTrimTimelineDuration = Duration(milliseconds: 100);
const _timelineDropBackground = TgiColors.surfacePressed;
const _timelineTransitionDropBackground = TgiColors.surfacePressed;

Color _trackAccentFor(TrackType type) {
  switch (type) {
    case TrackType.video:
      return TgiColors.accent;
    case TrackType.audio:
      return TgiColors.accentGreen;
    case TrackType.image:
      return TgiColors.accent;
    case TrackType.text:
      return TgiColors.accentRose;
  }
}

Color _timelineLaneFillFor(int index, Track track) {
  final base = index.isEven
      ? TgiColors.timelineLane
      : TgiColors.timelineLaneAlt;
  final accent = _trackAccentFor(track.type);
  if (track.isHidden) {
    return Color.lerp(
      base,
      TgiColors.surfaceAlt,
      0.42,
    )!.withValues(alpha: 0.58);
  }
  if (track.isLocked) {
    return Color.lerp(
      Color.lerp(base, accent, 0.05),
      TgiColors.surfaceRaised,
      0.18,
    )!;
  }
  return Color.lerp(base, accent, index.isEven ? 0.035 : 0.055)!;
}

Color _clipAccentFor(TrackType type) {
  switch (type) {
    case TrackType.video:
      return TgiColors.accent;
    case TrackType.audio:
      return TgiColors.accentGreen;
    case TrackType.image:
      return TgiColors.accent;
    case TrackType.text:
      return TgiColors.accentRose;
  }
}

Color _clipFillFor(TrackType type) {
  switch (type) {
    case TrackType.video:
      return TgiColors.surfacePressed;
    case TrackType.audio:
      return TgiColors.surfacePressed;
    case TrackType.image:
      return TgiColors.surfacePressed;
    case TrackType.text:
      return TgiColors.surfacePressed;
  }
}

typedef TimelineMediaDropCallback =
    void Function(
      MediaItem item,
      Duration timelineStart, {
      String? targetTrackId,
      bool forceNewVideoTrack,
      bool forceNewAudioTrack,
    });

typedef TimelineClipTrackMoveCallback =
    void Function(String clipId, String targetTrackId, Duration timelineStart);

typedef TimelineClipNewTrackMoveCallback =
    void Function(String clipId, Duration timelineStart);

typedef TimelineClipFadeCallback =
    void Function(
      String clipId, {
      required Duration fadeIn,
      required Duration fadeOut,
    });

typedef TimelineClipTrimCallback =
    void Function(
      String clipId, {
      required Duration sourceStart,
      required Duration sourceDuration,
      required Duration previewTimelinePosition,
    });

typedef ImageClipTrackMoveCallback = TimelineClipTrackMoveCallback;

typedef TimelineDragHoverCallback = void Function(Offset? globalPosition);

typedef _TimelineTrackDropTargetAtOffset =
    _TimelineTrackDropTarget Function(
      Offset globalPosition,
      TrackType trackType,
    );

typedef TimelineClipSelectionCallback =
    void Function(String timelineGroupId, {bool additive, bool toggle});

typedef TimelineBoxSelectionCallback =
    void Function(
      Set<String> timelineGroupIds, {
      bool additive,
      bool toggle,
      bool intersect,
    });

typedef TimelineTransitionDropCallback =
    void Function(TimelineTransitionAsset asset, Duration timelinePosition);

typedef TimelineTransitionMoveCallback =
    void Function(String transitionId, Duration timelinePosition);

typedef TimelineClipDeltaCallback =
    void Function(String clipId, Duration delta);

enum TimelineEditMode { move, slip, slide }

enum _TimelineTextMenuAction { addText, addQuickCaption, addTextTrack }

class _TimelineTrackDropTarget {
  const _TimelineTrackDropTarget({this.trackId, this.isBelowTracks = false});

  final String? trackId;
  final bool isBelowTracks;
}

class _TimelineMediaDropZone {
  const _TimelineMediaDropZone({this.track, this.isEmptyLaneArea = false});

  final Track? track;
  final bool isEmptyLaneArea;
}

class TimelinePanel extends StatefulWidget {
  const TimelinePanel({
    required this.project,
    required this.playheadPosition,
    this.audioWaveforms = const {},
    required this.onMediaDropped,
    required this.onClipMoved,
    required this.onPlayheadChanged,
    this.onClipResized,
    this.cutMode = false,
    this.rangeStart,
    this.rangeEnd,
    this.onMarkRangeStart,
    this.onMarkRangeEnd,
    this.onClearRange,
    this.selectedTimelineGroupId,
    this.selectedTimelineGroupIds = const {},
    this.onClipCut,
    this.onClipSelected,
    this.onBoxSelection,
    this.onTextClipEdit,
    this.onTextInsertRequested,
    this.onQuickCaptionInsertRequested,
    this.onClipVolumeChanged,
    this.onClipFadeChanged,
    this.onClipTrimPreview,
    this.onClipTrimmed,
    this.onClipTrimCanceled,
    this.onClipMovedToTrack,
    this.onClipMovedToNewTrack,
    this.onImageClipMovedToTrack,
    this.onAddTrack,
    this.onAudioInventoryOpen,
    this.onTrackRenamed,
    this.onTrackLockedChanged,
    this.onTrackHiddenChanged,
    this.onTrackMutedChanged,
    this.onTrackSoloChanged,
    this.onMarkerAdd,
    this.onMarkerRenamed,
    this.onMarkerDeleted,
    this.onTransitionDropped,
    this.onTransitionMoved,
    this.onTransitionEdit,
    this.onTransitionDeleted,
    this.onRippleDelete,
    this.audioVideoLinked = false,
    this.onAudioVideoLinkToggle,
    this.onClipSlipped,
    this.onClipSlid,
    super.key,
  });

  final TgiProject project;
  final Duration playheadPosition;
  final Map<String, AudioWaveform> audioWaveforms;
  final TimelineMediaDropCallback onMediaDropped;
  final void Function(String timelineGroupId, Duration timelineStart)
  onClipMoved;
  final void Function(String clipId, Duration timelineStart, Duration duration)?
  onClipResized;
  final ValueChanged<Duration> onPlayheadChanged;
  final bool cutMode;
  final Duration? rangeStart;
  final Duration? rangeEnd;
  final VoidCallback? onMarkRangeStart, onMarkRangeEnd, onClearRange;
  final String? selectedTimelineGroupId;
  final Set<String> selectedTimelineGroupIds;
  final void Function(String clipId, Duration timelinePosition)? onClipCut;
  final TimelineClipSelectionCallback? onClipSelected;
  final TimelineBoxSelectionCallback? onBoxSelection;
  final void Function(domain.Clip clip)? onTextClipEdit;
  final ValueChanged<Duration>? onTextInsertRequested;
  final ValueChanged<Duration>? onQuickCaptionInsertRequested;
  final void Function(String clipId, double volume)? onClipVolumeChanged;
  final TimelineClipFadeCallback? onClipFadeChanged;
  final TimelineClipTrimCallback? onClipTrimPreview;
  final TimelineClipTrimCallback? onClipTrimmed;
  final VoidCallback? onClipTrimCanceled;
  final TimelineClipTrackMoveCallback? onClipMovedToTrack;
  final TimelineClipNewTrackMoveCallback? onClipMovedToNewTrack;
  final ImageClipTrackMoveCallback? onImageClipMovedToTrack;
  final ValueChanged<TrackType>? onAddTrack;
  final VoidCallback? onAudioInventoryOpen;
  final void Function(String trackId, String name)? onTrackRenamed;
  final void Function(String trackId, bool isLocked)? onTrackLockedChanged;
  final void Function(String trackId, bool isHidden)? onTrackHiddenChanged;
  final void Function(String trackId, bool isMuted)? onTrackMutedChanged;
  final void Function(String trackId, bool isSolo)? onTrackSoloChanged;
  final VoidCallback? onMarkerAdd;
  final void Function(String markerId, String name)? onMarkerRenamed;
  final ValueChanged<String>? onMarkerDeleted;
  final TimelineTransitionDropCallback? onTransitionDropped;
  final TimelineTransitionMoveCallback? onTransitionMoved;
  final ValueChanged<TimelineTransition>? onTransitionEdit;
  final ValueChanged<String>? onTransitionDeleted;
  final VoidCallback? onRippleDelete;
  final bool audioVideoLinked;
  final VoidCallback? onAudioVideoLinkToggle;
  final TimelineClipDeltaCallback? onClipSlipped;
  final TimelineClipDeltaCallback? onClipSlid;

  @override
  State<TimelinePanel> createState() => _TimelinePanelState();
}

class _TimelinePanelState extends State<TimelinePanel> {
  final _timelineContentKey = GlobalKey();
  final _timelineLanesViewportKey = GlobalKey();
  final _horizontalScrollController = ScrollController();
  final _trackLabelScrollController = ScrollController();
  final _timelineLaneScrollController = ScrollController();
  Timer? _timelineAutoScrollTimer;
  double _timelineAutoScrollStep = 0;
  bool _syncingVerticalScroll = false;
  double _timelineZoom = 1.0;
  bool _snappingEnabled = true;
  TimelineEditMode _editMode = TimelineEditMode.move;
  double? _pendingHorizontalScrollFraction;
  late String _timelineStructureSignature;
  int _timelineRenderRevision = 0;

  @override
  void initState() {
    super.initState();
    _timelineStructureSignature = _timelineSignatureFor(widget.project);
    _trackLabelScrollController.addListener(_syncTrackLabelsFromLabels);
    _timelineLaneScrollController.addListener(_syncTrackLabelsFromLanes);
  }

  @override
  void didUpdateWidget(covariant TimelinePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextSignature = _timelineSignatureFor(widget.project);
    if (nextSignature != _timelineStructureSignature) {
      _timelineStructureSignature = nextSignature;
      _timelineRenderRevision++;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _syncLaneScrollToTrackLabels();
        setState(() {});
      });
    }
    if (oldWidget.playheadPosition != widget.playheadPosition) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _keepPlayheadVisible();
        }
      });
    }
  }

  @override
  void dispose() {
    _stopTimelineAutoScroll();
    _trackLabelScrollController.removeListener(_syncTrackLabelsFromLabels);
    _timelineLaneScrollController.removeListener(_syncTrackLabelsFromLanes);
    _horizontalScrollController.dispose();
    _trackLabelScrollController.dispose();
    _timelineLaneScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = _timelineExtent(widget.project);
    final activeGroupId = widget.project
        .clipAt(widget.playheadPosition, trackType: TrackType.video)
        ?.timelineGroupId;

    return DragTarget<MediaItem>(
      hitTestBehavior: HitTestBehavior.translucent,
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) {
        _handleMediaDrop(details.data, details.offset, duration);
      },
      builder: (context, candidateData, rejectedData) {
        return Column(
          children: [
            SizedBox(
              height: _timelineHeaderHeight,
              child: _TimelineHeader(
                zoom: _timelineZoom,
                playheadPosition: widget.playheadPosition,
                duration: duration,
                onAudioInventoryOpen: widget.onAudioInventoryOpen,
                onMarkerAdd: widget.onMarkerAdd,
                onZoomOut: _timelineZoom > _minimumTimelineZoom
                    ? () => _setTimelineZoom(_timelineZoom - _timelineZoomStep)
                    : null,
                onZoomIn: _timelineZoom < _maximumTimelineZoom
                    ? () => _setTimelineZoom(_timelineZoom + _timelineZoomStep)
                    : null,
                editMode: _editMode,
                snappingEnabled: _snappingEnabled,
                selectedCount: widget.selectedTimelineGroupIds.isNotEmpty
                    ? widget.selectedTimelineGroupIds.length
                    : (widget.selectedTimelineGroupId == null ? 0 : 1),
                canRippleDelete:
                    widget.selectedTimelineGroupId != null ||
                    widget.selectedTimelineGroupIds.isNotEmpty,
                audioVideoLinked: widget.audioVideoLinked,
                onAudioVideoLinkToggle: widget.onAudioVideoLinkToggle,
                onEditModeChanged: (mode) => setState(() => _editMode = mode),
                onSnappingChanged: () =>
                    setState(() => _snappingEnabled = !_snappingEnabled),
                onFocusSelection: _focusSelectedClips,
                onRippleDelete: widget.onRippleDelete,
              ),
            ),
            if (widget.onMarkRangeStart != null)
              SizedBox(
                height: 32,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: widget.onMarkRangeStart,
                        child: const Text('I · Marcar início'),
                      ),
                      TextButton(
                        onPressed: widget.onMarkRangeEnd,
                        child: const Text('O · Marcar fim'),
                      ),
                      Text(
                        widget.rangeStart == null && widget.rangeEnd == null
                            ? 'Exportação: timeline inteira'
                            : 'Trecho: ${formatDuration(widget.rangeStart ?? Duration.zero)} — ${formatDuration(widget.rangeEnd ?? widget.project.timelineDuration)}',
                      ),
                      if (widget.rangeStart != null || widget.rangeEnd != null)
                        IconButton(
                          tooltip: 'Limpar trecho',
                          onPressed: widget.onClearRange,
                          icon: const Icon(Icons.close, size: 16),
                        ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TrackLabels(
                    tracks: widget.project.tracks,
                    scrollController: _trackLabelScrollController,
                    onAddTrack: widget.onAddTrack,
                    onTrackRenamed: widget.onTrackRenamed,
                    onTrackLockedChanged: widget.onTrackLockedChanged,
                    onTrackHiddenChanged: widget.onTrackHiddenChanged,
                    onTrackMutedChanged: widget.onTrackMutedChanged,
                    onTrackSoloChanged: widget.onTrackSoloChanged,
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: DragTarget<TimelineTransition>(
                      hitTestBehavior: HitTestBehavior.opaque,
                      onWillAcceptWithDetails: (_) =>
                          widget.onTransitionMoved != null,
                      onAcceptWithDetails: (details) {
                        _handleTimelineTransitionMove(
                          details.data,
                          details.offset,
                          duration,
                        );
                      },
                      builder: (context, movedTransitionCandidateData, rejectedData) {
                        return DragTarget<TimelineTransitionAsset>(
                          hitTestBehavior: HitTestBehavior.opaque,
                          onWillAcceptWithDetails: (_) =>
                              widget.onTransitionDropped != null,
                          onAcceptWithDetails: (details) {
                            _handleTransitionDrop(
                              details.data,
                              details.offset,
                              duration,
                            );
                          },
                          builder: (context, transitionCandidateData, rejectedData) {
                            return DragTarget<MediaItem>(
                              hitTestBehavior: HitTestBehavior.opaque,
                              onWillAcceptWithDetails: (_) => true,
                              onAcceptWithDetails: (details) {
                                _handleMediaDrop(
                                  details.data,
                                  details.offset,
                                  duration,
                                );
                              },
                              builder: (context, mediaCandidateData, rejectedData) {
                                final accepting =
                                    mediaCandidateData.isNotEmpty ||
                                    transitionCandidateData.isNotEmpty ||
                                    movedTransitionCandidateData.isNotEmpty;
                                final acceptingTransition =
                                    transitionCandidateData.isNotEmpty ||
                                    movedTransitionCandidateData.isNotEmpty;
                                return LayoutBuilder(
                                  builder: (context, constraints) {
                                    final contentWidth = _timelineContentWidth(
                                      duration,
                                      constraints.maxWidth,
                                      zoom: _timelineZoom,
                                    );

                                    return AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 120,
                                      ),
                                      decoration: BoxDecoration(
                                        color: acceptingTransition
                                            ? _timelineTransitionDropBackground
                                            : accepting
                                            ? _timelineDropBackground
                                            : TgiColors.surface,
                                      ),
                                      child: Scrollbar(
                                        controller: _horizontalScrollController,
                                        thumbVisibility:
                                            contentWidth > constraints.maxWidth,
                                        child: SingleChildScrollView(
                                          key: const ValueKey(
                                            'timeline-horizontal-scroll',
                                          ),
                                          controller:
                                              _horizontalScrollController,
                                          scrollDirection: Axis.horizontal,
                                          child: SizedBox(
                                            key: _timelineContentKey,
                                            width: contentWidth,
                                            child: GestureDetector(
                                              behavior:
                                                  HitTestBehavior.translucent,
                                              onSecondaryTapDown:
                                                  widget.onTextInsertRequested ==
                                                          null &&
                                                      widget.onQuickCaptionInsertRequested ==
                                                          null
                                                  ? null
                                                  : (
                                                      details,
                                                    ) => _showTextContextMenu(
                                                      details.globalPosition,
                                                      _positionFromDx(
                                                        details
                                                            .localPosition
                                                            .dx,
                                                        duration,
                                                        contentWidth,
                                                      ),
                                                    ),
                                              child: _TimelineContent(
                                                key: ValueKey(
                                                  'timeline_content_$_timelineRenderRevision',
                                                ),
                                                project: widget.project,
                                                horizontalScrollController:
                                                    _horizontalScrollController,
                                                viewportWidth:
                                                    constraints.maxWidth,
                                                audioWaveforms:
                                                    widget.audioWaveforms,
                                                duration: duration,
                                                contentWidth: contentWidth,
                                                accepting: accepting,
                                                playheadPosition:
                                                    widget.playheadPosition,
                                                activeTimelineGroupId:
                                                    activeGroupId,
                                                selectedTimelineGroupId: widget
                                                    .selectedTimelineGroupId,
                                                selectedTimelineGroupIds: widget
                                                    .selectedTimelineGroupIds,
                                                cutMode: widget.cutMode,
                                                editMode: _editMode,
                                                snappingEnabled:
                                                    _snappingEnabled,
                                                onClipMoved: widget.onClipMoved,
                                                onClipResized:
                                                    widget.onClipResized,
                                                onClipCut: widget.onClipCut,
                                                onClipSelected:
                                                    widget.onClipSelected,
                                                onBoxSelection:
                                                    widget.onBoxSelection,
                                                onTextClipEdit:
                                                    widget.onTextClipEdit,
                                                onPlayheadChanged:
                                                    widget.onPlayheadChanged,
                                                onRulerPan: _panTimelineBy,
                                                onClipVolumeChanged:
                                                    widget.onClipVolumeChanged,
                                                onClipFadeChanged:
                                                    widget.onClipFadeChanged,
                                                onClipTrimPreview:
                                                    widget.onClipTrimPreview,
                                                onClipTrimmed:
                                                    widget.onClipTrimmed,
                                                onClipTrimCanceled:
                                                    widget.onClipTrimCanceled,
                                                onMediaDropped:
                                                    widget.onMediaDropped,
                                                onClipMovedToTrack:
                                                    widget.onClipMovedToTrack ??
                                                    widget
                                                        .onImageClipMovedToTrack,
                                                onClipMovedToNewTrack: widget
                                                    .onClipMovedToNewTrack,
                                                onClipSlipped:
                                                    widget.onClipSlipped,
                                                onClipSlid: widget.onClipSlid,
                                                verticalScrollController:
                                                    _timelineLaneScrollController,
                                                lanesViewportKey:
                                                    _timelineLanesViewportKey,
                                                onClipDragHover:
                                                    _handleClipDragHover,
                                                onMarkerRenamed:
                                                    widget.onMarkerRenamed,
                                                onMarkerDeleted:
                                                    widget.onMarkerDeleted,
                                                onTransitionMoved:
                                                    widget.onTransitionMoved,
                                                onTransitionEdit:
                                                    widget.onTransitionEdit,
                                                onTransitionDeleted:
                                                    widget.onTransitionDeleted,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showTextContextMenu(
    Offset globalPosition,
    Duration timelinePosition,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) return;
    final action = await showMenu<_TimelineTextMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        if (widget.onTextInsertRequested != null)
          const PopupMenuItem(
            value: _TimelineTextMenuAction.addText,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.title),
              title: Text('Adicionar texto aqui'),
            ),
          ),
        if (widget.onQuickCaptionInsertRequested != null)
          const PopupMenuItem(
            value: _TimelineTextMenuAction.addQuickCaption,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.add_comment_outlined),
              title: Text('Adicionar legenda aqui'),
            ),
          ),
        if (widget.onAddTrack != null)
          const PopupMenuItem(
            value: _TimelineTextMenuAction.addTextTrack,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.playlist_add),
              title: Text('Nova trilha de texto'),
            ),
          ),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _TimelineTextMenuAction.addText:
        widget.onTextInsertRequested?.call(timelinePosition);
        break;
      case _TimelineTextMenuAction.addQuickCaption:
        widget.onQuickCaptionInsertRequested?.call(timelinePosition);
        break;
      case _TimelineTextMenuAction.addTextTrack:
        widget.onAddTrack?.call(TrackType.text);
        break;
    }
  }

  void _handleMediaDrop(
    MediaItem item,
    Offset globalOffset,
    Duration duration,
  ) {
    final dropZone = _mediaDropZoneFromDrop(globalOffset);
    final content = _timelineContentKey.currentContext?.findRenderObject();
    final timelineStart = _snapMediaDropPosition(
      item: item,
      project: widget.project,
      targetTrack: dropZone.track,
      proposedStart: _positionFromDrop(globalOffset, duration, snap: false),
      playheadPosition: widget.playheadPosition,
      duration: duration,
      width: content is RenderBox ? content.size.width : 0,
      enabled: _snappingEnabled,
    );
    widget.onMediaDropped(
      item,
      timelineStart,
      targetTrackId: dropZone.track?.id,
      forceNewVideoTrack: _shouldCreateVideoTrackForDroppedMedia(
        item,
        widget.project,
        dropZone.track,
        timelineStart,
        isEmptyLaneArea: dropZone.isEmptyLaneArea,
      ),
      forceNewAudioTrack: _shouldCreateAudioTrackForMediaDrop(item, dropZone),
    );
  }

  void _handleTransitionDrop(
    TimelineTransitionAsset asset,
    Offset globalOffset,
    Duration duration,
  ) {
    final callback = widget.onTransitionDropped;
    if (callback == null) {
      return;
    }
    callback(asset, _positionFromDrop(globalOffset, duration, snap: false));
  }

  void _handleTimelineTransitionMove(
    TimelineTransition transition,
    Offset globalOffset,
    Duration duration,
  ) {
    final callback = widget.onTransitionMoved;
    if (callback == null) {
      return;
    }
    callback(
      transition.id,
      _positionFromDrop(globalOffset, duration, snap: false),
    );
  }

  Duration _positionFromDrop(
    Offset globalOffset,
    Duration duration, {
    bool snap = true,
  }) {
    final context = _timelineContentKey.currentContext;
    if (context == null) {
      return Duration.zero;
    }

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || renderObject.size.width <= 0) {
      return Duration.zero;
    }

    final localOffset = renderObject.globalToLocal(globalOffset);
    final position = _positionFromDx(
      localOffset.dx,
      duration,
      renderObject.size.width,
    );
    if (!snap || !_snappingEnabled) {
      return position;
    }
    return _snapPosition(
      position,
      _snapCandidatesForTimeline(
        tracks: widget.project.tracks,
        markers: widget.project.markers,
        playheadPosition: widget.playheadPosition,
        timelineDuration: duration,
      ),
      duration,
      renderObject.size.width,
    );
  }

  bool _shouldCreateAudioTrackForMediaDrop(
    MediaItem item,
    _TimelineMediaDropZone dropZone,
  ) {
    return item.type == MediaType.audio &&
        dropZone.track == null &&
        dropZone.isEmptyLaneArea;
  }

  _TimelineMediaDropZone _mediaDropZoneFromDrop(Offset globalOffset) {
    final context = _timelineContentKey.currentContext;
    if (context == null) {
      return const _TimelineMediaDropZone();
    }

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) {
      return const _TimelineMediaDropZone();
    }

    final localOffset = renderObject.globalToLocal(globalOffset);
    final trackY = localOffset.dy - _rulerHeight - 1;
    if (trackY < 0) {
      return const _TimelineMediaDropZone(isEmptyLaneArea: true);
    }

    if (widget.project.tracks.isEmpty) {
      return const _TimelineMediaDropZone(isEmptyLaneArea: true);
    }

    final scrollOffset = _timelineLaneScrollController.hasClients
        ? _timelineLaneScrollController.offset
        : 0.0;
    final absoluteTrackY = scrollOffset + trackY;
    final totalTrackHeight = widget.project.tracks.length * _trackHeight;
    if (absoluteTrackY >= totalTrackHeight) {
      return const _TimelineMediaDropZone(isEmptyLaneArea: true);
    }

    final trackIndex = (absoluteTrackY / _trackHeight).floor();
    if (trackIndex < 0 || trackIndex >= widget.project.tracks.length) {
      return const _TimelineMediaDropZone();
    }
    return _TimelineMediaDropZone(track: widget.project.tracks[trackIndex]);
  }

  void _setTimelineZoom(double value) {
    final nextZoom = value
        .clamp(_minimumTimelineZoom, _maximumTimelineZoom)
        .toDouble();
    if ((nextZoom - _timelineZoom).abs() < 0.001) {
      return;
    }

    if (_horizontalScrollController.hasClients &&
        _horizontalScrollController.position.maxScrollExtent > 0) {
      _pendingHorizontalScrollFraction =
          _horizontalScrollController.offset /
          _horizontalScrollController.position.maxScrollExtent;
    } else {
      _pendingHorizontalScrollFraction = 0;
    }

    setState(() {
      _timelineZoom = nextZoom;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreHorizontalScrollFraction();
    });
  }

  void _restoreHorizontalScrollFraction() {
    final fraction = _pendingHorizontalScrollFraction;
    _pendingHorizontalScrollFraction = null;
    if (fraction == null || !_horizontalScrollController.hasClients) {
      return;
    }

    final max = _horizontalScrollController.position.maxScrollExtent;
    if (max <= 0) {
      return;
    }
    _horizontalScrollController.jumpTo((max * fraction).clamp(0.0, max));
  }

  void _panTimelineBy(double delta) {
    if (!_horizontalScrollController.hasClients || delta.abs() < 0.01) {
      return;
    }
    final position = _horizontalScrollController.position;
    final next = (position.pixels + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((next - position.pixels).abs() < 0.01) {
      return;
    }
    _horizontalScrollController.jumpTo(next);
  }

  void _keepPlayheadVisible() {
    if (!_horizontalScrollController.hasClients) {
      return;
    }
    final content = _timelineContentKey.currentContext?.findRenderObject();
    if (content is! RenderBox || content.size.width <= 0) {
      return;
    }
    final timelineDuration = _timelineExtent(widget.project);
    if (timelineDuration <= Duration.zero) {
      return;
    }

    final position = _horizontalScrollController.position;
    final viewportWidth = position.viewportDimension;
    if (viewportWidth <= 0 || position.maxScrollExtent <= 0) {
      return;
    }
    final fraction =
        widget.playheadPosition.inMicroseconds /
        timelineDuration.inMicroseconds;
    final playheadX = content.size.width * fraction.clamp(0.0, 1.0);
    final leftEdge = position.pixels + viewportWidth * 0.12;
    final rightEdge = position.pixels + viewportWidth * 0.78;
    if (playheadX >= leftEdge && playheadX <= rightEdge) {
      return;
    }

    final target = playheadX < leftEdge
        ? playheadX - viewportWidth * 0.12
        : playheadX - viewportWidth * 0.72;
    final next = target
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((next - position.pixels).abs() < 0.5) {
      return;
    }
    _horizontalScrollController.jumpTo(next);
  }

  void _focusSelectedClips() {
    final selectedIds = <String>{
      ...widget.selectedTimelineGroupIds,
      if (widget.selectedTimelineGroupId != null)
        widget.selectedTimelineGroupId!,
    };
    if (selectedIds.isEmpty || !_horizontalScrollController.hasClients) {
      return;
    }
    final clips = widget.project.tracks
        .expand((track) => track.clips)
        .where((clip) => selectedIds.contains(clip.timelineGroupId))
        .toList();
    if (clips.isEmpty) return;

    var start = clips.first.timelineStart;
    var end = clips.first.timelineEnd;
    for (final clip in clips.skip(1)) {
      if (clip.timelineStart < start) start = clip.timelineStart;
      if (clip.timelineEnd > end) end = clip.timelineEnd;
    }
    final extent = _timelineExtent(widget.project);
    final viewport = _horizontalScrollController.position.viewportDimension;
    final spanSeconds = math.max(0.5, (end - start).inMilliseconds / 1000);
    final desiredContentWidth =
        viewport * 0.72 * (extent.inMilliseconds / 1000) / spanSeconds;
    final baseDurationWidth = math.max(1, extent.inSeconds) * _pixelsPerSecond;
    final nextZoom = (desiredContentWidth / baseDurationWidth)
        .clamp(_minimumTimelineZoom, _maximumTimelineZoom)
        .toDouble();
    setState(() => _timelineZoom = nextZoom);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_horizontalScrollController.hasClients) return;
      final content = _timelineContentKey.currentContext?.findRenderObject();
      if (content is! RenderBox || content.size.width <= 0) return;
      final center = Duration(
        microseconds: ((start.inMicroseconds + end.inMicroseconds) / 2).round(),
      );
      final centerFraction =
          center.inMicroseconds / math.max(1, extent.inMicroseconds);
      final position = _horizontalScrollController.position;
      final target =
          content.size.width * centerFraction - position.viewportDimension / 2;
      _horizontalScrollController.animateTo(
        target
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble(),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  void _syncTrackLabelsFromLabels() {
    _syncVerticalScroll(
      source: _trackLabelScrollController,
      target: _timelineLaneScrollController,
    );
  }

  void _syncTrackLabelsFromLanes() {
    _syncVerticalScroll(
      source: _timelineLaneScrollController,
      target: _trackLabelScrollController,
    );
  }

  void _syncVerticalScroll({
    required ScrollController source,
    required ScrollController target,
  }) {
    if (_syncingVerticalScroll || !source.hasClients || !target.hasClients) {
      return;
    }
    final next = source.offset.clamp(
      target.position.minScrollExtent,
      target.position.maxScrollExtent,
    );
    if ((target.offset - next).abs() < 0.5) {
      return;
    }

    _syncingVerticalScroll = true;
    target.jumpTo(next);
    _syncingVerticalScroll = false;
  }

  void _syncLaneScrollToTrackLabels() {
    if (!_trackLabelScrollController.hasClients ||
        !_timelineLaneScrollController.hasClients) {
      return;
    }
    final max = _timelineLaneScrollController.position.maxScrollExtent;
    final next = _trackLabelScrollController.offset.clamp(0.0, max).toDouble();
    if ((_timelineLaneScrollController.offset - next).abs() < 0.5) {
      return;
    }
    _timelineLaneScrollController.jumpTo(next);
  }

  void _handleClipDragHover(Offset? globalPosition) {
    if (globalPosition == null) {
      _stopTimelineAutoScroll();
      return;
    }

    final context = _timelineLanesViewportKey.currentContext;
    final renderObject = context?.findRenderObject();
    if (renderObject is! RenderBox || renderObject.size.height <= 0) {
      _stopTimelineAutoScroll();
      return;
    }

    final localY = renderObject.globalToLocal(globalPosition).dy;
    final height = renderObject.size.height;
    if (localY < _timelineAutoScrollEdgeThreshold) {
      final strength =
          ((_timelineAutoScrollEdgeThreshold - localY) /
                  _timelineAutoScrollEdgeThreshold)
              .clamp(0.0, 1.0);
      _startTimelineAutoScroll(-_timelineAutoScrollMaxStep * strength);
      return;
    }
    if (localY > height - _timelineAutoScrollEdgeThreshold) {
      final strength =
          ((localY - (height - _timelineAutoScrollEdgeThreshold)) /
                  _timelineAutoScrollEdgeThreshold)
              .clamp(0.0, 1.0);
      _startTimelineAutoScroll(_timelineAutoScrollMaxStep * strength);
      return;
    }

    _stopTimelineAutoScroll();
  }

  void _startTimelineAutoScroll(double step) {
    _timelineAutoScrollStep = step;
    _timelineAutoScrollTimer ??= Timer.periodic(
      _timelineAutoScrollInterval,
      (_) => _tickTimelineAutoScroll(),
    );
  }

  void _tickTimelineAutoScroll() {
    if (!_timelineLaneScrollController.hasClients ||
        _timelineAutoScrollStep.abs() < 0.1) {
      return;
    }
    final position = _timelineLaneScrollController.position;
    final next =
        (_timelineLaneScrollController.offset + _timelineAutoScrollStep).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
    if ((next - _timelineLaneScrollController.offset).abs() < 0.1) {
      return;
    }
    _timelineLaneScrollController.jumpTo(next);
  }

  void _stopTimelineAutoScroll() {
    _timelineAutoScrollTimer?.cancel();
    _timelineAutoScrollTimer = null;
    _timelineAutoScrollStep = 0;
  }
}
