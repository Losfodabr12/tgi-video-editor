part of 'editor_screen.dart';

class _QuickCaptionDialog extends StatefulWidget {
  const _QuickCaptionDialog();

  @override
  State<_QuickCaptionDialog> createState() => _QuickCaptionDialogState();
}

class _QuickCaptionDialogState extends State<_QuickCaptionDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: 'GANCHO AQUI');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _controller.text.trim().isEmpty
        ? 'GANCHO AQUI'
        : _controller.text.trim().toUpperCase();
    return AlertDialog(
      title: const Text('Legenda rápida'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 2,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Legenda',
                errorText: _errorText,
              ),
              onChanged: (_) => setState(() => _errorText = null),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: TgiSpacing.md),
            DecoratedBox(
              decoration: BoxDecoration(
                color: TgiColors.scrim,
                border: Border.all(color: TgiColors.accentMuted),
                borderRadius: BorderRadius.circular(TgiRadii.md),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TgiSpacing.lg,
                  vertical: TgiSpacing.md,
                ),
                child: Text(
                  preview,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: TgiColors.white,
                    fontFamily: 'Impact',
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('Adicionar legenda'),
        ),
      ],
    );
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _errorText = 'Digite a legenda.');
      return;
    }
    Navigator.of(context).pop(text);
  }
}

class _AutoCaptionsDialog extends StatefulWidget {
  const _AutoCaptionsDialog({
    required this.hasPaidPlan,
    required this.onOpenDownloads,
    this.initialSettings,
  });

  final bool hasPaidPlan;
  final VoidCallback onOpenDownloads;
  final _AutoCaptionsDialogResult? initialSettings;

  @override
  State<_AutoCaptionsDialog> createState() => _AutoCaptionsDialogState();
}

class _AutoCaptionsDialogState extends State<_AutoCaptionsDialog> {
  static const _allModelOptions = [
    _WhisperModelOption(value: 'base', label: 'Equilibrado recomendado'),
    _WhisperModelOption(value: 'small', label: 'Melhor qualidade'),
  ];

  static const _fontFamilies = EditorFontService.families;

  static const _textColors = [
    _TextColorOption('Branco', 0xFFFFFFFF),
    _TextColorOption('Preto', 0xFF111111),
    _TextColorOption('Amarelo', 0xFFFFD166),
    _TextColorOption('Vermelho', 0xFFFF5A5F),
    _TextColorOption('Verde', 0xFF66D28F),
    _TextColorOption('Azul', 0xFF6AA9FF),
  ];

  static const _backgroundColors = [
    _TextColorOption('Sem fundo', 0x00000000),
    _TextColorOption('Preto', 0xCC000000),
    _TextColorOption('Preto leve', 0x99000000),
    _TextColorOption('Branco', 0x99FFFFFF),
    _TextColorOption('Amarelo', 0x99FFD166),
    _TextColorOption('Azul', 0x994C7DFF),
  ];

  static const _captionStylePresets = [
    _TextStylePreset(
      label: 'Caixa preta limpa',
      fontFamily: 'Arial',
      fontSize: 52,
      textColor: 0xFFFFFFFF,
      backgroundColor: 0xCC000000,
      opacity: 1,
      animation: domain.TextClipAnimation.fade,
    ),
    _TextStylePreset(
      label: 'Shorts forte',
      fontFamily: 'Impact',
      fontSize: 72,
      textColor: 0xFFFFFFFF,
      backgroundColor: 0xDD000000,
      opacity: 1,
      animation: domain.TextClipAnimation.pop,
    ),
    _TextStylePreset(
      label: 'Amarelo viral',
      fontFamily: 'Impact',
      fontSize: 68,
      textColor: 0xFFFFD166,
      backgroundColor: 0xCC111111,
      opacity: 1,
      animation: domain.TextClipAnimation.rise,
    ),
    _TextStylePreset(
      label: 'Sem fundo discreta',
      fontFamily: 'Segoe UI',
      fontSize: 48,
      textColor: 0xFFFFFFFF,
      backgroundColor: 0x00000000,
      opacity: 0.95,
      animation: domain.TextClipAnimation.fade,
    ),
    _TextStylePreset(
      label: 'Entrada lateral',
      fontFamily: 'Arial',
      fontSize: 54,
      textColor: 0xFFFFFFFF,
      backgroundColor: 0x99000000,
      opacity: 1,
      animation: domain.TextClipAnimation.slideLeft,
    ),
  ];

