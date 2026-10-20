part of 'editor_screen.dart';

class _TextClipDialogResult {
  const _TextClipDialogResult({
    required this.text,
    required this.fontFamily,
    required this.fontSize,
    required this.textColor,
    required this.backgroundColor,
    required this.opacity,
  });

  final String text;
  final String fontFamily;
  final double fontSize;
  final int textColor;
  final int backgroundColor;
  final double opacity;
}

class _TimelineTransitionSettingsResult {
  const _TimelineTransitionSettingsResult({
    required this.duration,
    required this.blendMode,
    required this.direction,
    required this.color,
    required this.intensity,
  });

  final Duration duration;
  final TimelineTransitionBlendMode blendMode;
  final TimelineTransitionDirection direction;
  final int color;
  final double intensity;
}

class _TransitionColorOption {
  const _TransitionColorOption(this.label, this.color);

  final String label;
  final int color;
}

class _TimelineTransitionSettingsDialog extends StatefulWidget {
  const _TimelineTransitionSettingsDialog({required this.transition});

  final TimelineTransition transition;

  @override
  State<_TimelineTransitionSettingsDialog> createState() =>
      _TimelineTransitionSettingsDialogState();
}

class _TimelineTransitionSettingsDialogState
    extends State<_TimelineTransitionSettingsDialog> {
  static const _colorOptions = [
    _TransitionColorOption('Preto', 0xFF000000),
    _TransitionColorOption('Branco', 0xFFFFFFFF),
    _TransitionColorOption('Amarelo', 0xFFFFD166),
    _TransitionColorOption('Azul', 0xFF4C7DFF),
  ];

  late double _durationMs;
  late TimelineTransitionBlendMode _blendMode;
  late TimelineTransitionDirection _direction;
  late int _color;
  late double _intensity;

  @override
  void initState() {
    super.initState();
    _durationMs = widget.transition.duration.inMilliseconds
        .clamp(200, 2000)
        .toDouble();
    _blendMode = widget.transition.blendMode;
    _direction = widget.transition.direction;
    _color = widget.transition.color;
    _intensity = widget.transition.intensity.clamp(0.0, 1.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final transition = widget.transition;
    final colorOptions = [
      if (!_colorOptions.any((option) => option.color == _color))
        _TransitionColorOption('Atual', _color),
      ..._colorOptions,
    ];
    return AlertDialog(
      title: Text(transition.name),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              transition.isPreset
                  ? _presetLabel(transition.preset!)
                  : 'Transicao por video',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: TgiColors.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: TgiSpacing.md),
            Text('Duracao: ${_durationMs.round()} ms'),
            Slider(
              value: _durationMs,
              min: 200,
              max: 2000,
              divisions: 18,
              label: '${_durationMs.round()} ms',
              onChanged: (value) => setState(() => _durationMs = value),
            ),
            if (transition.isPreset) ...[
              const SizedBox(height: TgiSpacing.sm),
              DropdownButtonFormField<TimelineTransitionDirection>(
                initialValue: _direction,
                decoration: const InputDecoration(labelText: 'Direcao'),
                items: [
                  for (final direction in TimelineTransitionDirection.values)
                    DropdownMenuItem(
                      value: direction,
                      child: Text(_directionLabel(direction)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _direction = value);
                  }
                },
              ),
              const SizedBox(height: TgiSpacing.md),
              DropdownButtonFormField<int>(
                initialValue: _color,
                decoration: const InputDecoration(labelText: 'Cor'),
                items: [
                  for (final option in colorOptions)
                    DropdownMenuItem(
                      value: option.color,
                      child: Row(
                        children: [
                          Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: Color(option.color),
                              border: Border.all(color: TgiColors.border),
                              borderRadius: BorderRadius.circular(TgiRadii.sm),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(option.label),
                        ],
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _color = value);
                  }
                },
              ),
              const SizedBox(height: TgiSpacing.md),
              Text('Intensidade: ${(_intensity * 100).round()}%'),
              Slider(
                value: _intensity,
                min: 0.2,
                max: 1,
                divisions: 8,
                label: '${(_intensity * 100).round()}%',
                onChanged: (value) => setState(() => _intensity = value),
              ),
            ] else ...[
              const SizedBox(height: TgiSpacing.sm),
              DropdownButtonFormField<TimelineTransitionBlendMode>(
                initialValue: _blendMode,
                decoration: const InputDecoration(labelText: 'Blend'),
                items: [
                  for (final mode in TimelineTransitionBlendMode.values)
                    DropdownMenuItem(
                      value: mode,
                      child: Text(_blendModeLabel(mode)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _blendMode = value);
                  }
                },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.check),
          label: const Text('Salvar'),
        ),
      ],
    );
  }

  void _submit() {
    Navigator.of(context).pop(
      _TimelineTransitionSettingsResult(
        duration: Duration(milliseconds: _durationMs.round()),
        blendMode: _blendMode,
        direction: _direction,
        color: _color,
        intensity: _intensity,
      ),
    );
  }

  String _presetLabel(TimelineTransitionPreset preset) {
    return switch (preset) {
      TimelineTransitionPreset.fade => 'Preset: fade',
      TimelineTransitionPreset.flash => 'Preset: flash',
      TimelineTransitionPreset.wipe => 'Preset: wipe',
      TimelineTransitionPreset.dissolve => 'Preset: dissolve',
      TimelineTransitionPreset.blur => 'Preset: desfoque',
      TimelineTransitionPreset.glitch => 'Preset: glitch RGB',
      TimelineTransitionPreset.spin => 'Preset: giro',
      TimelineTransitionPreset.pixelate => 'Preset: pixelado',
      TimelineTransitionPreset.zoom => 'Preset: zoom impacto',
      TimelineTransitionPreset.lightLeak => 'Preset: light leak',
    };
  }

  String _directionLabel(TimelineTransitionDirection direction) {
    return switch (direction) {
      TimelineTransitionDirection.leftToRight => 'Esquerda para direita',
      TimelineTransitionDirection.rightToLeft => 'Direita para esquerda',
      TimelineTransitionDirection.topToBottom => 'Cima para baixo',
      TimelineTransitionDirection.bottomToTop => 'Baixo para cima',
    };
  }

  String _blendModeLabel(TimelineTransitionBlendMode mode) {
    return switch (mode) {
      TimelineTransitionBlendMode.normal => 'Normal',
      TimelineTransitionBlendMode.screen => 'Screen',
    };
  }
}

