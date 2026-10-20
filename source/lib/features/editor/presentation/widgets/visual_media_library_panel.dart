import 'package:flutter/material.dart';

import '../../../../app/theme/decorations.dart';
import '../../../../app/theme/design_tokens.dart';
import '../../../../services/visual_media_service.dart';

class VisualMediaLibraryPanel extends StatefulWidget {
  const VisualMediaLibraryPanel({
    required this.items,
    required this.onAddItem,
    this.addingItemId,
    super.key,
  });

  final List<PublicVisualMediaItem> items;
  final String? addingItemId;
  final ValueChanged<PublicVisualMediaItem> onAddItem;

  @override
  State<VisualMediaLibraryPanel> createState() =>
      _VisualMediaLibraryPanelState();
}

class _VisualMediaLibraryPanelState extends State<VisualMediaLibraryPanel> {
  static const _allLibraries = 'Todas';
  static const _allCategories = 'Todos';

  final _searchController = TextEditingController();
  final _libraryScrollController = ScrollController();
  String _type = PublicVisualMediaService.memeType;
  String _library = _allLibraries;
  String _category = _allCategories;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    _libraryScrollController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final types = const [
      PublicVisualMediaService.memeType,
      PublicVisualMediaService.imageType,
    ];
    final typeFiltered = widget.items
        .where((item) => item.type == _type)
        .toList(growable: false);
    final libraries = [
      _allLibraries,
      ...{for (final item in typeFiltered) item.library},
    ];
    final activeLibrary = libraries.contains(_library)
        ? _library
        : _allLibraries;
    final libraryFiltered = typeFiltered
        .where(
          (item) =>
              activeLibrary == _allLibraries || item.library == activeLibrary,
        )
        .toList(growable: false);
    final categories = [
      _allCategories,
      ...{for (final item in libraryFiltered) item.category},
    ];
    final activeCategory = categories.contains(_category)
        ? _category
        : _allCategories;
    final query = _searchController.text.trim().toLowerCase();
    final filtered = libraryFiltered
        .where((item) {
          final matchesCategory =
              activeCategory == _allCategories ||
              item.category == activeCategory;
          final matchesQuery =
              query.isEmpty ||
              item.name.toLowerCase().contains(query) ||
              item.category.toLowerCase().contains(query) ||
              item.sourceName.toLowerCase().contains(query) ||
              item.library.toLowerCase().contains(query) ||
              item.fileName.toLowerCase().contains(query);
          return matchesCategory && matchesQuery;
        })
        .toList(growable: false);
    final filtersActive =
        query.isNotEmpty ||
        activeLibrary != _allLibraries ||
        activeCategory != _allCategories;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(TgiSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _VisualTypeTabs(
                types: types,
                selectedType: _type,
                items: widget.items,
                onTypeChanged: (type) {
                  setState(() {
                    _type = type;
                    _library = _allLibraries;
                    _category = _allCategories;
                  });
                },
              ),
              const SizedBox(height: TgiSpacing.sm),
              _VisualSearchField(controller: _searchController),
              const SizedBox(height: TgiSpacing.sm),
              _VisualSourceCard(
                count: typeFiltered.length,
                resultCount: filtered.length,
                type: _type,
                filtersActive: filtersActive,
                onClearFilters: filtersActive
                    ? () => setState(() {
                        _searchController.clear();
                        _library = _allLibraries;
                        _category = _allCategories;
                      })
                    : null,
              ),
              const SizedBox(height: TgiSpacing.sm),
              _HorizontalFilterScroller(
                controller: _libraryScrollController,
                children: [
                  for (final library in libraries) ...[
                    _CategoryChip(
                      label: library,
                      selected: library == activeLibrary,
                      onTap: () => setState(() {
                        _library = library;
                        _category = _allCategories;
                      }),
                    ),
                    const SizedBox(width: TgiSpacing.xs),
                  ],
                ],
              ),
              const SizedBox(height: TgiSpacing.sm),
              _VisualCategoryDropdown(
                categories: categories,
                selectedCategory: activeCategory,
                onChanged: (category) => setState(() => _category = category),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: TgiColors.borderSubtle),
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Text(
                    'Nenhuma midia encontrada',
                    style: TextStyle(color: TgiColors.textSecondary),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(TgiSpacing.md),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: TgiSpacing.sm),
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return _VisualMediaTile(
                      item: item,
                      adding: widget.addingItemId == item.id,
                      addBlocked:
                          widget.addingItemId != null &&
                          widget.addingItemId != item.id,
                      onAdd: () => widget.onAddItem(item),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _VisualTypeTabs extends StatelessWidget {
  const _VisualTypeTabs({
    required this.types,
    required this.selectedType,
    required this.items,
    required this.onTypeChanged,
  });

  final List<String> types;
  final String selectedType;
  final List<PublicVisualMediaItem> items;
  final ValueChanged<String> onTypeChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TgiColors.background.withValues(alpha: 0.62),
        border: Border.all(color: TgiColors.borderStrong),
        borderRadius: BorderRadius.circular(TgiRadii.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            for (final type in types)
              Expanded(
                child: _VisualTypeTab(
                  label: type,
                  count: items.where((item) => item.type == type).length,
                  selected: type == selectedType,
                  onTap: () => onTypeChanged(type),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _VisualTypeTab extends StatelessWidget {
  const _VisualTypeTab({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TgiColors.transparent,
      child: InkWell(
        onTap: selected ? null : onTap,
        borderRadius: BorderRadius.circular(TgiRadii.md),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: selected
              ? TgiDecorations.activeControl(radius: TgiRadii.md)
              : const BoxDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              selected
                  ? TgiAccentText(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ) ??
                          const TextStyle(fontWeight: FontWeight.w900),
                    )
                  : Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: TgiColors.textMuted,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
              const SizedBox(height: 4),
              selected
                  ? TgiAccentText(
                      '$count',
                      style:
                          Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                          ) ??
                          const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                          ),
                    )
                  : Text(
                      '$count',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: TgiColors.textSecondary,
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HorizontalFilterScroller extends StatelessWidget {
  const _HorizontalFilterScroller({
    required this.controller,
    required this.children,
  });

  final ScrollController controller;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: controller,
      thumbVisibility: true,
      trackVisibility: true,
      interactive: true,
      radius: const Radius.circular(TgiRadii.pill),
      thickness: 4,
      child: SingleChildScrollView(
        controller: controller,
        scrollDirection: Axis.horizontal,
        primary: false,
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: children),
      ),
    );
  }
}

class _VisualSourceCard extends StatelessWidget {
  const _VisualSourceCard({
    required this.count,
    required this.resultCount,
    required this.type,
    required this.filtersActive,
    required this.onClearFilters,
  });

  final int count;
  final int resultCount;
  final String type;
  final bool filtersActive;
  final VoidCallback? onClearFilters;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TgiColors.surfacePanel,
        border: Border.all(color: TgiColors.accentMuted),
        borderRadius: BorderRadius.circular(TgiRadii.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(TgiSpacing.md),
        child: Row(
          children: [
            _VisualGlyph(
              icon: type == PublicVisualMediaService.memeType
                  ? Icons.theater_comedy_outlined
                  : Icons.image_outlined,
            ),
            const SizedBox(width: TgiSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: TgiColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: TgiSpacing.xxs),
                  Text(
                    '$count itens disponiveis',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: TgiColors.textSecondary,
                    ),
                  ),
                  if (filtersActive) ...[
                    const SizedBox(height: TgiSpacing.xxs),
                    Text(
                      '$resultCount resultados no filtro atual',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: TgiColors.accentSoft,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (filtersActive) ...[
              const SizedBox(width: TgiSpacing.sm),
              TextButton.icon(
                onPressed: onClearFilters,
                icon: const Icon(Icons.filter_alt_off_outlined, size: 15),
                label: const Text('Limpar'),
                style: TextButton.styleFrom(
                  foregroundColor: TgiColors.textSecondary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ] else
              const _LicensePill(label: 'GitHub'),
          ],
        ),
      ),
    );
  }
}

class _VisualSearchField extends StatelessWidget {
  const _VisualSearchField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: TgiColors.textPrimary, fontSize: 13),
      cursorColor: TgiColors.accent,
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Buscar midia visual',
        hintStyle: const TextStyle(color: TgiColors.textSecondary),
        prefixIcon: const Icon(
          Icons.search,
          size: TgiIconSizes.md,
          color: TgiColors.textSecondary,
        ),
        filled: true,
        fillColor: TgiColors.background.withValues(alpha: 0.62),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: TgiColors.borderStrong),
          borderRadius: BorderRadius.circular(TgiRadii.lg),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: TgiColors.accentDim),
          borderRadius: BorderRadius.circular(TgiRadii.lg),
        ),
      ),
    );
  }
}

