part of 'editor_screen.dart';

enum _EditorLibraryTab { media, audio, titles, transitions, effects, captions }

extension _DesktopWorkspace on _EditorScreenState {
  Widget _library(Widget Function(_LeftPanelMode) panel) {
    Widget content;
    final mode = switch (_libraryTab) {
      _EditorLibraryTab.media => _LeftPanelMode.mediaPool,
      _EditorLibraryTab.audio =>
        kStandalone ? _LeftPanelMode.mediaPool : _LeftPanelMode.soundEffects,
      _EditorLibraryTab.transitions => _LeftPanelMode.transitions,
      _EditorLibraryTab.captions => _LeftPanelMode.captions,
      _ => null,
    };
    if (mode != null) {
      final built = panel(mode);
      content = built is _Panel ? built.child : built;
    } else if (_libraryTab == _EditorLibraryTab.titles) {
      content = ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text(
            'TÍTULOS',
            style: TextStyle(
              fontSize: 12,
              color: TgiColors.textMuted,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          for (final template in [
            (
              'Título simples',
              'Seu título',
              NewTextStyle.fontFamily,
              48.0,
              domain.TextClipAnimation.none,
            ),
            (
              'Legenda',
              'Sua legenda',
              NewTextStyle.fontFamily,
              36.0,
              domain.TextClipAnimation.fade,
            ),
            (
              'Destaque',
              'EM DESTAQUE',
              'Bebas Neue',
              64.0,
              domain.TextClipAnimation.rise,
            ),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton(
                onPressed: () => _controller.addTextToTimeline(
                  template.$2,
                  fontFamily: template.$3,
                  fontSize: template.$4,
                  textAnimation: template.$5,
                  registerAsCaption: template.$1 == 'Legenda',
                ),
                child: SizedBox(
                  height: 72,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        template.$2,
                        style: TextStyle(fontFamily: template.$3, fontSize: 19),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        template.$1,
                        style: const TextStyle(
                          fontSize: 12,
                          color: TgiColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          TextButton.icon(
            onPressed: () =>
                _addTextAtTimelinePosition(_controller.playheadPosition),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Criar texto personalizado'),
          ),
        ],
      );
    } else {
      final hasVisual =
          _controller.selectedTimelineClip?.trackType == TrackType.video ||
          _controller.selectedTimelineClip?.trackType == TrackType.image;
      content = ListView(
        padding: const EdgeInsets.all(8),
        children: [
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'FERRAMENTAS DE EDIÇÃO',
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 1,
                color: TgiColors.textMuted,
              ),
            ),
          ),
          for (final tool in [
            ('Transformação e recorte', Icons.crop, _showTransformCropPanel),
            ('Cor e iluminação', Icons.tune, _showProfessionalColorPanel),
            (
              'Máscara e rastreamento',
              Icons.track_changes,
              _showMaskTrackingPanel,
            ),
            ('Chroma key', Icons.colorize_outlined, _showChromaKeyPanel),
            ('Velocidade', Icons.speed, _showAdvancedSpeedPanel),
            ('Animação', Icons.animation_outlined, _toggleKenBurnsTool),
            ('Remover pausas', Icons.content_cut, _showSmartCutPanel),
            (
              'Biblioteca de imagens',
              Icons.collections_outlined,
              _showVisualMediaLibrary,
            ),
          ])
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              enabled: hasVisual || tool.$2 == Icons.collections_outlined,
              leading: Icon(tool.$2, size: 17),
              title: Text(tool.$1, style: const TextStyle(fontSize: 12)),
              onTap: () {
                tool.$3();
                _refreshEditor(() => _inspectorVisible = true);
              },
            ),
          if (!hasVisual)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Selecione um vídeo ou uma imagem para editar seus efeitos.',
                style: TextStyle(fontSize: 12, color: TgiColors.textMuted),
              ),
            ),
        ],
      );
    }
    return ColoredBox(
      color: TgiColors.surfacePanel,
      child: Column(
        children: [
          SizedBox(
            height: 56,
            child: Row(
              children: [
                for (final tab in _EditorLibraryTab.values)
                  Expanded(
                    flex: switch (tab) {
                      _EditorLibraryTab.transitions => 18,
                      _EditorLibraryTab.captions => 14,
                      _ => 10,
                    },
                    child: _LibraryTabButton(
                      tab: tab,
                      selected: _libraryTab == tab,
                      onTap: () {
                        _refreshEditor(() => _libraryTab = tab);
                        switch (tab) {
                          case _EditorLibraryTab.media:
                            _showMediaPool();
                          case _EditorLibraryTab.audio:
                            _showSoundEffectsLibrary();
                          case _EditorLibraryTab.transitions:
                            _showTransitionLibrary();
                          case _EditorLibraryTab.captions:
                            _showCaptionsPanel();
                          default:
                            break;
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: TgiColors.borderSubtle),
          Expanded(child: content),
        ],
      ),
    );
  }

  Widget _inspector(Widget basics, Widget Function(_LeftPanelMode) panel) {
    final clip = _controller.selectedTimelineClip;
    final isVideo = clip?.trackType == TrackType.video;
    final isAudio = clip?.trackType == TrackType.audio;
    final isImage = clip?.trackType == TrackType.image;
    final modes = <(_LeftPanelMode, String)>[
      (_LeftPanelMode.mediaPool, 'Básico'),
      if (isVideo || isImage) (_LeftPanelMode.transformCrop, 'Transformar'),
      if (isVideo) (_LeftPanelMode.professionalColor, 'Cor'),
      if (isAudio || (isVideo && _controller.selectedTimelineAudioClip != null))
        (_LeftPanelMode.audioTools, 'Áudio'),
      if (isVideo) ...[
        (_LeftPanelMode.advancedSpeed, 'Velocidade'),
        (_LeftPanelMode.chromaKey, 'Chroma'),
        (_LeftPanelMode.maskTracking, 'Máscara'),
        (_LeftPanelMode.smartCut, 'Pausas'),
      ],
      if (isVideo || isImage) (_LeftPanelMode.animations, 'Animação'),
    ];
    final toolActive =
        modes.any((mode) => mode.$1 == _leftPanelMode) &&
        _leftPanelMode != _LeftPanelMode.mediaPool;
    final showVisualLibrary = _leftPanelMode == _LeftPanelMode.visualMedia;
    final built = clip == null
        ? _ProjectProperties(
            project: _controller.project,
            settings: _exportSettings,
          )
        : toolActive || showVisualLibrary
        ? panel(_leftPanelMode)
        : basics;
    final child = built is _Panel ? built.child : built;
    return ColoredBox(
      color: TgiColors.surfacePanel,
      child: Column(
        children: [
          SizedBox(
            height: 36,
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      switch (clip?.trackType) {
                        TrackType.video => 'Vídeo',
                        TrackType.audio => 'Áudio',
                        TrackType.image => 'Imagem',
                        TrackType.text => 'Texto',
                        null => 'Projeto',
                      },
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (isVideo && _controller.selectedTimelineAudioClip != null)
                    PopupMenuButton<String>(
                      tooltip: 'Áudio associado',
                      icon: const Icon(Icons.link, size: 16),
                      onSelected: (value) => value == 'unlink'
                          ? _controller.toggleSelectedAudioVideoLink()
                          : _controller.removeSelectedAudio(),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'unlink',
                          child: Text('Separar áudio do vídeo'),
                        ),
                        PopupMenuItem(
                          value: 'remove',
                          child: Text('Remover somente o áudio'),
                        ),
                      ],
                    ),
                  IconButton(
                    tooltip: 'Ocultar inspetor',
                    icon: const Icon(Icons.close, size: 15),
                    onPressed: () {
                      _refreshEditor(() => _inspectorVisible = false);
                      _scheduleWorkspaceLayoutSave();
                    },
                  ),
                ],
              ),
            ),
          ),
          if (clip != null)
            SizedBox(
              height: 32,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final mode in modes)
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: _leftPanelMode == mode.$1
                              ? TgiColors.textPrimary
                              : TgiColors.textSecondary,
                          textStyle: TgiTextStyles.control,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: () {
                          if (mode.$1 == _LeftPanelMode.audioTools) {
                            _showAudioToolsPanel();
                            return;
                          }
                          _refreshEditor(() {
                            _leftPanelMode = mode.$1;
                            _kenBurnsToolActive =
                                mode.$1 == _LeftPanelMode.animations;
                          });
                        },
                        child: Text(mode.$2),
                      ),
                  ],
                ),
              ),
            ),
          const Divider(height: 1, color: TgiColors.borderSubtle),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _desktopLayout(
    BoxConstraints constraints, {
    required Widget library,
    required Widget preview,
    required Widget inspector,
    required Widget timeline,
  }) {
    final width = constraints.maxWidth;
    final selected = _controller.selectedTimelineClip != null;
    final showInspector =
        _inspectorVisible &&
        !_timelineFocusMode &&
        width >= 720 &&
        (width >= 1120 || selected);
    final showLibrary =
        _libraryVisible &&
        !_timelineFocusMode &&
        width >= 720 &&
        (width >= 1120 || !showInspector);
    final libraryWidth = _sidePanelWidth(_leftPanelFraction, width, 200, 360);
    final inspectorWidth = _sidePanelWidth(
      _propertiesPanelFraction,
      width,
      220,
      340,
    );
    final height = math.max(
      0.0,
      constraints.maxHeight - _workspaceDividerExtent,
    );
    const minPreview = 124.0;
    final visibleTracks = _controller.project.tracks.take(3).toList();
    final threeTrackHeight =
        visibleTracks.fold<double>(0, (sum, t) => sum + t.height) +
        math.max(0, 3 - visibleTracks.length) * 64;
    // Header + ruler + new-lane target + scrollbar, then three complete rows.
    final requiredTimeline = 44 + 34 + 24 + 12 + threeTrackHeight;
    final minTimeline = math.min(
      requiredTimeline,
      math.max(0, height - minPreview),
    );
    final upper = (height * (_timelineFocusMode ? .42 : _previewPanelFraction))
        .clamp(minPreview, math.max(minPreview, height - minTimeline))
        .toDouble();
    return Column(
      children: [
        SizedBox(
          height: upper,
          child: Row(
            children: [
              if (showLibrary) ...[
                SizedBox(width: libraryWidth, child: library),
                _WorkspaceDivider(
                  key: const ValueKey('resize-library'),
                  axis: Axis.vertical,
                  onDragUpdate: (details) =>
                      _resizeLeftWorkspacePanel(details, width),
                  onReset: _resetWorkspaceLayout,
                ),
              ],
              Expanded(
                child: KeyedSubtree(
                  key: const ValueKey('desktop-preview-region'),
                  child: preview,
                ),
              ),
              if (showInspector) ...[
                _WorkspaceDivider(
                  key: const ValueKey('resize-properties'),
                  axis: Axis.vertical,
                  onDragUpdate: (details) =>
                      _resizePropertiesWorkspacePanel(details, width),
                  onReset: _resetWorkspaceLayout,
                ),
                SizedBox(width: inspectorWidth, child: inspector),
              ],
            ],
          ),
        ),
        _WorkspaceDivider(
          key: const ValueKey('resize-timeline'),
          axis: Axis.horizontal,
          onDragUpdate: (details) =>
              _resizePreviewWorkspacePanel(details, constraints.maxHeight),
          onReset: _resetWorkspaceLayout,
        ),
        Expanded(
          child: KeyedSubtree(
            key: const ValueKey('desktop-timeline-region'),
            child: timeline,
          ),
        ),
      ],
    );
  }
}