  late final TextEditingController _languageController;
  late String _modelName;
  List<_WhisperModelOption> _modelOptions = const [
    _WhisperModelOption(value: 'base', label: 'Equilibrado recomendado'),
    _WhisperModelOption(value: 'small', label: 'Melhor qualidade - Plano'),
  ];
  Set<String> _installedModelNames = const {};
  String? _modelHelpText = 'Verificando modelos instalados';
  late String _captionStyleLabel;
  late int _maxCharsPerCue;
  late String _fontFamily;
  late double _fontSize;
  late int _textColor;
  late int _backgroundColor;
  late double _opacity;
  late domain.TextClipAnimation _textAnimation;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSettings;
    _languageController = TextEditingController(
      text: initial?.languageCode ?? 'pt',
    );
    _modelName = initial?.modelName ?? defaultLocalWhisperModelName;
    _captionStyleLabel =
        _captionStylePresets.any(
          (preset) => preset.label == initial?.styleLabel,
        )
        ? initial!.styleLabel
        : _captionStylePresets.first.label;
    _maxCharsPerCue = (initial?.maxCharsPerCue ?? 44).clamp(32, 52);
    _fontFamily = _fontFamilies.contains(initial?.fontFamily)
        ? initial!.fontFamily
        : 'Arial';
    _fontSize = (initial?.fontSize ?? 52).clamp(24, 96);
    final initialTextColor = initial?.textColor ?? 0xFFFFFFFF;
    _textColor = _textColors.any((option) => option.value == initialTextColor)
        ? initialTextColor
        : 0xFFFFFFFF;
    final initialBackgroundColor = initial?.backgroundColor ?? 0xCC000000;
    _backgroundColor =
        _backgroundColors.any(
          (option) => option.value == initialBackgroundColor,
        )
        ? initialBackgroundColor
        : 0xCC000000;
    _opacity = (initial?.opacity ?? 1).clamp(0.2, 1.0).toDouble();
    _textAnimation = initial?.animation ?? domain.TextClipAnimation.fade;
    _loadInstalledWhisperModels();
  }

  @override
  void dispose() {
    _languageController.dispose();
    super.dispose();
  }

  Future<void> _loadInstalledWhisperModels() async {
    final installedModels = await availableLocalWhisperModelNames();
    if (!mounted) {
      return;
    }
    final installedSet = installedModels.toSet();
    setState(() {
      _modelOptions = _allModelOptions;
      _installedModelNames = installedSet;
      if (!_modelOptions.any((option) => option.value == _modelName)) {
        _modelName = _preferredWhisperModelName(_modelOptions);
      }
      _modelHelpText = installedSet.isEmpty
          ? 'Whisper Base gratuito; alta qualidade disponivel nos Downloads.'
          : 'Disponiveis nesta instalacao: '
                '${installedSet.join(', ')}';
    });
  }

  void _applyCaptionStylePreset(String label) {
    final preset = _captionStylePresets.firstWhere(
      (preset) => preset.label == label,
      orElse: () => _captionStylePresets.first,
    );
    setState(() {
      _captionStyleLabel = preset.label;
      _fontFamily = preset.fontFamily;
      _fontSize = preset.fontSize;
      _textColor = preset.textColor;
      _backgroundColor = preset.backgroundColor;
      _opacity = preset.opacity;
      _textAnimation = preset.animation;
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedModelName = _selectedWhisperModelName(
      _modelName,
      _modelOptions,
    );
    final modelHelpText = selectedModelName == 'medium'
        ? 'Modelo pesado: use quando puder esperar. Base e o recomendado.'
        : _modelHelpText;
    final modelOptionsKey = _modelOptions
        .map((option) => option.value)
        .join('|');
    final textOpacity = _opacity.clamp(0.2, 1.0).toDouble();
    final backgroundAlpha =
        (((_backgroundColor >> 24) & 0xff) / 255.0) * textOpacity;
    return AlertDialog(
      title: const Text('Legendas automaticas'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey(
                  'caption-model-$selectedModelName-$modelOptionsKey',
                ),
                initialValue: selectedModelName,
                decoration: InputDecoration(
                  labelText: 'Modelo local',
                  helperText: modelHelpText,
                ),
                items: [
                  for (final option in _modelOptions)
                    DropdownMenuItem(
                      value: option.value,
                      child: Row(
                        children: [
                          Expanded(child: Text(option.label)),
                          if (option.value == 'small' &&
                              (!widget.hasPaidPlan ||
                                  !_installedModelNames.contains('small')))
                            Icon(
                              widget.hasPaidPlan
                                  ? Icons.download_for_offline_outlined
                                  : Icons.lock_outline,
                              size: 17,
                              color: TgiColors.accent,
                            ),
                        ],
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  if (value == 'small' &&
                      (!widget.hasPaidPlan ||
                          !_installedModelNames.contains('small'))) {
                    widget.onOpenDownloads();
                    return;
                  }
                  setState(() => _modelName = value);
                },
              ),
              const SizedBox(height: TgiSpacing.md),
              TextField(
                controller: _languageController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Idioma',
                  hintText: 'pt, en, es...',
                ),
              ),
              const SizedBox(height: TgiSpacing.md),
              Text('Caracteres por legenda: $_maxCharsPerCue'),
              Slider(
                value: _maxCharsPerCue.toDouble(),
                min: 32,
                max: 52,
                divisions: 5,
                label: _maxCharsPerCue.toString(),
                onChanged: (value) => setState(
                  () => _maxCharsPerCue = value.round().clamp(32, 52).toInt(),
                ),
              ),
              const SizedBox(height: TgiSpacing.md),
              const Divider(),
              const SizedBox(height: TgiSpacing.sm),
              DropdownButtonFormField<String>(
                initialValue: _captionStyleLabel,
                decoration: const InputDecoration(
                  labelText: 'Estilo visual da legenda',
                ),
                items: [
                  for (final preset in _captionStylePresets)
                    DropdownMenuItem(
                      value: preset.label,
                      child: Text(preset.label),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    _applyCaptionStylePreset(value);
                  }
                },
              ),
              const SizedBox(height: TgiSpacing.md),
              DropdownButtonFormField<String>(
                key: ValueKey('caption-font-$_fontFamily'),
                initialValue: _fontFamily,
                decoration: const InputDecoration(labelText: 'Fonte'),
                items: [
                  for (final family in _fontFamilies)
                    DropdownMenuItem(
                      value: family,
                      child: Text(family, style: TextStyle(fontFamily: family)),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() => _fontFamily = value);
                },
              ),
              const SizedBox(height: TgiSpacing.md),
              Text('Tamanho da letra: ${_fontSize.round()}'),
              Slider(
                value: _fontSize,
                min: 24,
                max: 96,
                divisions: 72,
                label: _fontSize.round().toString(),
                onChanged: (value) => setState(() => _fontSize = value),
              ),
              const SizedBox(height: TgiSpacing.sm),
              _ColorChoiceGroup(
                label: 'Cor do texto',
                options: _textColors,
                selectedValue: _textColor,
                onSelected: (value) => setState(() => _textColor = value),
              ),
              const SizedBox(height: TgiSpacing.md),
              _ColorChoiceGroup(
                label: 'Fundo da legenda',
                options: _backgroundColors,
                selectedValue: _backgroundColor,
                onSelected: (value) => setState(() => _backgroundColor = value),
              ),
              const SizedBox(height: TgiSpacing.md),
              Text('Opacidade: ${(_opacity * 100).round()}%'),
              Slider(
                value: _opacity,
                min: 0.2,
                max: 1,
                divisions: 8,
                label: '${(_opacity * 100).round()}%',
                onChanged: (value) => setState(() => _opacity = value),
              ),
              const SizedBox(height: TgiSpacing.sm),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(
                        _backgroundColor,
                      ).withValues(alpha: backgroundAlpha.clamp(0.0, 1.0)),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: TgiColors.border),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Text(
                        'Legenda gerada automaticamente',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: _fontFamily,
                          fontSize: _fontSize,
                          height: 1.08,
                          fontWeight: FontWeight.w800,
                          color: Color(
                            _textColor,
                          ).withValues(alpha: textOpacity),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.subtitles_outlined, size: 18),
          label: const Text('Gerar legendas'),
        ),
      ],
    );
  }

  void _submit() {
    Navigator.of(context).pop(
      _AutoCaptionsDialogResult(
        modelName: _selectedWhisperModelName(_modelName, _modelOptions),
        languageCode: _languageController.text.trim().isEmpty
            ? null
            : _languageController.text.trim(),
        maxCharsPerCue: _maxCharsPerCue,
        styleLabel: _captionStyleLabel,
        fontFamily: _fontFamily,
        fontSize: _fontSize,
        textColor: _textColor,
        backgroundColor: _backgroundColor,
        opacity: _opacity,
        animation: _textAnimation,
      ),
    );
  }
}

