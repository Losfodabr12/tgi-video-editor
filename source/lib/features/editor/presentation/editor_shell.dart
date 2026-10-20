part of 'editor_screen.dart';

class _ResponsiveEditorWorkspace extends StatelessWidget {
  const _ResponsiveEditorWorkspace({required this.workspace});
  final Widget workspace;
  @override
  Widget build(BuildContext context) => workspace;
}

const _playbackSpeedOptions = <double>[0.25, 0.5, 1, 1.5, 2, 3, 4];
const _customPlaybackSpeedMenuValue = -1.0;

class _PreviewEditingActions extends StatelessWidget {
  const _PreviewEditingActions({
    required this.cutActive,
    required this.enabled,
    required this.deleteEnabled,
    required this.onCutPressed,
    required this.onDeletePressed,
    required this.onTextPressed,
  });

  final bool cutActive;
  final bool enabled;
  final bool deleteEnabled;
  final VoidCallback onCutPressed;
  final VoidCallback onDeletePressed;
  final VoidCallback onTextPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('preview-edit-tools'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _PreviewToolButton(
          tooltip: cutActive ? 'Sair do modo corte' : 'Ferramenta de corte',
          icon: Icons.content_cut,
          label: 'Corte',
          active: cutActive,
          enabled: enabled,
          onPressed: onCutPressed,
        ),
        const SizedBox(width: 4),
        _PreviewToolButton(
          tooltip: 'Excluir partes selecionadas',
          icon: Icons.delete_outline,
          label: 'Excluir',
          enabled: deleteEnabled,
          onPressed: onDeletePressed,
        ),
        const SizedBox(width: 4),
        _PreviewToolButton(
          tooltip: 'Adicionar texto',
          icon: Icons.title,
          label: 'Texto',
          enabled: enabled,
          onPressed: onTextPressed,
        ),
      ],
    );
  }
}

class _PreviewToolButton extends StatelessWidget {
  const _PreviewToolButton({
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onPressed,
    this.active = false,
  });

  final String tooltip;
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        height: 32,
        child: OutlinedButton.icon(
          onPressed: enabled ? onPressed : null,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            backgroundColor: active
                ? TgiColors.surfaceHover
                : TgiColors.surfaceAlt,
            foregroundColor: TgiColors.textPrimary,
            side: BorderSide(color: TgiColors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(TgiRadii.md),
            ),
          ),
          icon: Icon(icon, size: 15),
          label: Text(label, style: const TextStyle(fontSize: 13)),
        ),
      ),
    );
  }
}

class _PreviewOptimizeButton extends StatelessWidget {
  const _PreviewOptimizeButton({
    required this.isImporting,
    required this.isExporting,
    required this.isOptimizingPreview,
    required this.progress,
    required this.remaining,
    required this.isAutomatic,
    required this.usesProxy,
    required this.canOptimizePreview,
    required this.onPressed,
    required this.onCancel,
  });

