import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../../../domain/models/media_item.dart';
import '../../../../services/file_drop_service.dart';
import '../duration_formatter.dart';

class MediaPoolList extends StatefulWidget {
  const MediaPoolList({
    required this.items,
    required this.selectedItemId,
    required this.onItemSelected,
    this.onItemRemoved,
    this.onImportRequested,
    this.onExternalFilesDropped,
    this.onItemAppended,
    super.key,
  });

  final List<MediaItem> items;
  final String? selectedItemId;
  final ValueChanged<MediaItem> onItemSelected;
  final ValueChanged<MediaItem>? onItemRemoved;
  final VoidCallback? onImportRequested;
  final Future<void> Function(List<String> paths)? onExternalFilesDropped;
  final ValueChanged<MediaItem>? onItemAppended;

  @override
  State<MediaPoolList> createState() => _MediaPoolListState();
}

class _MediaPoolListState extends State<MediaPoolList> {
  final _dropKey = GlobalKey();
  StreamSubscription<DroppedFilesEvent>? _dropSubscription;

  @override
  void initState() {
    super.initState();
    _dropSubscription = FileDropService.events.listen(_handleDroppedFiles);
  }

  @override
  void dispose() {
    unawaited(_dropSubscription?.cancel());
    super.dispose();
  }

  void _handleDroppedFiles(DroppedFilesEvent event) {
    final onDropped = widget.onExternalFilesDropped;
    if (onDropped == null ||
        !canHandleFileDrop(
          routeIsCurrent: ModalRoute.of(context)?.isCurrent == true,
        ) ||
        !_containsDrop(event)) {
      return;
    }
    unawaited(onDropped(event.files));
  }