String _selectedWhisperModelName(
  String modelName,
  List<_WhisperModelOption> modelOptions,
) {
  return modelOptions.any((option) => option.value == modelName)
      ? modelName
      : _preferredWhisperModelName(modelOptions);
}

String _preferredWhisperModelName(List<_WhisperModelOption> modelOptions) {
  if (modelOptions.any(
    (option) => option.value == defaultLocalWhisperModelName,
  )) {
    return defaultLocalWhisperModelName;
  }
  return modelOptions.first.value;
}

class _TextClipDialog extends StatefulWidget {
  const _TextClipDialog({
    this.initialText = 'Texto',
    this.initialFontFamily = 'Arial',
    this.initialFontSize = 48,
    this.initialTextColor = 0xFFFFFFFF,
    this.initialBackgroundColor = 0x99000000,
    this.initialOpacity = 1,
    this.title = 'Adicionar texto',
    this.actionLabel = 'Adicionar',
  });

  final String initialText;
  final String initialFontFamily;
  final double initialFontSize;
  final int initialTextColor;
  final int initialBackgroundColor;
  final double initialOpacity;
  final String title;
  final String actionLabel;

  @override
  State<_TextClipDialog> createState() => _TextClipDialogState();
}

class _TextClipDialogState extends State<_TextClipDialog> {
  static const _fontFamilies = EditorFontService.families;
  static const _textColors = [
    _TextColorOption('Branco', 0xFFFFFFFF),
    _TextColorOption('Preto', 0xFF111111),
    _TextColorOption('Amarelo', 0xFFFFD166),
    _TextColorOption('Vermelho', 0xFFFF5A5F),
    _TextColorOption('Verde', 0xFF66D28F),
    _TextColorOption('Azul', 0xFF6AA9FF),
  ];
  static const _backgroundColors = [
    _TextColorOption('Sem fundo', 0x00000000),
    _TextColorOption('Preto', 0x99000000),
    _TextColorOption('Branco', 0x99FFFFFF),
    _TextColorOption('Amarelo', 0x99FFD166),
    _TextColorOption('Azul', 0x994C7DFF),
  ];

