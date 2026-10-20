part of 'timeline_panel.dart';

class _TimelineHeader extends StatelessWidget {
  const _TimelineHeader({
    required this.zoom,
    required this.playheadPosition,
    required this.duration,
    required this.onAudioInventoryOpen,
    required this.onMarkerAdd,
    required this.onZoomChanged,
    required this.onMarkRangeStart,
    required this.onMarkRangeEnd,
    required this.onClearRange,
    required this.rangeLabel,
    required this.hasRange,
    required this.editMode,
    required this.snappingEnabled,
    required this.selectedCount,
    required this.canRippleDelete,
    required this.audioVideoLinked,
    required this.onAudioVideoLinkToggle,
    required this.onEditModeChanged,
    required this.onSnappingChanged,
    required this.onFocusSelection,
    required this.onRippleDelete,
  });

  final double zoom;
  final Duration playheadPosition;
  final Duration duration;
  final VoidCallback? onAudioInventoryOpen;
  final VoidCallback? onMarkerAdd;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback? onMarkRangeStart, onMarkRangeEnd, onClearRange;
  final String rangeLabel;
  final bool hasRange;
  final TimelineEditMode editMode;
  final bool snappingEnabled;
  final int selectedCount;
  final bool canRippleDelete;
  final bool audioVideoLinked;
  final VoidCallback? onAudioVideoLinkToggle;
  final ValueChanged<TimelineEditMode> onEditModeChanged;
  final VoidCallback onSnappingChanged;
  final VoidCallback onFocusSelection;
  final VoidCallback? onRippleDelete;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TgiColors.surfacePanel,
        border: const Border(bottom: BorderSide(color: TgiColors.borderStrong)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: TgiSpacing.md),
        child: Row(
          children: [
            const TgiAccentIcon(
              Icons.view_timeline_rounded,
              size: TgiIconSizes.sm,
            ),
            const SizedBox(width: TgiSpacing.xs),
            TgiAccentText(
              'Timeline',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TgiTextStyles.display(
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: TgiSpacing.sm),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _TimelineHeaderTool(
                        tooltip: 'Mover clipe',
                        icon: Icons.open_with_rounded,
                        selected: editMode == TimelineEditMode.move,
                        onPressed: () =>
                            onEditModeChanged(TimelineEditMode.move),
                      ),
                      _TimelineHeaderTool(
                        tooltip: 'Slip: mover o conteudo dentro do clipe',
                        icon: Icons.swap_horiz_rounded,
                        selected: editMode == TimelineEditMode.slip,
                        onPressed: () =>
                            onEditModeChanged(TimelineEditMode.slip),
                      ),
                      _TimelineHeaderTool(
                        tooltip: 'Slide: mover ajustando os clipes vizinhos',
                        icon: Icons.view_week_outlined,
                        selected: editMode == TimelineEditMode.slide,
                        onPressed: () =>
                            onEditModeChanged(TimelineEditMode.slide),
                      ),
                      const SizedBox(width: 4),
                      _TimelineHeaderTool(
                        tooltip: snappingEnabled
                            ? 'Encaixe magnetico ligado: clipes grudam nas bordas'
                            : 'Encaixe magnetico desligado',
                        icon: Icons.join_inner_rounded,
                        selected: snappingEnabled,
                        onPressed: onSnappingChanged,
                      ),
                      _TimelineHeaderTool(
                        key: const ValueKey('timeline-focus-selection'),
                        tooltip: selectedCount > 0
                            ? 'Enquadrar $selectedCount selecionado${selectedCount == 1 ? '' : 's'}'
                            : 'Selecione um clipe para enquadrar',
                        icon: Icons.center_focus_strong,
                        onPressed: selectedCount > 0 ? onFocusSelection : null,
                      ),
                      _TimelineHeaderTool(
                        tooltip: audioVideoLinked
                            ? 'Separar audio do video'
                            : 'Vincular audio ao video',
                        icon: audioVideoLinked
                            ? Icons.link_rounded
                            : Icons.link_off_rounded,
                        selected: audioVideoLinked,
                        onPressed: onAudioVideoLinkToggle,
                      ),
                      _TimelineHeaderTool(
                        tooltip: 'Ripple delete: apagar e fechar o espaco',
                        icon: Icons.auto_delete_outlined,
                        onPressed: canRippleDelete ? onRippleDelete : null,
                      ),
                      if (onMarkRangeStart != null) ...[
                        _TimelineHeaderTool(
                          tooltip: 'I · Marcar início\n$rangeLabel',
                          icon: Icons.first_page,
                          onPressed: onMarkRangeStart,
                        ),
                        _TimelineHeaderTool(
                          tooltip: 'O · Marcar fim\n$rangeLabel',
                          icon: Icons.last_page,
                          onPressed: onMarkRangeEnd,
                        ),
                        if (hasRange)
                          _TimelineHeaderTool(
                            tooltip: 'Limpar trecho',
                            icon: Icons.close,
                            onPressed: onClearRange,
                          ),
                      ],
                      const SizedBox(width: TgiSpacing.sm),
                      TimelineZoomControls(
                        zoom: zoom,
                        playheadPosition: playheadPosition,
                        duration: duration,
                        onAudioInventoryOpen: onAudioInventoryOpen,
                        onMarkerAdd: onMarkerAdd,
                        onZoomChanged: onZoomChanged,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineHeaderTool extends StatelessWidget {
  const _TimelineHeaderTool({
    super.key,
    required this.tooltip,
    required this.icon,
    this.selected = false,
    this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: selected
              ? TgiColors.surfaceHover
              : Colors.transparent,
          foregroundColor: selected
              ? TgiColors.textPrimary
              : TgiColors.textSecondary,
        ),
        icon: Icon(icon, size: 18),
      ),
    );
  }
}

Future<String?> _showRenameTrackDialog(
  BuildContext context,
  String initialName,
) async {
  final controller = TextEditingController(text: initialName);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Renomear trilha'),
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