class _LibraryTabButton extends StatelessWidget {
  const _LibraryTabButton({
    required this.tab,
    required this.selected,
    required this.onTap,
  });
  final _EditorLibraryTab tab;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (tab) {
      _EditorLibraryTab.media => (Icons.video_library_outlined, 'Mídia'),
      _EditorLibraryTab.audio => (Icons.music_note_outlined, 'Áudio'),
      _EditorLibraryTab.titles => (Icons.title, 'Títulos'),
      _EditorLibraryTab.transitions => (Icons.flip_outlined, 'Transições'),
      _EditorLibraryTab.effects => (Icons.tune, 'Efeitos'),
      _EditorLibraryTab.captions => (Icons.subtitles_outlined, 'Legendas'),
    };
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected ? TgiColors.surfaceHover : TgiColors.surfacePanel,
            border: Border(
              bottom: BorderSide(
                width: 2,
                color: selected ? TgiColors.borderStrong : Colors.transparent,
              ),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected
                    ? TgiColors.textPrimary
                    : TgiColors.textSecondary,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: selected ? TgiColors.textPrimary : TgiColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectProperties extends StatelessWidget {
  const _ProjectProperties({required this.project, required this.settings});
  final TgiProject project;
  final FfmpegExportSettings settings;

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('project-properties'),
    padding: const EdgeInsets.all(16),
    children: [
      Text(
        project.name,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 24),
      for (final entry in [
        (
          'Resolução de saída',
          '${settings.resolution.width} × ${settings.resolution.height}',
        ),
        ('Taxa de quadros', '${settings.framesPerSecond} fps'),
        ('Duração', formatDuration(project.timelineDuration)),
        ('Trilhas', '${project.tracks.length}'),
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.$1,
                style: const TextStyle(
                  fontSize: 12,
                  color: TgiColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                entry.$2,
                style: const TextStyle(
                  fontSize: 14,
                  color: TgiColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

// Default widths stay at 280 px across desktop sizes. Saved/resized fractions
// still scale with the window; pixel minima keep the controls usable.
double _sidePanelWidth(
  double fraction,
  double width,
  double minimum,
  double maximum,
) => (fraction == _defaultLeftPanelFraction ? 280.0 : width * fraction)
    .clamp(minimum, maximum)
    .toDouble();