  late final TextEditingController _controller;
  late String _fontFamily;
  late double _fontSize;
  late int _textColor;
  late int _backgroundColor;
  late double _opacity;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _fontFamily = _fontFamilies.contains(widget.initialFontFamily)
        ? widget.initialFontFamily
        : _fontFamilies.first;
    _fontSize = _clampFontSize(widget.initialFontSize);
    _textColor = _optionValueOrDefault(_textColors, widget.initialTextColor);
    _backgroundColor = _optionValueOrDefault(
      _backgroundColors,
      widget.initialBackgroundColor,
    );
    _opacity = _clampOpacity(widget.initialOpacity);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final previewText = _controller.text.trim().isEmpty
        ? 'Texto'
        : _controller.text.trim();
    final textOpacity = _clampOpacity(_opacity);
    final backgroundAlpha =
        (((_backgroundColor >> 24) & 0xff) / 255.0) * textOpacity;

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _controller,
                autofocus: true,
                maxLines: 3,
                minLines: 1,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(labelText: 'Texto'),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _fontFamily,
                decoration: const InputDecoration(labelText: 'Fonte'),
                items: [
                  for (final family in _fontFamilies)
                    DropdownMenuItem(
                      value: family,
                      child: Text(family, style: TextStyle(fontFamily: family)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _fontFamily = value);
                  }
                },
              ),
              const SizedBox(height: 14),
              Text('Tamanho ${_fontSize.round()}'),
              Slider(
                value: _fontSize,
                min: 18,
                max: 120,
                divisions: 102,
                label: _fontSize.round().toString(),
                onChanged: (value) => setState(() => _fontSize = value),
              ),
              const SizedBox(height: 8),
              _ColorChoiceGroup(
                label: 'Cor do texto',
                options: _textColors,
                selectedValue: _textColor,
                onSelected: (value) => setState(() => _textColor = value),
              ),
              const SizedBox(height: 12),
              _ColorChoiceGroup(
                label: 'Fundo',
                options: _backgroundColors,
                selectedValue: _backgroundColor,
                onSelected: (value) => setState(() => _backgroundColor = value),
              ),
              const SizedBox(height: 12),
              Text('Opacidade ${(_opacity * 100).round()}%'),
              Slider(
                value: _opacity,
                min: 0.2,
                max: 1,
                divisions: 8,
                label: '${(_opacity * 100).round()}%',
                onChanged: (value) => setState(() => _opacity = value),
              ),
              const SizedBox(height: 10),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(
                        _backgroundColor,
                      ).withValues(alpha: backgroundAlpha.clamp(0.0, 1.0)),
                      border: Border.all(color: TgiColors.border),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Text(
                        previewText,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: _fontFamily,
                          color: Color(
                            _textColor,
                          ).withValues(alpha: textOpacity),
                          fontSize: _fontSize,
                          fontWeight: FontWeight.w800,
                          height: 1.08,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(onPressed: _submit, child: Text(widget.actionLabel)),
      ],
    );
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }
    Navigator.of(context).pop(
      _TextClipDialogResult(
        text: text,
        fontFamily: _fontFamily,
        fontSize: _fontSize,
        textColor: _textColor,
        backgroundColor: _backgroundColor,
        opacity: _opacity,
      ),
    );
  }

  int _optionValueOrDefault(List<_TextColorOption> options, int value) {
    return options.any((option) => option.value == value)
        ? value
        : options.first.value;
  }

  double _clampFontSize(double value) {
    if (value.isNaN || value.isInfinite) {
      return 48;
    }
    return value.clamp(18.0, 120.0).toDouble();
  }

  double _clampOpacity(double value) {
    if (value.isNaN || value.isInfinite) {
      return 1;
    }
    return value.clamp(0.2, 1.0).toDouble();
  }
}

