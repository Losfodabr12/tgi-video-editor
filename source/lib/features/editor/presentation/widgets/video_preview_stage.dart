part of 'video_preview_panel.dart';

class _PreviewStage extends StatelessWidget {
  const _PreviewStage({required this.aspectRatio, required this.child});

  final double aspectRatio;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;
        if (maxWidth <= 0 || maxHeight <= 0) {
          return const SizedBox.shrink();
        }

        var width = maxWidth;
        var height = width / aspectRatio;
        if (height > maxHeight) {
          height = maxHeight;
          width = height * aspectRatio;
        }

        return Center(
          child: SizedBox(width: width, height: height, child: child),
        );
      },
    );
  }
}

class _PreviewFrame extends StatelessWidget {
  const _PreviewFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TgiColors.black,
        border: Border.all(color: TgiColors.borderStrong),
        borderRadius: BorderRadius.circular(TgiRadii.lg),
        boxShadow: const [
          BoxShadow(
            color: TgiColors.shadow,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
          BoxShadow(
            color: TgiColors.glowSoft,
            blurRadius: 20,
            spreadRadius: -3,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(TgiSpacing.xs),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(TgiRadii.md),
          child: Stack(
            fit: StackFit.expand,
            children: [
              child,
              const IgnorePointer(child: _PreviewCornerGuides()),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewCornerGuides extends StatelessWidget {
  const _PreviewCornerGuides();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _PreviewCornerGuidesPainter());
  }
}

class _PreviewCornerGuidesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }
    final paint = Paint()
      ..color = TgiColors.accentSoft.withValues(alpha: 0.34)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    const length = 22.0;
    const inset = 10.0;
    final points = <List<Offset>>[
      [
        const Offset(inset, inset + length),
        const Offset(inset, inset),
        const Offset(inset + length, inset),
      ],
      [
        Offset(size.width - inset - length, inset),
        Offset(size.width - inset, inset),
        Offset(size.width - inset, inset + length),
      ],
      [
        Offset(inset, size.height - inset - length),
        Offset(inset, size.height - inset),
        Offset(inset + length, size.height - inset),
      ],
      [
        Offset(size.width - inset - length, size.height - inset),
        Offset(size.width - inset, size.height - inset),
        Offset(size.width - inset, size.height - inset - length),
      ],
    ];
    for (final pathPoints in points) {
      final path = Path()..moveTo(pathPoints.first.dx, pathPoints.first.dy);
      for (final point in pathPoints.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PreviewCornerGuidesPainter oldDelegate) =>
      false;
}

class _PreviewViewport extends StatelessWidget {
  const _PreviewViewport({
    required this.item,
    required this.cropMainVideoToFill,
    required this.player,
    required this.videoController,
    required this.loading,
    required this.errorMessage,
    required this.imageOverlayItem,
    required this.imageOverlayClipId,
    required this.imageOverlayX,
    required this.imageOverlayY,
    required this.imageOverlayScale,
    this.videoOverlayEntries = const [],
    this.imageOverlayEntries = const [],
    this.textOverlayEntries = const [],
    this.transitionPreviewEntries = const [],
    required this.transitionPreviewPlaying,
    this.onImageOverlayTap,
    this.onVideoOverlayMoved,
    this.onVideoOverlayResized,
    this.onVideoOverlayTap,
    this.onTextOverlayMoved,
    this.onTextOverlayTap,
    this.onTextOverlayEdit,
    this.onTextOverlayInteractionStart,
    this.onTextOverlayInteractionEnd,
    required this.onImageOverlayMoved,
    required this.onImageOverlayResized,
    required this.loadedItemId,
    required this.previewImage,
    required this.previewFrameSerial,
    required this.rawPreviewFallback,
    required this.previewDownscaled,
    required this.videoOpacity,
    required this.visualAdjustments,
    required this.timelinePosition,
    required this.kenBurnsToolActive,
    required this.kenBurnsPickStart,
    this.kenBurnsStartX,
    this.kenBurnsStartY,
    this.kenBurnsEndX,
    this.kenBurnsEndY,
    this.onKenBurnsPointSelected,
    required this.transformToolActive,
    required this.transformCropMode,
    this.onTransformPositionChanged,
    this.onTransformScaleChanged,
    this.onTransformCropChanged,
    this.onTransformInteractionStart,
    this.onTransformInteractionEnd,
    required this.chromaColorPickerActive,
    required this.chromaTransparencyPreview,
    required this.chromaColorSampling,
    this.onChromaColorPointSelected,
    required this.whiteBalanceColorPickerActive,
    required this.whiteBalanceColorSampling,
    this.onWhiteBalanceColorPointSelected,
    this.onImportRequested,
    this.mask,
    required this.maskToolActive,
    this.onMaskGeometryChanged,
  });

  final MediaItem? item;
  final bool cropMainVideoToFill;
  final Player? player;
  final VideoController? videoController;
  final bool loading;
  final String? errorMessage;
  final MediaItem? imageOverlayItem;
  final String? imageOverlayClipId;
  final double imageOverlayX;
  final double imageOverlayY;
  final double imageOverlayScale;
  final List<VideoOverlayEntry> videoOverlayEntries;
  final List<ImageOverlayEntry> imageOverlayEntries;
  final List<TextOverlayEntry> textOverlayEntries;
  final List<TransitionPreviewEntry> transitionPreviewEntries;
  final bool transitionPreviewPlaying;
  final void Function(String clipId, double overlayX, double overlayY)?
  onImageOverlayMoved;
  final void Function(String clipId, double overlayScale)?
  onImageOverlayResized;
  final void Function(String clipId)? onImageOverlayTap;
  final void Function(String clipId, double overlayX, double overlayY)?
  onVideoOverlayMoved;
  final void Function(String clipId, double overlayScale)?
  onVideoOverlayResized;
  final void Function(String timelineGroupId)? onVideoOverlayTap;
  final void Function(String clipId, double overlayX, double overlayY)?
  onTextOverlayMoved;
  final void Function(String timelineGroupId)? onTextOverlayTap;
  final void Function(String clipId)? onTextOverlayEdit;
  final VoidCallback? onTextOverlayInteractionStart;
  final VoidCallback? onTextOverlayInteractionEnd;
  final String? loadedItemId;
  final ui.Image? previewImage;
  final int previewFrameSerial;
  final bool rawPreviewFallback;
  final bool previewDownscaled;
  final double videoOpacity;
  final VideoPreviewVisualAdjustments visualAdjustments;
  final Duration timelinePosition;
  final bool kenBurnsToolActive;
  final bool kenBurnsPickStart;
  final double? kenBurnsStartX;
  final double? kenBurnsStartY;
  final double? kenBurnsEndX;
  final double? kenBurnsEndY;
  final void Function(double x, double y)? onKenBurnsPointSelected;
  final bool transformToolActive;
  final bool transformCropMode;
  final void Function(double x, double y)? onTransformPositionChanged;
  final ValueChanged<double>? onTransformScaleChanged;
  final void Function({
    double? left,
    double? top,
    double? right,
    double? bottom,
  })?
  onTransformCropChanged;
  final VoidCallback? onTransformInteractionStart;
  final VoidCallback? onTransformInteractionEnd;
  final bool chromaColorPickerActive;
  final bool chromaTransparencyPreview;
  final bool chromaColorSampling;
  final void Function(Offset point, Size previewSize)?
  onChromaColorPointSelected;
  final bool whiteBalanceColorPickerActive;
  final bool whiteBalanceColorSampling;
  final void Function(Offset point, Size previewSize)?
  onWhiteBalanceColorPointSelected;
  final VoidCallback? onImportRequested;
  final VideoPreviewMask? mask;
  final bool maskToolActive;
  final PreviewMaskGeometryChanged? onMaskGeometryChanged;

  @override
  Widget build(BuildContext context) {
    final currentItem = item;
    final currentPlayer = player;
    final currentVideoController = videoController;
    final hasTimelineVisuals =
        videoOverlayEntries.isNotEmpty ||
        imageOverlayEntries.isNotEmpty ||
        transitionPreviewEntries.isNotEmpty ||
        textOverlayEntries.isNotEmpty;

    if (currentItem == null) {
      if (hasTimelineVisuals) {
        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: TgiColors.black),
            ..._buildVideoOverlays(),
            ..._buildImageOverlays(),
            _TimelineTransitionPreviewLayer(
              entries: transitionPreviewEntries,
              playing: transitionPreviewPlaying,
            ),
            ..._buildTextOverlays(),
            if (kenBurnsToolActive)
              _KenBurnsToolOverlay(
                pickStart: kenBurnsPickStart,
                startX: kenBurnsStartX,
                startY: kenBurnsStartY,
                endX: kenBurnsEndX,
                endY: kenBurnsEndY,
                onPointSelected: onKenBurnsPointSelected,
              ),
            if (chromaColorPickerActive)
              _ChromaColorPickerOverlay(
                sampling: chromaColorSampling,
                onPointSelected: onChromaColorPointSelected,
              ),
            if (whiteBalanceColorPickerActive)
              _ChromaColorPickerOverlay(
                sampling: whiteBalanceColorSampling,
                instruction: 'Clique em um ponto branco ou cinza',
                samplingLabel: 'Calculando balanço de branco...',
                onPointSelected: onWhiteBalanceColorPointSelected,
              ),
          ],
        );
      }
      return _PreviewMessage(
        icon: Icons.video_library_outlined,
        title: 'Nenhum vídeo ou imagem na timeline',
        message: 'Adicione uma mídia para começar a editar.',
        actionLabel: 'Adicionar vídeo ou imagem',
        onAction: onImportRequested,
      );
    }

    final error = errorMessage;
    if (error != null) {
      return _PreviewMessage(
        icon: Icons.error_outline,
        title: 'N\u00E3o foi poss\u00EDvel abrir o preview',
        message: error,
      );
    }

    if (currentPlayer == null || loadedItemId != currentItem.id) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return StreamBuilder<bool>(
      stream: currentPlayer.stream.buffering,
      initialData: currentPlayer.state.buffering,
      builder: (context, snapshot) {
        final buffering = snapshot.data == true;
        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: TgiColors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (visualAdjustments.chromaKeyEnabled &&
                      chromaTransparencyPreview)
                    const _ChromaTransparencyGrid(
                      key: ValueKey('chroma_transparency_grid'),
                    ),
                  Opacity(
                    opacity: _clampOpacity(videoOpacity),
                    child: _buildAdjustedVideoSurface(currentVideoController),
                  ),
                ],
              ),
            ),
            if (mask != null) _PreviewMaskEffect(mask: mask!),
            ..._buildVideoOverlays(),
            ..._buildImageOverlays(),
            _TimelineTransitionPreviewLayer(
              entries: transitionPreviewEntries,
              playing: transitionPreviewPlaying,
            ),
            ..._buildTextOverlays(),
            if (loading || buffering)
              const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            if (rawPreviewFallback || previewDownscaled)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: _PreviewPerformanceNotice(
                  rawPreviewFallback: rawPreviewFallback,
                ),
              ),
            if (visualAdjustments.hasAnyEffect)
              Positioned(
                left: 12,
                top: 12,
                child: _PreviewEffectBadge(
                  label: _visualAdjustmentLabel(visualAdjustments),
                ),
              ),
            if (transformToolActive)
              _TransformCropInteractionOverlay(
                cropMode: transformCropMode,
                adjustments: visualAdjustments,
                onPositionChanged: onTransformPositionChanged,
                onScaleChanged: onTransformScaleChanged,
                onCropChanged: onTransformCropChanged,
                onInteractionStart: onTransformInteractionStart,
                onInteractionEnd: onTransformInteractionEnd,
              ),
            if (kenBurnsToolActive)
              _KenBurnsToolOverlay(
                pickStart: kenBurnsPickStart,
                startX: kenBurnsStartX,
                startY: kenBurnsStartY,
                endX: kenBurnsEndX,
                endY: kenBurnsEndY,
                onPointSelected: onKenBurnsPointSelected,
              ),
            if (chromaColorPickerActive)
              _ChromaColorPickerOverlay(
                sampling: chromaColorSampling,
                onPointSelected: onChromaColorPointSelected,
              ),
            if (whiteBalanceColorPickerActive)
              _ChromaColorPickerOverlay(
                sampling: whiteBalanceColorSampling,
                instruction: 'Clique em um ponto branco ou cinza',
                samplingLabel: 'Calculando balanço de branco...',
                onPointSelected: onWhiteBalanceColorPointSelected,
              ),
            if (mask != null && maskToolActive)
              _PreviewMaskInteraction(
                mask: mask!,
                onChanged: onMaskGeometryChanged,
              ),
          ],
        );
      },
    );
  }

  Widget _buildAdjustedVideoSurface(VideoController? currentVideoController) {
    final video = _ClipTransformPreviewSource(
      offsetX: visualAdjustments.transformOffsetX,
      offsetY: visualAdjustments.transformOffsetY,
      scale: visualAdjustments.transformScale,
      rotationDegrees: visualAdjustments.rotationDegrees,
      flipHorizontal: visualAdjustments.flipHorizontal,
      flipVertical: visualAdjustments.flipVertical,
      child: _CroppedPreviewSource(
        cropLeft: visualAdjustments.cropLeft,
        cropTop: visualAdjustments.cropTop,
        cropRight: visualAdjustments.cropRight,
        cropBottom: visualAdjustments.cropBottom,
        child: _KenBurnsCameraPreviewSource(
          adjustments: visualAdjustments,
          timelinePosition: timelinePosition,
          child: _buildVideoSurface(currentVideoController),
        ),
      ),
    );
    final chromaKeyed = _applyPreviewChromaKey(video, visualAdjustments);
    final colorFilter = _previewColorFilter(visualAdjustments);
    if (colorFilter == null) {
      return chromaKeyed;
    }
    return ColorFiltered(colorFilter: colorFilter, child: chromaKeyed);
  }

  Widget _buildVideoSurface(VideoController? currentVideoController) {
    if (rawPreviewFallback) {
      return previewImage != null
          ? RawImage(
              key: ValueKey(previewFrameSerial),
              image: previewImage,
              fit: cropMainVideoToFill ? BoxFit.cover : BoxFit.contain,
              filterQuality: FilterQuality.low,
            )
          : _moviePlaceholder();
    }

    if (currentVideoController == null) {
      return _moviePlaceholder();
    }

    return Video(
      controller: currentVideoController,
      fit: cropMainVideoToFill ? BoxFit.cover : BoxFit.contain,
      fill: TgiColors.black,
      filterQuality: FilterQuality.low,
      controls: NoVideoControls,
      wakelock: false,
    );
  }

  Widget _moviePlaceholder() {
    return Center(
      child: Icon(
        Icons.movie_outlined,
        size: 52,
        color: TgiColors.textSecondary,
      ),
    );
  }

  List<Widget> _buildVideoOverlays() {
    return [
      for (final entry in videoOverlayEntries)
        _VideoOverlay(
          key: ValueKey(entry.clipId),
          entry: entry,
          playing: transitionPreviewPlaying,
          onMoved: onVideoOverlayMoved,
          onResized: entry.isActive ? onVideoOverlayResized : null,
          onMaskGeometryChanged: onMaskGeometryChanged,
          onTap: onVideoOverlayTap != null
              ? () => onVideoOverlayTap!(entry.timelineGroupId)
              : null,
        ),
    ];
  }

  List<Widget> _buildImageOverlays() {
    return [
      for (final entry in imageOverlayEntries)
        _ImageOverlay(
          key: ValueKey(entry.clipId),
          item: entry.item,
          clipId: entry.clipId,
          active: entry.isActive,
          overlayX: entry.overlayX,
          overlayY: entry.overlayY,
          overlayScale: entry.overlayScale,
          imageFit: entry.imageFit,
          opacity: entry.opacity,
          cropLeft: entry.cropLeft,
          cropTop: entry.cropTop,
          cropRight: entry.cropRight,
          cropBottom: entry.cropBottom,
          transformOffsetX: entry.transformOffsetX,
          transformOffsetY: entry.transformOffsetY,
          transformScale: entry.transformScale,
          rotationDegrees: entry.rotationDegrees,
          flipHorizontal: entry.flipHorizontal,
          flipVertical: entry.flipVertical,
          onMoved: onImageOverlayMoved,
          onResized: entry.isActive ? onImageOverlayResized : null,
          onTap: onImageOverlayTap != null
              ? () => onImageOverlayTap!(entry.timelineGroupId)
              : null,
        ),
    ];
  }

  List<Widget> _buildTextOverlays() {
    return [
      for (final entry in textOverlayEntries)
        _TextOverlay(
          key: ValueKey(entry.clipId),
          entry: entry,
          onMoved: onTextOverlayMoved,
          onTap: onTextOverlayTap != null
              ? () => onTextOverlayTap!(entry.timelineGroupId)
              : null,
          onEdit: onTextOverlayEdit != null
              ? () => onTextOverlayEdit!(entry.clipId)
              : null,
          onInteractionStart: onTextOverlayInteractionStart,
          onInteractionEnd: onTextOverlayInteractionEnd,
        ),
    ];
  }
}

