part of 'editor_screen.dart';

class _ClipPropertiesPanel extends StatelessWidget {
  const _ClipPropertiesPanel({
    required this.clip,
    required this.selectedClipCount,
    required this.mediaItem,
    required this.audioClip,
    required this.videoClip,
    required this.canUnlinkAudio,
    required this.canRelinkAudio,
    required this.timelineDuration,
    required this.onStartChanged,
    required this.onDurationChanged,
    required this.onVolumeChanged,
    required this.onAudioNoiseReductionChanged,
    this.onAudioSpeedChanged,
    required this.onUnlinkAudio,
    required this.onFadeInChanged,
    required this.onFadeOutChanged,
    required this.onFadeEnabled,
    required this.onAudioFadeInChanged,
    required this.onAudioFadeOutChanged,
    required this.onAudioFadeEnabled,
    required this.onVideoStabilizationChanged,
    required this.onTextChanged,
    required this.onTextFontFamilyChanged,
    required this.onTextFontSizeChanged,
    required this.onTextColorChanged,
    required this.onTextBackgroundColorChanged,
    required this.onTextOpacityChanged,
    required this.onTextAnimationChanged,
    required this.onTextPresetSelected,
  });

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

  static const _textAnimations = [
    _TextAnimationOption('Sem animacao', domain.TextClipAnimation.none),
    _TextAnimationOption('Fade', domain.TextClipAnimation.fade),
    _TextAnimationOption('Subir', domain.TextClipAnimation.rise),
    _TextAnimationOption('Pop', domain.TextClipAnimation.pop),
    _TextAnimationOption(
      'Entrar da esquerda',
      domain.TextClipAnimation.slideLeft,
    ),
  ];

  static const _textStylePresets = [
    _TextStylePreset(
      label: 'Legenda forte',
      fontFamily: 'Impact',
      fontSize: 68,
      textColor: 0xFFFFFFFF,
      backgroundColor: 0xDD000000,
      opacity: 1,
      animation: domain.TextClipAnimation.pop,
    ),
    _TextStylePreset(
      label: 'Titulo limpo',
      fontFamily: 'Segoe UI',
      fontSize: 54,
      textColor: 0xFFFFFFFF,
      backgroundColor: 0x00000000,
      opacity: 1,
      animation: domain.TextClipAnimation.rise,
    ),
    _TextStylePreset(
      label: 'Alerta amarelo',
      fontFamily: 'Impact',
      fontSize: 76,
      textColor: 0xFFFFD166,
      backgroundColor: 0x99000000,
      opacity: 1,
      animation: domain.TextClipAnimation.fade,
    ),
    _TextStylePreset(
      label: 'Meme branco',
      fontFamily: 'Impact',
      fontSize: 72,
      textColor: 0xFFFFFFFF,
      backgroundColor: 0x00000000,
      opacity: 1,
      animation: domain.TextClipAnimation.slideLeft,
    ),
  ];

  final domain.Clip? clip;
  final int selectedClipCount;
  final ValueChanged<double>? onAudioSpeedChanged;
  final MediaItem? mediaItem;
  final domain.Clip? audioClip;
  final domain.Clip? videoClip;
  final bool canUnlinkAudio;
  final bool canRelinkAudio;
  final Duration timelineDuration;
  final ValueChanged<Duration> onStartChanged;
  final ValueChanged<Duration> onDurationChanged;
  final ValueChanged<double> onVolumeChanged;
  final ValueChanged<double> onAudioNoiseReductionChanged;
  final VoidCallback onUnlinkAudio;
  final ValueChanged<Duration> onFadeInChanged;
  final ValueChanged<Duration> onFadeOutChanged;
  final ValueChanged<domain.Clip> onFadeEnabled;
  final ValueChanged<Duration> onAudioFadeInChanged;
  final ValueChanged<Duration> onAudioFadeOutChanged;
  final ValueChanged<domain.Clip> onAudioFadeEnabled;
  final ValueChanged<bool> onVideoStabilizationChanged;
  final void Function(domain.Clip clip, String text) onTextChanged;
  final void Function(domain.Clip clip, String fontFamily)
  onTextFontFamilyChanged;
  final void Function(domain.Clip clip, double fontSize) onTextFontSizeChanged;
  final void Function(domain.Clip clip, int textColor) onTextColorChanged;
  final void Function(domain.Clip clip, int backgroundColor)
  onTextBackgroundColorChanged;
  final void Function(domain.Clip clip, double opacity) onTextOpacityChanged;
  final void Function(domain.Clip clip, domain.TextClipAnimation animation)
  onTextAnimationChanged;
  final void Function(domain.Clip clip, _TextStylePreset preset)
  onTextPresetSelected;

