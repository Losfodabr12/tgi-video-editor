part of 'timeline_panel.dart';

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
    this.onTrackDeleted,
    this.onTrackReordered,
    this.onTrackHeightChanged,
    this.onTrackResizeStart,
    this.onTrackResizeEnd,
  });

  final List<Track> tracks;
  final ScrollController scrollController;
  final ValueChanged<TrackType>? onAddTrack;
  final void Function(String, String)? onTrackRenamed;
  final void Function(String, bool)? onTrackLockedChanged,
      onTrackHiddenChanged,
      onTrackMutedChanged,
      onTrackSoloChanged;
  final ValueChanged<String>? onTrackDeleted;
  final void Function(String, int)? onTrackReordered;
  final void Function(String, double)? onTrackHeightChanged;
  final VoidCallback? onTrackResizeStart, onTrackResizeEnd;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: _trackHeaderWidth,
    child: Column(
      children: [
        SizedBox(
          height: _rulerHeight + 1,
          child: Row(
            children: [
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'CAMADAS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                    color: TgiColors.textMuted,
                  ),
                ),
              ),
              PopupMenuButton<TrackType>(
                tooltip: 'Adicionar pista',
                icon: const Icon(Icons.add, size: 16),
                onSelected: onAddTrack,
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: TrackType.video,
                    child: Text('Nova pista visual'),
                  ),
                  PopupMenuItem(
                    value: TrackType.audio,
                    child: Text('Nova pista de áudio'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            itemCount: tracks.length + 1,
            itemBuilder: (context, row) {
              if (row == 0) return const SizedBox(height: _newLaneExtent);
              final index = row - 1;
              final track = tracks[index];
              var resizeHeight = track.height;
              return SizedBox(
                key: ValueKey('track-header-${track.id}'),
                height: track.height,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        onDoubleTap: () async {
                          final name = await _showRenameTrackDialog(
                            context,
                            track.name,
                          );
                          if (name != null) {
                            onTrackRenamed?.call(track.id, name);
                          }
                        },
                        onSecondaryTapDown: (details) => _menu(
                          context,
                          track,
                          index,
                          details.globalPosition,
                        ),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: TgiColors.surfacePanel,
                            border: Border(
                              bottom: BorderSide(color: TgiColors.borderSubtle),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    track.kind == TrackKind.audio
                                        ? Icons.audiotrack_outlined
                                        : Icons.layers_outlined,
                                    size: 14,
                                    color: TgiColors.textMuted,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      track.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: IconButton(
                                      padding: EdgeInsets.zero,
                                      tooltip: 'Opções da pista',
                                      icon: const Icon(
                                        Icons.more_horiz,
                                        size: 16,
                                      ),
                                      onPressed: () {
                                        final box =
                                            context.findRenderObject()
                                                as RenderBox;
                                        _menu(
                                          context,
                                          track,
                                          index,
                                          box.localToGlobal(Offset.zero),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  _control(
                                    track.isLocked
                                        ? 'Destravar pista'
                                        : 'Bloquear pista',
                                    track.isLocked
                                        ? Icons.lock
                                        : Icons.lock_open_outlined,
                                    track.isLocked,
                                    () => onTrackLockedChanged?.call(
                                      track.id,
                                      !track.isLocked,
                                    ),
                                  ),
                                  _control(
                                    track.isHidden
                                        ? 'Mostrar pista'
                                        : 'Ocultar pista',
                                    track.isHidden
                                        ? Icons.visibility_off
                                        : Icons.visibility_outlined,
                                    track.isHidden,
                                    () => onTrackHiddenChanged?.call(
                                      track.id,
                                      !track.isHidden,
                                    ),
                                  ),
                                  if (track.kind == TrackKind.audio) ...[
                                    _control(
                                      'Silenciar pista',
                                      Icons.volume_off_outlined,
                                      track.isMuted,
                                      () => onTrackMutedChanged?.call(
                                        track.id,
                                        !track.isMuted,
                                      ),
                                    ),
                                    _control(
                                      'Ouvir somente esta pista',
                                      Icons.headphones_outlined,
                                      track.isSolo,
                                      () => onTrackSoloChanged?.call(
                                        track.id,
                                        !track.isSolo,
                                      ),
                                    ),
                                  ] else ...[
                                    Expanded(
                                      child: Text(
                                        '${track.clips.length} clipes',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(
                                          fontSize: 9,
                                          color: TgiColors.textMuted,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 4,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeRow,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onVerticalDragStart: (_) {
                            resizeHeight = track.height;
                            onTrackResizeStart?.call();
                          },
                          onVerticalDragUpdate: (details) {
                            resizeHeight = (resizeHeight + details.delta.dy)
                                .clamp(44, 180);
                            onTrackHeightChanged?.call(track.id, resizeHeight);
                          },
                          onVerticalDragEnd: (_) => onTrackResizeEnd?.call(),
                          onVerticalDragCancel: () => onTrackResizeEnd?.call(),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    ),
  );

  Widget _control(
    String tooltip,
    IconData icon,
    bool active,
    VoidCallback action,
  ) => SizedBox(
    width: 25,
    height: 18,
    child: IconButton(
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      icon: Icon(
        icon,
        size: 12,
        color: active ? TgiColors.accent : TgiColors.textMuted,
      ),
      onPressed: action,
    ),
  );

  Future<void> _menu(
    BuildContext context,
    Track track,
    int index,
    Offset position,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem(value: 'rename', child: Text('Renomear')),
        PopupMenuItem(
          value: 'up',
          enabled: !track.isLocked && index > 0,
          child: const Text('Mover pista para cima'),
        ),
        PopupMenuItem(
          value: 'down',
          enabled: !track.isLocked && index < tracks.length - 1,
          child: const Text('Mover pista para baixo'),
        ),
        for (final height in [44, 64, 96, 128])
          PopupMenuItem(
            value: 'height$height',
            child: Text('Altura: $height px'),
          ),
        PopupMenuItem(
          value: 'delete',
          enabled: !track.isLocked,
          child: const Text('Excluir pista'),
        ),
      ],
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case 'rename':
        final name = await _showRenameTrackDialog(context, track.name);
        if (name != null) onTrackRenamed?.call(track.id, name);
      case 'up':
        onTrackReordered?.call(track.id, index - 1);
      case 'down':
        onTrackReordered?.call(track.id, index + 1);
      case 'delete':
        final confirmed =
            track.clips.isEmpty ||
            await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Excluir pista?'),
                    content: Text(
                      'Remover ${track.clips.length} clipes desta pista? Você pode desfazer com Ctrl+Z.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Excluir'),
                      ),
                    ],
                  ),
                ) ==
                true;
        if (confirmed) onTrackDeleted?.call(track.id);
      default:
        if (action.startsWith('height')) {
          onTrackHeightChanged?.call(
            track.id,
            double.parse(action.substring(6)),
          );
        }
    }
  }
}

class _TrackMenuItem extends StatelessWidget {
  const _TrackMenuItem({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [Icon(icon, size: 16), const SizedBox(width: 8), Text(label)],
  );
}
