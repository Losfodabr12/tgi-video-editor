import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../../../app/theme/decorations.dart';
import '../../../../services/sound_effects_service.dart';

enum _SoundCollection { all, favorites, recent }

class SoundEffectsLibraryPanel extends StatefulWidget {
  const SoundEffectsLibraryPanel({
    required this.effects,
    required this.onAddEffect,
    required this.onPreviewEffect,
    this.addingEffectId,
    this.previewingEffectId,
    this.loadingPreviewEffectId,
    this.previewPosition = Duration.zero,
    this.previewDuration = Duration.zero,
    super.key,
  });

  final List<PublicSoundEffect> effects;
  final String? addingEffectId;
  final String? previewingEffectId;
  final String? loadingPreviewEffectId;
  final Duration previewPosition;
  final Duration previewDuration;
  final ValueChanged<PublicSoundEffect> onAddEffect;
  final ValueChanged<PublicSoundEffect> onPreviewEffect;

  @override
  State<SoundEffectsLibraryPanel> createState() =>
      _SoundEffectsLibraryPanelState();
}

class _SoundEffectsLibraryPanelState extends State<SoundEffectsLibraryPanel> {
  static const _allLibraries = 'Todas';
  static const _maxRecentItems = 24;

  final _searchController = TextEditingController();
  final _libraryScrollController = ScrollController();
  String _type = PublicSoundEffectsService.soundEffectType;
  String _library = _allLibraries;
  _SoundCollection _collection = _SoundCollection.all;
  Set<String> _favoriteIds = {};
  List<String> _recentIds = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    _loadLibraryState();
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

  Future<void> _loadLibraryState() async {
    try {
      final file = File(_libraryStatePath());
      if (!await file.exists()) {
        return;
      }
      final data = jsonDecode(await file.readAsString());
      if (data is! Map<String, Object?>) {
        return;
      }
      final favorites = data['favorites'];
      final recent = data['recent'];
      if (!mounted) {
        return;
      }
      setState(() {
        _favoriteIds = {
          if (favorites is List)
            for (final id in favorites)
              if (id is String) id,
        };
        _recentIds = [
          if (recent is List)
            for (final id in recent)
              if (id is String) id,
        ];
      });
    } catch (_) {
      // Corrupt state should not block the sound library.
    }
  }

