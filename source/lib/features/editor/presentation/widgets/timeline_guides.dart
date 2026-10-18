part of 'timeline_panel.dart';

class _TimelineRulerInteraction extends StatelessWidget {
  const _TimelineRulerInteraction({
    required this.duration,
    required this.width,
    required this.enabled,
    required this.onPlayheadChanged,
    required this.onRulerPan,
  });

  final Duration duration;
  final double width;
  final bool enabled;
  final ValueChanged<Duration> onPlayheadChanged;
  final ValueChanged<double> onRulerPan;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: enabled
          ? (details) {
              onPlayheadChanged(
                _positionFromDx(details.localPosition.dx, duration, width),
              );
            }
          : null,
      onHorizontalDragUpdate: enabled
          ? (details) {
              onRulerPan(-details.delta.dx);
            }
          : null,
      child: _TimelineRuler(duration: duration),
    );
  }
}

class _TimelineRuler extends StatelessWidget {
  const _TimelineRuler({required this.duration});

  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TgiColors.surfacePanel,
        border: const Border(bottom: BorderSide(color: TgiColors.borderStrong)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final ticks = _tickSeconds(duration);
          return Stack(
            children: [
              for (final seconds in ticks)
                Positioned(
                  left: _leftFor(
                    Duration(seconds: seconds),
                    duration,
                    constraints.maxWidth,
                  ),
                  top: 0,
                  bottom: 0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Container(
                          width: seconds % 5 == 0 ? 1.2 : 1,
                          color:
                              (seconds % 5 == 0
                                      ? TgiColors.accentMuted
                                      : TgiColors.timelineGrid)
                                  .withValues(
                                    alpha: seconds % 5 == 0 ? 0.80 : 0.46,
                                  ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 5, bottom: 4),
                        child: Text(
                          formatDuration(Duration(seconds: seconds)),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: seconds % 5 == 0
                                    ? TgiColors.accentSoft
                                    : TgiColors.textSecondary,
                                fontSize: 11,
                                fontWeight: seconds % 5 == 0
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TimelinePlayhead extends StatelessWidget {
  const _TimelinePlayhead({
    required this.position,
    required this.duration,
    required this.width,
    required this.enabled,
    required this.onChanged,
  });

  final Duration position;
  final Duration duration;
  final double width;
  final bool enabled;
  final ValueChanged<Duration> onChanged;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          IgnorePointer(
            child: CustomPaint(
              key: const ValueKey('timeline-playhead-line'),
              painter: _TimelinePlayheadPainter(
                position: position,
                duration: duration,
              ),
            ),
          ),
          _TimelinePlayheadHandle(
            position: position,
            duration: duration,
            width: width,
            enabled: enabled,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _TimelinePlayheadPainter extends CustomPainter {
  const _TimelinePlayheadPainter({
    required this.position,
    required this.duration,
  });

  final Duration position;
  final Duration duration;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }
    final rawLeft = _leftFor(position, duration, size.width);
    final left = rawLeft.clamp(1.0, math.max(1.0, size.width - 1)).toDouble();
    final glowPaint = Paint()
      ..color = TgiColors.playheadGlow
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    final softPaint = Paint()
      ..color = TgiColors.glowOuter
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    final paint = Paint()
      ..color = TgiColors.accent
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(left, 0), Offset(left, size.height), glowPaint);
    canvas.drawLine(Offset(left, 0), Offset(left, size.height), softPaint);
    canvas.drawLine(Offset(left, 0), Offset(left, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant _TimelinePlayheadPainter oldDelegate) {
    return oldDelegate.position != position || oldDelegate.duration != duration;
  }
}

class _TimelinePlayheadHandle extends StatelessWidget {
  const _TimelinePlayheadHandle({
    required this.position,
    required this.duration,
    required this.width,
    required this.enabled,
    required this.onChanged,
  });

  final Duration position;
  final Duration duration;
  final double width;
  final bool enabled;
  final ValueChanged<Duration> onChanged;

  @override
  Widget build(BuildContext context) {
    final left = _leftFor(position, duration, width);
    final hitLeft = (left - 6).clamp(0.0, math.max(0.0, width - 12)).toDouble();

    return Positioned(
      left: hitLeft,
      top: 0,
      bottom: 0,
      width: 12,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: enabled
            ? (details) {
                onChanged(
                  _positionFromDx(
                    hitLeft + details.localPosition.dx,
                    duration,
                    width,
                  ),
                );
              }
            : null,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: TgiColors.accent,
                border: Border.all(color: TgiColors.accentSoft),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TimelineMarkers extends StatelessWidget {
  const _TimelineMarkers({
    required this.markers,
    required this.duration,
    required this.width,
    required this.onMarkerRenamed,
    required this.onMarkerDeleted,
    required this.onMarkerSelected,
  });

  final List<TimelineMarker> markers;
  final Duration duration;
  final double width;
  final void Function(String markerId, String name)? onMarkerRenamed;
  final ValueChanged<String>? onMarkerDeleted;
  final ValueChanged<Duration> onMarkerSelected;

  @override
  Widget build(BuildContext context) {
    if (markers.isEmpty) {
      return const Positioned.fill(child: SizedBox.shrink());
    }
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Stack(
          children: [
            for (final marker in markers)
              _TimelineMarkerView(
                marker: marker,
                left: _leftFor(marker.position, duration, width),
                onMarkerRenamed: onMarkerRenamed,
                onMarkerDeleted: onMarkerDeleted,
                onMarkerSelected: onMarkerSelected,
              ),
          ],
        ),
      ),
    );
  }
}

class _TimelineMarkerView extends StatelessWidget {
  const _TimelineMarkerView({
    required this.marker,
    required this.left,
    required this.onMarkerRenamed,
    required this.onMarkerDeleted,
    required this.onMarkerSelected,
  });

  final TimelineMarker marker;
  final double left;
  final void Function(String markerId, String name)? onMarkerRenamed;
  final ValueChanged<String>? onMarkerDeleted;
  final ValueChanged<Duration> onMarkerSelected;

  @override
  Widget build(BuildContext context) {
    final markerColor = Color(marker.color);
    return Stack(
      children: [
        Positioned(
          left: left,
          top: _rulerHeight,
          bottom: 0,
          child: Container(
            width: 1,
            color: markerColor.withValues(alpha: 0.55),
          ),
        ),
        Positioned(
          left: (left - 18).clamp(0.0, double.infinity).toDouble(),
          top: 0,
          width: 36,
          height: _rulerHeight,
          child: PopupMenuButton<_MarkerMenuAction>(
            tooltip: marker.name,
            padding: EdgeInsets.zero,
            icon: Icon(Icons.flag, size: 17, color: markerColor),
            onSelected: (action) async {
              switch (action) {
                case _MarkerMenuAction.seek:
                  onMarkerSelected(marker.position);
                  break;
                case _MarkerMenuAction.rename:
                  final name = await _showRenameMarkerDialog(
                    context,
                    marker.name,
                  );
                  if (name != null) {
                    onMarkerRenamed?.call(marker.id, name);
                  }
                  break;
                case _MarkerMenuAction.delete:
                  onMarkerDeleted?.call(marker.id);
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _MarkerMenuAction.seek,
                child: _TrackMenuItem(icon: Icons.my_location, label: 'Ir ate'),
              ),
              PopupMenuItem(
                value: _MarkerMenuAction.rename,
                child: _TrackMenuItem(
                  icon: Icons.drive_file_rename_outline,
                  label: 'Renomear',
                ),
              ),
              PopupMenuItem(
                value: _MarkerMenuAction.delete,
                child: _TrackMenuItem(
                  icon: Icons.delete_outline,
                  label: 'Apagar',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _MarkerMenuAction { seek, rename, delete }

class _TimelineTransitions extends StatelessWidget {
  const _TimelineTransitions({
    required this.transitions,
    required this.duration,
    required this.width,
    required this.onTransitionSelected,
    required this.onTransitionMoved,
    required this.onTransitionEdit,
    required this.onTransitionDeleted,
  });

  final List<TimelineTransition> transitions;
  final Duration duration;
  final double width;
  final ValueChanged<Duration> onTransitionSelected;
  final TimelineTransitionMoveCallback? onTransitionMoved;
  final ValueChanged<TimelineTransition>? onTransitionEdit;
  final ValueChanged<String>? onTransitionDeleted;

  @override
  Widget build(BuildContext context) {
    if (transitions.isEmpty) {
      return const Positioned.fill(child: SizedBox.shrink());
    }
    return Positioned.fill(
      child: Stack(
        children: [
          for (final transition in transitions)
            _TimelineTransitionView(
              transition: transition,
              left: _leftFor(transition.timelinePosition, duration, width),
              startLeft: _leftFor(transition.timelineStart, duration, width),
              endLeft: _leftFor(transition.timelineEnd, duration, width),
              onTransitionSelected: onTransitionSelected,
              onTransitionMoved: onTransitionMoved,
              onTransitionEdit: onTransitionEdit,
              onTransitionDeleted: onTransitionDeleted,
            ),
        ],
      ),
    );
  }
}

class _TimelineTransitionView extends StatelessWidget {
  const _TimelineTransitionView({
    required this.transition,
    required this.left,
    required this.startLeft,
    required this.endLeft,
    required this.onTransitionSelected,
    required this.onTransitionMoved,
    required this.onTransitionEdit,
    required this.onTransitionDeleted,
  });

  final TimelineTransition transition;
  final double left;
  final double startLeft;
  final double endLeft;
  final ValueChanged<Duration> onTransitionSelected;
  final TimelineTransitionMoveCallback? onTransitionMoved;
  final ValueChanged<TimelineTransition>? onTransitionEdit;
  final ValueChanged<String>? onTransitionDeleted;

  @override
  Widget build(BuildContext context) {
    final spanWidth = math.max(3.0, endLeft - startLeft);
    final indicatorWidth = spanWidth.clamp(30.0, 88.0).toDouble();
    final indicatorLeft = (left - (indicatorWidth / 2))
        .clamp(0.0, double.infinity)
        .toDouble();
    final transitionIcon = switch (transition.preset) {
      TimelineTransitionPreset.fade => Icons.gradient,
      TimelineTransitionPreset.flash => Icons.flash_on_outlined,
      TimelineTransitionPreset.wipe => Icons.swipe_outlined,
      TimelineTransitionPreset.dissolve => Icons.blur_on_outlined,
      TimelineTransitionPreset.blur => Icons.blur_circular_outlined,
      TimelineTransitionPreset.glitch => Icons.broken_image_outlined,
      TimelineTransitionPreset.spin => Icons.rotate_right_outlined,
      TimelineTransitionPreset.pixelate => Icons.grid_4x4_outlined,
      TimelineTransitionPreset.zoom => Icons.zoom_in_map_outlined,
      TimelineTransitionPreset.lightLeak => Icons.wb_sunny_outlined,
      null => Icons.movie_filter_outlined,
    };
    Widget buildHandle() {
      return PopupMenuButton<_TransitionMenuAction>(
        tooltip: transition.name,
        padding: EdgeInsets.zero,
        icon: const TgiAccentIcon(Icons.movie_filter, size: 18),
        onSelected: (action) {
          switch (action) {
            case _TransitionMenuAction.seek:
              onTransitionSelected(transition.timelinePosition);
              break;
            case _TransitionMenuAction.edit:
              onTransitionEdit?.call(transition);
              break;
            case _TransitionMenuAction.delete:
              onTransitionDeleted?.call(transition.id);
              break;
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: _TransitionMenuAction.seek,
            child: _TrackMenuItem(icon: Icons.my_location, label: 'Ir ate'),
          ),
          if (onTransitionEdit != null)
            const PopupMenuItem(
              value: _TransitionMenuAction.edit,
              child: _TrackMenuItem(icon: Icons.tune_outlined, label: 'Editar'),
            ),
          const PopupMenuItem(
            value: _TransitionMenuAction.delete,
            child: _TrackMenuItem(icon: Icons.delete_outline, label: 'Remover'),
          ),
        ],
      );
    }

    final handle = onTransitionMoved == null
        ? buildHandle()
        : Draggable<TimelineTransition>(
            data: transition,
            feedback: Material(
              color: TgiColors.transparent,
              child: _TransitionDragFeedback(name: transition.name),
            ),
            childWhenDragging: Opacity(opacity: 0.35, child: buildHandle()),
            child: buildHandle(),
          );

    return Stack(
      children: [
        Positioned(
          left: (left - 0.5).clamp(0.0, double.infinity).toDouble(),
          top: _rulerHeight,
          bottom: 0,
          width: 1,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: TgiColors.accentSoft.withValues(alpha: 0.24),
              ),
            ),
          ),
        ),
        Positioned(
          left: indicatorLeft,
          top: _rulerHeight + 5,
          width: indicatorWidth,
          height: 22,
          child: IgnorePointer(
            child: DecoratedBox(
              key: ValueKey('timeline_transition_indicator_${transition.id}'),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    TgiColors.accent.withValues(alpha: 0.05),
                    TgiColors.accent.withValues(alpha: 0.34),
                    TgiColors.accent.withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: TgiColors.accentSoft.withValues(alpha: 0.48),
                ),
              ),
              child: Icon(
                transitionIcon,
                size: 14,
                color: TgiColors.textPrimary.withValues(alpha: 0.88),
              ),
            ),
          ),
        ),
        Positioned(
          left: (left - 20).clamp(0.0, double.infinity).toDouble(),
          top: 0,
          width: 40,
          height: _rulerHeight,
          child: handle,
        ),
      ],
    );
  }
}

class _TransitionDragFeedback extends StatelessWidget {
  const _TransitionDragFeedback({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TgiColors.surface,
        border: Border.all(color: TgiColors.accent.withValues(alpha: 0.70)),
        borderRadius: BorderRadius.circular(TgiRadii.md),
        boxShadow: const [
          BoxShadow(
            color: TgiColors.shadow,
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TgiAccentIcon(Icons.movie_filter, size: 16),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TgiColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _TransitionMenuAction { seek, edit, delete }

Future<String?> _showRenameMarkerDialog(
  BuildContext context,
  String initialName,
) async {
  final controller = TextEditingController(text: initialName);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Renomear marcador'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(labelText: 'Nome'),
        onSubmitted: (_) => Navigator.of(context).pop(controller.text.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: const Text('Salvar'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (result == null || result.trim().isEmpty) {
    return null;
  }
  return result.trim();
}