  @override
  Widget build(BuildContext context) {
    final selectedClip = clip;
    if (selectedClip == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'Selecione um clipe',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: TgiColors.textSecondary),
          ),
        ),
      );
    }

    final timelineMax = _panelTimelineMax(timelineDuration, selectedClip);
    final startMax = timelineMax.inMilliseconds.toDouble();
    final editableDuration =
        selectedClip.trackType == TrackType.image ||
        selectedClip.trackType == TrackType.text;
    final durationMax = math.max(
      1000.0,
      (timelineMax - selectedClip.timelineStart).inMilliseconds.toDouble(),
    );
    final fadeMaxMs = math.max(
      0.0,
      math.min(5000.0, selectedClip.duration.inMilliseconds / 2),
    );
    final selectedVideoClip = videoClip;
    final selectedAudioClip = audioClip;
    final audioFadeMaxMs = selectedAudioClip == null
        ? 0.0
        : math.max(
            0.0,
            math.min(5000.0, selectedAudioClip.duration.inMilliseconds / 2),
          );
    final showPrimaryTransition =
        fadeMaxMs > 0 && selectedClip.trackType != TrackType.audio;
    final primaryFadeEnabled =
        selectedClip.fadeIn > Duration.zero ||
        selectedClip.fadeOut > Duration.zero;
    final audioFadeEnabled =
        selectedAudioClip != null &&
        (selectedAudioClip.fadeIn > Duration.zero ||
            selectedAudioClip.fadeOut > Duration.zero);
    final isText = selectedClip.trackType == TrackType.text;
    final fontFamily = _fontFamilies.contains(selectedClip.fontFamily)
        ? selectedClip.fontFamily
        : _fontFamilies.first;
    final textAnimation =
        _textAnimations.any(
          (option) => option.animation == selectedClip.textAnimation,
        )
        ? selectedClip.textAnimation
        : domain.TextClipAnimation.none;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _PropertyCard(
          child: Row(
            children: [
              _ClipTypeBadge(type: selectedClip.trackType),
              const SizedBox(width: TgiSpacing.md),
              Expanded(
                child: _PropertyHeaderText(
                  title:
                      mediaItem?.name ?? _clipTypeLabel(selectedClip.trackType),
                  subtitle: _clipTypeLabel(selectedClip.trackType),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: TgiSpacing.md),
        if (isText) ...[
          const SizedBox(height: 12),
          const _PropertySectionTitle('Texto'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in _textStylePresets)
                OutlinedButton(
                  onPressed: () => onTextPresetSelected(selectedClip, preset),
                  child: Text(preset.label),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey('clip_text_${selectedClip.id}'),
            initialValue: selectedClip.textContent,
            maxLines: 3,
            minLines: 1,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: 'Conteudo'),
            onChanged: (value) => onTextChanged(selectedClip, value),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: fontFamily,
            decoration: const InputDecoration(labelText: 'Fonte'),
            items: [
              for (final family in _fontFamilies)
                DropdownMenuItem(
                  value: family,
                  child: Text(
                    family,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: family),
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                onTextFontFamilyChanged(selectedClip, value);
              }
            },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<domain.TextClipAnimation>(
            isExpanded: true,
            initialValue: textAnimation,
            decoration: const InputDecoration(labelText: 'Animacao'),
            items: [
              for (final option in _textAnimations)
                DropdownMenuItem(
                  value: option.animation,
                  child: Text(option.label),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                onTextAnimationChanged(selectedClip, value);
              }
            },
          ),
          const SizedBox(height: 8),
          _DeferredDoubleSlider(
            key: ValueKey('clip_font_size_${selectedClip.id}'),
            label: 'Tamanho',
            value: selectedClip.fontSize,
            min: 12,
            max: 160,
            divisions: 148,
            valueLabel: (value) => value.round().toString(),
            onChanged: (value) => onTextFontSizeChanged(selectedClip, value),
          ),
          const SizedBox(height: 8),
          _ColorChoiceGroup(
            label: 'Cor do texto',
            options: _textColors,
            selectedValue: selectedClip.textColor,
            onSelected: (value) => onTextColorChanged(selectedClip, value),
          ),
          const SizedBox(height: 12),
          _ColorChoiceGroup(
            label: 'Fundo',
            options: _backgroundColors,
            selectedValue: selectedClip.backgroundColor,
            onSelected: (value) =>
                onTextBackgroundColorChanged(selectedClip, value),
          ),
          const SizedBox(height: 8),
          _DeferredDoubleSlider(
            key: ValueKey('clip_text_opacity_${selectedClip.id}'),
            label: 'Opacidade',
            value: selectedClip.opacity,
            min: 0.2,
            max: 1,
            divisions: 8,
            valueLabel: (value) => '${(value * 100).round()}%',
            onChanged: (value) => onTextOpacityChanged(selectedClip, value),
          ),
        ],
        const _PropertyDivider(),
        _PropertyReadout(
          label: 'Tipo',
          value: _clipTypeLabel(selectedClip.trackType),
        ),
        _PropertyReadout(
          label: 'Inicio',
          value: _formatPanelDuration(selectedClip.timelineStart),
        ),
        _PropertyReadout(
          label: 'Fim',
          value: _formatPanelDuration(selectedClip.timelineEnd),
        ),
        _PropertyReadout(
          label: 'Duracao',
          value: _formatPanelDuration(selectedClip.duration),
        ),
        if (selectedClipCount > 1)
          _PropertyReadout(
            label: 'Selecao',
            value: '$selectedClipCount grupos',
          ),
        const _PropertyDivider(),
        const _PropertySectionTitle('Tempo'),
        _DeferredDoubleSlider(
          key: ValueKey('clip_start_${selectedClip.id}'),
          label: 'Posicao',
          value: selectedClip.timelineStart.inMilliseconds.toDouble(),
          min: 0,
          max: math.max(1.0, startMax),
          valueLabel: (value) =>
              _formatPanelDuration(Duration(milliseconds: value.round())),
          onChanged: (value) =>
              onStartChanged(Duration(milliseconds: value.round())),
        ),
        if (editableDuration)
          _DeferredDoubleSlider(
            key: ValueKey('clip_duration_${selectedClip.id}'),
            label: 'Duracao',
            value: selectedClip.duration.inMilliseconds.toDouble(),
            min: 1000,
            max: durationMax,
            valueLabel: (value) =>
                _formatPanelDuration(Duration(milliseconds: value.round())),
            onChanged: (value) =>
                onDurationChanged(Duration(milliseconds: value.round())),
          ),
        if (showPrimaryTransition) ...[
          const SizedBox(height: 12),
          _PropertySectionTitle(
            selectedClip.trackType == TrackType.video
                ? 'Transicao de video'
                : 'Transicao',
          ),
          if (!primaryFadeEnabled)
            OutlinedButton.icon(
              onPressed: () => onFadeEnabled(selectedClip),
              icon: const Icon(Icons.opacity, size: 17),
              label: const Text('Ativar fade'),
            )
          else ...[
            _DeferredDoubleSlider(
              key: ValueKey('clip_fade_in_${selectedClip.id}'),
              label: 'Fade in',
              value: selectedClip.fadeIn.inMilliseconds.toDouble(),
              min: 0,
              max: fadeMaxMs,
              divisions: math.max(1, (fadeMaxMs / 100).round()).toInt(),
              valueLabel: (value) =>
                  _formatPanelDuration(Duration(milliseconds: value.round())),
              onChanged: (value) =>
                  onFadeInChanged(Duration(milliseconds: value.round())),
            ),
            _DeferredDoubleSlider(
              key: ValueKey('clip_fade_out_${selectedClip.id}'),
              label: 'Fade out',
              value: selectedClip.fadeOut.inMilliseconds.toDouble(),
              min: 0,
              max: fadeMaxMs,
              divisions: math.max(1, (fadeMaxMs / 100).round()).toInt(),
              valueLabel: (value) =>
                  _formatPanelDuration(Duration(milliseconds: value.round())),
              onChanged: (value) =>
                  onFadeOutChanged(Duration(milliseconds: value.round())),
            ),
          ],
        ],
        if (selectedVideoClip != null) ...[
          const SizedBox(height: 12),
          const _PropertySectionTitle('Faixa de video'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: selectedVideoClip.stabilizationEnabled,
            title: const Text('Estabilizar video'),
            subtitle: const Text('Aumenta bastante o tempo de exportacao.'),
            onChanged: onVideoStabilizationChanged,
          ),
        ],
        if (selectedAudioClip != null) ...[
          const SizedBox(height: 12),
          const _PropertySectionTitle('Audio'),
          if (selectedClip.trackType == TrackType.audio &&
              onAudioSpeedChanged != null)
            _DeferredDoubleSlider(
              label: 'Velocidade',
              value: selectedAudioClip.playbackSpeed,
              min: .25,
              max: 4,
              divisions: 15,
              valueLabel: (value) => '${value.toStringAsFixed(2)}×',
              onChanged: onAudioSpeedChanged!,
            ),
          _DeferredDoubleSlider(
            key: ValueKey('clip_volume_${selectedAudioClip.id}'),
            label: 'Volume',
            value: selectedAudioClip.volume,
            min: 0,
            max: 2,
            divisions: 40,
            valueLabel: (value) => '${(value * 100).round()}%',
            onChanged: onVolumeChanged,
          ),
          _DeferredDoubleSlider(
            key: ValueKey('clip_noise_${selectedAudioClip.id}'),
            label: 'Reducao de ruido',
            value: selectedAudioClip.audioNoiseReductionDb,
            min: 0,
            max: 30,
            divisions: 30,
            valueLabel: (value) => value <= 0.1 ? 'Off' : '${value.round()} dB',
            onChanged: onAudioNoiseReductionChanged,
          ),
          if (audioFadeMaxMs > 0) ...[
            const SizedBox(height: TgiSpacing.xs),
            if (!audioFadeEnabled)
              OutlinedButton.icon(
                onPressed: () => onAudioFadeEnabled(selectedAudioClip),
                icon: const Icon(Icons.opacity, size: 17),
                label: const Text('Ativar fade de áudio'),
              )
            else ...[
              _DeferredDoubleSlider(
                key: ValueKey('clip_audio_fade_in_${selectedAudioClip.id}'),
                label: 'Fade in audio',
                value: selectedAudioClip.fadeIn.inMilliseconds.toDouble(),
                min: 0,
                max: audioFadeMaxMs,
                divisions: math.max(1, (audioFadeMaxMs / 100).round()).toInt(),
                valueLabel: (value) =>
                    _formatPanelDuration(Duration(milliseconds: value.round())),
                onChanged: (value) =>
                    onAudioFadeInChanged(Duration(milliseconds: value.round())),
              ),
              _DeferredDoubleSlider(
                key: ValueKey('clip_audio_fade_out_${selectedAudioClip.id}'),
                label: 'Fade out audio',
                value: selectedAudioClip.fadeOut.inMilliseconds.toDouble(),
                min: 0,
                max: audioFadeMaxMs,
                divisions: math.max(1, (audioFadeMaxMs / 100).round()).toInt(),
                valueLabel: (value) =>
                    _formatPanelDuration(Duration(milliseconds: value.round())),
                onChanged: (value) => onAudioFadeOutChanged(
                  Duration(milliseconds: value.round()),
                ),
              ),
            ],
          ],
          if (canUnlinkAudio || canRelinkAudio) ...[
            const SizedBox(height: TgiSpacing.xs),
            OutlinedButton.icon(
              key: const ValueKey('audio-video-link-toggle'),
              onPressed: onUnlinkAudio,
              icon: Icon(
                canUnlinkAudio ? Icons.link_off_outlined : Icons.link_outlined,
                size: 18,
              ),
              label: Text(
                canUnlinkAudio
                    ? 'Separar áudio do vídeo'
                    : 'Vincular áudio ao vídeo',
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _ClipKeyframeEditor extends StatefulWidget {
  const _ClipKeyframeEditor({
    required this.clip,
    required this.playheadPosition,
    required this.onPlayheadChanged,
    required this.onSaved,
    required this.onRemovedNear,
    required this.onCleared,
  });

  final domain.Clip clip;
  final Duration playheadPosition;
  final ValueChanged<Duration> onPlayheadChanged;
  final void Function(domain.ClipKeyframeProperty property, double value)
  onSaved;
  final ValueChanged<domain.ClipKeyframeProperty> onRemovedNear;
  final ValueChanged<domain.ClipKeyframeProperty> onCleared;

  @override
  State<_ClipKeyframeEditor> createState() => _ClipKeyframeEditorState();
}

class _ClipKeyframeEditorState extends State<_ClipKeyframeEditor> {
  domain.ClipKeyframeProperty? _property;
  double? _value;

  @override
  void initState() {
    super.initState();
    _syncSelection(resetProperty: true);
  }

  @override
  void didUpdateWidget(covariant _ClipKeyframeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clip.id != widget.clip.id ||
        oldWidget.playheadPosition != widget.playheadPosition ||
        oldWidget.clip.keyframes != widget.clip.keyframes) {
      _syncSelection(resetProperty: oldWidget.clip.id != widget.clip.id);
    }
  }

  void _syncSelection({required bool resetProperty}) {
    final specs = _keyframeSpecsForClip(widget.clip);
    if (specs.isEmpty) {
      _property = null;
      _value = null;
      return;
    }
    if (resetProperty ||
        _property == null ||
        !specs.any((spec) => spec.property == _property)) {
      _property = specs.first.property;
    }
    _value = _currentValue(_property!);
  }

  double _currentValue(domain.ClipKeyframeProperty property) {
    return widget.clip.keyframedValue(
      property,
      _normalizedClipTime(widget.clip, widget.playheadPosition),
    );
  }

  @override
  Widget build(BuildContext context) {
    final specs = _keyframeSpecsForClip(widget.clip);
    if (specs.isEmpty) {
      return const SizedBox.shrink();
    }
    final selectedProperty = _property ?? specs.first.property;
    final spec = _keyframeSpecFor(selectedProperty);
    final value = (_value ?? _currentValue(selectedProperty))
        .clamp(spec.min, spec.max)
        .toDouble();
    final keyframes = widget.clip.keyframesFor(selectedProperty);
    final playheadTime = _normalizedClipTime(
      widget.clip,
      widget.playheadPosition,
    );
    final currentKeyframe = _keyframeNear(keyframes, playheadTime);
    final previousKeyframe = _previousKeyframe(keyframes, playheadTime);
    final nextKeyframe = _nextKeyframe(keyframes, playheadTime);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          key: const ValueKey('keyframe_help_card'),
          decoration: BoxDecoration(
            color: TgiColors.accentRose.withValues(alpha: 0.1),
            border: Border.all(
              color: TgiColors.accentRose.withValues(alpha: 0.42),
            ),
            borderRadius: BorderRadius.circular(TgiRadii.lg),
          ),
          child: Padding(
            padding: EdgeInsets.all(TgiSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.auto_awesome_motion_outlined,
                  color: TgiColors.accentRose,
                  size: 22,
                ),
                SizedBox(width: TgiSpacing.sm),
                Expanded(
                  child: Text(
                    'Crie dois pontos com valores diferentes. O editor faz a '
                    'mudanca suave entre eles automaticamente.',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: TgiSpacing.md),
        _PropertyCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _KeyframeStepTitle(
                number: '1',
                title: 'Escolha o que vai mudar',
              ),
              const SizedBox(height: TgiSpacing.sm),
              DropdownButtonFormField<domain.ClipKeyframeProperty>(
                key: const ValueKey('keyframe_property_selector'),
                isExpanded: true,
                initialValue: selectedProperty,
                decoration: const InputDecoration(
                  labelText: 'Propriedade animada',
                  helperText: 'Ex.: zoom, posicao, brilho ou volume',
                ),
                items: [
                  for (final option in specs)
                    DropdownMenuItem(
                      value: option.property,
                      child: Text(option.label),
                    ),
                ],
                onChanged: (property) {
                  if (property == null) return;
                  setState(() {
                    _property = property;
                    _value = _currentValue(property);
                  });
                },
              ),
              const SizedBox(height: TgiSpacing.lg),
              const _KeyframeStepTitle(number: '2', title: 'Escolha o momento'),
              const SizedBox(height: 4),
              Text(
                'Clique na linha ou em um losango para mover o marcador.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: TgiColors.textSecondary),
              ),
              const SizedBox(height: TgiSpacing.sm),
              _KeyframeTimeline(
                key: const ValueKey('keyframe_interactive_timeline'),
                playheadTime: playheadTime,
                keyframes: keyframes,
                onSeek: _seekTo,
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: previousKeyframe == null
                          ? null
                          : () => _seekTo(previousKeyframe.time),
                      icon: const Icon(Icons.skip_previous, size: 17),
                      label: const Text('Anterior'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: nextKeyframe == null
                          ? null
                          : () => _seekTo(nextKeyframe.time),
                      icon: const Icon(Icons.skip_next, size: 17),
                      label: const Text('Proximo'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: TgiSpacing.lg),
              _KeyframeStepTitle(
                number: '3',
                title: currentKeyframe == null
                    ? 'Defina o valor e crie o ponto'
                    : 'Ajuste o ponto selecionado',
              ),
              const SizedBox(height: TgiSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      spec.label,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: TgiColors.surfaceRaised,
                      borderRadius: BorderRadius.circular(TgiRadii.sm),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Text(
                        spec.valueLabel(value),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: TgiColors.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: TgiColors.accentRose,
                  inactiveTrackColor: TgiColors.borderStrong,
                  thumbColor: TgiColors.accentRose,
                  overlayColor: TgiColors.accentRose.withValues(alpha: 0.14),
                  trackHeight: 6,
                  trackShape: const TgiSliderTrackShape(),
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 18,
                  ),
                  tickMarkShape: SliderTickMarkShape.noTickMark,
                ),
                child: Slider(
                  key: const ValueKey('keyframe_value_slider'),
                  value: value,
                  min: spec.min,
                  max: spec.max,
                  divisions: spec.divisions,
                  label: spec.valueLabel(value),
                  onChanged: (next) => setState(() => _value = next),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  key: const ValueKey('keyframe_save_point'),
                  onPressed: () =>
                      widget.onSaved(selectedProperty, _value ?? value),
                  icon: Icon(
                    currentKeyframe == null
                        ? Icons.add_location_alt_outlined
                        : Icons.save_outlined,
                    size: 18,
                  ),
                  label: Text(
                    currentKeyframe == null
                        ? 'Criar ponto neste momento'
                        : 'Atualizar este ponto',
                  ),
                ),
              ),
              const SizedBox(height: TgiSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_formatPanelDuration(Duration(microseconds: (widget.clip.duration.inMicroseconds * playheadTime).round()))} de ${_formatPanelDuration(widget.clip.duration)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: TgiColors.textSecondary,
                      ),
                    ),
                  ),
                  Text(
                    '${keyframes.length} ${keyframes.length == 1 ? 'ponto' : 'pontos'}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: TgiColors.textSecondary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              if (keyframes.length == 1) ...[
                const SizedBox(height: TgiSpacing.sm),
                const _KeyframeHint(
                  icon: Icons.arrow_forward,
                  text:
                      'Agora avance o marcador, mude o valor e crie o '
                      'segundo ponto.',
                ),
              ] else if (keyframes.length >= 2) ...[
                const SizedBox(height: TgiSpacing.sm),
                const _KeyframeHint(
                  icon: Icons.check_circle_outline,
                  text: 'Animacao pronta. Dê play para conferir o movimento.',
                ),
              ],
              if (keyframes.isNotEmpty) ...[
                const SizedBox(height: TgiSpacing.md),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final keyframe in keyframes)
                      _KeyframePill(
                        label:
                            '${_formatPanelDuration(Duration(microseconds: (widget.clip.duration.inMicroseconds * keyframe.time).round()))}  ${spec.valueLabel(keyframe.value)}',
                        selected: keyframe.id == currentKeyframe?.id,
                        onPressed: () => _seekTo(keyframe.time),
                      ),
                  ],
                ),
                const SizedBox(height: TgiSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: currentKeyframe == null
                            ? null
                            : () => widget.onRemovedNear(selectedProperty),
                        icon: const Icon(Icons.remove_circle_outline, size: 17),
                        label: const Text('Remover ponto'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Apagar todos os pontos desta propriedade',
                      child: IconButton.outlined(
                        onPressed: () => widget.onCleared(selectedProperty),
                        icon: const Icon(Icons.delete_sweep_outlined),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _seekTo(double normalizedTime) {
    final safeTime = normalizedTime.clamp(0.0, 1.0);
    widget.onPlayheadChanged(
      widget.clip.timelineStart +
          Duration(
            microseconds: (widget.clip.duration.inMicroseconds * safeTime)
                .round(),
          ),
    );
  }

  domain.ClipKeyframe? _keyframeNear(
    List<domain.ClipKeyframe> keyframes,
    double time,
  ) {
    for (final keyframe in keyframes) {
      if ((keyframe.time - time).abs() <= 0.02) return keyframe;
    }
    return null;
  }

  domain.ClipKeyframe? _previousKeyframe(
    List<domain.ClipKeyframe> keyframes,
    double time,
  ) {
    for (final keyframe in keyframes.reversed) {
      if (keyframe.time < time - 0.005) return keyframe;
    }
    return null;
  }

  domain.ClipKeyframe? _nextKeyframe(
    List<domain.ClipKeyframe> keyframes,
    double time,
  ) {
    for (final keyframe in keyframes) {
      if (keyframe.time > time + 0.005) return keyframe;
    }
    return null;
  }
}

class _KeyframePill extends StatelessWidget {
  const _KeyframePill({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(TgiRadii.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected
              ? TgiColors.accentRose.withValues(alpha: 0.16)
              : TgiColors.surfaceRaised,
          border: Border.all(
            color: selected ? TgiColors.accentRose : TgiColors.borderSubtle,
          ),
          borderRadius: BorderRadius.circular(TgiRadii.sm),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: TgiColors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _KeyframeStepTitle extends StatelessWidget {
  const _KeyframeStepTitle({required this.number, required this.title});

  final String number;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: TgiColors.accentRose,
            shape: BoxShape.circle,
          ),
          child: SizedBox.square(
            dimension: 24,
            child: Center(
              child: Text(
                number,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: TgiColors.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _KeyframeHint extends StatelessWidget {
  const _KeyframeHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TgiColors.surfaceRaised,
        borderRadius: BorderRadius.circular(TgiRadii.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(TgiSpacing.sm),
        child: Row(
          children: [
            Icon(icon, size: 17, color: TgiColors.accentRose),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: TgiColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyframeTimeline extends StatelessWidget {
  const _KeyframeTimeline({
    super.key,
    required this.playheadTime,
    required this.keyframes,
    required this.onSeek,
  });

  final double playheadTime;
  final List<domain.ClipKeyframe> keyframes;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    const horizontalInset = 10.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final usableWidth = math.max(
          1.0,
          constraints.maxWidth - horizontalInset * 2,
        );
        double xFor(double time) =>
            horizontalInset + time.clamp(0.0, 1.0) * usableWidth;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final normalized =
                ((details.localPosition.dx - horizontalInset) / usableWidth)
                    .clamp(0.0, 1.0);
            onSeek(normalized);
          },
          child: SizedBox(
            height: 58,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: horizontalInset,
                  right: horizontalInset,
                  top: 27,
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: TgiColors.borderStrong,
                      borderRadius: BorderRadius.circular(TgiRadii.md),
                    ),
                  ),
                ),
                Positioned(
                  left: horizontalInset,
                  top: 19,
                  child: Text(
                    'Inicio',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: TgiColors.textMuted,
                      fontSize: 9,
                    ),
                  ),
                ),
                Positioned(
                  right: horizontalInset,
                  top: 19,
                  child: Text(
                    'Fim',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: TgiColors.textMuted,
                      fontSize: 9,
                    ),
                  ),
                ),
                for (final keyframe in keyframes)
                  Positioned(
                    left: xFor(keyframe.time) - 9,
                    top: 20,
                    child: Tooltip(
                      message: 'Ir para este ponto',
                      child: GestureDetector(
                        onTap: () => onSeek(keyframe.time),
                        child: Transform.rotate(
                          angle: math.pi / 4,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: TgiColors.accentRose,
                              border: Border.all(color: Colors.white, width: 2),
                              borderRadius: BorderRadius.circular(TgiRadii.sm),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: xFor(playheadTime) - 1,
                  top: 7,
                  child: Container(
                    width: 2,
                    height: 44,
                    color: TgiColors.playheadGlow,
                  ),
                ),
                Positioned(
                  left: xFor(playheadTime) - 6,
                  top: 2,
                  child: Icon(
                    Icons.arrow_drop_down,
                    size: 12,
                    color: TgiColors.playheadGlow,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _KeyframePropertySpec {
  const _KeyframePropertySpec({
    required this.property,
    required this.label,
    required this.min,
    required this.max,
    required this.valueLabel,
    this.divisions,
  });

  final domain.ClipKeyframeProperty property;
  final String label;
  final double min;
  final double max;
  final int? divisions;
  final String Function(double value) valueLabel;
}

List<_KeyframePropertySpec> _keyframeSpecsForClip(domain.Clip clip) {
  final properties = switch (clip.trackType) {
    TrackType.video => const [
      domain.ClipKeyframeProperty.overlayX,
      domain.ClipKeyframeProperty.overlayY,
      domain.ClipKeyframeProperty.overlayScale,
      domain.ClipKeyframeProperty.opacity,
      domain.ClipKeyframeProperty.brightness,
      domain.ClipKeyframeProperty.contrast,
      domain.ClipKeyframeProperty.saturation,
      domain.ClipKeyframeProperty.exposure,
      domain.ClipKeyframeProperty.hue,
      domain.ClipKeyframeProperty.cropLeft,
      domain.ClipKeyframeProperty.cropTop,
      domain.ClipKeyframeProperty.cropRight,
      domain.ClipKeyframeProperty.cropBottom,
      domain.ClipKeyframeProperty.maskX,
      domain.ClipKeyframeProperty.maskY,
      domain.ClipKeyframeProperty.maskWidth,
      domain.ClipKeyframeProperty.maskHeight,
    ],
    TrackType.image => const [
      domain.ClipKeyframeProperty.overlayX,
      domain.ClipKeyframeProperty.overlayY,
      domain.ClipKeyframeProperty.overlayScale,
      domain.ClipKeyframeProperty.opacity,
      domain.ClipKeyframeProperty.cropLeft,
      domain.ClipKeyframeProperty.cropTop,
      domain.ClipKeyframeProperty.cropRight,
      domain.ClipKeyframeProperty.cropBottom,
    ],
    TrackType.text => const [
      domain.ClipKeyframeProperty.overlayX,
      domain.ClipKeyframeProperty.overlayY,
      domain.ClipKeyframeProperty.opacity,
    ],
    TrackType.audio => const [domain.ClipKeyframeProperty.volume],
  };
  return [for (final property in properties) _keyframeSpecFor(property)];
}

_KeyframePropertySpec _keyframeSpecFor(domain.ClipKeyframeProperty property) {
  String percent(double value) => '${(value * 100).round()}%';
  String signed(double value) => value.toStringAsFixed(2);
  switch (property) {
    case domain.ClipKeyframeProperty.overlayX:
      return _KeyframePropertySpec(
        property: property,
        label: 'Posicao X',
        min: 0,
        max: 1,
        divisions: 100,
        valueLabel: percent,
      );
    case domain.ClipKeyframeProperty.overlayY:
      return _KeyframePropertySpec(
        property: property,
        label: 'Posicao Y',
        min: 0,
        max: 1,
        divisions: 100,
        valueLabel: percent,
      );
    case domain.ClipKeyframeProperty.overlayScale:
      return _KeyframePropertySpec(
        property: property,
        label: 'Escala / zoom',
        min: 0.35,
        max: 8,
        divisions: 153,
        valueLabel: percent,
      );
    case domain.ClipKeyframeProperty.opacity:
      return _KeyframePropertySpec(
        property: property,
        label: 'Opacidade',
        min: 0,
        max: 1,
        divisions: 100,
        valueLabel: percent,
      );
    case domain.ClipKeyframeProperty.volume:
      return _KeyframePropertySpec(
        property: property,
        label: 'Volume',
        min: 0,
        max: 2,
        divisions: 100,
        valueLabel: percent,
      );
    case domain.ClipKeyframeProperty.brightness:
      return _KeyframePropertySpec(
        property: property,
        label: 'Brilho',
        min: -1,
        max: 1,
        divisions: 100,
        valueLabel: signed,
      );
    case domain.ClipKeyframeProperty.contrast:
      return _KeyframePropertySpec(
        property: property,
        label: 'Contraste',
        min: 0,
        max: 3,
        divisions: 150,
        valueLabel: signed,
      );
    case domain.ClipKeyframeProperty.saturation:
      return _KeyframePropertySpec(
        property: property,
        label: 'Saturacao',
        min: 0,
        max: 3,
        divisions: 150,
        valueLabel: signed,
      );
    case domain.ClipKeyframeProperty.exposure:
      return _KeyframePropertySpec(
        property: property,
        label: 'Exposicao',
        min: -1,
        max: 1,
        divisions: 100,
        valueLabel: signed,
      );
    case domain.ClipKeyframeProperty.hue:
      return _KeyframePropertySpec(
        property: property,
        label: 'Matiz',
        min: -180,
        max: 180,
        divisions: 180,
        valueLabel: (value) => '${value.round()}°',
      );
    case domain.ClipKeyframeProperty.cropLeft:
      return _cropKeyframeSpec(property, 'Crop esquerda');
    case domain.ClipKeyframeProperty.cropTop:
      return _cropKeyframeSpec(property, 'Crop topo');
    case domain.ClipKeyframeProperty.cropRight:
      return _cropKeyframeSpec(property, 'Crop direita');
    case domain.ClipKeyframeProperty.cropBottom:
      return _cropKeyframeSpec(property, 'Crop base');
    case domain.ClipKeyframeProperty.chromaKeySimilarity:
      return _KeyframePropertySpec(
        property: property,
        label: 'Chroma similaridade',
        min: 0,
        max: 1,
        divisions: 100,
        valueLabel: percent,
      );
    case domain.ClipKeyframeProperty.chromaKeyBlend:
      return _KeyframePropertySpec(
        property: property,
        label: 'Chroma suavidade',
        min: 0,
        max: 1,
        divisions: 100,
        valueLabel: percent,
      );
    case domain.ClipKeyframeProperty.maskX:
      return _KeyframePropertySpec(
        property: property,
        label: 'Mascara X',
        min: 0,
        max: 1,
        divisions: 100,
        valueLabel: percent,
      );
    case domain.ClipKeyframeProperty.maskY:
      return _KeyframePropertySpec(
        property: property,
        label: 'Mascara Y',
        min: 0,
        max: 1,
        divisions: 100,
        valueLabel: percent,
      );
    case domain.ClipKeyframeProperty.maskWidth:
      return _KeyframePropertySpec(
        property: property,
        label: 'Largura da mascara',
        min: 0.04,
        max: 1,
        divisions: 96,
        valueLabel: percent,
      );
    case domain.ClipKeyframeProperty.maskHeight:
      return _KeyframePropertySpec(
        property: property,
        label: 'Altura da mascara',
        min: 0.04,
        max: 1,
        divisions: 96,
        valueLabel: percent,
      );
  }
}

_KeyframePropertySpec _cropKeyframeSpec(
  domain.ClipKeyframeProperty property,
  String label,
) {
  return _KeyframePropertySpec(
    property: property,
    label: label,
    min: 0,
    max: 0.8,
    divisions: 80,
    valueLabel: (value) => '${(value * 100).round()}%',
  );
}

double _normalizedClipTime(domain.Clip clip, Duration playheadPosition) {
  if (clip.duration <= Duration.zero) {
    return 0;
  }
  final value =
      (playheadPosition - clip.timelineStart).inMicroseconds /
      clip.duration.inMicroseconds;
  if (value.isNaN || value.isInfinite) {
    return 0;
  }
  return value.clamp(0.0, 1.0).toDouble();
}

class _PropertySectionTitle extends StatelessWidget {
  const _PropertySectionTitle(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 8),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: TgiColors.textSecondary,
      ),
    ),
  );
}

class _PropertyCard extends StatelessWidget {
  const _PropertyCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: TgiSpacing.sm),
      child: child,
    );
  }
}

class _ClipTypeBadge extends StatelessWidget {
  const _ClipTypeBadge({required this.type});

  final TrackType type;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 34,
      child: TgiFramedBox(
        radius: TgiRadii.md,
        strokeWidth: 1.2,
        child: TgiAccentIcon(_clipTypeIcon(type), size: TgiIconSizes.md),
      ),
    );
  }
}

class _PropertyDivider extends StatelessWidget {
  const _PropertyDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: TgiSpacing.sm),
      child: Divider(height: 1),
    );
  }
}

class _PropertyHeaderText extends StatelessWidget {
  const _PropertyHeaderText({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: TgiColors.textPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: TgiColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _PropertyReadout extends StatelessWidget {
  const _PropertyReadout({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: TgiSpacing.xs),
      child: Row(
        children: [
          Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: TgiColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: TgiSpacing.sm),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: TgiColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeferredDoubleSlider extends StatefulWidget {
  const _DeferredDoubleSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.valueLabel,
    required this.onChanged,
    this.divisions,
    super.key,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String Function(double value) valueLabel;
  final ValueChanged<double> onChanged;

  @override
  State<_DeferredDoubleSlider> createState() => _DeferredDoubleSliderState();
}

class _DeferredDoubleSliderState extends State<_DeferredDoubleSlider> {
  double? _draftValue;

  @override
  void didUpdateWidget(covariant _DeferredDoubleSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value ||
        oldWidget.min != widget.min ||
        oldWidget.max != widget.max) {
      _draftValue = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final min = widget.min;
    final max = math.max(min, widget.max);
    final value = (_draftValue ?? widget.value).clamp(min, max).toDouble();
    final enabled = max > min;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                widget.valueLabel(value),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TgiColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: TgiColors.accentSoft,
              inactiveTrackColor: TgiColors.borderStrong,
              thumbColor: TgiColors.textPrimary,
              overlayColor: TgiColors.glowSoft,
              trackHeight: 5,
              trackShape: const TgiSliderTrackShape(),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              tickMarkShape: SliderTickMarkShape.noTickMark,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: widget.divisions,
              label: widget.valueLabel(value),
              onChanged: enabled
                  ? (next) {
                      setState(() => _draftValue = next);
                    }
                  : null,
              onChangeEnd: enabled
                  ? (next) {
                      setState(() => _draftValue = null);
                      widget.onChanged(next);
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