class _VisualCategoryDropdown extends StatelessWidget {
  const _VisualCategoryDropdown({
    required this.categories,
    required this.selectedCategory,
    required this.onChanged,
  });

  final List<String> categories;
  final String selectedCategory;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: selectedCategory,
      isExpanded: true,
      menuMaxHeight: 320,
      dropdownColor: TgiColors.surfacePanel,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: TgiColors.textPrimary,
        fontWeight: FontWeight.w800,
      ),
      decoration: InputDecoration(
        isDense: true,
        labelText: 'Categoria',
        labelStyle: const TextStyle(color: TgiColors.textSecondary),
        prefixIcon: const Icon(
          Icons.category_outlined,
          size: TgiIconSizes.md,
          color: TgiColors.textSecondary,
        ),
        filled: true,
        fillColor: TgiColors.background.withValues(alpha: 0.62),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: TgiColors.borderStrong),
          borderRadius: BorderRadius.circular(TgiRadii.lg),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: TgiColors.accentDim),
          borderRadius: BorderRadius.circular(TgiRadii.lg),
        ),
      ),
      items: [
        for (final category in categories)
          DropdownMenuItem<String>(
            value: category,
            child: Text(category, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (category) {
        if (category != null) {
          onChanged(category);
        }
      },
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TgiColors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TgiRadii.pill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: selected
              ? TgiDecorations.activeControl(radius: TgiRadii.pill)
              : BoxDecoration(
                  color: TgiColors.surface.withValues(alpha: 0.62),
                  border: Border.all(color: TgiColors.borderStrong),
                  borderRadius: BorderRadius.circular(TgiRadii.pill),
                ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: selected ? TgiColors.textPrimary : TgiColors.textMuted,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _VisualMediaTile extends StatelessWidget {
  const _VisualMediaTile({
    required this.item,
    required this.adding,
    required this.addBlocked,
    required this.onAdd,
  });

  final PublicVisualMediaItem item;
  final bool adding;
  final bool addBlocked;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TgiColors.surface.withValues(alpha: 0.62),
        border: Border.all(color: TgiColors.borderSubtle),
        borderRadius: BorderRadius.circular(TgiRadii.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(TgiSpacing.sm),
        child: Row(
          children: [
            _VisualMediaThumbnail(item: item),
            const SizedBox(width: TgiSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: TgiColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: TgiSpacing.xxs),
                  Text(
                    '${item.sourceName} - ${item.category} - ${item.license}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: TgiColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: TgiSpacing.xxs),
                  Row(
                    children: [
                      Icon(
                        item.isVideo
                            ? Icons.movie_filter_outlined
                            : Icons.image_outlined,
                        size: 12,
                        color: TgiColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          item.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: TgiColors.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: TgiSpacing.sm),
            SizedBox(
              height: 34,
              child: TextButton.icon(
                onPressed: adding || addBlocked ? null : onAdd,
                icon: adding
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: TgiColors.textSecondary,
                        ),
                      )
                    : const TgiAccentIcon(Icons.add, size: TgiIconSizes.sm),
                label: Text(adding ? 'Baixando' : 'Adicionar'),
                style: TextButton.styleFrom(
                  foregroundColor: TgiColors.accentSoft,
                  disabledForegroundColor: TgiColors.textSecondary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(TgiRadii.md),
                    side: BorderSide(color: TgiColors.accentMuted),
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

class _VisualMediaThumbnail extends StatelessWidget {
  const _VisualMediaThumbnail({required this.item});

  final PublicVisualMediaItem item;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(TgiRadii.md),
      child: TgiFramedBox(
        radius: TgiRadii.md,
        strokeWidth: 1.2,
        child: SizedBox(
          width: 46,
          height: 46,
          child: item.isImage
              ? Image.network(
                  item.downloadUrl,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, _, _) =>
                      const _ThumbnailIcon(icon: Icons.broken_image_outlined),
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) {
                      return child;
                    }
                    return Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: TgiColors.textSecondary,
                        ),
                      ),
                    );
                  },
                )
              : const _ThumbnailIcon(icon: Icons.movie_filter_outlined),
        ),
      ),
    );
  }
}

class _ThumbnailIcon extends StatelessWidget {
  const _ThumbnailIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return TgiAccentIcon(icon, size: TgiIconSizes.lg);
  }
}

class _VisualGlyph extends StatelessWidget {
  const _VisualGlyph({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return TgiFramedBox(
      radius: TgiRadii.md,
      strokeWidth: 1.2,
      child: SizedBox(
        width: 38,
        height: 38,
        child: TgiAccentIcon(icon, size: TgiIconSizes.lg),
      ),
    );
  }
}

class _LicensePill extends StatelessWidget {
  const _LicensePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TgiColors.background.withValues(alpha: 0.72),
        border: Border.all(color: TgiColors.accentMuted),
        borderRadius: BorderRadius.circular(TgiRadii.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: TgiAccentText(
          label,
          style:
              Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w900,
                fontSize: 10,
              ) ??
              const TextStyle(fontWeight: FontWeight.w900, fontSize: 10),
        ),
      ),
    );
  }
}