class _ColorChoiceGroup extends StatelessWidget {
  const _ColorChoiceGroup({
    required this.label,
    required this.options,
    required this.selectedValue,
    required this.onSelected,
  });

  final String label;
  final List<_TextColorOption> options;
  final int selectedValue;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              Tooltip(
                message: option.label,
                child: _ColorSwatchButton(
                  value: option.value,
                  selected: option.value == selectedValue,
                  onPressed: () => onSelected(option.value),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ColorSwatchButton extends StatelessWidget {
  const _ColorSwatchButton({
    required this.value,
    required this.selected,
    required this.onPressed,
  });

  final int value;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = Color(value);
    final alpha = ((value >> 24) & 0xff) / 255.0;
    return InkResponse(
      onTap: onPressed,
      radius: 20,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? TgiColors.accent : TgiColors.border,
            width: selected ? 3 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: alpha == 0 ? TgiColors.transparent : color,
              border: alpha == 0
                  ? Border.all(color: TgiColors.textSecondary)
                  : null,
            ),
            child: const SizedBox.square(dimension: 24),
          ),
        ),
      ),
    );
  }
}

class _ExportSettingsDialog extends StatefulWidget {
  const _ExportSettingsDialog({
    required this.initial,
    required this.timelineDuration,
    required this.hasPaidPlan,
    required this.onOpenDownloads,
    this.playheadPosition = Duration.zero,
  });

  final FfmpegExportSettings initial;
  final Duration timelineDuration;
  final Duration playheadPosition;
  final bool hasPaidPlan;
  final VoidCallback onOpenDownloads;

  @override
  State<_ExportSettingsDialog> createState() => _ExportSettingsDialogState();
}