class _PreviewMaskEffect extends StatelessWidget {
  const _PreviewMaskEffect({required this.mask});

  final VideoPreviewMask mask;

  @override
  Widget build(BuildContext context) {
    final clipper = _PreviewMaskClipper(mask);
    final intensity = mask.intensity.clamp(0.05, 1.0);
    final child = switch (mask.effect) {
      VideoMaskEffect.blur => BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: 2 + intensity * 22,
          sigmaY: 2 + intensity * 22,
        ),
        child: ColoredBox(color: Colors.white.withValues(alpha: 0.001)),
      ),
      VideoMaskEffect.pixelate => BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: 1 + intensity * 7,
          sigmaY: 1 + intensity * 7,
        ),
        child: CustomPaint(
          painter: _PixelMaskPainter(intensity),
          child: const SizedBox.expand(),
        ),
      ),
      VideoMaskEffect.darken => ColoredBox(
        color: Colors.black.withValues(alpha: intensity * 0.78),
      ),
    };
    return Positioned.fill(
      child: IgnorePointer(
        child: ClipPath(clipper: clipper, child: child),
      ),
    );
  }
}

class _PreviewMaskInteraction extends StatefulWidget {
  const _PreviewMaskInteraction({required this.mask, this.onChanged});

  final VideoPreviewMask mask;
  final PreviewMaskGeometryChanged? onChanged;

