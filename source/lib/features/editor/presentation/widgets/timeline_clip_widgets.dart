part of 'timeline_panel.dart';

class _ClipResizeHandle extends StatefulWidget {
  const _ClipResizeHandle({
    required this.edge,
    required this.color,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragCancel,
    required this.onDragEnd,
  });

  final _ClipResizeEdge edge;
  final Color color;
  final VoidCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final VoidCallback onDragCancel;
  final VoidCallback onDragEnd;

  @override
  State<_ClipResizeHandle> createState() => _ClipResizeHandleState();
}

class _ClipResizeHandleState extends State<_ClipResizeHandle> {
  bool _hovering = false;
  @override
  Widget build(BuildContext context) {
    final isLeft = widget.edge == _ClipResizeEdge.left;
    return Positioned(
      left: isLeft ? 0 : null,
      right: isLeft ? null : 0,
      top: 0,
      bottom: 0,
      width: 14,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => widget.onDragStart(),
          onHorizontalDragUpdate: widget.onDragUpdate,
          onHorizontalDragCancel: widget.onDragCancel,
          onHorizontalDragEnd: (_) => widget.onDragEnd(),
          child: Align(
            alignment: isLeft ? Alignment.centerLeft : Alignment.centerRight,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 110),
              width: 2,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: _hovering
                    ? Color.lerp(widget.color, TgiColors.white, .45)
                    : widget.color,
                borderRadius: BorderRadius.circular(TgiRadii.xs),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClipTrimHandle extends StatefulWidget {
  const _ClipTrimHandle({
    required this.edge,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragCancel,
    required this.onDragEnd,
  });

  final _ClipResizeEdge edge;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragCancel;
  final VoidCallback onDragEnd;

  @override
  State<_ClipTrimHandle> createState() => _ClipTrimHandleState();
}

class _ClipTrimHandleState extends State<_ClipTrimHandle> {
  int? _activePointer;
  Offset? _startGlobalPosition;
  double _lastReportedDx = 0;
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final isLeft = widget.edge == _ClipResizeEdge.left;
    return Positioned(
      left: isLeft ? 0 : null,
      right: isLeft ? null : 0,
      top: 0,
      bottom: 0,
      width: _clipTrimHandleWidth,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: Align(
            alignment: isLeft ? Alignment.centerLeft : Alignment.centerRight,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 110),
              width: _hovering || _activePointer != null ? 2 : 1,
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: TgiColors.accentSoft.withValues(
                  alpha: _hovering || _activePointer != null ? 0.92 : 0.30,
                ),
                borderRadius: BorderRadius.circular(TgiRadii.xs),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_activePointer != null) {
      return;
    }
    setState(() {
      _activePointer = event.pointer;
      _startGlobalPosition = event.position;
      _lastReportedDx = 0;
    });
    _logHandle('pointer-down');
    widget.onDragStart();
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_activePointer != event.pointer) {
      return;
    }
    final start = _startGlobalPosition;
    if (start == null) {
      return;
    }
    final currentDx = event.position.dx - start.dx;
    final deltaDx = currentDx - _lastReportedDx;
    if (deltaDx == 0) {
      return;
    }
    _lastReportedDx = currentDx;
    _logHandle(
      'pointer-move dx=${currentDx.toStringAsFixed(2)} '
      'delta=${deltaDx.toStringAsFixed(2)}',
    );
    widget.onDragUpdate(deltaDx);
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_activePointer != event.pointer) {
      return;
    }
    _logHandle('pointer-up');
    _clearPointerState();
    widget.onDragEnd();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_activePointer != event.pointer) {
      return;
    }
    _logHandle('pointer-cancel');
    _clearPointerState();
    widget.onDragCancel();
  }

  void _clearPointerState() {
    setState(() {
      _activePointer = null;
      _startGlobalPosition = null;
      _lastReportedDx = 0;
    });
  }

  void _logHandle(String message) {
    final line = '[trim-handle ${widget.edge.name}] $message';
    if (EditorDebugLog.enabled) {
      debugPrint(line);
    }
    EditorDebugLog.write('timeline', line);
  }
}

class _ClipTrimPreviewBubble extends StatelessWidget {
  const _ClipTrimPreviewBubble({
    required this.mediaItem,
    required this.sourcePosition,
    required this.edge,
  });

  final MediaItem? mediaItem;
  final Duration sourcePosition;
  final _ClipResizeEdge edge;