  bool _containsDrop(DroppedFilesEvent event) {
    final context = _dropKey.currentContext;
    final renderObject = context?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return false;
    }
    final topLeft = renderObject.localToGlobal(Offset.zero);
    return (topLeft & renderObject.size).contains(Offset(event.x, event.y));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return KeyedSubtree(
        key: _dropKey,
        child: _MediaPoolDropZone(onImportRequested: widget.onImportRequested),
      );
    }

    return KeyedSubtree(
      key: _dropKey,
      child: Column(
        children: [
          if (widget.onImportRequested != null)
            Padding(
              padding: const EdgeInsets.all(TgiSpacing.sm),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const ValueKey('media-pool-select-files'),
                  onPressed: widget.onImportRequested,
                  icon: const Icon(Icons.add),
                  label: const Text('Selecionar arquivos'),
                ),
              ),
            ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(TgiSpacing.sm),
              itemCount: widget.items.length,
              separatorBuilder: (_, _) => const SizedBox(height: TgiSpacing.sm),
              itemBuilder: (context, index) {
                final item = widget.items[index];
                final tile = _MediaPoolTile(
                  item: item,
                  selected: item.id == widget.selectedItemId,
                  onTap: () => widget.onItemSelected(item),
                  onAppend: widget.onItemAppended == null
                      ? null
                      : () => widget.onItemAppended!(item),
                  onRemove: widget.onItemRemoved == null
                      ? null
                      : () => widget.onItemRemoved!(item),
                );

                return Draggable<MediaItem>(
                  data: item,
                  // DragTarget offsets must follow the pointer, not the tile's
                  // top-left corner (which could insert seconds before the cursor).
                  dragAnchorStrategy: pointerDragAnchorStrategy,
                  maxSimultaneousDrags: 1,
                  feedback: _MediaDragFeedback(item: item),
                  childWhenDragging: Opacity(opacity: 0.45, child: tile),
                  onDragStarted: () => widget.onItemSelected(item),
                  child: tile,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaPoolDropZone extends StatelessWidget {
  const _MediaPoolDropZone({required this.onImportRequested});

  final VoidCallback? onImportRequested;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(TgiSpacing.md),
        child: _MediaPoolDropCard(
          title: 'Arraste midias aqui',
          message:
              'Nenhum arquivo importado. Solte videos, audios, imagens ou textos no Media Pool.',
          onImportRequested: onImportRequested,
          large: true,
        ),
      ),
    );
  }
}

class _MediaPoolDropCard extends StatelessWidget {
  const _MediaPoolDropCard({
    required this.title,
    required this.message,
    required this.onImportRequested,
    required this.large,
  });

  final String title;
  final String message;
  final VoidCallback? onImportRequested;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final windowSize = MediaQuery.sizeOf(context);
    final dense = !large || windowSize.width < 520 || windowSize.height < 900;
    return Material(
      color: TgiColors.transparent,
      child: InkWell(
        onTap: onImportRequested,
        borderRadius: BorderRadius.circular(TgiRadii.lg),
        child: TgiFramedBox(
          radius: TgiRadii.lg,
          padding: EdgeInsets.all(dense ? TgiSpacing.sm : TgiSpacing.lg),
          backgroundColor: TgiColors.surface.withValues(alpha: 0.78),
          borderColor: TgiColors.borderStrong,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: dense
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: TgiColors.accent.withValues(alpha: 0.10),
                  border: Border.all(color: TgiColors.accentDim),
                  borderRadius: BorderRadius.circular(TgiRadii.md),
                ),
                child: SizedBox(
                  width: dense ? 34 : 54,
                  height: dense ? 34 : 54,
                  child: Icon(
                    Icons.file_upload_outlined,
                    color: TgiColors.accent,
                    size: dense ? TgiIconSizes.sm : TgiIconSizes.lg,
                  ),
                ),
              ),
              SizedBox(height: dense ? TgiSpacing.sm : TgiSpacing.md),
              Text(
                title,
                textAlign: dense ? TextAlign.center : TextAlign.start,
                maxLines: dense ? 2 : null,
                overflow: dense ? TextOverflow.ellipsis : null,
                style: TextStyle(
                  color: TgiColors.textPrimary,
                  fontSize: dense ? 13 : 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: TgiSpacing.xs),
              Text(
                message,
                textAlign: dense ? TextAlign.center : TextAlign.start,
                maxLines: dense ? 3 : null,
                overflow: dense ? TextOverflow.ellipsis : null,
                style: TextStyle(
                  color: TgiColors.textSecondary,
                  fontSize: dense ? 11 : 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaPoolTile extends StatelessWidget {
  const _MediaPoolTile({
    required this.item,
    required this.selected,
    required this.onTap,
    this.onRemove,
    this.onAppend,
  });

  final MediaItem item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final VoidCallback? onAppend;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TgiColors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TgiRadii.lg),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: selected
                ? TgiColors.surfacePressed
                : TgiColors.surface.withValues(alpha: 0.62),
            border: Border.all(
              color: selected ? TgiColors.accentMuted : TgiColors.borderSubtle,
            ),
            borderRadius: BorderRadius.circular(TgiRadii.lg),
          ),
          padding: const EdgeInsets.all(TgiSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _Thumbnail(item: item),
              const SizedBox(width: TgiSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: TgiSpacing.xs),
                    Row(
                      children: [
                        _MediaTypePill(type: item.type),
                        const SizedBox(width: TgiSpacing.sm),
                        Expanded(
                          child: Text(
                            formatDuration(item.duration),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onAppend != null || onRemove != null) ...[
                const SizedBox(width: TgiSpacing.xs),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onAppend != null)
                      IconButton(
                        key: ValueKey('media-pool-append-${item.id}'),
                        tooltip: 'Adicionar ao fim da timeline',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.playlist_add),
                        onPressed: onAppend,
                      ),
                    if (onRemove != null)
                      IconButton(
                        tooltip: 'Remover do Media Pool',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.delete_outline),
                        color: TgiColors.textMuted,
                        onPressed: onRemove,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaDragFeedback extends StatelessWidget {
  const _MediaDragFeedback({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TgiColors.transparent,
      child: Container(
        width: 280,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: TgiColors.surfacePressed,
          border: Border.all(color: TgiColors.accentMuted),
          borderRadius: BorderRadius.circular(TgiRadii.lg),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TgiAccentIcon(Icons.drag_indicator, size: TgiIconSizes.md),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: TgiColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatDuration(item.duration),
                    style: const TextStyle(color: TgiColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final thumbnailPath = item.thumbnailPath;
    final hasThumbnail =
        thumbnailPath != null && File(thumbnailPath).existsSync();

    return ClipRRect(
      borderRadius: BorderRadius.circular(TgiRadii.md),
      child: Stack(
        children: [
          Container(
            width: 112,
            height: 64,
            decoration: BoxDecoration(
              color: TgiColors.surfaceAlt,
              border: Border.all(color: TgiColors.borderStrong),
            ),
            child: hasThumbnail
                ? Image.file(File(thumbnailPath), fit: BoxFit.cover)
                : Icon(
                    _placeholderIcon(item.type),
                    color: TgiColors.textSecondary,
                  ),
          ),
          Positioned(
            left: 5,
            bottom: 5,
            child: _MediaTypeGlyph(type: item.type),
          ),
        ],
      ),
    );
  }
}

class _MediaTypePill extends StatelessWidget {
  const _MediaTypePill({required this.type});

  final MediaType type;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TgiColors.background.withValues(alpha: 0.58),
        border: Border.all(color: TgiColors.borderStrong),
        borderRadius: BorderRadius.circular(TgiRadii.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          _typeLabel(type),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: TgiColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _MediaTypeGlyph extends StatelessWidget {
  const _MediaTypeGlyph({required this.type});

  final MediaType type;

  @override
  Widget build(BuildContext context) {
    return TgiFramedBox(
      radius: TgiRadii.sm,
      strokeWidth: 1,
      backgroundColor: TgiColors.black,
      padding: const EdgeInsets.all(4),
      child: TgiAccentIcon(_placeholderIcon(type), size: TgiIconSizes.sm),
    );
  }
}

String _typeLabel(MediaType type) {
  return switch (type) {
    MediaType.audio => 'AUDIO',
    MediaType.image => 'IMG',
    MediaType.text => 'TEXTO',
    MediaType.video => 'VIDEO',
  };
}

IconData _placeholderIcon(MediaType type) {
  return switch (type) {
    MediaType.audio => Icons.volume_up_outlined,
    MediaType.image => Icons.image_outlined,
    MediaType.text => Icons.title,
    MediaType.video => Icons.movie_outlined,
  };
}