  @override
  State<_PreviewMaskInteraction> createState() =>
      _PreviewMaskInteractionState();
}

class _PreviewMaskInteractionState extends State<_PreviewMaskInteraction> {
  late double _x = widget.mask.x;
  late double _y = widget.mask.y;
  late double _width = widget.mask.width;
  late double _height = widget.mask.height;
  bool _resizing = false;
  bool _activeDrag = false;

  @override
  void didUpdateWidget(covariant _PreviewMaskInteraction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_activeDrag) {
      _x = widget.mask.x;
      _y = widget.mask.y;
      _width = widget.mask.width;
      _height = widget.mask.height;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final rect = _maskRect(size, _x, _y, _width, _height);
          return GestureDetector(
            key: const ValueKey('preview_mask_interaction'),
            behavior: HitTestBehavior.opaque,
            onPanStart: (details) {
              final nearHandle =
                  (details.localPosition - rect.bottomRight).distance <= 30;
              _resizing = nearHandle;
              _activeDrag =
                  nearHandle ||
                  rect.inflate(12).contains(details.localPosition);
            },
            onPanUpdate: (details) {
              if (!_activeDrag || size.width <= 0 || size.height <= 0) return;
              setState(() {
                if (_resizing) {
                  _width = (_width + details.delta.dx * 2 / size.width).clamp(
                    0.04,
                    1.0,
                  );
                  _height = (_height + details.delta.dy * 2 / size.height)
                      .clamp(0.04, 1.0);
                } else {
                  _x = (_x + details.delta.dx / size.width).clamp(0.0, 1.0);
                  _y = (_y + details.delta.dy / size.height).clamp(0.0, 1.0);
                }
              });
            },
            onPanCancel: () => _activeDrag = false,
            onPanEnd: (_) {
              if (!_activeDrag) return;
              _activeDrag = false;
              widget.onChanged?.call(
                x: _x,
                y: _y,
                width: _width,
                height: _height,
              );
            },
            child: CustomPaint(
              painter: _MaskGuidePainter(
                shape: widget.mask.shape,
                rect: rect,
                feather: widget.mask.feather,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PreviewMaskClipper extends CustomClipper<Path> {
  const _PreviewMaskClipper(this.mask);

  final VideoPreviewMask mask;

  @override
  Path getClip(Size size) {
    final rect = _maskRect(size, mask.x, mask.y, mask.width, mask.height);
    final shape = Path();
    if (mask.shape == VideoMaskShape.ellipse) {
      shape.addOval(rect);
    } else {
      shape.addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)));
    }
    if (!mask.inverted) return shape;
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addPath(shape, Offset.zero);
  }

  @override
  bool shouldReclip(covariant _PreviewMaskClipper oldClipper) =>
      oldClipper.mask != mask;
}

class _MaskGuidePainter extends CustomPainter {
  const _MaskGuidePainter({
    required this.shape,
    required this.rect,
    required this.feather,
  });

  final VideoMaskShape shape;
  final Rect rect;
  final double feather;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Paint()
      ..color = TgiColors.accentSoft
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final fill = Paint()
      ..color = TgiColors.accent.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    if (shape == VideoMaskShape.ellipse) {
      canvas.drawOval(rect, fill);
      canvas.drawOval(rect, outline);
    } else {
      final rounded = RRect.fromRectAndRadius(rect, const Radius.circular(6));
      canvas.drawRRect(rounded, fill);
      canvas.drawRRect(rounded, outline);
    }
    final featherInset = math.min(
      rect.shortestSide / 3,
      feather * rect.shortestSide,
    );
    if (featherInset > 1) {
      final featherPaint = Paint()
        ..color = TgiColors.white.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      final inner = rect.deflate(featherInset);
      if (shape == VideoMaskShape.ellipse) {
        canvas.drawOval(inner, featherPaint);
      } else {
        canvas.drawRect(inner, featherPaint);
      }
    }
    canvas.drawCircle(
      rect.bottomRight,
      7,
      Paint()..color = TgiColors.accentSoft,
    );
    canvas.drawCircle(rect.center, 4, Paint()..color = TgiColors.white);
  }

  @override
  bool shouldRepaint(covariant _MaskGuidePainter oldDelegate) =>
      oldDelegate.rect != rect ||
      oldDelegate.shape != shape ||
      oldDelegate.feather != feather;
}

class _PixelMaskPainter extends CustomPainter {
  const _PixelMaskPainter(this.intensity);

  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = 5 + intensity * 16;
    final paint = Paint()..style = PaintingStyle.fill;
    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = 0.0; x < size.width; x += cell) {
        final dark = ((x / cell).floor() + (y / cell).floor()).isEven;
        paint.color = (dark ? Colors.black : Colors.white).withValues(
          alpha: 0.025 + intensity * 0.045,
        );
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PixelMaskPainter oldDelegate) =>
      oldDelegate.intensity != intensity;
}