  @override
  Widget build(BuildContext context) {
    final thumbnailPath = mediaItem?.thumbnailPath;
    final thumbnailExists =
        thumbnailPath != null && File(thumbnailPath).existsSync();
    return Positioned(
      left: 8,
      right: 8,
      top: 4,
      child: IgnorePointer(
        child: Align(
          alignment: edge == _ClipResizeEdge.left
              ? Alignment.topLeft
              : Alignment.topRight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: TgiColors.black.withValues(alpha: 0.78),
              border: Border.all(color: TgiColors.accent, width: 2),
              borderRadius: BorderRadius.circular(TgiRadii.sm),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(TgiRadii.sm),
                    child: SizedBox(
                      width: 34,
                      height: 20,
                      child: thumbnailExists
                          ? Image.file(File(thumbnailPath), fit: BoxFit.cover)
                          : DecoratedBox(
                              decoration: BoxDecoration(
                                color: TgiColors.surfaceAlt,
                              ),
                              child: Icon(
                                Icons.movie_outlined,
                                color: TgiColors.accentSoft,
                                size: 14,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatDuration(sourcePosition),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: TgiColors.textPrimary,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClipFadeHandle extends StatelessWidget {
  const _ClipFadeHandle({
    required this.edge,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragCancel,
    required this.onDragEnd,
  });

  final _ClipResizeEdge edge;
  final VoidCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final VoidCallback onDragCancel;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final isLeft = edge == _ClipResizeEdge.left;
    return Positioned(
      left: isLeft ? 4 : null,
      right: isLeft ? null : 4,
      top: 3,
      width: 26,
      height: 20,
      child: Tooltip(
        message: isLeft ? 'Fade in' : 'Fade out',
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) => onDragStart(),
            onHorizontalDragUpdate: onDragUpdate,
            onHorizontalDragCancel: onDragCancel,
            onHorizontalDragEnd: (_) => onDragEnd(),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: TgiColors.black.withValues(alpha: 0.66),
                border: Border.all(
                  color: TgiColors.white.withValues(alpha: 0.72),
                ),
                borderRadius: BorderRadius.circular(TgiRadii.pill),
              ),
              child: Icon(
                Icons.opacity,
                size: 13,
                color: TgiColors.white.withValues(alpha: 0.9),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClipFadeRamps extends StatelessWidget {
  const _ClipFadeRamps({required this.clip, required this.color});

  final domain.Clip clip;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ClipFadeRampsPainter(clip: clip, color: color),
    );
  }
}

class _ClipFadeRampsPainter extends CustomPainter {
  const _ClipFadeRampsPainter({required this.clip, required this.color});

  final domain.Clip clip;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 1 || size.height <= 1 || clip.duration <= Duration.zero) {
      return;
    }

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = TgiColors.white.withValues(alpha: 0.55)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final fadeInWidth = _fadeWidth(clip.fadeIn, size.width);
    if (fadeInWidth > 1) {
      final path = Path()
        ..moveTo(0, size.height)
        ..lineTo(fadeInWidth, 0)
        ..lineTo(fadeInWidth, size.height)
        ..close();
      canvas.drawPath(path, fillPaint);
      canvas.drawLine(
        Offset(0, size.height),
        Offset(fadeInWidth, 0),
        linePaint,
      );
    }

    final fadeOutWidth = _fadeWidth(clip.fadeOut, size.width);
    if (fadeOutWidth > 1) {
      final startX = size.width - fadeOutWidth;
      final path = Path()
        ..moveTo(startX, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(startX, size.height)
        ..close();
      canvas.drawPath(path, fillPaint);
      canvas.drawLine(
        Offset(startX, 0),
        Offset(size.width, size.height),
        linePaint,
      );
    }
  }

  double _fadeWidth(Duration fade, double width) {
    if (fade <= Duration.zero) {
      return 0;
    }
    final totalUs = math.max(1, clip.duration.inMicroseconds);
    return (fade.inMicroseconds / totalUs * width).clamp(0.0, width).toDouble();
  }

  @override
  bool shouldRepaint(covariant _ClipFadeRampsPainter oldDelegate) {
    return oldDelegate.clip.fadeIn != clip.fadeIn ||
        oldDelegate.clip.fadeOut != clip.fadeOut ||
        oldDelegate.clip.duration != clip.duration ||
        oldDelegate.color != color;
  }
}

class _TimelineClip extends StatelessWidget {
  const _TimelineClip({
    required this.clip,
    required this.mediaItem,
    required this.audioWaveform,
    required this.dragging,
    required this.active,
    required this.selected,
    required this.locked,
    required this.hidden,
    required this.cutMode,
    required this.connectedAbove,
    required this.connectedBelow,
    this.onVolumeChanged,
  });

  final domain.Clip clip;
  final MediaItem? mediaItem;
  final AudioWaveform? audioWaveform;
  final bool dragging;
  final bool active;
  final bool selected;
  final bool locked;
  final bool hidden;
  final bool cutMode;
  final bool connectedAbove;
  final bool connectedBelow;
  final void Function(String clipId, double volume)? onVolumeChanged;

  @override
  Widget build(BuildContext context) {
    final isAudio = clip.trackType == TrackType.audio;
    final isVideo = clip.trackType == TrackType.video;
    final isImage = clip.trackType == TrackType.image;
    final isText = clip.trackType == TrackType.text;
    final name = isText
        ? (clip.textContent.trim().isEmpty ? 'Texto' : clip.textContent.trim())
        : mediaItem?.name ?? 'Midia removida';
    final icon = isAudio
        ? Icons.volume_up_outlined
        : isImage
        ? Icons.image_outlined
        : isText
        ? Icons.title
        : Icons.movie_outlined;
    final accentColor = _clipAccentFor(clip.trackType);
    final clipFill = _clipFillFor(clip.trackType);
    final emphasized = dragging || selected;
    final linkedPair = connectedAbove || connectedBelow;
    final clipRadius = BorderRadius.only(
      topLeft: Radius.circular(connectedAbove ? 0 : TgiRadii.xs),
      topRight: Radius.circular(connectedAbove ? 0 : TgiRadii.xs),
      bottomLeft: Radius.circular(connectedBelow ? 0 : TgiRadii.xs),
      bottomRight: Radius.circular(connectedBelow ? 0 : TgiRadii.xs),
    );
    final speedSuffix = isVideo && (clip.playbackSpeed - 1).abs() > 0.001
        ? ' | ${_playbackSpeedLabel(clip.playbackSpeed)}'
        : '';
    final volumeSuffix = isAudio ? ' | ${(clip.volume * 100).round()}%' : '';
    final lookSuffix = isVideo && _clipHasVideoLook(clip) ? ' | Look' : '';
    final reverseSuffix = isVideo && clip.reverseVideo ? ' | Reverso' : '';
    final thumbnailPath = mediaItem?.thumbnailPath;
    final hasTimelineThumbnail =
        (isVideo || isImage) &&
        thumbnailPath != null &&
        File(thumbnailPath).existsSync();

    final transitionSuffix =
        clip.fadeIn > Duration.zero || clip.fadeOut > Duration.zero
        ? ' | Fade'
        : '';
    final contentPadding = const EdgeInsets.fromLTRB(8, 8, 8, 8);
    final waveformSamples = isAudio
        ? audioWaveform?.samplesFor(
                sourceStart: clip.sourceStart,
                duration: clip.effectiveSourceDuration,
              ) ??
              const <double>[]
        : const <double>[];
    final child = Opacity(
      opacity: hidden ? 0.48 : 1,
      child: ClipRect(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          clipBehavior: Clip.hardEdge,
          padding: EdgeInsets.zero,
          decoration: BoxDecoration(
            color: clipFill,
            border: Border.all(
              color: emphasized ? TgiColors.accent : TgiColors.border,
              width: emphasized ? 2 : 1,
            ),
            borderRadius: clipRadius,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasTimelineThumbnail)
                _TimelineThumbnailStrip(path: thumbnailPath),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 3, color: clipFill),
              ),
              if (isAudio)
                CustomPaint(
                  key: ValueKey('audio-waveform-${clip.id}'),
                  painter: _AudioWaveformPainter(
                    samples: waveformSamples,
                    startColor: TgiColors.waveformLow,
                    endColor: TgiColors.waveformHigh,
                  ),
                ),
              if (clip.fadeIn > Duration.zero || clip.fadeOut > Duration.zero)
                Positioned.fill(
                  child: IgnorePointer(
                    child: _ClipFadeRamps(clip: clip, color: accentColor),
                  ),
                ),
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 48) {
                    return constraints.maxWidth >= 16
                        ? Center(
                            child: Icon(
                              locked ? Icons.lock_outline : icon,
                              size: 11,
                              color: accentColor,
                            ),
                          )
                        : const SizedBox.shrink();
                  }
                  return Padding(
                    padding: contentPadding,
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: TgiColors.backgroundDeep.withValues(
                              alpha: 0.38,
                            ),
                            border: Border.all(color: TgiColors.border),
                            borderRadius: BorderRadius.circular(TgiRadii.sm),
                          ),
                          child: Icon(
                            locked ? Icons.lock_outline : icon,
                            size: 15,
                            color: accentColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: TgiColors.textPrimary,
                                      backgroundColor:
                                          isAudio || hasTimelineThumbnail
                                          ? TgiColors.background.withValues(
                                              alpha: .75,
                                            )
                                          : null,
                                      fontSize: 12,
                                      height: 1,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${formatDuration(clip.timelineStart)} - ${formatDuration(clip.timelineEnd)}$speedSuffix$volumeSuffix$transitionSuffix$lookSuffix$reverseSuffix',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      fontSize: 11,
                                      height: 1,
                                      color: TgiColors.textPrimary,
                                      backgroundColor:
                                          isAudio || hasTimelineThumbnail
                                          ? TgiColors.background.withValues(
                                              alpha: .75,
                                            )
                                          : null,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isVideo && _clipHasVideoLook(clip)) ...[
                          const _TimelineMiniBadge(label: 'LOOK'),
                          const SizedBox(width: 4),
                        ],
                        if (isVideo && clip.reverseVideo) ...[
                          const _TimelineMiniBadge(label: 'REV'),
                          const SizedBox(width: 4),
                        ],
                        Icon(
                          linkedPair
                              ? Icons.link
                              : isAudio
                              ? Icons.drag_handle
                              : Icons.drag_indicator,
                          size: 16,
                          color: linkedPair
                              ? accentColor
                              : isAudio
                              ? TgiColors.textSecondary
                              : TgiColors.textSecondary,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
    return isAudio
        ? Tooltip(
            message: 'Alt + arraste a linha para ajustar o volume',
            child: child,
          )
        : child;
  }
}

class _TimelineThumbnailStrip extends StatelessWidget {
  const _TimelineThumbnailStrip({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final count = math.max(1, (constraints.maxWidth / 72).ceil());
          return Stack(
            fit: StackFit.expand,
            children: [
              Row(
                children: [
                  for (var index = 0; index < count; index++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(left: index == 0 ? 0 : 4),
                        child: Image.file(
                          File(path),
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.low,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                ],
              ),
              ColoredBox(
                color: TgiColors.backgroundDeep.withValues(alpha: 0.58),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TimelineMiniBadge extends StatelessWidget {
  const _TimelineMiniBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TgiColors.backgroundDeep.withValues(alpha: 0.46),
        border: Border.all(color: TgiColors.accentMuted),
        borderRadius: BorderRadius.circular(TgiRadii.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(
          label,
          maxLines: 1,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: TgiColors.accentSoft,
            fontSize: 8,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

bool _clipHasVideoLook(domain.Clip clip) {
  return clip.filterPreset != domain.VideoFilterPreset.none ||
      clip.brightness.abs() > 0.000001 ||
      (clip.contrast - 1).abs() > 0.000001 ||
      (clip.saturation - 1).abs() > 0.000001 ||
      clip.exposure.abs() > 0.000001 ||
      clip.hue.abs() > 0.000001 ||
      clip.temperature.abs() > 0.000001 ||
      clip.tint.abs() > 0.000001 ||
      clip.shadows.abs() > 0.000001 ||
      clip.highlights.abs() > 0.000001 ||
      clip.curveShadows.abs() > 0.000001 ||
      clip.curveMidtones.abs() > 0.000001 ||
      clip.curveHighlights.abs() > 0.000001;
}

class _AudioVolumeLineLayer extends StatelessWidget {
  const _AudioVolumeLineLayer({
    required this.clipId,
    required this.volume,
    required this.enabled,
  });

  final String clipId;
  final double volume;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            key: ValueKey('audio-volume-line-$clipId'),
            painter: _AudioVolumeLinePainter(volume: volume, enabled: enabled),
          ),
          if (enabled)
            SizedBox.expand(key: ValueKey('audio-volume-line-hit-$clipId')),
        ],
      ),
    );
  }
}

class _AudioWaveformPainter extends CustomPainter {
  const _AudioWaveformPainter({
    required this.samples,
    required this.startColor,
    required this.endColor,
  });

  final List<double> samples;
  final Color startColor;
  final Color endColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || samples.isEmpty) {
      return;
    }
    final sampleCount = math.min(
      samples.length,
      (size.width / 4).clamp(24, 180).round(),
    );
    if (sampleCount <= 0) {
      return;
    }
    final centerY = size.height / 2;
    final barWidth = math.max(2.0, size.width / sampleCount * 0.62);
    final paint = Paint()..style = PaintingStyle.fill;
    final glowPaint = Paint()
      ..color = endColor.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;

    for (var i = 0; i < sampleCount; i++) {
      final start = (i * samples.length / sampleCount).floor();
      final end = math
          .max(start + 1, ((i + 1) * samples.length / sampleCount).ceil())
          .clamp(start + 1, samples.length);
      var amplitude = 0.0;
      for (var index = start; index < end; index++) {
        amplitude = math.max(amplitude, samples[index]);
      }
      amplitude = amplitude.clamp(0.0, 1.0).toDouble();
      final height = math.max(3.0, amplitude * size.height * 0.84);
      final x = (i + 0.5) / sampleCount * size.width;
      final t = sampleCount <= 1 ? 0.0 : i / (sampleCount - 1);
      paint.color = Color.lerp(
        startColor,
        endColor,
        t,
      )!.withValues(alpha: 0.54);
      final rect = Rect.fromCenter(
        center: Offset(x, centerY),
        width: barWidth,
        height: height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(1.4), const Radius.circular(3)),
        glowPaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AudioWaveformPainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.startColor != startColor ||
        oldDelegate.endColor != endColor;
  }
}

class _AudioVolumeLinePainter extends CustomPainter {
  const _AudioVolumeLinePainter({required this.volume, required this.enabled});

  final double volume;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }
    final y = _volumeLineY(volume, size.height);
    final shadowPaint = Paint()
      ..color = TgiColors.shadow
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final linePaint = Paint()
      ..color = enabled ? TgiColors.textPrimary : TgiColors.textSecondary
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final handlePaint = Paint()
      ..color = enabled ? TgiColors.textPrimary : TgiColors.textSecondary
      ..style = PaintingStyle.fill;

    canvas.drawLine(
      Offset(7, y + 1),
      Offset(size.width - 7, y + 1),
      shadowPaint,
    );
    canvas.drawLine(Offset(7, y), Offset(size.width - 7, y), linePaint);
    canvas.drawCircle(Offset(size.width - 13, y), enabled ? 5 : 4, handlePaint);
  }

  @override
  bool shouldRepaint(covariant _AudioVolumeLinePainter oldDelegate) {
    return oldDelegate.volume != volume || oldDelegate.enabled != enabled;
  }
}

double _volumeLineY(double volume, double height) {
  final normalized = _clampVolume(volume) / _maxClipVolume;
  return (height * (1 - normalized)).clamp(2.0, math.max(2.0, height - 2));
}

double _volumeFromLocalY(double localY, double height) {
  if (height <= 0) {
    return 1;
  }
  return ((height - localY) / height * _maxClipVolume)
      .clamp(0.0, _maxClipVolume)
      .toDouble();
}

double _clampVolume(double value) {
  if (value.isNaN || value.isInfinite) {
    return 1;
  }
  return value.clamp(0.0, _maxClipVolume).toDouble();
}

class _ClipResizeResult {
  const _ClipResizeResult({
    required this.timelineStart,
    required this.duration,
  });

  final Duration timelineStart;
  final Duration duration;
}

class _ClipTrimResult {
  const _ClipTrimResult({
    required this.timelineStart,
    required this.sourceStart,
    required this.sourceDuration,
    required this.timelineDuration,
    required this.previewSourcePosition,
    required this.previewTimelinePosition,
  });

  final Duration timelineStart;
  final Duration sourceStart;
  final Duration sourceDuration;
  final Duration timelineDuration;
  final Duration previewSourcePosition;
  final Duration previewTimelinePosition;
}

class _SnapMatch {
  const _SnapMatch({required this.position, required this.distancePx});

  final Duration position;
  final double distancePx;
}

class _EmptyTimeline extends StatelessWidget {
  const _EmptyTimeline({required this.accepting});

  final bool accepting;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 170;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: accepting
                ? _timelineDropBackground.withValues(alpha: 0.82)
                : TgiColors.transparent,
          ),
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(compact ? 8 : 16),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: TgiColors.surfacePanel.withValues(
                    alpha: accepting ? 0.94 : 0.72,
                  ),
                  border: Border.all(
                    color: accepting
                        ? TgiColors.accent
                        : TgiColors.borderStrong,
                    width: accepting ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(TgiRadii.lg),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 12 : 24,
                    vertical: compact ? 8 : 16,
                  ),
                  child: compact
                      ? Text(
                          accepting ? 'Soltar na timeline' : 'Timeline vazia',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            accepting
                                ? const TgiAccentIcon(
                                    Icons.add_circle_outline,
                                    size: 34,
                                  )
                                : const Icon(
                                    Icons.timeline,
                                    color: TgiColors.textSecondary,
                                    size: 34,
                                  ),
                            const SizedBox(height: 8),
                            Text(
                              accepting
                                  ? 'Soltar na timeline'
                                  : 'Timeline vazia',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              accepting
                                  ? 'O clipe sera criado na timeline.'
                                  : 'Arraste videos, audios, imagens ou textos para comecar.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

Duration _timelineExtent(TgiProject project) {
  final projectDuration = project.timelineDuration;
  if (projectDuration <= _minimumTimelineDuration) {
    return _minimumTimelineDuration;
  }
  return projectDuration + const Duration(seconds: 5);
}

double _timelineContentWidth(
  Duration duration,
  double viewportWidth, {
  required double zoom,
}) {
  final durationWidth =
      math.max(1, duration.inSeconds) * _pixelsPerSecond * zoom;
  return math.max(viewportWidth, durationWidth);
}

Duration _positionFromDx(double dx, Duration duration, double width) {
  final safeWidth = math.max(1.0, width);
  final fraction = (dx / safeWidth).clamp(0.0, 1.0);
  final milliseconds = (duration.inMilliseconds * fraction).round();
  return Duration(milliseconds: milliseconds);
}

double _leftFor(Duration position, Duration duration, double width) {
  final totalMs = math.max(1, duration.inMilliseconds);
  final left = position.inMilliseconds / totalMs * width;
  return left.clamp(0.0, math.max(0.0, width - 1)).toDouble();
}

double _widthFor(
  Duration clipDuration,
  Duration timelineDuration,
  double width,
) {
  final totalMs = math.max(1, timelineDuration.inMilliseconds);
  return clipDuration.inMilliseconds / totalMs * width;
}

_ClipResizeResult _resizeForDragDelta(
  domain.Clip clip,
  _ClipResizeEdge edge,
  double delta,
  Duration duration,
  double width, {
  Iterable<Duration> snapCandidates = const [],
}) {
  final start = clip.timelineStart;
  final end = clip.timelineEnd;
  if (edge == _ClipResizeEdge.left) {
    final left = _leftFor(start, duration, width);
    final maxStart = end - _minimumClipResizeDuration;
    final rawNextStart = _clampDuration(
      _positionFromDx(left + delta, duration, width),
      Duration.zero,
      maxStart,
    );
    final nextStart = _snapPosition(
      rawNextStart,
      snapCandidates.where(
        (candidate) =>
            candidate >= Duration.zero &&
            candidate <= maxStart &&
            candidate != end,
      ),
      duration,
      width,
    );
    return _ClipResizeResult(
      timelineStart: nextStart,
      duration: end - nextStart,
    );
  }

  final right = _leftFor(end, duration, width);
  final minEnd = start + _minimumClipResizeDuration;
  final rawNextEnd = _clampDuration(
    _positionFromDx(right + delta, duration, width),
    minEnd,
    duration,
  );
  final nextEnd = _snapPosition(
    rawNextEnd,
    snapCandidates.where(
      (candidate) =>
          candidate >= minEnd && candidate <= duration && candidate != start,
    ),
    duration,
    width,
  );
  return _ClipResizeResult(timelineStart: start, duration: nextEnd - start);
}

_ClipTrimResult _trimForDragDelta(
  domain.Clip clip,
  MediaItem? mediaItem,
  _ClipResizeEdge edge,
  double delta,
  Duration timelineDuration,
  double width,
) {
  final mediaDuration = mediaItem?.duration ?? clip.sourceEnd;
  final safeMediaDuration = mediaDuration <= Duration.zero
      ? clip.sourceEnd
      : mediaDuration;
  final currentSourceStart = _clampDuration(
    clip.sourceStart,
    Duration.zero,
    safeMediaDuration,
  );
  final currentSourceEnd = _clampDuration(
    clip.sourceEnd,
    currentSourceStart,
    safeMediaDuration,
  );
  final requestedSourceDelta = _sourceDurationDeltaForPixels(
    delta,
    timelineDuration,
    width,
    clip.playbackSpeed,
  );
  final minimumSourceDuration = _sourceDurationForTimeline(
    _minimumClipTrimTimelineDuration,
    clip.playbackSpeed,
  );
  final effectiveMinimumSourceDuration =
      safeMediaDuration < minimumSourceDuration
      ? safeMediaDuration
      : minimumSourceDuration;

  late final Duration nextSourceStart;
  late final Duration nextSourceDuration;
  late final Duration previewSourcePosition;
  if (edge == _ClipResizeEdge.left) {
    final maxStart = currentSourceEnd - effectiveMinimumSourceDuration;
    nextSourceStart = _clampDuration(
      currentSourceStart + requestedSourceDelta,
      Duration.zero,
      maxStart < Duration.zero ? Duration.zero : maxStart,
    );
    nextSourceDuration = currentSourceEnd - nextSourceStart;
    previewSourcePosition = nextSourceStart;
  } else {
    final minEnd = currentSourceStart + effectiveMinimumSourceDuration;
    final nextSourceEnd = _clampDuration(
      currentSourceEnd + requestedSourceDelta,
      minEnd,
      safeMediaDuration,
    );
    nextSourceStart = currentSourceStart;
    nextSourceDuration = nextSourceEnd - nextSourceStart;
    previewSourcePosition = _clampDuration(
      nextSourceEnd - const Duration(milliseconds: 16),
      nextSourceStart,
      nextSourceEnd,
    );
  }

  final nextTimelineDuration = _timelineDurationForSource(
    nextSourceDuration,
    clip.playbackSpeed,
  );
  final previewTimelinePosition = edge == _ClipResizeEdge.left
      ? clip.timelineStart
      : _clampDuration(
          clip.timelineStart +
              nextTimelineDuration -
              const Duration(milliseconds: 16),
          clip.timelineStart,
          clip.timelineStart + nextTimelineDuration,
        );
  return _ClipTrimResult(
    timelineStart: clip.timelineStart,
    sourceStart: nextSourceStart,
    sourceDuration: nextSourceDuration,
    timelineDuration: nextTimelineDuration,
    previewSourcePosition: previewSourcePosition,
    previewTimelinePosition: previewTimelinePosition,
  );
}

_ClipFadeValues _fadeForDragDelta(
  domain.Clip clip,
  _ClipResizeEdge edge,
  double delta,
  Duration timelineDuration,
  double width,
) {
  final deltaDuration = _durationDeltaForPixels(delta, timelineDuration, width);
  final fadeIn = edge == _ClipResizeEdge.left
      ? _clampFadeDuration(clip.fadeIn + deltaDuration, clip.duration)
      : clip.fadeIn;
  final fadeOut = edge == _ClipResizeEdge.right
      ? _clampFadeDuration(clip.fadeOut - deltaDuration, clip.duration)
      : clip.fadeOut;
  return _ClipFadeValues(fadeIn: fadeIn, fadeOut: fadeOut);
}

Duration _durationDeltaForPixels(
  double delta,
  Duration timelineDuration,
  double width,
) {
  if (width <= 0 || timelineDuration <= Duration.zero) {
    return Duration.zero;
  }
  return Duration(
    microseconds: (delta / width * timelineDuration.inMicroseconds).round(),
  );
}

Duration _sourceDurationDeltaForPixels(
  double delta,
  Duration timelineDuration,
  double width,
  double playbackSpeed,
) {
  final timelineDelta = _durationDeltaForPixels(delta, timelineDuration, width);
  return Duration(
    microseconds:
        (timelineDelta.inMicroseconds * _clampPlaybackSpeed(playbackSpeed))
            .round(),
  );
}

Duration _sourceDurationForTimeline(
  Duration timelineDuration,
  double playbackSpeed,
) {
  if (timelineDuration <= Duration.zero) {
    return Duration.zero;
  }
  return Duration(
    microseconds:
        (timelineDuration.inMicroseconds * _clampPlaybackSpeed(playbackSpeed))
            .round(),
  );
}

Duration _timelineDurationForSource(
  Duration sourceDuration,
  double playbackSpeed,
) {
  if (sourceDuration <= Duration.zero) {
    return Duration.zero;
  }
  final microseconds =
      (sourceDuration.inMicroseconds / _clampPlaybackSpeed(playbackSpeed))
          .round();
  return Duration(microseconds: microseconds <= 0 ? 1 : microseconds);
}

double _clampPlaybackSpeed(double value) {
  if (value.isNaN || value.isInfinite || value <= 0) {
    return 1;
  }
  return value.clamp(0.25, 4.0).toDouble();
}

Duration _clampFadeDuration(Duration value, Duration clipDuration) {
  if (value <= Duration.zero || clipDuration <= Duration.zero) {
    return Duration.zero;
  }
  final maxFade = Duration(
    microseconds: (clipDuration.inMicroseconds / 2).floor(),
  );
  return value > maxFade ? maxFade : value;
}

Duration _clampDuration(Duration value, Duration minimum, Duration maximum) {
  if (maximum < minimum) {
    return minimum;
  }
  if (value < minimum) {
    return minimum;
  }
  if (value > maximum) {
    return maximum;
  }
  return value;
}

Duration _startForDragDelta(
  domain.Clip clip,
  double delta,
  Duration duration,
  double width, {
  Iterable<Duration> snapCandidates = const [],
}) {
  final totalMs = math.max(1, duration.inMilliseconds);
  final safeWidth = math.max(1, width);
  final deltaMs = (delta / safeWidth * totalMs).round();
  final rawMs = clip.timelineStart.inMilliseconds + deltaMs;
  final clampedMs = rawMs.clamp(0, duration.inMilliseconds);
  final start = Duration(milliseconds: clampedMs);
  return _snapClipStart(clip, start, snapCandidates, duration, width);
}

Duration _sourceStartForSlipDrag(
  domain.Clip clip,
  MediaItem? mediaItem,
  double dragDelta,
  Duration timelineDuration,
  double width,
) {
  if (mediaItem == null || width <= 0 || timelineDuration <= Duration.zero) {
    return clip.sourceStart;
  }
  final timelineDeltaUs = (dragDelta / width * timelineDuration.inMicroseconds)
      .round();
  final sourceDeltaUs = (timelineDeltaUs * clip.playbackSpeed).round();
  final maximumStart = math.max(
    0,
    (mediaItem.duration - clip.effectiveSourceDuration).inMicroseconds,
  );
  final nextUs = (clip.sourceStart.inMicroseconds + sourceDeltaUs).clamp(
    0,
    maximumStart,
  );
  return Duration(microseconds: nextUs.toInt());
}

Duration _snapClipStart(
  domain.Clip clip,
  Duration proposedStart,
  Iterable<Duration> candidates,
  Duration timelineDuration,
  double width,
) => _snapSpanStart(
  clip.duration,
  proposedStart,
  candidates,
  timelineDuration,
  width,
);

Duration _snapSpanStart(
  Duration clipDuration,
  Duration proposedStart,
  Iterable<Duration> candidates,
  Duration timelineDuration,
  double width,
) {
  final proposedEnd = proposedStart + clipDuration;
  final startMatch = _closestSnapMatch(
    proposedStart,
    candidates,
    timelineDuration,
    width,
  );
  final endMatch = _closestSnapMatch(
    proposedEnd,
    candidates,
    timelineDuration,
    width,
  );
  final match = _nearestSnapMatch(startMatch, endMatch);
  if (match == null) {
    return proposedStart;
  }

  final snappedStart = match == startMatch
      ? match.position
      : proposedStart + (match.position - proposedEnd);
  return _clampDuration(snappedStart, Duration.zero, timelineDuration);
}

Duration _snapPosition(
  Duration position,
  Iterable<Duration> candidates,
  Duration timelineDuration,
  double width,
) {
  final match = _closestSnapMatch(
    position,
    candidates,
    timelineDuration,
    width,
  );
  return match?.position ?? position;
}

_SnapMatch? _nearestSnapMatch(_SnapMatch? first, _SnapMatch? second) {
  if (first == null) {
    return second;
  }
  if (second == null) {
    return first;
  }
  return first.distancePx <= second.distancePx ? first : second;
}

_SnapMatch? _closestSnapMatch(
  Duration position,
  Iterable<Duration> candidates,
  Duration timelineDuration,
  double width,
) {
  _SnapMatch? best;
  final positionPx = _leftFor(position, timelineDuration, width);
  for (final candidate in candidates) {
    final clampedCandidate = _clampDuration(
      candidate,
      Duration.zero,
      timelineDuration,
    );
    final candidatePx = _leftFor(clampedCandidate, timelineDuration, width);
    final distancePx = (candidatePx - positionPx).abs();
    if (distancePx > _timelineSnapThresholdPx) {
      continue;
    }
    if (best == null ||
        distancePx < best.distancePx ||
        (distancePx == best.distancePx && clampedCandidate < best.position)) {
      best = _SnapMatch(position: clampedCandidate, distancePx: distancePx);
    }
  }
  return best;
}

Iterable<Duration> _snapCandidatesForTimeline({
  required List<Track> tracks,
  required List<TimelineMarker> markers,
  required Duration playheadPosition,
  required Duration timelineDuration,
  String? ignoredTimelineGroupId,
}) {
  return _trackIndexFor(tracks).snapCandidates(
    markers: markers,
    playhead: playheadPosition,
    duration: timelineDuration,
    ignoredGroup: ignoredTimelineGroupId,
  );
}

bool _timelineGroupHasTrackType(
  List<Track> tracks,
  String timelineGroupId,
  TrackType type,
) {
  return _trackIndexFor(
    tracks,
  ).groupTracks.containsKey((timelineGroupId, type));
}

int? _timelineGroupTrackIndex(
  List<Track> tracks,
  String timelineGroupId,
  TrackType type,
) {
  return _trackIndexFor(tracks).groupTracks[(timelineGroupId, type)];
}

bool _canDropMediaOnTrack(MediaItem item, Track track) =>
    !track.isLocked &&
    (item.type == MediaType.audio
        ? track.kind == TrackKind.audio
        : track.kind == TrackKind.visual);

bool _shouldCreateVideoTrackForDroppedMedia(
  MediaItem item,
  TgiProject project,
  Track? targetTrack,
  Duration timelineStart, {
  required bool isEmptyLaneArea,
}) => item.type != MediaType.audio && targetTrack == null && isEmptyLaneArea;

Duration _snapMediaDropPosition({
  required MediaItem item,
  required TgiProject project,
  required Track? targetTrack,
  required Duration proposedStart,
  required Duration playheadPosition,
  required Duration duration,
  required double width,
  required bool enabled,
}) {
  if (!enabled) return proposedStart;
  final clipDuration = item.type == MediaType.image
      ? const Duration(seconds: 5)
      : item.duration;
  final lane = item.type == MediaType.video
      ? (targetTrack == null
            ? project.trackById(TgiProject.defaultVideoTrackId)
            : _videoTrackUsedByVideoDrop(project, targetTrack))
      : targetTrack;
  if (lane != null) {
    // Close to an edit, prefer a free slot on the target track over unrelated
    // captions/playhead positions that would create an accidental PIP track.
    final freeEdges = <Duration>[];
    for (final clip in lane.clips) {
      for (final start in [
        clip.timelineEnd,
        clip.timelineStart - clipDuration,
      ]) {
        if (start < Duration.zero || start > duration) continue;
        if (_closestSnapMatch(proposedStart, [start], duration, width) !=
                null &&
            !_trackHasClipOverlap(lane, start, clipDuration)) {
          freeEdges.add(start);
        }
      }
    }
    final freeMatch = _closestSnapMatch(
      proposedStart,
      freeEdges,
      duration,
      width,
    );
    if (freeMatch != null) return freeMatch.position;
  }
  return _snapSpanStart(
    clipDuration,
    proposedStart,
    _snapCandidatesForTimeline(
      tracks: project.tracks,
      markers: project.markers,
      playheadPosition: playheadPosition,
      timelineDuration: duration,
    ),
    duration,
    width,
  );
}

Track? _videoTrackUsedByVideoDrop(TgiProject project, Track targetTrack) =>
    targetTrack.kind == TrackKind.visual ? targetTrack : null;

bool _trackHasClipOverlap(
  Track track,
  Duration timelineStart,
  Duration duration,
) {
  final timelineEnd = timelineStart + duration;
  return track.clips.any(
    (clip) =>
        timelineStart < clip.timelineEnd && timelineEnd > clip.timelineStart,
  );
}

String _playbackSpeedLabel(double speed) {
  if (speed == 0.25) return '0.25x';
  if (speed == 0.5) return '0.5x';
  if (speed == 1.5) return '1.5x';
  if (speed == speed.roundToDouble()) {
    return '${speed.toStringAsFixed(0)}x';
  }
  return '${speed.toStringAsFixed(2)}x';
}

MediaItem? _findMediaItem(TgiProject project, String id) {
  final index = _mediaIndexes[project] ??= {
    for (final item in project.mediaPool) item.id: item,
  };
  return index[id];
}

final _timelineSignatures = Expando<String>();
String _timelineSignatureFor(TgiProject project) =>
    _timelineSignatures[project] ??= _computeTimelineSignature(project);

String _computeTimelineSignature(TgiProject project) {
  final buffer = StringBuffer()
    ..write('tracks:')
    ..write(project.tracks.length)
    ..write('|markers:')
    ..write(project.markers.length)
    ..write('|transitions:')
    ..write(project.transitions.length);
  for (final track in project.tracks) {
    buffer
      ..write('|t:')
      ..write(track.id)
      ..write(track.height)
      ..write(',')
      ..write(track.type.name)
      ..write(',')
      ..write(track.isLocked)
      ..write(',')
      ..write(track.isHidden)
      ..write(',')
      ..write(track.isMuted)
      ..write(',')
      ..write(track.isSolo)
      ..write(',')
      ..write(track.clips.length);
    for (final clip in track.clips) {
      buffer
        ..write('|c:')
        ..write(clip.id)
        ..write(',')
        ..write(clip.timelineGroupId);
    }
  }
  for (final transition in project.transitions) {
    buffer
      ..write('|x:')
      ..write(transition.id)
      ..write(',')
      ..write(transition.timelinePosition.inMilliseconds)
      ..write(',')
      ..write(transition.duration.inMilliseconds)
      ..write(',')
      ..write(transition.filePath);
  }
  return buffer.toString();
}

bool _additiveSelectPressed() {
  final keyboard = HardwareKeyboard.instance;
  return !keyboard.isControlPressed &&
      !keyboard.isMetaPressed &&
      keyboard.isShiftPressed;
}

bool _toggleSelectPressed() {
  final keyboard = HardwareKeyboard.instance;
  return keyboard.isControlPressed || keyboard.isMetaPressed;
}
