part of 'timeline_panel.dart';

class _TimelineHeader extends StatelessWidget {
  const _TimelineHeader({
    required this.zoom,
    required this.playheadPosition,
    required this.duration,
    required this.onAudioInventoryOpen,
    required this.onMarkerAdd,
    required this.onZoomOut,
    required this.onZoomIn,
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
  final VoidCallback? onZoomOut;
  final VoidCallback? onZoomIn;
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
                      const SizedBox(width: TgiSpacing.sm),
                      TimelineZoomControls(
                        zoom: zoom,
                        playheadPosition: playheadPosition,
                        duration: duration,
                        onAudioInventoryOpen: onAudioInventoryOpen,
                        onMarkerAdd: onMarkerAdd,
                        onZoomOut: onZoomOut,
                        onZoomIn: onZoomIn,
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
              ? TgiColors.accent.withValues(alpha: 0.18)
              : Colors.transparent,
          foregroundColor: selected ? TgiColors.accent : TgiColors.textMuted,
        ),
        icon: Icon(icon, size: 18),
      ),
    );
  }
}

class _TrackLabels extends StatelessWidget {
  const _TrackLabels({
    required this.tracks,
    required this.scrollController,
    this.onAddTrack,
    this.onTrackRenamed,
    this.onTrackLockedChanged,
    this.onTrackHiddenChanged,
    this.onTrackMutedChanged,
    this.onTrackSoloChanged,
  });

  final List<Track> tracks;
  final ScrollController scrollController;
  final ValueChanged<TrackType>? onAddTrack;
  final void Function(String trackId, String name)? onTrackRenamed;
  final void Function(String trackId, bool isLocked)? onTrackLockedChanged;
  final void Function(String trackId, bool isHidden)? onTrackHiddenChanged;
  final void Function(String trackId, bool isMuted)? onTrackMutedChanged;
  final void Function(String trackId, bool isSolo)? onTrackSoloChanged;

  @override
  Widget build(BuildContext context) {
    final trackHeaderWidth = MediaQuery.sizeOf(context).width < 520
        ? 180.0
        : _trackHeaderWidth;
    return SizedBox(
      width: trackHeaderWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: _rulerHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: TgiColors.surfacePanel,
                border: const Border(
                  right: BorderSide(color: TgiColors.border),
                  bottom: BorderSide(color: TgiColors.borderStrong),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: TgiSpacing.sm, right: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: const TgiFramedBox(
                        radius: TgiRadii.sm,
                        strokeWidth: 1,
                        backgroundColor: TgiColors.backgroundDeep,
                        child: TgiAccentIcon(
                          Icons.layers_outlined,
                          size: TgiIconSizes.sm,
                        ),
                      ),
                    ),
                    const SizedBox(width: TgiSpacing.sm),
                    Expanded(
                      child: Text(
                        'Trilhas',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: TgiColors.textMuted,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (onAddTrack != null)
                      _AddTrackMenu(onSelected: onAddTrack!),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: tracks.isEmpty
                ? const SizedBox.shrink()
                : ListView.builder(
                    controller: scrollController,
                    itemExtent: _trackHeight,
                    itemCount: tracks.length,
                    itemBuilder: (context, index) {
                      final track = tracks[index];
                      return _TrackLabel(
                        track: track,
                        index: index,
                        onRenamed: onTrackRenamed,
                        onLockedChanged: onTrackLockedChanged,
                        onHiddenChanged: onTrackHiddenChanged,
                        onMutedChanged: onTrackMutedChanged,
                        onSoloChanged: onTrackSoloChanged,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AddTrackMenu extends StatelessWidget {
  const _AddTrackMenu({required this.onSelected});

  final ValueChanged<TrackType> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<TrackType>(
      tooltip: 'Adicionar trilha',
      icon: const Icon(Icons.add, size: 18),
      padding: EdgeInsets.zero,
      iconColor: TgiColors.textPrimary,
      onSelected: onSelected,
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: TrackType.video,
          child: _AddTrackMenuItem(
            icon: Icons.movie_outlined,
            label: 'Video + audio',
          ),
        ),
        PopupMenuItem(
          value: TrackType.image,
          child: _AddTrackMenuItem(icon: Icons.image_outlined, label: 'Imagem'),
        ),
        PopupMenuItem(
          value: TrackType.text,
          child: _AddTrackMenuItem(icon: Icons.title, label: 'Texto'),
        ),
        PopupMenuItem(
          value: TrackType.audio,
          child: _AddTrackMenuItem(
            icon: Icons.volume_up_outlined,
            label: 'Audio',
          ),
        ),
      ],
    );
  }
}

class _AddTrackMenuItem extends StatelessWidget {
  const _AddTrackMenuItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 18), const SizedBox(width: 10), Text(label)],
    );
  }
}

class _TrackLabel extends StatelessWidget {
  const _TrackLabel({
    required this.track,
    required this.index,
    required this.onRenamed,
    required this.onLockedChanged,
    required this.onHiddenChanged,
    required this.onMutedChanged,
    required this.onSoloChanged,
  });

  final Track track;
  final int index;
  final void Function(String trackId, String name)? onRenamed;
  final void Function(String trackId, bool isLocked)? onLockedChanged;
  final void Function(String trackId, bool isHidden)? onHiddenChanged;
  final void Function(String trackId, bool isMuted)? onMutedChanged;
  final void Function(String trackId, bool isSolo)? onSoloChanged;

