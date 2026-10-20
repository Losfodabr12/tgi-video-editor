part of 'video_preview_panel.dart';

class _TextOverlay extends StatefulWidget {
  const _TextOverlay({
    required this.entry,
    this.onMoved,
    this.onTap,
    this.onEdit,
    this.onInteractionStart,
    this.onInteractionEnd,
    super.key,
  });

  final TextOverlayEntry entry;
  final void Function(String clipId, double overlayX, double overlayY)? onMoved;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onInteractionStart;
  final VoidCallback? onInteractionEnd;

  @override
  State<_TextOverlay> createState() => _TextOverlayState();
}

class _TextOverlayState extends State<_TextOverlay> {
  Offset? _dragOverlayPosition;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final content = entry.text.trim();
    if (content.isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final overlayPosition =
              _dragOverlayPosition ??
              Offset(_clampUnit(entry.overlayX), _clampUnit(entry.overlayY));
          final shortestSide = math.min(
            constraints.maxWidth,
            constraints.maxHeight,
          );
          final scale = shortestSide / 720;
          final maximumFontSize = math.max(8.0, shortestSide / 4);
          final fontSize = (entry.fontSize * scale).clamp(8.0, maximumFontSize);
          final boxPadding = (18 * scale).clamp(4.0, 24.0);
          final opacity = _clampOpacity(entry.opacity);
          final animationProgress = _easeOutCubic(
            _clampOpacity(entry.animationProgress),
          );
          final animationOpacity = _textAnimationOpacity(
            entry.animation,
            animationProgress,
          );
          final displayOpacity = (opacity * animationOpacity).clamp(0.0, 1.0);
          final animationOffset = _textAnimationOffset(
            entry.animation,
            animationProgress,
            scale,
          );
          final animationScale = _textAnimationScale(
            entry.animation,
            animationProgress,
          );
          final backgroundAlpha =
              (((entry.backgroundColor >> 24) & 0xff) / 255.0) * displayOpacity;
          final textColor = Color(
            entry.textColor,
          ).withValues(alpha: displayOpacity);
          final backgroundColor = Color(
            entry.backgroundColor,
          ).withValues(alpha: backgroundAlpha.clamp(0.0, 1.0));
          final canMove = widget.onMoved != null;

          return Align(
            alignment: Alignment(
              _clampUnit(overlayPosition.dx) * 2 - 1,
              _clampUnit(overlayPosition.dy) * 2 - 1,
            ),
            child: Transform.translate(
              offset: animationOffset,
              child: Transform.scale(
                scale: animationScale,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * 0.82,
                  ),
                  child: MouseRegion(
                    cursor: canMove
                        ? SystemMouseCursors.move
                        : MouseCursor.defer,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onTap,
                      onDoubleTap: widget.onEdit,
                      onPanStart: canMove ? (_) => _beginMove() : null,
                      onPanUpdate: canMove
                          ? (details) =>
                                _updateMove(details.delta, constraints.biggest)
                          : null,
                      onPanEnd: canMove ? (_) => _endMove() : null,
                      onPanCancel: canMove ? _endMove : null,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: backgroundColor,
                          border: entry.isActive
                              ? Border.all(color: TgiColors.accent, width: 2)
                              : null,
                          borderRadius: BorderRadius.circular(TgiRadii.md),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(boxPadding),
                          child: NewTextStyle.appliesTo(entry.fontFamily)
                              ? StyledCaptionText(
                                  content,
                                  fontSize: fontSize,
                                  color: textColor,
                                  scale: scale,
                                )
                              : Text(
                                  content,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: entry.fontFamily,
                                    color: textColor,
                                    fontSize: fontSize,
                                    height: 1.08,
                                    fontWeight: FontWeight.w800,
                                    shadows: const [
                                      Shadow(
                                        color: TgiColors.black,
                                        blurRadius: 4,
                                        offset: Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _beginMove() {
    widget.onTap?.call();
    widget.onInteractionStart?.call();
    setState(() {
      _dragOverlayPosition = Offset(
        _clampUnit(widget.entry.overlayX),
        _clampUnit(widget.entry.overlayY),
      );
    });
  }

  void _updateMove(Offset delta, Size viewportSize) {
    final callback = widget.onMoved;
    if (callback == null ||
        viewportSize.width <= 0 ||
        viewportSize.height <= 0) {
      return;
    }

    final current =
        _dragOverlayPosition ??
        Offset(
          _clampUnit(widget.entry.overlayX),
          _clampUnit(widget.entry.overlayY),
        );
    final next = Offset(
      _clampUnit(current.dx + delta.dx / viewportSize.width),
      _clampUnit(current.dy + delta.dy / viewportSize.height),
    );
    setState(() {
      _dragOverlayPosition = next;
    });
    callback(widget.entry.clipId, next.dx, next.dy);
  }

  void _endMove() {
    if (_dragOverlayPosition == null) {
      return;
    }
    setState(() {
      _dragOverlayPosition = null;
    });
    widget.onInteractionEnd?.call();
  }

  double _easeOutCubic(double value) {
    final t = _clampOpacity(value);
    return 1 - math.pow(1 - t, 3).toDouble();
  }

  double _textAnimationOpacity(TextClipAnimation animation, double progress) {
    return switch (animation) {
      TextClipAnimation.none => 1,
      TextClipAnimation.rise => 1,
      TextClipAnimation.slideLeft => 1,
      TextClipAnimation.fade => progress,
      TextClipAnimation.pop => progress,
    };
  }

  Offset _textAnimationOffset(
    TextClipAnimation animation,
    double progress,
    double scale,
  ) {
    return switch (animation) {
      TextClipAnimation.rise => Offset(0, (1 - progress) * 28 * scale),
      TextClipAnimation.slideLeft => Offset((1 - progress) * -90 * scale, 0),
      _ => Offset.zero,
    };
  }

  double _textAnimationScale(TextClipAnimation animation, double progress) {
    return switch (animation) {
      TextClipAnimation.pop => 0.82 + progress * 0.18,
      _ => 1,
    };
  }

  double _clampOpacity(double value) {
    if (value.isNaN || value.isInfinite) {
      return 1;
    }
    return value.clamp(0.0, 1.0).toDouble();
  }

  double _clampUnit(double value) {
    if (value.isNaN || value.isInfinite) {
      return 0.5;
    }
    return value.clamp(0.0, 1.0).toDouble();
  }
}

double _clampOpacity(double value) {
  if (value.isNaN || value.isInfinite) {
    return 1;
  }
  return value.clamp(0.0, 1.0).toDouble();
}

class _VideoOverlay extends StatefulWidget {
  const _VideoOverlay({
    required this.entry,
    required this.playing,
    required this.onMoved,
    required this.onResized,
    this.onMaskGeometryChanged,
    this.onTap,
    super.key,
  });

  final VideoOverlayEntry entry;
  final bool playing;
  final void Function(String clipId, double overlayX, double overlayY)? onMoved;
  final void Function(String clipId, double overlayScale)? onResized;
  final PreviewMaskGeometryChanged? onMaskGeometryChanged;
  final VoidCallback? onTap;

  @override
  State<_VideoOverlay> createState() => _VideoOverlayState();
}

class _VideoOverlayState extends State<_VideoOverlay> {
  final _overlayKey = GlobalKey();
  Player? _player;
  VideoController? _videoController;
  String? _openedPath;
  bool _disposed = false;
  bool _syncInProgress = false;
  bool _syncAgain = false;
  int _syncRevision = 0;
  Rect? _dragStartRect;
  Rect? _resizeStartRect;
  _OverlayHandle? _activeHandle;

  @override
  void initState() {
    super.initState();
    _scheduleSync();
  }

  @override
  void didUpdateWidget(covariant _VideoOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_needsPlayerSync(oldWidget)) {
      _scheduleSync();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _syncAgain = false;
    _syncRevision++;
    final player = _player;
    _player = null;
    _videoController = null;
    if (player != null) {
      unawaited(player.dispose());
    }
    super.dispose();
  }

  bool _needsPlayerSync(_VideoOverlay oldWidget) {
    if (oldWidget.entry.item.filePath != widget.entry.item.filePath ||
        oldWidget.entry.playbackSpeed != widget.entry.playbackSpeed ||
        oldWidget.entry.visualAdjustments.reverseVideo !=
            widget.entry.visualAdjustments.reverseVideo ||
        oldWidget.playing != widget.playing) {
      return true;
    }

    if (oldWidget.entry.sourcePosition == widget.entry.sourcePosition) {
      return false;
    }
    if (!widget.playing) {
      return true;
    }

    final sourceDelta =
        widget.entry.sourcePosition - oldWidget.entry.sourcePosition;
    return sourceDelta < Duration.zero ||
        sourceDelta.abs() > _videoOverlaySeekResyncThreshold;
  }

  void _scheduleSync() {
    if (_disposed) {
      return;
    }
    if (_syncInProgress) {
      _syncAgain = true;
      return;
    }
    _syncInProgress = true;
    unawaited(_runScheduledSync());
  }

  Future<void> _runScheduledSync() async {
    try {
      do {
        _syncAgain = false;
        await _syncPlayer();
      } while (_syncAgain && mounted && !_disposed);
    } finally {
      _syncInProgress = false;
      if (_syncAgain && mounted && !_disposed) {
        _scheduleSync();
      }
    }
  }

  Future<void> _syncPlayer() async {
    final revision = ++_syncRevision;
    final entry = widget.entry;
    final path = entry.item.filePath;
    try {
      if (!await File(path).exists()) {
        return;
      }
      if (_disposed || !mounted || revision != _syncRevision) {
        return;
      }

      if (_player == null) {
        final player = Player();
        _player = player;
        _videoController = VideoController(player);
        if (mounted) {
          setState(() {});
        }
      }

      final player = _player;
      if (player == null) {
        return;
      }

      if (_openedPath != path) {
        await player.open(Media(Uri.file(path).toString()), play: false);
        _openedPath = path;
      }
      if (_disposed || !mounted || revision != _syncRevision) {
        return;
      }

      await player.setVolume(0);
      await player.setRate(_normalizedPlaybackSpeed());

      final current = player.state.position;
      final drift = (current - entry.sourcePosition).inMilliseconds.abs();
      if (!widget.playing ||
          entry.visualAdjustments.reverseVideo ||
          drift > _requestedSourceSeekTolerance.inMilliseconds) {
        await player.seek(entry.sourcePosition);
      }
      if (_disposed || !mounted || revision != _syncRevision) {
        return;
      }

      if (widget.playing && !entry.visualAdjustments.reverseVideo) {
        await player.play();
      } else {
        await player.pause();
      }
    } catch (_) {
      // PIP preview is best-effort. Export still uses FFmpeg and timeline data.
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = File(widget.entry.item.filePath);
    if (!file.existsSync()) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      key: _overlayKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = _clampOverlayScale(widget.entry.overlayScale);
          final baseSize = _baseOverlaySize(constraints);
          final baseWidth = baseSize.width;
          final baseHeight = baseSize.height;
          final width = math.max(32.0, baseWidth * scale);
          final height = math.max(24.0, baseHeight * scale);
          final left = _axisOffsetForUnit(
            constraints.maxWidth,
            width,
            widget.entry.overlayX,
          );
          final top = _axisOffsetForUnit(
            constraints.maxHeight,
            height,
            widget.entry.overlayY,
          );
          final canMove =
              widget.onMoved != null && !widget.entry.maskToolActive;
          final canResize =
              widget.entry.isActive &&
              widget.onResized != null &&
              !widget.entry.maskToolActive;
          final currentRect = Rect.fromLTWH(left, top, width, height);
          final previewMask = widget.entry.maskEnabled
              ? VideoPreviewMask(
                  shape: widget.entry.maskShape,
                  effect: widget.entry.maskEffect,
                  x: widget.entry.maskX,
                  y: widget.entry.maskY,
                  width: widget.entry.maskWidth,
                  height: widget.entry.maskHeight,
                  feather: widget.entry.maskFeather,
                  intensity: widget.entry.maskIntensity,
                  inverted: widget.entry.maskInverted,
                )
              : null;

          return Stack(
            children: [
              Positioned(
                left: left,
                top: top,
                width: width,
                height: height,
                child: MouseRegion(
                  cursor: canMove ? SystemMouseCursors.move : MouseCursor.defer,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: canMove
                        ? (_) {
                            widget.onTap?.call();
                            setState(() {
                              _dragStartRect = currentRect;
                              _activeHandle = null;
                              _resizeStartRect = null;
                            });
                          }
                        : null,
                    onPanUpdate: canMove
                        ? (details) =>
                              _updateMove(details.delta, constraints.biggest)
                        : null,
                    onPanEnd: canMove ? (_) => _clearInteraction() : null,
                    onPanCancel: canMove ? _clearInteraction : null,
                    onTap: widget.onTap,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(TgiRadii.sm),
                          child: Opacity(
                            opacity: _clampOpacity(widget.entry.opacity),
                            child: _buildAdjustedVideoSurface(),
                          ),
                        ),
                        if (previewMask != null)
                          _PreviewMaskEffect(mask: previewMask),
                        if (widget.entry.visualAdjustments.hasAnyEffect)
                          Positioned(
                            left: 8,
                            top: 8,
                            child: _PreviewEffectBadge(
                              label: _visualAdjustmentLabel(
                                widget.entry.visualAdjustments,
                              ),
                            ),
                          ),
                        if (widget.entry.isActive)
                          DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: TgiColors.accent,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(TgiRadii.sm),
                            ),
                          ),
                        if (previewMask != null && widget.entry.maskToolActive)
                          _PreviewMaskInteraction(
                            mask: previewMask,
                            onChanged: widget.onMaskGeometryChanged,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (canResize)
                ..._buildResizeHandles(
                  constraints: constraints,
                  currentRect: currentRect,
                  baseWidth: baseWidth,
                  baseHeight: baseHeight,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAdjustedVideoSurface() {
    final controller = _videoController;
    final video = controller == null
        ? ColoredBox(
            color: TgiColors.black,
            child: Center(
              child: Icon(
                Icons.movie_outlined,
                color: TgiColors.white.withValues(alpha: 0.54),
              ),
            ),
          )
        : Video(
            controller: controller,
            fit: BoxFit.contain,
            fill: TgiColors.black,
            filterQuality: FilterQuality.low,
            controls: NoVideoControls,
            wakelock: false,
          );
    final cropped = _ClipTransformPreviewSource(
      offsetX: widget.entry.visualAdjustments.transformOffsetX,
      offsetY: widget.entry.visualAdjustments.transformOffsetY,
      scale: widget.entry.visualAdjustments.transformScale,
      rotationDegrees: widget.entry.visualAdjustments.rotationDegrees,
      flipHorizontal: widget.entry.visualAdjustments.flipHorizontal,
      flipVertical: widget.entry.visualAdjustments.flipVertical,
      child: _CroppedPreviewSource(
        cropLeft: widget.entry.visualAdjustments.cropLeft,
        cropTop: widget.entry.visualAdjustments.cropTop,
        cropRight: widget.entry.visualAdjustments.cropRight,
        cropBottom: widget.entry.visualAdjustments.cropBottom,
        child: video,
      ),
    );
    final chromaKeyed = _applyPreviewChromaKey(
      cropped,
      widget.entry.visualAdjustments,
    );
    final colorFilter = _previewColorFilter(widget.entry.visualAdjustments);
    if (colorFilter == null) {
      return chromaKeyed;
    }
    return ColorFiltered(colorFilter: colorFilter, child: chromaKeyed);
  }

  Size _baseOverlaySize(BoxConstraints constraints) {
    final aspect = _aspectRatioFromMediaItem(widget.entry.item);
    final maxWidth = math.max(
      32.0,
      math.min(360.0, constraints.maxWidth * 0.52),
    );
    final maxHeight = math.max(
      24.0,
      math.min(260.0, constraints.maxHeight * 0.52),
    );
    var width = math.min(maxWidth, math.max(72.0, constraints.maxWidth * 0.28));
    var height = width / aspect;

    if (height > maxHeight) {
      height = maxHeight;
      width = height * aspect;
    }
    if (width > maxWidth) {
      width = maxWidth;
      height = width / aspect;
    }

    final minWidth = math.min(48.0, maxWidth);
    final minHeight = math.min(36.0, maxHeight);
    if (width < minWidth) {
      width = minWidth;
      height = width / aspect;
    }
    if (height < minHeight) {
      height = minHeight;
      width = height * aspect;
    }

    return Size(
      width.clamp(24.0, constraints.maxWidth).toDouble(),
      height.clamp(18.0, constraints.maxHeight).toDouble(),
    );
  }

  double _aspectRatioFromMediaItem(MediaItem item) {
    final width = item.width;
    final height = item.height;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return 16 / 9;
    }
    final ratio = width / height;
    if (ratio.isNaN || ratio.isInfinite || ratio <= 0) {
      return 16 / 9;
    }
    return ratio.clamp(0.45, 2.4).toDouble();
  }

  List<Widget> _buildResizeHandles({
    required BoxConstraints constraints,
    required Rect currentRect,
    required double baseWidth,
    required double baseHeight,
  }) {
    const handleSize = 28.0;
    final halfHandle = handleSize / 2;

    Offset pos(_OverlayHandle handle) {
      switch (handle) {
        case _OverlayHandle.topLeft:
          return Offset(
            currentRect.left - halfHandle,
            currentRect.top - halfHandle,
          );
        case _OverlayHandle.top:
          return Offset(
            currentRect.center.dx - halfHandle,
            currentRect.top - halfHandle,
          );
        case _OverlayHandle.topRight:
          return Offset(
            currentRect.right - halfHandle,
            currentRect.top - halfHandle,
          );
        case _OverlayHandle.right:
          return Offset(
            currentRect.right - halfHandle,
            currentRect.center.dy - halfHandle,
          );
        case _OverlayHandle.bottomRight:
          return Offset(
            currentRect.right - halfHandle,
            currentRect.bottom - halfHandle,
          );
        case _OverlayHandle.bottom:
          return Offset(
            currentRect.center.dx - halfHandle,
            currentRect.bottom - halfHandle,
          );
        case _OverlayHandle.bottomLeft:
          return Offset(
            currentRect.left - halfHandle,
            currentRect.bottom - halfHandle,
          );
        case _OverlayHandle.left:
          return Offset(
            currentRect.left - halfHandle,
            currentRect.center.dy - halfHandle,
          );
      }
    }

    return [
      for (final handle in _OverlayHandle.values)
        Positioned(
          left: pos(handle).dx,
          top: pos(handle).dy,
          width: handleSize,
          height: handleSize,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) {
              widget.onTap?.call();
              _beginResize(handle, currentRect);
            },
            onPanUpdate: (details) => _updateResize(
              details.globalPosition,
              constraints,
              baseWidth,
              baseHeight,
            ),
            onPanEnd: (_) => _clearInteraction(),
            onPanCancel: _clearInteraction,
            child: Align(
              alignment: _alignmentForHandle(handle),
              child: _HandleGlyph(handle: handle),
            ),
          ),
        ),
    ];
  }

  Alignment _alignmentForHandle(_OverlayHandle handle) {
    switch (handle) {
      case _OverlayHandle.topLeft:
        return Alignment.topLeft;
      case _OverlayHandle.top:
        return Alignment.topCenter;
      case _OverlayHandle.topRight:
        return Alignment.topRight;
      case _OverlayHandle.right:
        return Alignment.centerRight;
      case _OverlayHandle.bottomRight:
        return Alignment.bottomRight;
      case _OverlayHandle.bottom:
        return Alignment.bottomCenter;
      case _OverlayHandle.bottomLeft:
        return Alignment.bottomLeft;
      case _OverlayHandle.left:
        return Alignment.centerLeft;
    }
  }

  void _updateMove(Offset delta, Size frameSize) {
    final callback = widget.onMoved;
    final startRect = _dragStartRect;
    if (callback == null || startRect == null) {
      return;
    }

    final nextRect = startRect.shift(delta);
    final clampedLeft = _clampAxisOffset(
      nextRect.left,
      frameSize.width,
      nextRect.width,
    );
    final clampedTop = _clampAxisOffset(
      nextRect.top,
      frameSize.height,
      nextRect.height,
    );
    _dragStartRect = Rect.fromLTWH(
      clampedLeft,
      clampedTop,
      nextRect.width,
      nextRect.height,
    );
    callback(
      widget.entry.clipId,
      _unitForAxisOffset(clampedLeft, frameSize.width, nextRect.width),
      _unitForAxisOffset(clampedTop, frameSize.height, nextRect.height),
    );
  }

  void _beginResize(_OverlayHandle handle, Rect rect) {
    setState(() {
      _activeHandle = handle;
      _resizeStartRect = rect;
      _dragStartRect = null;
    });
  }

  void _updateResize(
    Offset globalPosition,
    BoxConstraints constraints,
    double baseWidth,
    double baseHeight,
  ) {
    final resizeCallback = widget.onResized;
    final handle = _activeHandle;
    final startRect = _resizeStartRect;
    if (resizeCallback == null || handle == null || startRect == null) {
      return;
    }

    final localPos = _viewportLocal(globalPosition);
    final frameSize = constraints.biggest;
    final nextRect = _resizedRectForHandle(
      handle,
      startRect,
      localPos,
      baseWidth,
      baseHeight,
    );
    final clampedLeft = _clampAxisOffset(
      nextRect.left,
      frameSize.width,
      nextRect.width,
    );
    final clampedTop = _clampAxisOffset(
      nextRect.top,
      frameSize.height,
      nextRect.height,
    );
    widget.onMoved?.call(
      widget.entry.clipId,
      _unitForAxisOffset(clampedLeft, frameSize.width, nextRect.width),
      _unitForAxisOffset(clampedTop, frameSize.height, nextRect.height),
    );
    resizeCallback(
      widget.entry.clipId,
      _clampOverlayScale(nextRect.width / baseWidth),
    );
  }

  Rect _resizedRectForHandle(
    _OverlayHandle handle,
    Rect startRect,
    Offset localPosition,
    double baseWidth,
    double baseHeight,
  ) {
    final startScale = math.max(
      startRect.width / baseWidth,
      startRect.height / baseHeight,
    );
    var candidateScale = startScale;

    switch (handle) {
      case _OverlayHandle.topLeft:
      case _OverlayHandle.topRight:
      case _OverlayHandle.bottomLeft:
      case _OverlayHandle.bottomRight:
        final opposite = _oppositeCorner(handle, startRect);
        final widthScale = (localPosition.dx - opposite.dx).abs() / baseWidth;
        final heightScale = (localPosition.dy - opposite.dy).abs() / baseHeight;
        candidateScale = math.max(widthScale, heightScale);
        break;
      case _OverlayHandle.top:
      case _OverlayHandle.bottom:
        candidateScale =
            (localPosition.dy - _edgeAnchor(handle, startRect).dy).abs() /
            baseHeight;
        break;
      case _OverlayHandle.left:
      case _OverlayHandle.right:
        candidateScale =
            (localPosition.dx - _edgeAnchor(handle, startRect).dx).abs() /
            baseWidth;
        break;
    }

    if (candidateScale.isNaN || candidateScale.isInfinite) {
      candidateScale = startScale;
    }
    candidateScale = candidateScale
        .clamp(_minImageOverlayScale, _maxImageOverlayScale)
        .toDouble();

    final nextWidth = baseWidth * candidateScale;
    final nextHeight = baseHeight * candidateScale;
    final anchor = _anchorFor(handle, startRect);
    return Rect.fromLTWH(
      _leftForHandle(handle, anchor, nextWidth),
      _topForHandle(handle, anchor, nextHeight),
      nextWidth,
      nextHeight,
    );
  }

  Offset _viewportLocal(Offset global) {
    final renderBox = _overlayKey.currentContext?.findRenderObject();
    if (renderBox is RenderBox) {
      return renderBox.globalToLocal(global);
    }
    return global;
  }

  Offset _anchorFor(_OverlayHandle handle, Rect rect) {
    switch (handle) {
      case _OverlayHandle.topLeft:
        return rect.bottomRight;
      case _OverlayHandle.top:
        return Offset(rect.center.dx, rect.bottom);
      case _OverlayHandle.topRight:
        return rect.bottomLeft;
      case _OverlayHandle.right:
        return Offset(rect.left, rect.center.dy);
      case _OverlayHandle.bottomRight:
        return rect.topLeft;
      case _OverlayHandle.bottom:
        return Offset(rect.center.dx, rect.top);
      case _OverlayHandle.bottomLeft:
        return rect.topRight;
      case _OverlayHandle.left:
        return Offset(rect.right, rect.center.dy);
    }
  }

  Offset _oppositeCorner(_OverlayHandle handle, Rect rect) {
    switch (handle) {
      case _OverlayHandle.topLeft:
        return rect.bottomRight;
      case _OverlayHandle.topRight:
        return rect.bottomLeft;
      case _OverlayHandle.bottomLeft:
        return rect.topRight;
      case _OverlayHandle.bottomRight:
        return rect.topLeft;
      case _OverlayHandle.top:
      case _OverlayHandle.bottom:
      case _OverlayHandle.left:
      case _OverlayHandle.right:
        return rect.center;
    }
  }

  Offset _edgeAnchor(_OverlayHandle handle, Rect rect) {
    switch (handle) {
      case _OverlayHandle.top:
        return Offset(rect.center.dx, rect.bottom);
      case _OverlayHandle.bottom:
        return Offset(rect.center.dx, rect.top);
      case _OverlayHandle.left:
        return Offset(rect.right, rect.center.dy);
      case _OverlayHandle.right:
        return Offset(rect.left, rect.center.dy);
      case _OverlayHandle.topLeft:
      case _OverlayHandle.topRight:
      case _OverlayHandle.bottomLeft:
      case _OverlayHandle.bottomRight:
        return rect.center;
    }
  }

  double _leftForHandle(_OverlayHandle handle, Offset anchor, double width) {
    switch (handle) {
      case _OverlayHandle.topLeft:
      case _OverlayHandle.left:
      case _OverlayHandle.bottomLeft:
        return anchor.dx - width;
      case _OverlayHandle.top:
      case _OverlayHandle.bottom:
        return anchor.dx - width / 2;
      case _OverlayHandle.topRight:
      case _OverlayHandle.right:
      case _OverlayHandle.bottomRight:
        return anchor.dx;
    }
  }

  double _topForHandle(_OverlayHandle handle, Offset anchor, double height) {
    switch (handle) {
      case _OverlayHandle.topLeft:
      case _OverlayHandle.top:
      case _OverlayHandle.topRight:
        return anchor.dy - height;
      case _OverlayHandle.left:
      case _OverlayHandle.right:
        return anchor.dy - height / 2;
      case _OverlayHandle.bottomLeft:
      case _OverlayHandle.bottom:
      case _OverlayHandle.bottomRight:
        return anchor.dy;
    }
  }

  void _clearInteraction() {
    setState(() {
      _dragStartRect = null;
      _resizeStartRect = null;
      _activeHandle = null;
    });
  }

  double _normalizedPlaybackSpeed() {
    final speed = widget.entry.playbackSpeed;
    if (speed.isNaN || speed.isInfinite || speed <= 0) {
      return 1;
    }
    return speed.clamp(0.25, 4.0).toDouble();
  }

  double _clampOverlayScale(double value) {
    if (value.isNaN || value.isInfinite) {
      return 1;
    }
    return value.clamp(_minImageOverlayScale, _maxImageOverlayScale).toDouble();
  }

  double _axisOffsetForUnit(
    double frameExtent,
    double contentExtent,
    double unit,
  ) {
    final travel = frameExtent - contentExtent;
    if (travel.abs() < 0.0001) {
      return 0;
    }
    return travel * _clampUnit(unit);
  }

  double _clampAxisOffset(
    double offset,
    double frameExtent,
    double contentExtent,
  ) {
    final travel = frameExtent - contentExtent;
    final minOffset = math.min(0.0, travel);
    final maxOffset = math.max(0.0, travel);
    return offset.clamp(minOffset, maxOffset).toDouble();
  }

  double _unitForAxisOffset(
    double offset,
    double frameExtent,
    double contentExtent,
  ) {
    final travel = frameExtent - contentExtent;
    if (travel.abs() < 0.0001) {
      return 0.5;
    }
    return _clampUnit(offset / travel);
  }

  double _clampUnit(double value) {
    if (value.isNaN || value.isInfinite) {
      return 0;
    }
    return value.clamp(0.0, 1.0).toDouble();
  }
}

class _ImageOverlay extends StatefulWidget {
  const _ImageOverlay({
    required this.item,
    required this.clipId,
    required this.active,
    required this.overlayX,
    required this.overlayY,
    required this.overlayScale,
    required this.imageFit,
    required this.opacity,
    required this.cropLeft,
    required this.cropTop,
    required this.cropRight,
    required this.cropBottom,
    required this.transformOffsetX,
    required this.transformOffsetY,
    required this.transformScale,
    required this.rotationDegrees,
    required this.flipHorizontal,
    required this.flipVertical,
    required this.onMoved,
    required this.onResized,
    this.onTap,
    super.key,
  });

  final MediaItem item;
  final String? clipId;
  final bool active;
  final double overlayX;
  final double overlayY;
  final double overlayScale;
  final ImageClipFit imageFit;
  final double opacity;
  final double cropLeft;
  final double cropTop;
  final double cropRight;
  final double cropBottom;
  final double transformOffsetX;
  final double transformOffsetY;
  final double transformScale;
  final double rotationDegrees;
  final bool flipHorizontal;
  final bool flipVertical;
  final void Function(String clipId, double overlayX, double overlayY)? onMoved;
  final void Function(String clipId, double overlayScale)? onResized;
  final VoidCallback? onTap;

  @override
  State<_ImageOverlay> createState() => _ImageOverlayState();
}

class _ImageOverlayState extends State<_ImageOverlay> {
  final _overlayKey = GlobalKey();
  Rect? _dragStartRect;
  Rect? _resizeStartRect;
  _OverlayHandle? _activeHandle;
  double? _imageAspectRatio;

  @override
  void initState() {
    super.initState();
    _loadImageAspectRatio();
  }

  @override
  void didUpdateWidget(covariant _ImageOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.filePath != widget.item.filePath) {
      _imageAspectRatio = null;
      _loadImageAspectRatio();
    }
  }

  Future<void> _loadImageAspectRatio() async {
    final path = widget.item.filePath;
    final file = File(path);
    if (!await file.exists()) {
      return;
    }

    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final width = image.width;
      final height = image.height;
      image.dispose();
      codec.dispose();
      if (!mounted ||
          widget.item.filePath != path ||
          width <= 0 ||
          height <= 0) {
        return;
      }
      setState(() {
        _imageAspectRatio = width / height;
      });
    } catch (_) {
      // Keep the fallback 16:9 box if the file cannot be decoded for sizing.
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = File(widget.item.filePath);
    if (!file.existsSync()) {
      return const SizedBox.shrink();
    }

    final isTrackedOverlay = widget.imageFit == ImageClipFit.trackedOverlay;
    final isFloatingOverlay =
        widget.imageFit == ImageClipFit.overlay || isTrackedOverlay;
    if (!isFloatingOverlay) {
      return Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Opacity(
                opacity: _clampOpacity(widget.opacity),
                child: _ClipTransformPreviewSource(
                  offsetX: widget.transformOffsetX,
                  offsetY: widget.transformOffsetY,
                  scale: widget.transformScale,
                  rotationDegrees: widget.rotationDegrees,
                  flipHorizontal: widget.flipHorizontal,
                  flipVertical: widget.flipVertical,
                  child: _CroppedPreviewSource(
                    cropLeft: widget.cropLeft,
                    cropTop: widget.cropTop,
                    cropRight: widget.cropRight,
                    cropBottom: widget.cropBottom,
                    child: Image.file(
                      file,
                      fit: widget.imageFit == ImageClipFit.cover
                          ? BoxFit.cover
                          : BoxFit.contain,
                      alignment: Alignment(
                        _clampUnit(widget.overlayX) * 2 - 1,
                        _clampUnit(widget.overlayY) * 2 - 1,
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.active)
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: TgiColors.accent, width: 2),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Positioned.fill(
      key: _overlayKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = _clampOverlayScale(
            widget.overlayScale * widget.transformScale,
          );
          final baseSize = _baseOverlaySize(constraints);
          final baseWidth = baseSize.width;
          final baseHeight = baseSize.height;
          final width = math.max(32.0, baseWidth * scale);
          final height = math.max(24.0, baseHeight * scale);
          final positionX = _clampUnit(
            widget.overlayX + widget.transformOffsetX / 2,
          );
          final positionY = _clampUnit(
            widget.overlayY + widget.transformOffsetY / 2,
          );
          final left = isTrackedOverlay
              ? constraints.maxWidth * positionX - width / 2
              : _axisOffsetForUnit(constraints.maxWidth, width, positionX);
          final top = isTrackedOverlay
              ? constraints.maxHeight * positionY - height / 2
              : _axisOffsetForUnit(constraints.maxHeight, height, positionY);
          final canMove = widget.clipId != null && widget.onMoved != null;
          final canResize =
              widget.active &&
              widget.clipId != null &&
              widget.onResized != null;
          final currentRect = Rect.fromLTWH(left, top, width, height);

          return Stack(
            children: [
              Positioned(
                left: left,
                top: top,
                width: width,
                height: height,
                child: MouseRegion(
                  cursor: canMove ? SystemMouseCursors.move : MouseCursor.defer,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: canMove
                        ? (_) {
                            widget.onTap?.call();
                            setState(() {
                              _dragStartRect = currentRect;
                              _activeHandle = null;
                              _resizeStartRect = null;
                            });
                          }
                        : null,
                    onPanUpdate: canMove
                        ? (details) =>
                              _updateMove(details.delta, constraints.biggest)
                        : null,
                    onPanEnd: canMove ? (_) => _clearInteraction() : null,
                    onPanCancel: canMove ? _clearInteraction : null,
                    onTap: widget.onTap,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Transform.rotate(
                          angle: widget.rotationDegrees * math.pi / 180,
                          child: Transform.scale(
                            scaleX: widget.flipHorizontal ? -1 : 1,
                            scaleY: widget.flipVertical ? -1 : 1,
                            child: Opacity(
                              opacity: _clampOpacity(widget.opacity),
                              child: _CroppedPreviewSource(
                                cropLeft: widget.cropLeft,
                                cropTop: widget.cropTop,
                                cropRight: widget.cropRight,
                                cropBottom: widget.cropBottom,
                                child: Image.file(file, fit: BoxFit.contain),
                              ),
                            ),
                          ),
                        ),
                        if (widget.active)
                          DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: TgiColors.accent,
                                width: 2,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (canResize)
                ..._buildResizeHandles(
                  constraints: constraints,
                  currentRect: currentRect,
                  baseWidth: baseWidth,
                  baseHeight: baseHeight,
                ),
            ],
          );
        },
      ),
    );
  }

  Size _baseOverlaySize(BoxConstraints constraints) {
    final aspect = _validAspectRatio(_imageAspectRatio)
        ? _imageAspectRatio!
        : 16 / 9;
    final maxWidth = math.max(
      32.0,
      math.min(360.0, constraints.maxWidth * 0.52),
    );
    final maxHeight = math.max(
      24.0,
      math.min(260.0, constraints.maxHeight * 0.52),
    );
    var width = math.min(maxWidth, math.max(72.0, constraints.maxWidth * 0.28));
    var height = width / aspect;

    if (height > maxHeight) {
      height = maxHeight;
      width = height * aspect;
    }
    if (width > maxWidth) {
      width = maxWidth;
      height = width / aspect;
    }

    final minWidth = math.min(48.0, maxWidth);
    final minHeight = math.min(36.0, maxHeight);
    if (width < minWidth) {
      width = minWidth;
      height = width / aspect;
    }
    if (height < minHeight) {
      height = minHeight;
      width = height * aspect;
    }

    return Size(
      width.clamp(24.0, constraints.maxWidth).toDouble(),
      height.clamp(18.0, constraints.maxHeight).toDouble(),
    );
  }

  bool _validAspectRatio(double? value) {
    return value != null && value.isFinite && value > 0;
  }

  Offset _viewportLocal(Offset global) {
    final renderBox = _overlayKey.currentContext?.findRenderObject();
    if (renderBox is RenderBox) {
      return renderBox.globalToLocal(global);
    }
    return global;
  }

  List<Widget> _buildResizeHandles({
    required BoxConstraints constraints,
    required Rect currentRect,
    required double baseWidth,
    required double baseHeight,
  }) {
    const handleSize = 28.0;
    final halfHandle = handleSize / 2;

    Offset pos(_OverlayHandle handle) {
      switch (handle) {
        case _OverlayHandle.topLeft:
          return Offset(
            currentRect.left - halfHandle,
            currentRect.top - halfHandle,
          );
        case _OverlayHandle.top:
          return Offset(
            currentRect.center.dx - halfHandle,
            currentRect.top - halfHandle,
          );
        case _OverlayHandle.topRight:
          return Offset(
            currentRect.right - halfHandle,
            currentRect.top - halfHandle,
          );
        case _OverlayHandle.right:
          return Offset(
            currentRect.right - halfHandle,
            currentRect.center.dy - halfHandle,
          );
        case _OverlayHandle.bottomRight:
          return Offset(
            currentRect.right - halfHandle,
            currentRect.bottom - halfHandle,
          );
        case _OverlayHandle.bottom:
          return Offset(
            currentRect.center.dx - halfHandle,
            currentRect.bottom - halfHandle,
          );
        case _OverlayHandle.bottomLeft:
          return Offset(
            currentRect.left - halfHandle,
            currentRect.bottom - halfHandle,
          );
        case _OverlayHandle.left:
          return Offset(
            currentRect.left - halfHandle,
            currentRect.center.dy - halfHandle,
          );
      }
    }

    return [
      for (final handle in _OverlayHandle.values)
        Positioned(
          left: pos(handle).dx,
          top: pos(handle).dy,
          width: handleSize,
          height: handleSize,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) {
              widget.onTap?.call();
              _beginResize(handle, currentRect);
            },
            onPanUpdate: (details) => _updateResize(
              details.globalPosition,
              constraints,
              baseWidth,
              baseHeight,
            ),
            onPanEnd: (_) => _clearInteraction(),
            onPanCancel: _clearInteraction,
            child: Align(
              alignment: _alignmentForHandle(handle),
              child: _HandleGlyph(handle: handle),
            ),
          ),
        ),
    ];
  }

  Alignment _alignmentForHandle(_OverlayHandle handle) {
    switch (handle) {
      case _OverlayHandle.topLeft:
        return Alignment.topLeft;
      case _OverlayHandle.top:
        return Alignment.topCenter;
      case _OverlayHandle.topRight:
        return Alignment.topRight;
      case _OverlayHandle.right:
        return Alignment.centerRight;
      case _OverlayHandle.bottomRight:
        return Alignment.bottomRight;
      case _OverlayHandle.bottom:
        return Alignment.bottomCenter;
      case _OverlayHandle.bottomLeft:
        return Alignment.bottomLeft;
      case _OverlayHandle.left:
        return Alignment.centerLeft;
    }
  }

  void _updateMove(Offset delta, Size frameSize) {
    final id = widget.clipId;
    final callback = widget.onMoved;
    final startRect = _dragStartRect;
    if (id == null || callback == null || startRect == null) {
      return;
    }

    final nextRect = startRect.shift(delta);
    final clampedLeft = _clampAxisOffset(
      nextRect.left,
      frameSize.width,
      nextRect.width,
    );
    final clampedTop = _clampAxisOffset(
      nextRect.top,
      frameSize.height,
      nextRect.height,
    );
    _dragStartRect = Rect.fromLTWH(
      clampedLeft,
      clampedTop,
      nextRect.width,
      nextRect.height,
    );
    callback(
      id,
      _unitForImageOffset(clampedLeft, frameSize.width, nextRect.width),
      _unitForImageOffset(clampedTop, frameSize.height, nextRect.height),
    );
  }

  void _beginResize(_OverlayHandle handle, Rect rect) {
    setState(() {
      _activeHandle = handle;
      _resizeStartRect = rect;
      _dragStartRect = null;
    });
  }

  void _updateResize(
    Offset globalPosition,
    BoxConstraints constraints,
    double baseWidth,
    double baseHeight,
  ) {
    final id = widget.clipId;
    final moveCallback = widget.onMoved;
    final resizeCallback = widget.onResized;
    final handle = _activeHandle;
    final startRect = _resizeStartRect;
    if (id == null ||
        resizeCallback == null ||
        handle == null ||
        startRect == null) {
      return;
    }

    final localPos = _viewportLocal(globalPosition);
    final frameSize = constraints.biggest;
    final nextRect = _resizedRectForHandle(
      handle,
      startRect,
      localPos,
      baseWidth,
      baseHeight,
    );
    final clampedLeft = _clampAxisOffset(
      nextRect.left,
      frameSize.width,
      nextRect.width,
    );
    final clampedTop = _clampAxisOffset(
      nextRect.top,
      frameSize.height,
      nextRect.height,
    );
    moveCallback?.call(
      id,
      _unitForImageOffset(clampedLeft, frameSize.width, nextRect.width),
      _unitForImageOffset(clampedTop, frameSize.height, nextRect.height),
    );
    resizeCallback(id, _clampOverlayScale(nextRect.width / baseWidth));
  }

  Rect _resizedRectForHandle(
    _OverlayHandle handle,
    Rect startRect,
    Offset localPosition,
    double baseWidth,
    double baseHeight,
  ) {
    final startScale = math.max(
      startRect.width / baseWidth,
      startRect.height / baseHeight,
    );
    var candidateScale = startScale;

    switch (handle) {
      case _OverlayHandle.topLeft:
      case _OverlayHandle.topRight:
      case _OverlayHandle.bottomLeft:
      case _OverlayHandle.bottomRight:
        final opposite = _oppositeCorner(handle, startRect);
        final widthScale = (localPosition.dx - opposite.dx).abs() / baseWidth;
        final heightScale = (localPosition.dy - opposite.dy).abs() / baseHeight;
        candidateScale = math.max(widthScale, heightScale);
        break;
      case _OverlayHandle.top:
      case _OverlayHandle.bottom:
        candidateScale =
            (localPosition.dy - _edgeAnchor(handle, startRect).dy).abs() /
            baseHeight;
        break;
      case _OverlayHandle.left:
      case _OverlayHandle.right:
        candidateScale =
            (localPosition.dx - _edgeAnchor(handle, startRect).dx).abs() /
            baseWidth;
        break;
    }

    if (candidateScale.isNaN || candidateScale.isInfinite) {
      candidateScale = startScale;
    }
    candidateScale = candidateScale
        .clamp(_minImageOverlayScale, _maxImageOverlayScale)
        .toDouble();

    final nextWidth = baseWidth * candidateScale;
    final nextHeight = baseHeight * candidateScale;
    final anchor = _anchorFor(handle, startRect);
    return Rect.fromLTWH(
      _leftForHandle(handle, anchor, nextWidth),
      _topForHandle(handle, anchor, nextHeight),
      nextWidth,
      nextHeight,
    );
  }

  Offset _anchorFor(_OverlayHandle handle, Rect rect) {
    switch (handle) {
      case _OverlayHandle.topLeft:
        return rect.bottomRight;
      case _OverlayHandle.top:
        return Offset(rect.center.dx, rect.bottom);
      case _OverlayHandle.topRight:
        return rect.bottomLeft;
      case _OverlayHandle.right:
        return Offset(rect.left, rect.center.dy);
      case _OverlayHandle.bottomRight:
        return rect.topLeft;
      case _OverlayHandle.bottom:
        return Offset(rect.center.dx, rect.top);
      case _OverlayHandle.bottomLeft:
        return rect.topRight;
      case _OverlayHandle.left:
        return Offset(rect.right, rect.center.dy);
    }
  }

  Offset _oppositeCorner(_OverlayHandle handle, Rect rect) {
    switch (handle) {
      case _OverlayHandle.topLeft:
        return rect.bottomRight;
      case _OverlayHandle.topRight:
        return rect.bottomLeft;
      case _OverlayHandle.bottomLeft:
        return rect.topRight;
      case _OverlayHandle.bottomRight:
        return rect.topLeft;
      case _OverlayHandle.top:
      case _OverlayHandle.bottom:
      case _OverlayHandle.left:
      case _OverlayHandle.right:
        return rect.center;
    }
  }

  Offset _edgeAnchor(_OverlayHandle handle, Rect rect) {
    switch (handle) {
      case _OverlayHandle.top:
        return Offset(rect.center.dx, rect.bottom);
      case _OverlayHandle.bottom:
        return Offset(rect.center.dx, rect.top);
      case _OverlayHandle.left:
        return Offset(rect.right, rect.center.dy);
      case _OverlayHandle.right:
        return Offset(rect.left, rect.center.dy);
      case _OverlayHandle.topLeft:
      case _OverlayHandle.topRight:
      case _OverlayHandle.bottomLeft:
      case _OverlayHandle.bottomRight:
        return rect.center;
    }
  }

  double _leftForHandle(_OverlayHandle handle, Offset anchor, double width) {
    switch (handle) {
      case _OverlayHandle.topLeft:
      case _OverlayHandle.left:
      case _OverlayHandle.bottomLeft:
        return anchor.dx - width;
      case _OverlayHandle.top:
      case _OverlayHandle.bottom:
        return anchor.dx - width / 2;
      case _OverlayHandle.topRight:
      case _OverlayHandle.right:
      case _OverlayHandle.bottomRight:
        return anchor.dx;
    }
  }

  double _topForHandle(_OverlayHandle handle, Offset anchor, double height) {
    switch (handle) {
      case _OverlayHandle.topLeft:
      case _OverlayHandle.top:
      case _OverlayHandle.topRight:
        return anchor.dy - height;
      case _OverlayHandle.left:
      case _OverlayHandle.right:
        return anchor.dy - height / 2;
      case _OverlayHandle.bottomLeft:
      case _OverlayHandle.bottom:
      case _OverlayHandle.bottomRight:
        return anchor.dy;
    }
  }

  void _clearInteraction() {
    setState(() {
      _dragStartRect = null;
      _resizeStartRect = null;
      _activeHandle = null;
    });
  }

  double _clampOverlayScale(double value) {
    if (value.isNaN || value.isInfinite) {
      return 1;
    }
    return value.clamp(_minImageOverlayScale, _maxImageOverlayScale).toDouble();
  }

  double _axisOffsetForUnit(
    double frameExtent,
    double contentExtent,
    double unit,
  ) {
    final travel = frameExtent - contentExtent;
    if (travel.abs() < 0.0001) {
      return 0;
    }
    return travel * _clampUnit(unit);
  }

  double _clampAxisOffset(
    double offset,
    double frameExtent,
    double contentExtent,
  ) {
    final travel = frameExtent - contentExtent;
    final minOffset = math.min(0.0, travel);
    final maxOffset = math.max(0.0, travel);
    return offset.clamp(minOffset, maxOffset).toDouble();
  }

  double _unitForAxisOffset(
    double offset,
    double frameExtent,
    double contentExtent,
  ) {
    final travel = frameExtent - contentExtent;
    if (travel.abs() < 0.0001) {
      return 0.5;
    }
    return _clampUnit(offset / travel);
  }

  double _unitForImageOffset(
    double offset,
    double frameExtent,
    double contentExtent,
  ) {
    if (widget.imageFit == ImageClipFit.trackedOverlay) {
      if (frameExtent.abs() < 0.0001) return 0.5;
      return _clampUnit((offset + contentExtent / 2) / frameExtent);
    }
    return _unitForAxisOffset(offset, frameExtent, contentExtent);
  }

  double _clampUnit(double value) {
    if (value.isNaN || value.isInfinite) {
      return 0;
    }
    return value.clamp(0.0, 1.0).toDouble();
  }
}

enum _OverlayHandle {
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left,
}

class _HandleGlyph extends StatelessWidget {
  const _HandleGlyph({required this.handle});

  final _OverlayHandle handle;

  @override
  Widget build(BuildContext context) {
    final isCorner =
        handle == _OverlayHandle.topLeft ||
        handle == _OverlayHandle.topRight ||
        handle == _OverlayHandle.bottomLeft ||
        handle == _OverlayHandle.bottomRight;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TgiColors.black.withValues(alpha: 0.78),
        border: Border.all(color: TgiColors.accent, width: 2),
        borderRadius: BorderRadius.circular(
          isCorner ? TgiRadii.xs : TgiRadii.sm,
        ),
      ),
      child: SizedBox(width: isCorner ? 10 : 18, height: isCorner ? 10 : 4),
    );
  }
}
