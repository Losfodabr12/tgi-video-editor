part of 'timeline_panel.dart';

class _TimelineContent extends StatelessWidget {
  const _TimelineContent({
    required this.project,
    required this.horizontalScrollController,
    required this.viewportWidth,
    required this.audioWaveforms,
    required this.duration,
    required this.contentWidth,
    required this.accepting,
    required this.playheadPosition,
    required this.activeTimelineGroupId,
    required this.selectedTimelineGroupId,
    required this.selectedTimelineGroupIds,
    required this.cutMode,
    required this.editMode,
    required this.snappingEnabled,
    required this.onClipMoved,
    required this.onClipResized,
    required this.onClipCut,
    required this.onClipSelected,
    required this.onBoxSelection,
    required this.onTextClipEdit,
    required this.onPlayheadChanged,
    required this.onRulerPan,
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
    required this.verticalScrollController,
    required this.lanesViewportKey,
    required this.onClipDragHover,
    required this.onMarkerRenamed,
    required this.onMarkerDeleted,
    required this.onTransitionMoved,
    required this.onTransitionEdit,
    required this.onTransitionDeleted,
    super.key,
  });

  final TgiProject project;
  final ScrollController horizontalScrollController;
  final double viewportWidth;
  final Map<String, AudioWaveform> audioWaveforms;
  final Duration duration;
  final double contentWidth;
  final bool accepting;
  final Duration playheadPosition;
  final String? activeTimelineGroupId;
  final String? selectedTimelineGroupId;
  final Set<String> selectedTimelineGroupIds;
  final bool cutMode;
  final TimelineEditMode editMode;
  final bool snappingEnabled;
  final void Function(String timelineGroupId, Duration timelineStart)
  onClipMoved;
  final void Function(String clipId, Duration timelineStart, Duration duration)?
  onClipResized;
  final void Function(String clipId, Duration timelinePosition)? onClipCut;
  final TimelineClipSelectionCallback? onClipSelected;
  final TimelineBoxSelectionCallback? onBoxSelection;
  final void Function(domain.Clip clip)? onTextClipEdit;
  final ValueChanged<Duration> onPlayheadChanged;
  final ValueChanged<double> onRulerPan;
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
  final ScrollController verticalScrollController;
  final GlobalKey lanesViewportKey;
  final TimelineDragHoverCallback onClipDragHover;
  final void Function(String markerId, String name)? onMarkerRenamed;
  final ValueChanged<String>? onMarkerDeleted;
  final TimelineTransitionMoveCallback? onTransitionMoved;
  final ValueChanged<TimelineTransition>? onTransitionEdit;
  final ValueChanged<String>? onTransitionDeleted;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: cutMode ? SystemMouseCursors.precise : MouseCursor.defer,
      child: _TimelineBoxSelectionRegion(
        project: project,
        duration: duration,
        width: contentWidth,
        verticalScrollController: verticalScrollController,
        horizontalScrollController: horizontalScrollController,
        viewportWidth: viewportWidth,
        enabled: !cutMode && onBoxSelection != null,
        onSelection: onBoxSelection,
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Column(
                children: [
                  SizedBox(
                    height: _rulerHeight,
                    child: _TimelineRulerInteraction(
                      duration: duration,
                      width: contentWidth,
                      enabled: !cutMode,
                      onPlayheadChanged: onPlayheadChanged,
                      onRulerPan: onRulerPan,
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: project.tracks.isEmpty
                        ? _EmptyTimeline(accepting: accepting)
                        : _TimelineLanes(
                            project: project,
                            horizontalScrollController:
                                horizontalScrollController,
                            viewportWidth: viewportWidth,
                            audioWaveforms: audioWaveforms,
                            duration: duration,
                            width: contentWidth,
                            scrollController: verticalScrollController,
                            viewportKey: lanesViewportKey,
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
                          ),
                  ),
                ],
              ),
            ),
            _TimelineMarkers(
              markers: project.markers,
              duration: duration,
              width: contentWidth,
              onMarkerRenamed: onMarkerRenamed,
              onMarkerDeleted: onMarkerDeleted,
              onMarkerSelected: onPlayheadChanged,
            ),
            _TimelineTransitions(
              transitions: project.transitions,
              duration: duration,
              width: contentWidth,
              onTransitionSelected: onPlayheadChanged,
              onTransitionMoved: onTransitionMoved,
              onTransitionEdit: onTransitionEdit,
              onTransitionDeleted: onTransitionDeleted,
            ),
            _TimelinePlayhead(
              position: playheadPosition,
              duration: duration,
              width: contentWidth,
              enabled: !cutMode,
              onChanged: onPlayheadChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineBoxSelectionRegion extends StatefulWidget {
  const _TimelineBoxSelectionRegion({
    required this.project,
    required this.duration,
    required this.width,
    required this.verticalScrollController,
    required this.horizontalScrollController,
    required this.viewportWidth,
    required this.enabled,
    required this.onSelection,
    required this.child,
  });

  final TgiProject project;
  final Duration duration;
  final double width;
  final ScrollController verticalScrollController;
  final ScrollController horizontalScrollController;
  final double viewportWidth;
  final bool enabled;
  final TimelineBoxSelectionCallback? onSelection;
  final Widget child;

  @override
  State<_TimelineBoxSelectionRegion> createState() =>
      _TimelineBoxSelectionRegionState();
}

class _TimelineBoxSelectionRegionState
    extends State<_TimelineBoxSelectionRegion> {
  static const _timelineTracksTop = _rulerHeight + 1;

  Offset? _selectionStart;
  Offset? _selectionCurrent;
  int? _selectionPointer;
  bool _selectionDragging = false;
  bool _selectionAdditive = false;
  bool _selectionToggle = false;
  bool _selectionIntersect = false;
  Offset? _lastPointerPosition;
  Timer? _selectionScrollTimer;

  @override
  void dispose() {
    _selectionScrollTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _TimelineBoxSelectionRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _selectionPointer != null) {
      _clearSelectionDrag();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _TimelineBoxSelectionPainter(
                  rect: _selectionRect,
                  visible: _selectionDragging,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Rect? get _selectionRect {
    final start = _selectionStart;
    final current = _selectionCurrent;
    if (start == null || current == null) {
      return null;
    }
    // Anchors live in content coordinates, so scrolling must not move the
    // selection's original anchor to a different clip/track.
    return Rect.fromPoints(
      start,
      current,
    ).shift(Offset(0, -_verticalScrollOffset));
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.enabled ||
        _selectionPointer != null ||
        event.kind == PointerDeviceKind.touch ||
        (event.buttons & kPrimaryMouseButton) == 0) {
      return;
    }

    final local = _localPosition(event.position);
    if (!_canStartSelectionAt(local)) {
      return;
    }

    final keys = HardwareKeyboard.instance;
    _selectionPointer = event.pointer;
    _selectionStart = local;
    _selectionCurrent = local;
    _lastPointerPosition = event.position;
    _selectionDragging = false;
    _selectionToggle = keys.isControlPressed || keys.isMetaPressed;
    _selectionIntersect = keys.isAltPressed;
    _selectionAdditive = !_selectionToggle && keys.isShiftPressed;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _selectionPointer) {
      return;
    }
    if ((event.buttons & kPrimaryMouseButton) == 0) {
      _finishSelection(event.position);
      return;
    }

    final start = _selectionStart;
    if (start == null) {
      return;
    }
    final current = _localPosition(event.position);
    if (!_selectionDragging &&
        (current - start).distance < _clipDragStartThreshold) {
      return;
    }
    setState(() {
      _selectionDragging = true;
      _selectionCurrent = current;
      _lastPointerPosition = event.position;
    });
    _selectionScrollTimer ??= Timer.periodic(
      _timelineAutoScrollInterval,
      (_) => _tickSelectionAutoScroll(),
    );
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer != _selectionPointer) {
      return;
    }
    _finishSelection(event.position);
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer != _selectionPointer) {
      return;
    }
    setState(_clearSelectionDrag);
  }

  void _finishSelection(Offset globalPosition) {
    final start = _selectionStart;
    final wasDragging = _selectionDragging;
    final current = wasDragging
        ? _localPosition(globalPosition)
        : _selectionCurrent;
    final additive = _selectionAdditive;
    final toggle = _selectionToggle;
    final intersect = _selectionIntersect;

    setState(_clearSelectionDrag);

    if (start == null || !widget.enabled) {
      return;
    }

    if (!wasDragging || current == null) {
      widget.onSelection?.call(const <String>{});
      return;
    }

    final selectedGroupIds = _clipGroupIdsIntersecting(
      Rect.fromPoints(start, current),
    );
    widget.onSelection?.call(
      selectedGroupIds,
      additive: selectedGroupIds.isNotEmpty && additive,
      toggle: selectedGroupIds.isNotEmpty && toggle,
      intersect: selectedGroupIds.isNotEmpty && intersect,
    );
  }

  void _clearSelectionDrag() {
    _selectionScrollTimer?.cancel();
    _selectionScrollTimer = null;
    _lastPointerPosition = null;
    _selectionStart = null;
    _selectionCurrent = null;
    _selectionPointer = null;
    _selectionDragging = false;
    _selectionAdditive = false;
    _selectionToggle = false;
    _selectionIntersect = false;
  }

  bool _canStartSelectionAt(Offset local) {
    if (local.dy - _verticalScrollOffset < _timelineTracksTop ||
        local.dx < 0 ||
        local.dx > widget.width) {
      return false;
    }
    final trackY = local.dy - _timelineTracksTop;
    if (widget.project.tracks.isNotEmpty && trackY < 0) {
      return false;
    }

    final tapRect = Rect.fromCenter(center: local, width: 2, height: 2);
    return _clipGroupIdsIntersecting(tapRect).isEmpty;
  }

  Set<String> _clipGroupIdsIntersecting(Rect selectionRect) {
    final normalized = _normalizeRect(selectionRect);
    if (normalized.isEmpty) {
      return const <String>{};
    }

    final selected = <String>{};
    for (
      var trackIndex = 0;
      trackIndex < widget.project.tracks.length;
      trackIndex++
    ) {
      final track = widget.project.tracks[trackIndex];
      final trackTop =
          _timelineTracksTop + _trackTop(widget.project.tracks, trackIndex);
      final trackBottom = trackTop + track.height;
      if (trackBottom < normalized.top || trackTop > normalized.bottom) {
        continue;
      }

      for (final clip in track.clips) {
        final clipRect = _clipRectFor(clip, trackTop, track.height);
        if (clipRect.overlaps(normalized)) {
          selected.add(clip.timelineGroupId);
        }
      }
    }
    return selected;
  }

  Rect _clipRectFor(domain.Clip clip, double trackTop, double height) {
    final left = _leftFor(clip.timelineStart, widget.duration, widget.width);
    final rawWidth = _widthFor(clip.duration, widget.duration, widget.width);
    final availableWidth = math.max(
      _minimumTimelineClipWidth,
      widget.width - left,
    );
    final clipWidth = math.min(
      math.max(rawWidth, _minimumTimelineClipWidth),
      availableWidth,
    );
    return Rect.fromLTWH(left, trackTop + 7, clipWidth, height - 14);
  }

  Rect _normalizeRect(Rect rect) {
    return Rect.fromLTRB(
      math.min(rect.left, rect.right),
      math.min(rect.top, rect.bottom),
      math.max(rect.left, rect.right),
      math.max(rect.top, rect.bottom),
    );
  }

  Offset _localPosition(Offset globalPosition) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) {
      return Offset.zero;
    }
    return renderObject.globalToLocal(globalPosition) +
        Offset(0, _verticalScrollOffset);
  }

  void _tickSelectionAutoScroll() {
    final pointer = _lastPointerPosition;
    final box = context.findRenderObject();
    if (!_selectionDragging ||
        pointer == null ||
        box is! RenderBox ||
        !box.hasSize) {
      return;
    }
    final horizontal = widget.horizontalScrollController;
    final horizontalOffset = horizontal.hasClients ? horizontal.offset : 0.0;
    final local = box.globalToLocal(pointer);
    final dx = _edgeScrollStep(
      local.dx - horizontalOffset,
      0,
      widget.viewportWidth,
    );
    final dy = _edgeScrollStep(local.dy, _timelineTracksTop, box.size.height);
    final movedX = _scrollSelectionAxis(horizontal, dx);
    final movedY = _scrollSelectionAxis(widget.verticalScrollController, dy);
    if (movedX || movedY) {
      setState(() => _selectionCurrent = _localPosition(pointer));
    } else {
      _selectionScrollTimer?.cancel();
      _selectionScrollTimer = null;
    }
  }

  double _edgeScrollStep(double position, double minimum, double maximum) {
    final edge = math.min(
      _timelineAutoScrollEdgeThreshold,
      (maximum - minimum) / 3,
    );
    if (edge <= 0) return 0;
    if (position < minimum + edge) {
      return -_timelineAutoScrollMaxStep *
          ((minimum + edge - position) / edge).clamp(0.0, 1.0);
    }
    if (position > maximum - edge) {
      return _timelineAutoScrollMaxStep *
          ((position - maximum + edge) / edge).clamp(0.0, 1.0);
    }
    return 0;
  }

  bool _scrollSelectionAxis(ScrollController controller, double step) {
    if (!controller.hasClients || step.abs() < 0.1) return false;
    final position = controller.position;
    final next = (position.pixels + step).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((next - position.pixels).abs() < 0.1) return false;
    controller.jumpTo(next);
    return true;
  }

  double get _verticalScrollOffset {
    return widget.verticalScrollController.hasClients
        ? widget.verticalScrollController.offset
        : 0.0;
  }
}

class _TimelineBoxSelectionPainter extends CustomPainter {
  const _TimelineBoxSelectionPainter({
    required this.rect,
    required this.visible,
  });

  final Rect? rect;
  final bool visible;

  @override
  void paint(Canvas canvas, Size size) {
    final selectionRect = rect;
    if (!visible || selectionRect == null || selectionRect.isEmpty) {
      return;
    }

    final normalized = Rect.fromLTRB(
      math.min(selectionRect.left, selectionRect.right),
      math.min(selectionRect.top, selectionRect.bottom),
      math.max(selectionRect.left, selectionRect.right),
      math.max(selectionRect.top, selectionRect.bottom),
    );
    final fillPaint = Paint()
      ..color = TgiColors.accentSoft.withValues(alpha: 0.13)
      ..style = PaintingStyle.fill;
    final glowPaint = Paint()
      ..color = TgiColors.accent.withValues(alpha: 0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final borderPaint = Paint()
      ..color = TgiColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    canvas.drawRect(normalized, fillPaint);
    canvas.drawRect(normalized, glowPaint);
    canvas.drawRect(normalized, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _TimelineBoxSelectionPainter oldDelegate) {
    return oldDelegate.rect != rect || oldDelegate.visible != visible;
  }
}