Rect _maskRect(Size size, double x, double y, double width, double height) {
  final rectWidth = size.width * width.clamp(0.04, 1.0);
  final rectHeight = size.height * height.clamp(0.04, 1.0);
  final center = Offset(
    size.width * x.clamp(0.0, 1.0),
    size.height * y.clamp(0.0, 1.0),
  );
  return Rect.fromCenter(center: center, width: rectWidth, height: rectHeight);
}

class _ChromaColorPickerOverlay extends StatefulWidget {
  const _ChromaColorPickerOverlay({
    required this.sampling,
    required this.onPointSelected,
    this.instruction = 'Clique na cor que deseja remover',
    this.samplingLabel = 'Lendo a cor do quadro...',
  });

  final bool sampling;
  final void Function(Offset point, Size previewSize)? onPointSelected;
  final String instruction;
  final String samplingLabel;

  @override
  State<_ChromaColorPickerOverlay> createState() =>
      _ChromaColorPickerOverlayState();
}

class _ChromaColorPickerOverlayState extends State<_ChromaColorPickerOverlay> {
  Offset? _hoverPosition;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          return MouseRegion(
            cursor: widget.sampling
                ? SystemMouseCursors.wait
                : SystemMouseCursors.click,
            onHover: widget.sampling
                ? null
                : (event) =>
                      setState(() => _hoverPosition = event.localPosition),
            onExit: (_) => setState(() => _hoverPosition = null),
            child: GestureDetector(
              key: const ValueKey('chroma_preview_color_picker'),
              behavior: HitTestBehavior.opaque,
              onTapDown: widget.sampling
                  ? null
                  : (details) => widget.onPointSelected?.call(
                      details.localPosition,
                      size,
                    ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: TgiColors.accentSoft, width: 2),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_hoverPosition != null && !widget.sampling)
                      IgnorePointer(
                        child: CustomPaint(
                          painter: _ColorPickerCrosshairPainter(
                            position: _hoverPosition!,
                          ),
                        ),
                      ),
                    Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.all(TgiSpacing.sm),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: TgiColors.black.withValues(alpha: 0.82),
                            borderRadius: BorderRadius.circular(TgiRadii.md),
                            border: Border.all(color: TgiColors.accentSoft),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: TgiSpacing.sm,
                              vertical: TgiSpacing.xs,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.colorize_outlined,
                                  size: 17,
                                  color: TgiColors.accentSoft,
                                ),
                                const SizedBox(width: TgiSpacing.xs),
                                Text(
                                  widget.sampling
                                      ? widget.samplingLabel
                                      : widget.instruction,
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(
                                        color: TgiColors.white,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (widget.sampling)
                      const Center(
                        child: SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ColorPickerCrosshairPainter extends CustomPainter {
  const _ColorPickerCrosshairPainter({required this.position});

  final Offset position;

  @override
  void paint(Canvas canvas, Size size) {
    final shadow = Paint()
      ..color = TgiColors.black.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    final foreground = Paint()
      ..color = TgiColors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final paint in [shadow, foreground]) {
      canvas.drawCircle(position, 10, paint);
      canvas.drawLine(
        Offset(position.dx - 17, position.dy),
        Offset(position.dx - 7, position.dy),
        paint,
      );
      canvas.drawLine(
        Offset(position.dx + 7, position.dy),
        Offset(position.dx + 17, position.dy),
        paint,
      );
      canvas.drawLine(
        Offset(position.dx, position.dy - 17),
        Offset(position.dx, position.dy - 7),
        paint,
      );
      canvas.drawLine(
        Offset(position.dx, position.dy + 7),
        Offset(position.dx, position.dy + 17),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ColorPickerCrosshairPainter oldDelegate) =>
      oldDelegate.position != position;
}

Offset? _previewPointToSourcePoint({
  required Offset previewPoint,
  required Size previewSize,
  required Size sourceSize,
  required VideoPreviewVisualAdjustments adjustments,
  required Duration timelinePosition,
}) {
  if (previewSize.isEmpty || sourceSize.isEmpty) {
    return null;
  }
  var point = previewPoint;
  final center = Offset(previewSize.width / 2, previewSize.height / 2);

  final offsetX = adjustments.transformOffsetX.isFinite
      ? adjustments.transformOffsetX.clamp(-1.0, 1.0)
      : 0.0;
  final offsetY = adjustments.transformOffsetY.isFinite
      ? adjustments.transformOffsetY.clamp(-1.0, 1.0)
      : 0.0;
  point -= Offset(
    offsetX * previewSize.width / 2,
    offsetY * previewSize.height / 2,
  );

  final angle =
      -(adjustments.rotationDegrees.isFinite
          ? adjustments.rotationDegrees
          : 0.0) *
      math.pi /
      180;
  final relative = point - center;
  point =
      center +
      Offset(
        relative.dx * math.cos(angle) - relative.dy * math.sin(angle),
        relative.dx * math.sin(angle) + relative.dy * math.cos(angle),
      );

  final transformScale = adjustments.transformScale.isFinite
      ? adjustments.transformScale.clamp(0.1, 8.0).toDouble()
      : 1.0;
  final transformScaleX =
      transformScale * (adjustments.flipHorizontal ? -1 : 1);
  final transformScaleY = transformScale * (adjustments.flipVertical ? -1 : 1);
  point = Offset(
    center.dx + (point.dx - center.dx) / transformScaleX,
    center.dy + (point.dy - center.dy) / transformScaleY,
  );

  final cropLeft = _safeUnit(adjustments.cropLeft);
  final cropTop = _safeUnit(adjustments.cropTop);
  final cropRight = _safeUnit(adjustments.cropRight);
  final cropBottom = _safeUnit(adjustments.cropBottom);
  final cropWidth = math.max(0.05, 1 - cropLeft - cropRight);
  final cropHeight = math.max(0.05, 1 - cropTop - cropBottom);
  final cropAnchor = Offset(
    (cropLeft + cropWidth / 2) * previewSize.width,
    (cropTop + cropHeight / 2) * previewSize.height,
  );
  point = Offset(
    cropAnchor.dx + (point.dx - cropAnchor.dx) * cropWidth,
    cropAnchor.dy + (point.dy - cropAnchor.dy) * cropHeight,
  );

  if (adjustments.kenBurnsEnabled && adjustments.duration > Duration.zero) {
    final progress = _kenBurnsProgress(adjustments, timelinePosition);
    final scale =
        adjustments.startOverlayScale +
        (adjustments.endOverlayScale - adjustments.startOverlayScale) *
            progress;
    final x =
        adjustments.startOverlayX +
        (adjustments.endOverlayX - adjustments.startOverlayX) * progress;
    final y =
        adjustments.startOverlayY +
        (adjustments.endOverlayY - adjustments.startOverlayY) * progress;
    final safeScale = scale.isFinite ? scale.clamp(1.0, 8.0).toDouble() : 1.0;
    final anchor = Offset(
      _safeUnit(x) * previewSize.width,
      _safeUnit(y) * previewSize.height,
    );
    point = anchor + (point - anchor) / safeScale;
  }

  final fitScale = math.min(
    previewSize.width / sourceSize.width,
    previewSize.height / sourceSize.height,
  );
  final fittedSize = Size(
    sourceSize.width * fitScale,
    sourceSize.height * fitScale,
  );
  final fittedRect = Rect.fromCenter(
    center: center,
    width: fittedSize.width,
    height: fittedSize.height,
  );
  if (!fittedRect.contains(point)) {
    return null;
  }
  return Offset(
    ((point.dx - fittedRect.left) / fitScale)
        .clamp(0.0, sourceSize.width - 1)
        .toDouble(),
    ((point.dy - fittedRect.top) / fitScale)
        .clamp(0.0, sourceSize.height - 1)
        .toDouble(),
  );
}

double _safeUnit(double value) {
  if (!value.isFinite) {
    return 0;
  }
  return value.clamp(0.0, 1.0).toDouble();
}

double _kenBurnsProgress(
  VideoPreviewVisualAdjustments adjustments,
  Duration timelinePosition,
) {
  final start =
      adjustments.timelineStart +
      Duration(
        microseconds:
            (adjustments.duration.inMicroseconds * adjustments.kenBurnsStart)
                .round(),
      );
  final end =
      adjustments.timelineStart +
      Duration(
        microseconds:
            (adjustments.duration.inMicroseconds * adjustments.kenBurnsEnd)
                .round(),
      );
  final span = end - start;
  if (span <= Duration.zero) {
    return 1;
  }
  final progress =
      (timelinePosition - start).inMicroseconds / span.inMicroseconds;
  return progress.isFinite ? progress.clamp(0.0, 1.0).toDouble() : 1;
}

int _averageBgraColor(
  List<int> bytes, {
  required int width,
  required int height,
  required int rowBytes,
  required int x,
  required int y,
}) {
  const radius = 2;
  var red = 0;
  var green = 0;
  var blue = 0;
  var count = 0;
  final startX = math.max(0, x - radius);
  final endX = math.min(width - 1, x + radius);
  final startY = math.max(0, y - radius);
  final endY = math.min(height - 1, y + radius);
  for (var sampleY = startY; sampleY <= endY; sampleY++) {
    for (var sampleX = startX; sampleX <= endX; sampleX++) {
      final offset = sampleY * rowBytes + sampleX * 4;
      blue += bytes[offset];
      green += bytes[offset + 1];
      red += bytes[offset + 2];
      count++;
    }
  }
  return 0xFF000000 |
      ((red ~/ count) << 16) |
      ((green ~/ count) << 8) |
      (blue ~/ count);
}

VideoColorAnalysis _analyzeBgraFrame(
  List<int> bytes, {
  required int width,
  required int height,
  required int rowBytes,
}) {
  const bins = 64;
  final luma = List<int>.filled(bins, 0);
  final red = List<int>.filled(bins, 0);
  final green = List<int>.filled(bins, 0);
  final blue = List<int>.filled(bins, 0);
  final pixelCount = width * height;
  final step = math.max(1, math.sqrt(pixelCount / 150000).floor());
  var redTotal = 0;
  var greenTotal = 0;
  var blueTotal = 0;
  var samples = 0;
  for (var y = 0; y < height; y += step) {
    for (var x = 0; x < width; x += step) {
      final offset = y * rowBytes + x * 4;
      final b = bytes[offset];
      final g = bytes[offset + 1];
      final r = bytes[offset + 2];
      final luminance = (r * 0.2126 + g * 0.7152 + b * 0.0722).round();
      red[(r * bins ~/ 256).clamp(0, bins - 1)]++;
      green[(g * bins ~/ 256).clamp(0, bins - 1)]++;
      blue[(b * bins ~/ 256).clamp(0, bins - 1)]++;
      luma[(luminance * bins ~/ 256).clamp(0, bins - 1)]++;
      redTotal += r;
      greenTotal += g;
      blueTotal += b;
      samples++;
    }
  }
  List<double> normalize(List<int> values) {
    final maximum = values.fold<int>(1, math.max);
    return [
      for (final value in values) math.sqrt(value / maximum).clamp(0.0, 1.0),
    ];
  }

  return VideoColorAnalysis(
    luma: normalize(luma),
    red: normalize(red),
    green: normalize(green),
    blue: normalize(blue),
    averageColor:
        0xFF000000 |
        ((redTotal ~/ samples) << 16) |
        ((greenTotal ~/ samples) << 8) |
        (blueTotal ~/ samples),
  );
}

class _TransformCropInteractionOverlay extends StatelessWidget {
  const _TransformCropInteractionOverlay({
    required this.cropMode,
    required this.adjustments,
    required this.onPositionChanged,
    required this.onScaleChanged,
    required this.onCropChanged,
    required this.onInteractionStart,
    required this.onInteractionEnd,
  });

  final bool cropMode;
  final VideoPreviewVisualAdjustments adjustments;
  final void Function(double x, double y)? onPositionChanged;
  final ValueChanged<double>? onScaleChanged;
  final void Function({
    double? left,
    double? top,
    double? right,
    double? bottom,
  })?
  onCropChanged;
  final VoidCallback? onInteractionStart;
  final VoidCallback? onInteractionEnd;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          if (cropMode) {
            return _buildCropOverlay(size);
          }
          return Listener(
            onPointerSignal: (event) {
              if (event is! PointerScrollEvent || onScaleChanged == null) {
                return;
              }
              final factor = event.scrollDelta.dy > 0 ? 0.94 : 1.06;
              onScaleChanged!(
                (adjustments.transformScale * factor)
                    .clamp(0.1, 8.0)
                    .toDouble(),
              );
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.move,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanUpdate: onPositionChanged == null
                    ? null
                    : (details) {
                        final nextX =
                            adjustments.transformOffsetX +
                            (details.delta.dx / math.max(1, size.width)) * 2;
                        final nextY =
                            adjustments.transformOffsetY +
                            (details.delta.dy / math.max(1, size.height)) * 2;
                        onPositionChanged!(
                          nextX.clamp(-1.0, 1.0).toDouble(),
                          nextY.clamp(-1.0, 1.0).toDouble(),
                        );
                      },
                onPanStart: onPositionChanged == null
                    ? null
                    : (_) => onInteractionStart?.call(),
                onPanEnd: onPositionChanged == null
                    ? null
                    : (_) => onInteractionEnd?.call(),
                onPanCancel: onPositionChanged == null
                    ? null
                    : () => onInteractionEnd?.call(),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: TgiColors.accent, width: 1.5),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.open_with_outlined,
                      color: TgiColors.accent,
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

  Widget _buildCropOverlay(Size size) {
    final left = adjustments.cropLeft.clamp(0.0, 0.95).toDouble();
    final top = adjustments.cropTop.clamp(0.0, 0.95).toDouble();
    final right = adjustments.cropRight.clamp(0.0, 0.95 - left).toDouble();
    final bottom = adjustments.cropBottom.clamp(0.0, 0.95 - top).toDouble();
    final rect = Rect.fromLTRB(
      left * size.width,
      top * size.height,
      (1 - right) * size.width,
      (1 - bottom) * size.height,
    );
    const handle = 14.0;
    return Stack(
      children: [
        Positioned.fromRect(
          rect: rect,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: TgiColors.accent, width: 2),
              ),
              child: CustomPaint(painter: _CropGridPainter()),
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          right: 0,
          height: rect.top,
          child: _shade(),
        ),
        Positioned(
          left: 0,
          top: rect.bottom,
          right: 0,
          bottom: 0,
          child: _shade(),
        ),
        Positioned(
          left: 0,
          top: rect.top,
          width: rect.left,
          height: rect.height,
          child: _shade(),
        ),
        Positioned(
          left: rect.right,
          top: rect.top,
          right: 0,
          height: rect.height,
          child: _shade(),
        ),
        _cropHandle(
          left: rect.left - handle / 2,
          top: rect.top,
          width: handle,
          height: rect.height,
          cursor: SystemMouseCursors.resizeLeftRight,
          onPan: (delta) => onCropChanged?.call(
            left: (left + delta.dx / math.max(1, size.width))
                .clamp(0.0, 0.95 - right)
                .toDouble(),
          ),
        ),
        _cropHandle(
          left: rect.right - handle / 2,
          top: rect.top,
          width: handle,
          height: rect.height,
          cursor: SystemMouseCursors.resizeLeftRight,
          onPan: (delta) => onCropChanged?.call(
            right: (right - delta.dx / math.max(1, size.width))
                .clamp(0.0, 0.95 - left)
                .toDouble(),
          ),
        ),
        _cropHandle(
          left: rect.left,
          top: rect.top - handle / 2,
          width: rect.width,
          height: handle,
          cursor: SystemMouseCursors.resizeUpDown,
          onPan: (delta) => onCropChanged?.call(
            top: (top + delta.dy / math.max(1, size.height))
                .clamp(0.0, 0.95 - bottom)
                .toDouble(),
          ),
        ),
        _cropHandle(
          left: rect.left,
          top: rect.bottom - handle / 2,
          width: rect.width,
          height: handle,
          cursor: SystemMouseCursors.resizeUpDown,
          onPan: (delta) => onCropChanged?.call(
            bottom: (bottom - delta.dy / math.max(1, size.height))
                .clamp(0.0, 0.95 - top)
                .toDouble(),
          ),
        ),
      ],
    );
  }

  Widget _shade() => ColoredBox(color: TgiColors.black.withValues(alpha: 0.56));

  Widget _cropHandle({
    required double left,
    required double top,
    required double width,
    required double height,
    required MouseCursor cursor,
    required ValueChanged<Offset> onPan,
  }) {
    return Positioned(
      left: left,
      top: top,
      width: math.max(1, width),
      height: math.max(1, height),
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanStart: (_) => onInteractionStart?.call(),
          onPanUpdate: (details) => onPan(details.delta),
          onPanEnd: (_) => onInteractionEnd?.call(),
          onPanCancel: () => onInteractionEnd?.call(),
        ),
      ),
    );
  }
}

class _CropGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = TgiColors.white.withValues(alpha: 0.45)
      ..strokeWidth = 0.8;
    for (final fraction in const [1 / 3, 2 / 3]) {
      canvas.drawLine(
        Offset(size.width * fraction, 0),
        Offset(size.width * fraction, size.height),
        paint,
      );
      canvas.drawLine(
        Offset(0, size.height * fraction),
        Offset(size.width, size.height * fraction),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ClipTransformPreviewSource extends StatelessWidget {
  const _ClipTransformPreviewSource({
    required this.child,
    required this.offsetX,
    required this.offsetY,
    required this.scale,
    required this.rotationDegrees,
    required this.flipHorizontal,
    required this.flipVertical,
  });

  final Widget child;
  final double offsetX;
  final double offsetY;
  final double scale;
  final double rotationDegrees;
  final bool flipHorizontal;
  final bool flipVertical;

  @override
  Widget build(BuildContext context) {
    final safeX = offsetX.isFinite ? offsetX.clamp(-1.0, 1.0) : 0.0;
    final safeY = offsetY.isFinite ? offsetY.clamp(-1.0, 1.0) : 0.0;
    final safeScale = scale.isFinite ? scale.clamp(0.1, 8.0) : 1.0;
    final radians =
        (rotationDegrees.isFinite ? rotationDegrees : 0.0) * math.pi / 180;
    return ClipRect(
      child: FractionalTranslation(
        translation: Offset(safeX / 2, safeY / 2),
        child: Transform.rotate(
          angle: radians,
          alignment: Alignment.center,
          child: Transform.scale(
            scaleX: safeScale * (flipHorizontal ? -1 : 1),
            scaleY: safeScale * (flipVertical ? -1 : 1),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _CroppedPreviewSource extends StatelessWidget {
  const _CroppedPreviewSource({
    required this.child,
    required this.cropLeft,
    required this.cropTop,
    required this.cropRight,
    required this.cropBottom,
  });

  final Widget child;
  final double cropLeft;
  final double cropTop;
  final double cropRight;
  final double cropBottom;

  @override
  Widget build(BuildContext context) {
    final left = _unit(cropLeft);
    final top = _unit(cropTop);
    final right = _unit(cropRight);
    final bottom = _unit(cropBottom);
    if (left <= 0.000001 &&
        top <= 0.000001 &&
        right <= 0.000001 &&
        bottom <= 0.000001) {
      return child;
    }
    final width = math.max(0.05, 1 - left - right);
    final height = math.max(0.05, 1 - top - bottom);
    final centerX = left + width / 2;
    final centerY = top + height / 2;
    return ClipRect(
      child: Transform.scale(
        scaleX: 1 / width,
        scaleY: 1 / height,
        alignment: Alignment(centerX * 2 - 1, centerY * 2 - 1),
        child: child,
      ),
    );
  }

  double _unit(double value) {
    if (value.isNaN || value.isInfinite) {
      return 0;
    }
    return value.clamp(0.0, 1.0).toDouble();
  }
}

class _KenBurnsCameraPreviewSource extends StatelessWidget {
  const _KenBurnsCameraPreviewSource({
    required this.child,
    required this.adjustments,
    required this.timelinePosition,
  });

  final Widget child;
  final VideoPreviewVisualAdjustments adjustments;
  final Duration timelinePosition;

  @override
  Widget build(BuildContext context) {
    if (!adjustments.kenBurnsEnabled || adjustments.duration <= Duration.zero) {
      return child;
    }
    final progress = _progress();
    final scale =
        adjustments.startOverlayScale +
        (adjustments.endOverlayScale - adjustments.startOverlayScale) *
            progress;
    final x =
        adjustments.startOverlayX +
        (adjustments.endOverlayX - adjustments.startOverlayX) * progress;
    final y =
        adjustments.startOverlayY +
        (adjustments.endOverlayY - adjustments.startOverlayY) * progress;
    final safeScale = scale.isNaN || scale.isInfinite
        ? 1.0
        : scale.clamp(1.0, 8.0).toDouble();
    return ClipRect(
      child: Transform.scale(
        scale: safeScale,
        alignment: Alignment(_unit(x) * 2 - 1, _unit(y) * 2 - 1),
        child: child,
      ),
    );
  }

  double _progress() {
    final start =
        adjustments.timelineStart +
        Duration(
          microseconds:
              (adjustments.duration.inMicroseconds * adjustments.kenBurnsStart)
                  .round(),
        );
    final end =
        adjustments.timelineStart +
        Duration(
          microseconds:
              (adjustments.duration.inMicroseconds * adjustments.kenBurnsEnd)
                  .round(),
        );
    final span = end - start;
    if (span <= Duration.zero) {
      return 1;
    }
    final value =
        (timelinePosition - start).inMicroseconds / span.inMicroseconds;
    if (value.isNaN || value.isInfinite) {
      return 1;
    }
    return value.clamp(0.0, 1.0).toDouble();
  }

  double _unit(double value) {
    if (value.isNaN || value.isInfinite) {
      return 0.5;
    }
    return value.clamp(0.0, 1.0).toDouble();
  }
}

class _KenBurnsToolOverlay extends StatelessWidget {
  const _KenBurnsToolOverlay({
    required this.pickStart,
    required this.onPointSelected,
    this.startX,
    this.startY,
    this.endX,
    this.endY,
  });

  final bool pickStart;
  final double? startX;
  final double? startY;
  final double? endX;
  final double? endY;
  final void Function(double x, double y)? onPointSelected;

  @override
  Widget build(BuildContext context) {
    final callback = onPointSelected;
    return Positioned.fill(
      child: MouseRegion(
        cursor: callback == null
            ? MouseCursor.defer
            : SystemMouseCursors.precise,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: callback == null
              ? null
              : (details) {
                  final box = context.findRenderObject();
                  if (box is! RenderBox || box.size.isEmpty) {
                    return;
                  }
                  final local = details.localPosition;
                  callback(
                    (local.dx / box.size.width).clamp(0.0, 1.0).toDouble(),
                    (local.dy / box.size.height).clamp(0.0, 1.0).toDouble(),
                  );
                },
          child: CustomPaint(
            painter: _KenBurnsToolPainter(
              pickStart: pickStart,
              startX: startX,
              startY: startY,
              endX: endX,
              endY: endY,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: TgiColors.scrim,
                    border: Border.all(color: TgiColors.accentMuted),
                    borderRadius: BorderRadius.circular(TgiRadii.md),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Text(
                      pickStart
                          ? 'Clique no preview para marcar o INICIO da camera'
                          : 'Clique no preview para marcar o FIM da camera',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: TgiColors.textPrimary,
                        fontWeight: FontWeight.w800,
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
  }
}

class _KenBurnsToolPainter extends CustomPainter {
  const _KenBurnsToolPainter({
    required this.pickStart,
    this.startX,
    this.startY,
    this.endX,
    this.endY,
  });

  final bool pickStart;
  final double? startX;
  final double? startY;
  final double? endX;
  final double? endY;

  @override
  void paint(Canvas canvas, Size size) {
    final start = _point(size, startX, startY);
    final end = _point(size, endX, endY);
    final linePaint = Paint()
      ..color = TgiColors.accent.withValues(alpha: 0.76)
      ..strokeWidth = 2;
    if (start != null && end != null) {
      canvas.drawLine(start, end, linePaint);
    }
    if (start != null) {
      _drawMarker(canvas, start, 'IN', TgiColors.textPrimary);
    }
    if (end != null) {
      _drawMarker(canvas, end, 'FIM', TgiColors.accent);
    }
    final active = pickStart ? start : end;
    if (active != null) {
      canvas.drawCircle(
        active,
        18,
        Paint()
          ..color = TgiColors.accent.withValues(alpha: 0.16)
          ..style = PaintingStyle.fill,
      );
    }
  }

  Offset? _point(Size size, double? x, double? y) {
    if (x == null || y == null) {
      return null;
    }
    return Offset(
      x.clamp(0.0, 1.0).toDouble() * size.width,
      y.clamp(0.0, 1.0).toDouble() * size.height,
    );
  }

  void _drawMarker(Canvas canvas, Offset point, String label, Color color) {
    final fill = Paint()..color = TgiColors.scrim;
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas
      ..drawCircle(point, 12, fill)
      ..drawCircle(point, 12, stroke)
      ..drawLine(point.translate(-18, 0), point.translate(-6, 0), stroke)
      ..drawLine(point.translate(6, 0), point.translate(18, 0), stroke)
      ..drawLine(point.translate(0, -18), point.translate(0, -6), stroke)
      ..drawLine(point.translate(0, 6), point.translate(0, 18), stroke);
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, point.translate(16, -20));
  }

  @override
  bool shouldRepaint(covariant _KenBurnsToolPainter oldDelegate) {
    return pickStart != oldDelegate.pickStart ||
        startX != oldDelegate.startX ||
        startY != oldDelegate.startY ||
        endX != oldDelegate.endX ||
        endY != oldDelegate.endY;
  }
}

class _PreviewEffectBadge extends StatelessWidget {
  const _PreviewEffectBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TgiColors.scrim,
        border: Border.all(color: TgiColors.white.withValues(alpha: 0.24)),
        borderRadius: BorderRadius.circular(TgiRadii.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: TgiColors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

ColorFilter? _previewColorFilter(VideoPreviewVisualAdjustments adjustments) {
  if (!adjustments.hasManualAdjustments && !adjustments.hasPreset) {
    return null;
  }

  var matrix = _identityColorMatrix();
  switch (adjustments.filterPreset) {
    case VideoFilterPreset.none:
      break;
    case VideoFilterPreset.blackAndWhite:
      matrix = _multiplyColorMatrices(_saturationColorMatrix(0), matrix);
      break;
    case VideoFilterPreset.sepia:
      matrix = _multiplyColorMatrices(_sepiaColorMatrix(), matrix);
      break;
    case VideoFilterPreset.vintage:
      matrix = _multiplyColorMatrices(
        _linearColorMatrix(
          red: 1.08,
          green: 1.02,
          blue: 0.92,
          redOffset: 9,
          greenOffset: 5,
          blueOffset: -8,
        ),
        matrix,
      );
      matrix = _multiplyColorMatrices(_saturationColorMatrix(0.85), matrix);
      break;
    case VideoFilterPreset.cinematic:
      matrix = _multiplyColorMatrices(
        _linearColorMatrix(
          red: 1.10,
          green: 1.03,
          blue: 1.12,
          redOffset: 4,
          greenOffset: -2,
          blueOffset: 8,
        ),
        matrix,
      );
      matrix = _multiplyColorMatrices(_saturationColorMatrix(1.08), matrix);
      break;
  }

  if ((adjustments.saturation - 1).abs() > 0.000001) {
    matrix = _multiplyColorMatrices(
      _saturationColorMatrix(adjustments.saturation),
      matrix,
    );
  }
  if (adjustments.hue.abs() > 0.000001) {
    matrix = _multiplyColorMatrices(
      _hueRotationColorMatrix(adjustments.hue),
      matrix,
    );
  }
  if (adjustments.temperature.abs() > 0.000001 ||
      adjustments.tint.abs() > 0.000001) {
    final temperature = adjustments.temperature.clamp(-1.0, 1.0).toDouble();
    final tint = adjustments.tint.clamp(-1.0, 1.0).toDouble();
    matrix = _multiplyColorMatrices(
      _linearColorMatrix(
        red: 1 + temperature * 0.18 + tint * 0.05,
        green: 1 - tint * 0.12,
        blue: 1 - temperature * 0.18 + tint * 0.05,
      ),
      matrix,
    );
  }
  if (adjustments.brightness.abs() > 0.000001 ||
      (adjustments.contrast - 1).abs() > 0.000001 ||
      adjustments.exposure.abs() > 0.000001 ||
      adjustments.shadows.abs() > 0.000001 ||
      adjustments.highlights.abs() > 0.000001 ||
      adjustments.curveShadows.abs() > 0.000001 ||
      adjustments.curveMidtones.abs() > 0.000001 ||
      adjustments.curveHighlights.abs() > 0.000001) {
    final exposureGain = math
        .pow(2, adjustments.exposure.clamp(-1.0, 1.0).toDouble())
        .toDouble();
    final curveContrast =
        1 +
        adjustments.curveMidtones.clamp(-1.0, 1.0).toDouble() * 0.18 +
        adjustments.highlights.clamp(-1.0, 1.0).toDouble() * 0.08 -
        adjustments.shadows.clamp(-1.0, 1.0).toDouble() * 0.08;
    final contrast =
        adjustments.contrast.clamp(0.0, 3.0).toDouble() * curveContrast;
    final shadowLift =
        (adjustments.shadows + adjustments.curveShadows)
            .clamp(-2.0, 2.0)
            .toDouble() *
        24;
    final highlightGain =
        1 +
        (adjustments.highlights + adjustments.curveHighlights)
                .clamp(-2.0, 2.0)
                .toDouble() *
            0.1;
    matrix = _multiplyColorMatrices(
      _linearColorMatrix(
        red: contrast * exposureGain * highlightGain,
        green: contrast * exposureGain * highlightGain,
        blue: contrast * exposureGain * highlightGain,
        redOffset:
            128 * (1 - contrast) +
            adjustments.brightness.clamp(-1.0, 1.0).toDouble() * 255 +
            shadowLift,
        greenOffset:
            128 * (1 - contrast) +
            adjustments.brightness.clamp(-1.0, 1.0).toDouble() * 255 +
            shadowLift,
        blueOffset:
            128 * (1 - contrast) +
            adjustments.brightness.clamp(-1.0, 1.0).toDouble() * 255 +
            shadowLift,
      ),
      matrix,
    );
  }

  return ColorFilter.matrix(matrix);
}

Widget _applyPreviewChromaKey(
  Widget child,
  VideoPreviewVisualAdjustments adjustments,
) {
  if (!adjustments.chromaKeyEnabled) return child;
  return ChromaKeyPreview(
    key: const ValueKey('preview_chroma_filter'),
    color: adjustments.chromaKeyColor,
    similarity: adjustments.chromaKeySimilarity,
    blend: adjustments.chromaKeyBlend,
    child: child,
  );
}

class _ChromaTransparencyGrid extends StatelessWidget {
  const _ChromaTransparencyGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return const RepaintBoundary(
      child: CustomPaint(painter: _ChromaTransparencyGridPainter()),
    );
  }
}

class _ChromaTransparencyGridPainter extends CustomPainter {
  const _ChromaTransparencyGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const tileSize = 14.0;
    final light = Paint()..color = const Color(0xFFB8BEC9);
    final dark = Paint()..color = const Color(0xFF7E8796);
    for (var y = 0.0, row = 0; y < size.height; y += tileSize, row++) {
      for (var x = 0.0, column = 0; x < size.width; x += tileSize, column++) {
        canvas.drawRect(
          Rect.fromLTWH(x, y, tileSize, tileSize),
          (row + column).isEven ? light : dark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChromaTransparencyGridPainter oldDelegate) =>
      false;
}

List<double> _identityColorMatrix() {
  return const <double>[
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}

List<double> _sepiaColorMatrix() {
  return const <double>[
    0.393,
    0.769,
    0.189,
    0,
    0,
    0.349,
    0.686,
    0.168,
    0,
    0,
    0.272,
    0.534,
    0.131,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}

List<double> _linearColorMatrix({
  required double red,
  required double green,
  required double blue,
  double redOffset = 0,
  double greenOffset = 0,
  double blueOffset = 0,
}) {
  return <double>[
    red,
    0,
    0,
    0,
    redOffset,
    0,
    green,
    0,
    0,
    greenOffset,
    0,
    0,
    blue,
    0,
    blueOffset,
    0,
    0,
    0,
    1,
    0,
  ];
}

List<double> _saturationColorMatrix(double saturation) {
  final value = saturation.isNaN || saturation.isInfinite
      ? 1.0
      : saturation.clamp(0.0, 3.0).toDouble();
  const r = 0.2126;
  const g = 0.7152;
  const b = 0.0722;
  final inv = 1 - value;
  return <double>[
    r * inv + value,
    g * inv,
    b * inv,
    0,
    0,
    r * inv,
    g * inv + value,
    b * inv,
    0,
    0,
    r * inv,
    g * inv,
    b * inv + value,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}

List<double> _hueRotationColorMatrix(double degrees) {
  final radians = degrees * math.pi / 180;
  final cosValue = math.cos(radians);
  final sinValue = math.sin(radians);
  const r = 0.213;
  const g = 0.715;
  const b = 0.072;
  return <double>[
    r + cosValue * (1 - r) + sinValue * -r,
    g + cosValue * -g + sinValue * -g,
    b + cosValue * -b + sinValue * (1 - b),
    0,
    0,
    r + cosValue * -r + sinValue * 0.143,
    g + cosValue * (1 - g) + sinValue * 0.140,
    b + cosValue * -b + sinValue * -0.283,
    0,
    0,
    r + cosValue * -r + sinValue * -(1 - r),
    g + cosValue * -g + sinValue * g,
    b + cosValue * (1 - b) + sinValue * b,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}

List<double> _multiplyColorMatrices(List<double> a, List<double> b) {
  final result = List<double>.filled(20, 0);
  for (var row = 0; row < 4; row++) {
    for (var column = 0; column < 5; column++) {
      var value = column == 4 ? a[row * 5 + 4] : 0.0;
      for (var i = 0; i < 4; i++) {
        value += a[row * 5 + i] * b[i * 5 + column];
      }
      result[row * 5 + column] = value.isFinite ? value : 0;
    }
  }
  return result;
}

String _visualAdjustmentLabel(VideoPreviewVisualAdjustments adjustments) {
  final labels = <String>[];
  if (adjustments.reverseVideo) {
    labels.add('Reverso');
  }
  if (adjustments.chromaKeyEnabled) {
    labels.add('Chroma Key');
  }
  if (adjustments.hasPreset) {
    labels.add(_videoFilterPresetLabel(adjustments.filterPreset));
  }
  if (adjustments.hasManualAdjustments) {
    labels.add('Ajustes');
  }
  if (adjustments.hasCrop) {
    labels.add('Crop');
  }
  if (adjustments.hasTransform) {
    labels.add('Enquadramento');
  }
  if (adjustments.kenBurnsEnabled) {
    labels.add('Ken Burns');
  }
  return labels.isEmpty ? 'Original' : labels.join(' + ');
}

String _videoFilterPresetLabel(VideoFilterPreset preset) {
  switch (preset) {
    case VideoFilterPreset.none:
      return 'Original';
    case VideoFilterPreset.blackAndWhite:
      return 'P&B';
    case VideoFilterPreset.sepia:
      return 'Sepia';
    case VideoFilterPreset.vintage:
      return 'Vintage';
    case VideoFilterPreset.cinematic:
      return 'Cinematic';
  }
}