class _AutoCaptionsDialogResult {
  const _AutoCaptionsDialogResult({
    required this.modelName,
    required this.languageCode,
    required this.maxCharsPerCue,
    required this.styleLabel,
    required this.fontFamily,
    required this.fontSize,
    required this.textColor,
    required this.backgroundColor,
    required this.opacity,
    required this.animation,
  });

  final String modelName;
  final String? languageCode;
  final int maxCharsPerCue;
  final String styleLabel;
  final String fontFamily;
  final double fontSize;
  final int textColor;
  final int backgroundColor;
  final double opacity;
  final domain.TextClipAnimation animation;
}

class _WhisperModelOption {
  const _WhisperModelOption({required this.value, required this.label});

  final String value;
  final String label;
}

class _TextColorOption {
  const _TextColorOption(this.label, this.value);

  final String label;
  final int value;
}

class _TextAnimationOption {
  const _TextAnimationOption(this.label, this.animation);

  final String label;
  final domain.TextClipAnimation animation;
}

class _TextStylePreset {
  const _TextStylePreset({
    required this.label,
    required this.fontFamily,
    required this.fontSize,
    required this.textColor,
    required this.backgroundColor,
    required this.opacity,
    required this.animation,
  });

  final String label;
  final String fontFamily;
  final double fontSize;
  final int textColor;
  final int backgroundColor;
  final double opacity;
  final domain.TextClipAnimation animation;
}

class _MissingMediaEntry {
  const _MissingMediaEntry({
    required this.mediaItemId,
    required this.name,
    required this.originalPath,
    required this.originalFilename,
    required this.type,
  });

  final String mediaItemId;
  final String name;
  final String originalPath;
  final String originalFilename;
  final MediaType type;

  List<String> get allowedExtensions {
    return switch (type) {
      MediaType.video => const ['mp4', 'mov', 'mkv', 'avi', 'webm', 'm4v'],
      MediaType.audio => const [
        'mp3',
        'wav',
        'aac',
        'm4a',
        'flac',
        'ogg',
        'opus',
        'wma',
      ],
      MediaType.image => const ['png', 'jpg', 'jpeg'],
      MediaType.text => const [
        'mp4',
        'mov',
        'mkv',
        'avi',
        'webm',
        'm4v',
        'mp3',
        'wav',
        'aac',
        'm4a',
        'flac',
        'ogg',
        'opus',
        'wma',
        'png',
        'jpg',
        'jpeg',
      ],
    };
  }
}