  Future<void> _saveLibraryState() async {
    try {
      final file = File(_libraryStatePath());
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'favorites': _favoriteIds.toList()..sort(),
          'recent': _recentIds.take(_maxRecentItems).toList(),
        }),
      );
    } catch (_) {
      // Persistence is helpful, but the editor must remain usable without it.
    }
  }

  String _libraryStatePath() {
    final base =
        Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    return [
      base,
      'TGIAPP',
      'sound_library_state.json',
    ].join(Platform.pathSeparator);
  }

  void _toggleFavorite(PublicSoundEffect effect) {
    setState(() {
      final next = Set<String>.of(_favoriteIds);
      if (!next.add(effect.id)) {
        next.remove(effect.id);
      }
      _favoriteIds = next;
    });
    unawaited(_saveLibraryState());
  }

  void _recordRecent(PublicSoundEffect effect) {
    setState(() {
      _recentIds = [
        effect.id,
        for (final id in _recentIds)
          if (id != effect.id) id,
      ].take(_maxRecentItems).toList(growable: false);
    });
    unawaited(_saveLibraryState());
  }

  @override
  Widget build(BuildContext context) {
    final types = const [
      PublicSoundEffectsService.soundEffectType,
      PublicSoundEffectsService.soundtrackType,
    ];
    final typeFiltered = widget.effects
        .where((effect) => effect.type == _type)
        .toList(growable: false);
    final libraries = [
      _allLibraries,
      ...{for (final effect in typeFiltered) effect.library},
    ];
    final activeLibrary = libraries.contains(_library)
        ? _library
        : _allLibraries;
    final libraryFiltered = typeFiltered
        .where(
          (effect) =>
              activeLibrary == _allLibraries || effect.library == activeLibrary,
        )
        .toList(growable: false);
    final query = _searchController.text.trim().toLowerCase();
    final filtered = libraryFiltered
        .where((effect) {
          final matchesCollection = switch (_collection) {
            _SoundCollection.all => true,
            _SoundCollection.favorites => _favoriteIds.contains(effect.id),
            _SoundCollection.recent => _recentIds.contains(effect.id),
          };
          final matchesQuery =
              query.isEmpty ||
              effect.name.toLowerCase().contains(query) ||
              effect.category.toLowerCase().contains(query) ||
              effect.sourceName.toLowerCase().contains(query) ||
              effect.library.toLowerCase().contains(query);
          return matchesCollection && matchesQuery;
        })
        .toList(growable: false);
    if (_collection == _SoundCollection.recent) {
      final recentOrder = {
        for (var index = 0; index < _recentIds.length; index++)
          _recentIds[index]: index,
      };
      filtered.sort((a, b) => recentOrder[a.id]!.compareTo(recentOrder[b.id]!));
    }
    final filtersActive =
        query.isNotEmpty ||
        activeLibrary != _allLibraries ||
        _collection != _SoundCollection.all;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(TgiSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SoundTypeTabs(
                types: types,
                selectedType: _type,
                effects: widget.effects,
                onTypeChanged: (type) {
                  setState(() {
                    _type = type;
                    _library = _allLibraries;
                  });
                },
              ),
              const SizedBox(height: TgiSpacing.sm),
              _SoundSearchField(controller: _searchController),
              const SizedBox(height: TgiSpacing.xs),
              _SoundCollectionFilters(
                selected: _collection,
                favoriteCount: typeFiltered
                    .where((effect) => _favoriteIds.contains(effect.id))
                    .length,
                recentCount: typeFiltered
                    .where((effect) => _recentIds.contains(effect.id))
                    .length,
                onSelected: (collection) {
                  setState(() => _collection = collection);
                },
              ),
              const SizedBox(height: TgiSpacing.sm),
              _LibrarySourceCard(
                count: typeFiltered.length,
                resultCount: filtered.length,
                type: _type,
                filtersActive: filtersActive,
                onClearFilters: filtersActive
                    ? () => setState(() {
                        _searchController.clear();
                        _library = _allLibraries;
                        _collection = _SoundCollection.all;
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
                      onTap: () => setState(() => _library = library),
                    ),
                    const SizedBox(width: TgiSpacing.xs),
                  ],
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: TgiColors.borderSubtle),
        Expanded(
          child: filtered.isEmpty
              ? _EmptySoundResults(
                  query: _searchController.text.trim(),
                  collection: _collection,
                  onClear: filtersActive
                      ? () => setState(() {
                          _searchController.clear();
                          _library = _allLibraries;
                          _collection = _SoundCollection.all;
                        })
                      : null,
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(TgiSpacing.md),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: TgiSpacing.sm),
                  itemBuilder: (context, index) {
                    final effect = filtered[index];
                    return _SoundEffectTile(
                      effect: effect,
                      query: query,
                      favorite: _favoriteIds.contains(effect.id),
                      adding: widget.addingEffectId == effect.id,
                      previewing: widget.previewingEffectId == effect.id,
                      previewPosition: widget.previewPosition,
                      previewDuration: widget.previewDuration,
                      loadingPreview:
                          widget.loadingPreviewEffectId == effect.id,
                      addBlocked:
                          widget.addingEffectId != null &&
                          widget.addingEffectId != effect.id,
                      onAdd: () {
                        _recordRecent(effect);
                        widget.onAddEffect(effect);
                      },
                      onPreview: () {
                        _recordRecent(effect);
                        widget.onPreviewEffect(effect);
                      },
                      onFavorite: () => _toggleFavorite(effect),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SoundTypeTabs extends StatelessWidget {
  const _SoundTypeTabs({
    required this.types,
    required this.selectedType,
    required this.effects,
    required this.onTypeChanged,
  });

  final List<String> types;
  final String selectedType;
  final List<PublicSoundEffect> effects;
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
                child: _SoundTypeTab(
                  label: type,
                  count: effects.where((effect) => effect.type == type).length,
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

class _SoundTypeTab extends StatelessWidget {
  const _SoundTypeTab({
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

class _LibrarySourceCard extends StatelessWidget {
  const _LibrarySourceCard({
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
            const _SoundGlyph(icon: Icons.library_music_outlined),
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

class _SoundSearchField extends StatelessWidget {
  const _SoundSearchField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const Key('sound_effects_search_field'),
      controller: controller,
      style: const TextStyle(color: TgiColors.textPrimary, fontSize: 13),
      cursorColor: TgiColors.accent,
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Buscar som',
        hintStyle: const TextStyle(color: TgiColors.textSecondary),
        prefixIcon: const Icon(
          Icons.search,
          size: TgiIconSizes.md,
          color: TgiColors.textSecondary,
        ),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                key: const Key('clear_sound_search'),
                tooltip: 'Limpar pesquisa',
                onPressed: controller.clear,
                icon: const Icon(
                  Icons.close,
                  size: TgiIconSizes.md,
                  color: TgiColors.textSecondary,
                ),
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

class _SoundCollectionFilters extends StatelessWidget {
  const _SoundCollectionFilters({
    required this.selected,
    required this.favoriteCount,
    required this.recentCount,
    required this.onSelected,
  });

  final _SoundCollection selected;
  final int favoriteCount;
  final int recentCount;
  final ValueChanged<_SoundCollection> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SoundCollectionButton(
            key: const Key('sound_collection_all'),
            label: 'Todos',
            icon: Icons.library_music_outlined,
            selected: selected == _SoundCollection.all,
            onTap: () => onSelected(_SoundCollection.all),
          ),
        ),
        const SizedBox(width: TgiSpacing.xs),
        Expanded(
          child: _SoundCollectionButton(
            key: const Key('sound_collection_favorites'),
            label: 'Favoritos',
            count: favoriteCount,
            icon: Icons.star_border,
            selected: selected == _SoundCollection.favorites,
            onTap: () => onSelected(_SoundCollection.favorites),
          ),
        ),
        const SizedBox(width: TgiSpacing.xs),
        Expanded(
          child: _SoundCollectionButton(
            key: const Key('sound_collection_recent'),
            label: 'Recentes',
            count: recentCount,
            icon: Icons.history,
            selected: selected == _SoundCollection.recent,
            onTap: () => onSelected(_SoundCollection.recent),
          ),
        ),
      ],
    );
  }
}

class _SoundCollectionButton extends StatelessWidget {
  const _SoundCollectionButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.count,
    super.key,
  });

  final String label;
  final IconData icon;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TgiColors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TgiRadii.md),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: selected
              ? TgiDecorations.activeControl(radius: TgiRadii.md)
              : BoxDecoration(
                  color: TgiColors.surface.withValues(alpha: 0.48),
                  border: Border.all(color: TgiColors.borderStrong),
                  borderRadius: BorderRadius.circular(TgiRadii.md),
                ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: selected
                    ? TgiColors.accentSoft
                    : TgiColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  count == null ? label : '$label $count',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: selected
                        ? TgiColors.textPrimary
                        : TgiColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptySoundResults extends StatelessWidget {
  const _EmptySoundResults({
    required this.query,
    required this.collection,
    required this.onClear,
  });

  final String query;
  final _SoundCollection collection;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final (icon, title, description) = switch ((query, collection)) {
      (final query, _) when query.isNotEmpty => (
        Icons.search_off,
        'Nenhum resultado para "$query"',
        'Tente outro termo ou limpe os filtros.',
      ),
      (_, _SoundCollection.favorites) => (
        Icons.star_border,
        'Nenhum som favorito',
        'Use a estrela de um som para guardá-lo aqui.',
      ),
      (_, _SoundCollection.recent) => (
        Icons.history,
        'Nenhum som recente',
        'Os sons ouvidos e adicionados aparecerão aqui.',
      ),
      _ => (
        Icons.graphic_eq,
        'Nenhum som encontrado',
        'Tente selecionar outra biblioteca.',
      ),
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight < 96) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: TgiSpacing.sm),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TgiColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }

        return Center(
          child: Padding(
            padding: const EdgeInsets.all(TgiSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 30, color: TgiColors.textMuted),
                const SizedBox(height: TgiSpacing.sm),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: TgiColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: TgiSpacing.xxs),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: TgiColors.textSecondary,
                  ),
                ),
                if (onClear != null) ...[
                  const SizedBox(height: TgiSpacing.md),
                  TextButton.icon(
                    onPressed: onClear,
                    icon: const Icon(Icons.filter_alt_off_outlined, size: 15),
                    label: const Text('Limpar filtros'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HighlightedSoundName extends StatelessWidget {
  const _HighlightedSoundName({required this.text, required this.query});

  final String text;
  final String query;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: TgiColors.textPrimary,
      fontWeight: FontWeight.w800,
    );
    final matchStart = query.isEmpty ? -1 : text.toLowerCase().indexOf(query);
    if (matchStart < 0) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    final matchEnd = matchStart + query.length;
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          if (matchStart > 0) TextSpan(text: text.substring(0, matchStart)),
          TextSpan(
            text: text.substring(matchStart, matchEnd),
            style: TextStyle(
              color: TgiColors.accentSoft,
              backgroundColor: TgiColors.surfacePressed,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (matchEnd < text.length) TextSpan(text: text.substring(matchEnd)),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
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

class _SoundEffectTile extends StatelessWidget {
  const _SoundEffectTile({
    required this.effect,
    required this.query,
    required this.favorite,
    required this.adding,
    required this.previewing,
    required this.previewPosition,
    required this.previewDuration,
    required this.loadingPreview,
    required this.addBlocked,
    required this.onAdd,
    required this.onPreview,
    required this.onFavorite,
  });

  final PublicSoundEffect effect;
  final String query;
  final bool favorite;
  final bool adding;
  final bool previewing;
  final Duration previewPosition;
  final Duration previewDuration;
  final bool loadingPreview;
  final bool addBlocked;
  final VoidCallback onAdd;
  final VoidCallback onPreview;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final effectivePreviewDuration = previewDuration > Duration.zero
        ? previewDuration
        : effect.duration;
    final previewProgress =
        previewing && effectivePreviewDuration > Duration.zero
        ? (previewPosition.inMilliseconds /
                  effectivePreviewDuration.inMilliseconds)
              .clamp(0.0, 1.0)
              .toDouble()
        : 0.0;

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
            _SoundPreviewButton(
              icon: _iconForCategory(effect.category),
              previewing: previewing,
              loading: loadingPreview,
              onPressed: onPreview,
            ),
            const SizedBox(width: TgiSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HighlightedSoundName(text: effect.name, query: query),
                  const SizedBox(height: TgiSpacing.xxs),
                  Text(
                    '${effect.sourceName} - ${effect.category} - ${effect.license}',
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
                        Icons.timer_outlined,
                        size: 12,
                        color: TgiColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatAudioDuration(effect.duration),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: TgiColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (previewing) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(TgiRadii.pill),
                            child: TgiProgressBar(
                              value: previewProgress,
                              height: 4,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatAudioDuration(previewPosition),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: TgiColors.accentSoft,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: TgiSpacing.sm),
            _FavoriteButton(favorite: favorite, onPressed: onFavorite),
            const SizedBox(width: TgiSpacing.xs),
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

  static String _formatAudioDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds ~/ 60) % 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  static IconData _iconForCategory(String category) {
    if (category.startsWith('Trilha')) {
      return Icons.music_note_outlined;
    }
    return switch (category) {
      'Cliques' => Icons.ads_click_outlined,
      'Mouse' => Icons.mouse_outlined,
      'Hover' => Icons.touch_app_outlined,
      'Switches' => Icons.toggle_on_outlined,
      'Bass' => Icons.surround_sound_outlined,
      'Click' => Icons.ads_click_outlined,
      'Digitando' => Icons.keyboard_outlined,
      'Dinheiro' => Icons.payments_outlined,
      'Electric' => Icons.bolt_outlined,
      'Fogo' => Icons.local_fire_department_outlined,
      'Impactos' => Icons.album_outlined,
      'Memes' => Icons.theater_comedy_outlined,
      'Whoosh' => Icons.air_outlined,
      _ => Icons.graphic_eq,
    };
  }
}

class _FavoriteButton extends StatelessWidget {
  const _FavoriteButton({required this.favorite, required this.onPressed});

  final bool favorite;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: favorite ? 'Remover dos favoritos' : 'Favoritar',
      child: SizedBox(
        width: 32,
        height: 34,
        child: IconButton(
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          icon: favorite
              ? const TgiAccentIcon(Icons.star, size: TgiIconSizes.md)
              : const Icon(
                  Icons.star_border,
                  size: TgiIconSizes.md,
                  color: TgiColors.textSecondary,
                ),
          style: IconButton.styleFrom(
            backgroundColor: favorite
                ? TgiColors.surfacePressed
                : TgiColors.surfacePressed,
            side: BorderSide(
              color: favorite ? TgiColors.accentMuted : TgiColors.borderStrong,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(TgiRadii.md),
            ),
          ),
        ),
      ),
    );
  }
}

class _SoundGlyph extends StatelessWidget {
  const _SoundGlyph({required this.icon});

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

class _SoundPreviewButton extends StatelessWidget {
  const _SoundPreviewButton({
    required this.icon,
    required this.previewing,
    required this.loading,
    required this.onPressed,
  });

  final IconData icon;
  final bool previewing;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: previewing ? 'Parar preview' : 'Ouvir preview',
      child: InkWell(
        onTap: loading ? null : onPressed,
        borderRadius: BorderRadius.circular(TgiRadii.md),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: TgiColors.surfacePressed,
            border: Border.all(color: TgiColors.accentMuted),
            borderRadius: BorderRadius.circular(TgiRadii.md),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              TgiAccentIcon(
                previewing ? Icons.stop_circle_outlined : icon,
                size: TgiIconSizes.lg,
              ),
              if (loading)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: TgiColors.textSecondary,
                  ),
                )
              else if (!previewing)
                Positioned(
                  right: 3,
                  bottom: 3,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: TgiColors.background.withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(TgiRadii.pill),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        previewing ? Icons.stop : Icons.play_arrow,
                        size: 12,
                        color: TgiColors.textPrimary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
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