  @override
  Widget build(BuildContext context) {
    final accentColor = _trackAccentFor(track.type);
    return Container(
      padding: const EdgeInsets.only(left: TgiSpacing.sm, right: 4),
      decoration: BoxDecoration(
        color: _timelineLaneFillFor(index, track),
        border: Border(
          left: BorderSide(
            color: track.isHidden
                ? TgiColors.borderSubtle
                : accentColor.withValues(alpha: track.isLocked ? 0.34 : 0.68),
            width: 3,
          ),
          bottom: const BorderSide(color: TgiColors.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          _TrackIconBadge(
            icon: track.isLocked ? Icons.lock_outline : _trackIcon(track.type),
            muted: track.isHidden,
            accentColor: accentColor,
          ),
          const SizedBox(width: TgiSpacing.sm),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: track.isHidden
                        ? TgiColors.textSecondary
                        : TgiColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (track.isHidden)
                      const _TrackStateIcon(
                        icon: Icons.visibility_off_outlined,
                        tooltip: 'Oculta',
                      ),
                    if (track.isMuted)
                      const _TrackStateIcon(
                        icon: Icons.volume_off_outlined,
                        tooltip: 'Mutada',
                      ),
                    if (track.isSolo)
                      const _TrackStateIcon(
                        icon: Icons.headphones_outlined,
                        tooltip: 'Solo',
                      ),
                    if (!track.isHidden && !track.isMuted && !track.isSolo)
                      Expanded(
                        child: Text(
                          _trackTypeLabel(track.type),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontSize: 10,
                                color: TgiColors.textSecondary,
                              ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          _TrackControlMenu(
            track: track,
            onRenamed: onRenamed,
            onLockedChanged: onLockedChanged,
            onHiddenChanged: onHiddenChanged,
            onMutedChanged: onMutedChanged,
            onSoloChanged: onSoloChanged,
          ),
        ],
      ),
    );
  }
}

class _TrackStateIcon extends StatelessWidget {
  const _TrackStateIcon({required this.icon, required this.tooltip});

  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.only(right: 5),
        child: Icon(icon, size: 13, color: TgiColors.textSecondary),
      ),
    );
  }
}

class _TrackIconBadge extends StatelessWidget {
  const _TrackIconBadge({
    required this.icon,
    required this.muted,
    required this.accentColor,
  });

  final IconData icon;
  final bool muted;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final color = muted ? TgiColors.textSecondary : accentColor;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: muted
            ? TgiColors.surface.withValues(alpha: 0.74)
            : accentColor.withValues(alpha: 0.14),
        border: Border.all(
          color: muted
              ? TgiColors.borderStrong
              : accentColor.withValues(alpha: 0.58),
        ),
        borderRadius: BorderRadius.circular(TgiRadii.md),
        boxShadow: muted
            ? null
            : [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.10),
                  blurRadius: 12,
                  spreadRadius: -4,
                ),
              ],
      ),
      child: Icon(icon, size: TgiIconSizes.md, color: color),
    );
  }
}

class _TrackControlMenu extends StatelessWidget {
  const _TrackControlMenu({
    required this.track,
    required this.onRenamed,
    required this.onLockedChanged,
    required this.onHiddenChanged,
    required this.onMutedChanged,
    required this.onSoloChanged,
  });

  final Track track;
  final void Function(String trackId, String name)? onRenamed;
  final void Function(String trackId, bool isLocked)? onLockedChanged;
  final void Function(String trackId, bool isHidden)? onHiddenChanged;
  final void Function(String trackId, bool isMuted)? onMutedChanged;
  final void Function(String trackId, bool isSolo)? onSoloChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_TrackMenuAction>(
      tooltip: 'Controles da trilha',
      icon: const Icon(Icons.more_vert, size: 18),
      padding: EdgeInsets.zero,
      onSelected: (action) async {
        switch (action) {
          case _TrackMenuAction.rename:
            final name = await _showRenameTrackDialog(context, track.name);
            if (name != null) {
              onRenamed?.call(track.id, name);
            }
            break;
          case _TrackMenuAction.lock:
            onLockedChanged?.call(track.id, !track.isLocked);
            break;
          case _TrackMenuAction.hide:
            onHiddenChanged?.call(track.id, !track.isHidden);
            break;
          case _TrackMenuAction.mute:
            onMutedChanged?.call(track.id, !track.isMuted);
            break;
          case _TrackMenuAction.solo:
            onSoloChanged?.call(track.id, !track.isSolo);
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: _TrackMenuAction.rename,
          child: _TrackMenuItem(
            icon: Icons.drive_file_rename_outline,
            label: 'Renomear',
          ),
        ),
        PopupMenuItem(
          value: _TrackMenuAction.lock,
          child: _TrackMenuItem(
            icon: track.isLocked
                ? Icons.lock_open_outlined
                : Icons.lock_outline,
            label: track.isLocked ? 'Destravar' : 'Travar',
          ),
        ),
        PopupMenuItem(
          value: _TrackMenuAction.hide,
          child: _TrackMenuItem(
            icon: track.isHidden
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            label: track.isHidden ? 'Mostrar' : 'Ocultar',
          ),
        ),
        if (track.type == TrackType.audio) ...[
          PopupMenuItem(
            value: _TrackMenuAction.mute,
            child: _TrackMenuItem(
              icon: track.isMuted
                  ? Icons.volume_up_outlined
                  : Icons.volume_off_outlined,
              label: track.isMuted ? 'Ativar audio' : 'Mutar',
            ),
          ),
          PopupMenuItem(
            value: _TrackMenuAction.solo,
            child: _TrackMenuItem(
              icon: Icons.headphones_outlined,
              label: track.isSolo ? 'Sair do solo' : 'Solo',
            ),
          ),
        ],
      ],
    );
  }
}

enum _TrackMenuAction { rename, lock, hide, mute, solo }

class _TrackMenuItem extends StatelessWidget {
  const _TrackMenuItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 18), const SizedBox(width: 10), Text(label)],
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

String _trackTypeLabel(TrackType type) {
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