  final bool isImporting;
  final bool isExporting;
  final bool isOptimizingPreview;
  final double progress;
  final Duration? remaining;
  final bool isAutomatic;
  final bool usesProxy;
  final bool canOptimizePreview;
  final VoidCallback onPressed;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final percent = (progress.clamp(0.0, 1.0) * 100).round();
    final remainingLabel = remaining == null || remaining == Duration.zero
        ? ''
        : ' · ~${formatDuration(remaining!)}';
    final label = isOptimizingPreview
        ? '${isAutomatic ? 'AUTO ' : ''}$percent%'
        : usesProxy
        ? 'PROXY'
        : 'ORIGINAL';
    return Tooltip(
      message: isOptimizingPreview
          ? 'Criando proxy $percent%$remainingLabel · clique para cancelar'
          : usesProxy
          ? 'Preview usando proxy leve · clique para recriar'
          : 'Preview usando arquivo original · clique para otimizar',
      child: SizedBox(
        height: 32,
        child: OutlinedButton.icon(
          key: const Key('preview_proxy_control'),
          onPressed: isOptimizingPreview
              ? onCancel
              : isImporting || isExporting || !canOptimizePreview
              ? null
              : onPressed,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            backgroundColor: isOptimizingPreview || usesProxy
                ? TgiColors.surfaceHover
                : TgiColors.surfaceRaised,
            foregroundColor: isOptimizingPreview || usesProxy
                ? TgiColors.accentSoft
                : TgiColors.textSecondary,
            side: BorderSide(
              color: isOptimizingPreview || usesProxy
                  ? TgiColors.accentMuted
                  : TgiColors.border,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(TgiRadii.md),
            ),
          ),
          icon: isOptimizingPreview
              ? SizedBox.square(
                  dimension: 15,
                  child: CircularProgressIndicator(
                    value: progress > 0 ? progress : null,
                    strokeWidth: 2,
                  ),
                )
              : Icon(
                  usesProxy ? Icons.bolt_rounded : Icons.speed_outlined,
                  size: 16,
                ),
          label: Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _PlaybackSpeedMenu extends StatelessWidget {
  const _PlaybackSpeedMenu({
    required this.speed,
    required this.enabled,
    required this.onChanged,
  });

  final double speed;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = _playbackSpeedLabel(speed);
    return PopupMenuButton<double>(
      enabled: enabled,
      tooltip: enabled ? 'Velocidade do clipe' : 'Selecione um clipe de video',
      onSelected: (value) {
        if (value == _customPlaybackSpeedMenuValue) {
          unawaited(_showCustomSpeedDialog(context));
          return;
        }
        onChanged(value);
      },
      itemBuilder: (context) => [
        for (final option in _playbackSpeedOptions)
          PopupMenuItem<double>(
            value: option,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 22,
                  child: option == speed
                      ? const Icon(Icons.check, size: 18)
                      : const SizedBox.shrink(),
                ),
                const SizedBox(width: 8),
                Text(_playbackSpeedLabel(option)),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<double>(
          value: _customPlaybackSpeedMenuValue,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune, size: 18),
              SizedBox(width: 8),
              Text('Personalizada...'),
            ],
          ),
        ),
      ],
      child: Opacity(
        opacity: enabled ? 1 : 0.55,
        child: Container(
          height: 32,
          constraints: const BoxConstraints(minWidth: 70),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: TgiColors.surfaceAlt,
            borderRadius: BorderRadius.circular(TgiRadii.md),
            border: Border.all(color: TgiColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.speed_outlined,
                size: 16,
                color: enabled
                    ? TgiColors.textPrimary
                    : TgiColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: enabled
                      ? TgiColors.textPrimary
                      : TgiColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCustomSpeedDialog(BuildContext context) async {
    final controller = TextEditingController(text: _speedInputValue(speed));
    String? errorText;
    final result = await showDialog<double>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Velocidade'),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
              ],
              decoration: InputDecoration(
                labelText: 'Multiplicador',
                suffixText: 'x',
                errorText: errorText,
              ),
              onSubmitted: (_) {
                final parsed = _parsePlaybackSpeed(controller.text);
                if (parsed == null) {
                  setState(() => errorText = 'Use um valor entre 0.25 e 4.');
                  return;
                }
                Navigator.of(context).pop(parsed);
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  final parsed = _parsePlaybackSpeed(controller.text);
                  if (parsed == null) {
                    setState(() => errorText = 'Use um valor entre 0.25 e 4.');
                    return;
                  }
                  Navigator.of(context).pop(parsed);
                },
                child: const Text('Aplicar'),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    if (result != null) {
      onChanged(result);
    }
  }
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

Duration _panelTimelineMax(Duration timelineDuration, domain.Clip clip) {
  final maxMs = math.max(
    math.max(
      const Duration(seconds: 30).inMilliseconds,
      timelineDuration.inMilliseconds,
    ),
    clip.timelineEnd.inMilliseconds + const Duration(seconds: 5).inMilliseconds,
  );
  return Duration(milliseconds: maxMs);
}

String _formatPanelDuration(Duration duration) {
  final milliseconds = duration.inMilliseconds.remainder(1000);
  if (milliseconds == 0) {
    return formatDuration(duration);
  }
  return '${formatDuration(duration)}.${milliseconds.toString().padLeft(3, '0')}';
}

IconData _clipTypeIcon(TrackType type) {
  switch (type) {
    case TrackType.video:
      return Icons.movie_outlined;
    case TrackType.audio:
      return Icons.volume_up_outlined;
    case TrackType.image:
      return Icons.image_outlined;
    case TrackType.text:
      return Icons.title;
  }
}

String _clipTypeLabel(TrackType type) {
  switch (type) {
    case TrackType.video:
      return 'Video';
    case TrackType.audio:
      return 'Audio';
    case TrackType.image:
      return 'Imagem';
    case TrackType.text:
      return 'Texto';
  }
}

String _speedInputValue(double speed) {
  if (speed == speed.roundToDouble()) {
    return speed.toStringAsFixed(0);
  }
  return speed
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

double? _parsePlaybackSpeed(String value) {
  final parsed = double.tryParse(value.replaceAll(',', '.'));
  if (parsed == null || parsed < 0.25 || parsed > 4) {
    return null;
  }
  return parsed;
}

class _WorkspaceDivider extends StatelessWidget {
  const _WorkspaceDivider({
    super.key,
    required this.axis,
    required this.onDragUpdate,
    required this.onReset,
  });

  final Axis axis;
  final GestureDragUpdateCallback onDragUpdate;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final vertical = axis == Axis.vertical;
    return Tooltip(
      message: 'Arraste para redimensionar. Duplo clique para restaurar.',
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: vertical
            ? SystemMouseCursors.resizeColumn
            : SystemMouseCursors.resizeRow,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: vertical ? onDragUpdate : null,
          onVerticalDragUpdate: vertical ? null : onDragUpdate,
          onDoubleTap: onReset,
          child: SizedBox(
            width: vertical ? _workspaceDividerExtent : double.infinity,
            height: vertical ? double.infinity : _workspaceDividerExtent,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: vertical ? 2 : 28,
                height: vertical ? 28 : 2,
                decoration: BoxDecoration(
                  color: TgiColors.borderStrong,
                  borderRadius: BorderRadius.circular(TgiRadii.md),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.child,
    this.icon,
    this.glow = false,
    this.showHeader = true,
    this.accentColor,
    this.trailing,
  });

  final String title;
  final Widget child;
  final IconData? icon;
  final bool glow;
  final bool showHeader;
  final Color? accentColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: TgiColors.surfacePanel,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader)
          SizedBox(
            height: 32,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: TgiColors.textSecondary,
                      ),
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          ),
        Expanded(child: child),
      ],
    ),
  );
}