class _RelinkMissingMediaDialog extends StatefulWidget {
  const _RelinkMissingMediaDialog({required this.missingMediaItems});

  final List<Map<String, dynamic>> missingMediaItems;

  @override
  State<_RelinkMissingMediaDialog> createState() =>
      _RelinkMissingMediaDialogState();
}

class _RelinkMissingMediaDialogState extends State<_RelinkMissingMediaDialog> {
  late final List<_MissingMediaEntry> _entries;
  final Map<String, String> _selectedPaths = {};

  @override
  void initState() {
    super.initState();
    _entries = widget.missingMediaItems
        .map(_missingMediaEntryFromData)
        .where((entry) => entry.mediaItemId.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> _pickFile(_MissingMediaEntry entry) async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Religar ${entry.name}',
      type: FileType.custom,
      allowedExtensions: entry.allowedExtensions,
      allowMultiple: false,
      lockParentWindow: true,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    final path = result.files.single.path;
    if (path == null || path.isEmpty) {
      return;
    }
    setState(() => _selectedPaths[entry.mediaItemId] = path);
  }

  void _apply() {
    final relinked = [
      for (final entry in _entries)
        if (_selectedPaths[entry.mediaItemId] case final newPath?)
          MediaRelinkResult(
            mediaItemId: entry.mediaItemId,
            originalFilename: entry.originalFilename,
            newPath: newPath,
          ),
    ];
    Navigator.of(context).pop(relinked);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Religar midias ausentes'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Escolha os novos arquivos para restaurar previews, timeline e exportacao.',
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 380),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _entries.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) => _MissingMediaTile(
                  entry: _entries[index],
                  selectedPath: _selectedPaths[_entries[index].mediaItemId],
                  onPick: () => _pickFile(_entries[index]),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(<MediaRelinkResult>[]),
          child: const Text('Ignorar'),
        ),
        FilledButton.icon(
          onPressed: _selectedPaths.isEmpty ? null : _apply,
          icon: const Icon(Icons.link_outlined),
          label: const Text('Aplicar'),
        ),
      ],
    );
  }
}

class _MissingMediaTile extends StatelessWidget {
  const _MissingMediaTile({
    required this.entry,
    required this.selectedPath,
    required this.onPick,
  });

  final _MissingMediaEntry entry;
  final String? selectedPath;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final selectedPath = this.selectedPath;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TgiColors.surfaceAlt,
        border: Border.all(color: TgiColors.borderSubtle),
        borderRadius: BorderRadius.circular(TgiRadii.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(_missingMediaIcon(entry.type), color: TgiColors.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: TgiColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entry.originalPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (selectedPath != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Novo: ${_fileNameFromPath(selectedPath)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: TgiColors.accentSoft,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.folder_open_outlined),
              label: Text(selectedPath == null ? 'Localizar' : 'Trocar'),
            ),
          ],
        ),
      ),
    );
  }
}

_MissingMediaEntry _missingMediaEntryFromData(Map<String, dynamic> data) {
  final originalPath = data['filePath'] as String? ?? '';
  final originalFilename = _fileNameFromPath(originalPath);
  final rawName = data['name'] as String?;
  final name = rawName == null || rawName.trim().isEmpty
      ? (originalFilename.isEmpty ? 'Midia ausente' : originalFilename)
      : rawName.trim();
  return _MissingMediaEntry(
    mediaItemId: data['id'] as String? ?? '',
    name: name,
    originalPath: originalPath,
    originalFilename: originalFilename.isEmpty ? name : originalFilename,
    type: _mediaTypeFromName(data['type'] as String?),
  );
}

MediaType _mediaTypeFromName(String? typeName) {
  for (final type in MediaType.values) {
    if (type.name == typeName) {
      return type;
    }
  }
  return MediaType.video;
}

IconData _missingMediaIcon(MediaType type) {
  return switch (type) {
    MediaType.audio => Icons.volume_up_outlined,
    MediaType.image => Icons.image_outlined,
    MediaType.text => Icons.title,
    MediaType.video => Icons.movie_outlined,
  };
}

String _fileNameFromPath(String path) {
  if (path.isEmpty) {
    return '';
  }
  final parts = path.split(RegExp(r'[\\/]'));
  return parts.isEmpty ? path : parts.last;
}