class _ExportSettingsDialogState extends State<_ExportSettingsDialog> {
  late FfmpegExportResolution _resolution;
  late int _fps = widget.initial.framesPerSecond;
  late FfmpegExportQuality _quality = widget.initial.quality;
  bool _advancedOpen = false;
  late FfmpegVideoEncoder _encoder = widget.initial.encoder;
  late bool _rangeEnabled = widget.initial.hasRange;
  late final _rangeStartText = TextEditingController(
    text: ((widget.initial.rangeStart ?? Duration.zero).inMilliseconds / 1000)
        .toStringAsFixed(3),
  );
  late final _rangeEndText = TextEditingController(
    text:
        ((widget.initial.rangeEnd ?? widget.timelineDuration).inMilliseconds /
                1000)
            .toStringAsFixed(3),
  );
  double? _secondsValue(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));
  bool get _validRange {
    if (!_rangeEnabled) return true;
    final start = _secondsValue(_rangeStartText.text);
    final end = _secondsValue(_rangeEndText.text);
    return start != null &&
        end != null &&
        start.isFinite &&
        end.isFinite &&
        start >= 0 &&
        end > start &&
        end * 1000 <= widget.timelineDuration.inMilliseconds;
  }

  Duration get _outputDuration => !_rangeEnabled || !_validRange
      ? widget.timelineDuration
      : Duration(
          milliseconds:
              ((_secondsValue(_rangeEndText.text)! -
                          _secondsValue(_rangeStartText.text)!) *
                      1000)
                  .round(),
        );

  @override
  void dispose() {
    _rangeStartText.dispose();
    _rangeEndText.dispose();
    super.dispose();
  }

  Widget _rangeControls() => Column(
    children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        key: const ValueKey('export_range_enabled'),
        title: const Text('Exportar somente um trecho'),
        value: _rangeEnabled,
        onChanged: (v) => setState(() => _rangeEnabled = v),
      ),
      if (_rangeEnabled) ...[
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _rangeStartText,
                key: const ValueKey('export_range_start'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Início (segundos)',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _rangeEndText,
                key: const ValueKey('export_range_end'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Fim (segundos)'),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => setState(
                () => _rangeStartText.text =
                    (widget.playheadPosition.inMilliseconds / 1000)
                        .toStringAsFixed(3),
              ),
              child: const Text('Início na agulha'),
            ),
            TextButton(
              onPressed: () => setState(
                () => _rangeEndText.text =
                    (widget.playheadPosition.inMilliseconds / 1000)
                        .toStringAsFixed(3),
              ),
              child: const Text('Fim na agulha'),
            ),
          ],
        ),
        if (!_validRange)
          const Text(
            'Informe um trecho válido dentro da timeline.',
            style: TextStyle(color: Colors.redAccent),
          ),
      ],
      if (Platform.isWindows) ...[
        const SizedBox(height: 12),
        DropdownButtonFormField<FfmpegVideoEncoder>(
          key: const ValueKey('export_encoder'),
          initialValue: _encoder,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Processamento'),
          items: [
            for (final e in FfmpegVideoEncoder.values)
              DropdownMenuItem(value: e, child: Text(e.label)),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _encoder = value);
          },
        ),
        const SizedBox(height: 6),
        const Text(
          'A GPU é verificada antes de exportar. Se não estiver disponível, o aplicativo usa a CPU.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    ],
  );

  @override
  void initState() {
    super.initState();
    _resolution =
        canExportResolution(
          widget.initial.resolution,
          hasPaidPlan: widget.hasPaidPlan,
        )
        ? widget.initial.resolution
        : FfmpegExportResolution.p2k;
    if (_resolution == FfmpegExportResolution.p4k &&
        _quality != FfmpegExportQuality.maximum) {
      _quality = FfmpegExportQuality.maximum;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.ios_share_outlined, color: TgiColors.accent),
          SizedBox(width: 10),
          Text('Pronto para exportar'),
        ],
      ),
      content: SizedBox(
        width: 510,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Escolha a qualidade. Na proxima tela voce escolhe a pasta '
                'onde o arquivo MP4 sera salvo.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: TgiColors.textSecondary,
                ),
              ),
              const SizedBox(height: TgiSpacing.md),
              DecoratedBox(
                key: const ValueKey('export_summary_card'),
                decoration: BoxDecoration(
                  color: TgiColors.surfaceRaised,
                  border: Border.all(color: TgiColors.borderSubtle),
                  borderRadius: BorderRadius.circular(TgiRadii.lg),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(TgiSpacing.md),
                  child: Row(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: TgiColors.accentMuted,
                          shape: BoxShape.circle,
                        ),
                        child: SizedBox.square(
                          dimension: 42,
                          child: Icon(
                            Icons.movie_creation_outlined,
                            color: TgiColors.accentSoft,
                          ),
                        ),
                      ),
                      const SizedBox(width: TgiSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_resolution.label}  •  ${_resolution.dimensionsLabel}',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$_fps fps  •  ${_quality.label}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: TgiColors.textSecondary),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_estimatedFileSizeLabel()}  •  MP4',
                              key: const ValueKey('export_size_estimate'),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: TgiColors.accentSoft,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: TgiSpacing.lg),
              _rangeControls(),
              const SizedBox(height: TgiSpacing.md),
              Text(
                'Qualidade do arquivo',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                'A recomendada funciona bem para YouTube e redes sociais.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: TgiColors.textSecondary),
              ),
              const SizedBox(height: TgiSpacing.sm),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ExportQualityChoice(
                    key: const ValueKey('export_quality_light'),
                    title: 'Arquivo menor',
                    subtitle: 'Mais rapido',
                    icon: Icons.bolt_outlined,
                    selected: _quality == FfmpegExportQuality.light,
                    onPressed: () =>
                        setState(() => _quality = FfmpegExportQuality.light),
                  ),
                  _ExportQualityChoice(
                    key: const ValueKey('export_quality_recommended'),
                    title: 'Recomendada',
                    subtitle: 'Melhor equilibrio',
                    icon: Icons.thumb_up_alt_outlined,
                    badge: 'INDICADO',
                    selected: _quality == FfmpegExportQuality.standard,
                    onPressed: () =>
                        setState(() => _quality = FfmpegExportQuality.standard),
                  ),
                  _ExportQualityChoice(
                    key: const ValueKey('export_quality_high'),
                    title: 'Alta',
                    subtitle: 'Mais detalhes',
                    icon: Icons.high_quality_outlined,
                    selected: _quality == FfmpegExportQuality.high,
                    onPressed: () =>
                        setState(() => _quality = FfmpegExportQuality.high),
                  ),
                  _ExportQualityChoice(
                    key: const ValueKey('export_quality_maximum'),
                    title: 'Maxima',
                    subtitle: 'Arquivo maior',
                    icon: Icons.diamond_outlined,
                    selected: _quality == FfmpegExportQuality.maximum,
                    onPressed: () =>
                        setState(() => _quality = FfmpegExportQuality.maximum),
                  ),
                ],
              ),
              const SizedBox(height: TgiSpacing.md),
              InkWell(
                key: const ValueKey('export_advanced_toggle'),
                onTap: () => setState(() => _advancedOpen = !_advancedOpen),
                borderRadius: BorderRadius.circular(TgiRadii.md),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Row(
                    children: [
                      const Icon(Icons.tune, size: 19),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Mais opcoes',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Icon(
                        _advancedOpen
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                      ),
                    ],
                  ),
                ),
              ),
              if (_advancedOpen)
                Padding(
                  padding: const EdgeInsets.only(top: TgiSpacing.sm),
                  child: Column(
                    children: [
                      DropdownButtonFormField<FfmpegExportResolution>(
                        key: const ValueKey('export_resolution_selector'),
                        isExpanded: true,
                        initialValue: _resolution,
                        decoration: const InputDecoration(
                          labelText: 'Tamanho / formato',
                        ),
                        items: [
                          for (final resolution in FfmpegExportResolution.all)
                            DropdownMenuItem(
                              value: resolution,
                              child: Text(
                                '${resolution.label}  ${resolution.dimensionsLabel}'
                                '${resolution.requiresPaidPlan && !widget.hasPaidPlan ? '  - Bloqueado' : ''}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _changeResolution,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        key: const ValueKey('export_fps_selector'),
                        isExpanded: true,
                        initialValue: _fps,
                        decoration: const InputDecoration(
                          labelText: 'Suavidade (quadros por segundo)',
                        ),
                        items: [
                          for (final fps
                              in FfmpegExportSettings.frameRateOptions)
                            DropdownMenuItem(
                              value: fps,
                              child: Text(
                                '$fps fps${fps == 30 ? '  - Recomendado' : ''}',
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => _fps = value);
                        },
                      ),
                      if (_resolution == FfmpegExportResolution.p4k) ...[
                        const SizedBox(height: 8),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '4K usa 3840x2160, qualidade Maxima e escala '
                            'Lanczos. Um video original menor nao ganha '
                            'detalhes que nao existiam.',
                            style: TextStyle(
                              color: TgiColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                      if (!widget.hasPaidPlan) ...[
                        const SizedBox(height: 8),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Gratis ate 2K. Ao escolher 4K, abriremos as '
                            'opcoes para liberar o recurso.',
                            style: TextStyle(
                              color: TgiColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton.icon(
          key: const ValueKey('export_choose_folder_button'),
          onPressed: !_validRange
              ? null
              : () {
                  Navigator.of(context).pop(
                    FfmpegExportSettings(
                      resolution: _resolution,
                      framesPerSecond: _fps,
                      quality: _quality,
                      encoder: _encoder,
                      rangeStart: _rangeEnabled
                          ? Duration(
                              milliseconds:
                                  (_secondsValue(_rangeStartText.text)! * 1000)
                                      .round(),
                            )
                          : null,
                      rangeEnd: _rangeEnabled
                          ? Duration(
                              milliseconds:
                                  (_secondsValue(_rangeEndText.text)! * 1000)
                                      .round(),
                            )
                          : null,
                    ),
                  );
                },
          icon: const Icon(Icons.folder_open_outlined, size: 18),
          label: const Text('Exportar e escolher pasta'),
        ),
      ],
    );
  }

  void _changeResolution(FfmpegExportResolution? value) {
    if (value == null) return;
    if (!canExportResolution(value, hasPaidPlan: widget.hasPaidPlan)) {
      widget.onOpenDownloads();
      return;
    }
    setState(() {
      _resolution = value;
      if (value == FfmpegExportResolution.p4k) {
        _quality = FfmpegExportQuality.maximum;
      }
    });
  }

  String _estimatedFileSizeLabel() {
    final seconds = math.max(1.0, _outputDuration.inMilliseconds / 1000);
    final pixels = _resolution.width * _resolution.height;
    final baseMbps = pixels >= 3840 * 2160
        ? 35.0
        : pixels >= 2560 * 1440
        ? 16.0
        : pixels >= 1920 * 1080
        ? 8.0
        : pixels >= 1280 * 720
        ? 5.0
        : 2.5;
    final qualityFactor = switch (_quality.id) {
      'light' => 0.62,
      'high' => 1.35,
      'maximum' => 1.8,
      _ => 1.0,
    };
    final fpsFactor = _fps >= 60 ? 1.45 : (_fps <= 24 ? 0.88 : 1.0);
    final megabytes = baseMbps * qualityFactor * fpsFactor * seconds / 8;
    final low = megabytes * 0.72;
    final high = megabytes * 1.28;
    String size(double value) => value >= 1024
        ? '${(value / 1024).toStringAsFixed(1)} GB'
        : '${math.max(1, value.round())} MB';
    return 'Tamanho estimado: ${size(low)}–${size(high)}';
  }
}

class _ExportQualityChoice extends StatelessWidget {
  const _ExportQualityChoice({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onPressed,
    this.badge,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 119,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(TgiRadii.md),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: selected ? TgiColors.accentMuted : TgiColors.surfaceRaised,
            border: Border.all(
              color: selected ? TgiColors.accent : TgiColors.borderSubtle,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(TgiRadii.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: selected
                        ? TgiColors.accentSoft
                        : TgiColors.textSecondary,
                  ),
                  const Spacer(),
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    size: 17,
                    color: selected ? TgiColors.accent : TgiColors.textMuted,
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TgiColors.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TgiColors.textMuted,
                  fontSize: 10,
                ),
              ),
              if (badge != null) ...[
                const SizedBox(height: 6),
                Text(
                  badge!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: TgiColors.accentSoft,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WatermarkSettingsDialog extends StatefulWidget {
  const _WatermarkSettingsDialog({required this.initial});

  final ProjectWatermark initial;

  @override
  State<_WatermarkSettingsDialog> createState() =>
      _WatermarkSettingsDialogState();
}

class _WatermarkSettingsDialogState extends State<_WatermarkSettingsDialog> {
  late bool _enabled;
  late String _imagePath;
  late WatermarkPosition _position;
  late double _x;
  late double _y;
  late double _scale;
  late double _opacity;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _enabled = initial.enabled;
    _imagePath = initial.imagePath;
    _position = initial.position;
    _x = initial.x;
    _y = initial.y;
    _scale = initial.scale;
    _opacity = initial.opacity;
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
    );
    final path = result?.files.single.path;
    if (path == null || path.isEmpty || !mounted) {
      return;
    }
    setState(() {
      _imagePath = path;
      _enabled = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Marca dagua'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _enabled,
              title: const Text('Ativar no export'),
              onChanged: (value) => setState(() => _enabled = value),
            ),
            const SizedBox(height: TgiSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _imagePath.isEmpty ? 'Nenhuma imagem' : _imagePath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: TgiColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: TgiSpacing.sm),
                OutlinedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: const Text('Imagem'),
                ),
              ],
            ),
            const SizedBox(height: TgiSpacing.md),
            DropdownButtonFormField<WatermarkPosition>(
              initialValue: _position,
              decoration: const InputDecoration(labelText: 'Posicao'),
              items: const [
                DropdownMenuItem(
                  value: WatermarkPosition.topLeft,
                  child: Text('Superior esquerda'),
                ),
                DropdownMenuItem(
                  value: WatermarkPosition.topRight,
                  child: Text('Superior direita'),
                ),
                DropdownMenuItem(
                  value: WatermarkPosition.bottomLeft,
                  child: Text('Inferior esquerda'),
                ),
                DropdownMenuItem(
                  value: WatermarkPosition.bottomRight,
                  child: Text('Inferior direita'),
                ),
                DropdownMenuItem(
                  value: WatermarkPosition.custom,
                  child: Text('Personalizada'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _position = value);
                }
              },
            ),
            const SizedBox(height: TgiSpacing.sm),
            if (_position == WatermarkPosition.custom) ...[
              _WatermarkSlider(
                label: 'X',
                value: _x,
                onChanged: (value) => setState(() => _x = value),
              ),
              _WatermarkSlider(
                label: 'Y',
                value: _y,
                onChanged: (value) => setState(() => _y = value),
              ),
            ],
            _WatermarkSlider(
              label: 'Escala',
              value: _scale,
              min: 0.1,
              max: 4,
              labelFor: (value) => '${(value * 100).round()}%',
              onChanged: (value) => setState(() => _scale = value),
            ),
            _WatermarkSlider(
              label: 'Opacidade',
              value: _opacity,
              labelFor: (value) => '${(value * 100).round()}%',
              onChanged: (value) => setState(() => _opacity = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              ProjectWatermark(
                enabled: _enabled && _imagePath.trim().isNotEmpty,
                imagePath: _imagePath,
                position: _position,
                x: _x,
                y: _y,
                scale: _scale,
                opacity: _opacity,
              ),
            );
          },
          child: const Text('Aplicar'),
        ),
      ],
    );
  }
}

class _WatermarkSlider extends StatelessWidget {
  const _WatermarkSlider({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.labelFor,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String Function(double value)? labelFor;

  @override
  Widget build(BuildContext context) {
    final formatter =
        labelFor ?? (value) => '${(value.clamp(0.0, 1.0) * 100).round()}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label ${formatter(value)}'),
        Slider(value: value, min: min, max: max, onChanged: onChanged),
      ],
    );
  }
}
