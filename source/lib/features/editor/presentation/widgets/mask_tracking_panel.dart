import 'package:flutter/material.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../../../domain/models/clip.dart';

typedef MaskGeometryChanged =
    void Function({double? x, double? y, double? width, double? height});

class MaskTrackingPanel extends StatefulWidget {
  const MaskTrackingPanel({
    required this.clip,
    required this.mediaName,
    required this.currentX,
    required this.currentY,
    required this.isTracking,
    required this.trackingProgress,
    required this.onEnabledChanged,
    required this.onShapeChanged,
    required this.onEffectChanged,
    required this.onGeometryChanged,
    required this.onFeatherChanged,
    required this.onIntensityChanged,
    required this.onInvertedChanged,
    required this.onSavePoint,
    required this.onTrack,
    required this.onAttachImage,
    required this.onClearTracking,
    super.key,
  });

  final Clip? clip;
  final String? mediaName;
  final double currentX;
  final double currentY;
  final bool isTracking;
  final double trackingProgress;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<VideoMaskShape> onShapeChanged;
  final ValueChanged<VideoMaskEffect> onEffectChanged;
  final MaskGeometryChanged onGeometryChanged;
  final ValueChanged<double> onFeatherChanged;
  final ValueChanged<double> onIntensityChanged;
  final ValueChanged<bool> onInvertedChanged;
  final VoidCallback onSavePoint;
  final VoidCallback onTrack;
  final VoidCallback onAttachImage;
  final VoidCallback onClearTracking;

  @override
  State<MaskTrackingPanel> createState() => _MaskTrackingPanelState();
}

class _MaskTrackingPanelState extends State<MaskTrackingPanel> {
  late double _x;
  late double _y;
  late double _width;
  late double _height;
  late double _feather;
  late double _intensity;

  @override
  void initState() {
    super.initState();
    _syncDrafts();
  }

  @override
  void didUpdateWidget(covariant MaskTrackingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clip?.id != widget.clip?.id ||
        oldWidget.currentX != widget.currentX ||
        oldWidget.currentY != widget.currentY ||
        oldWidget.clip?.maskWidth != widget.clip?.maskWidth ||
        oldWidget.clip?.maskHeight != widget.clip?.maskHeight ||
        oldWidget.clip?.maskFeather != widget.clip?.maskFeather ||
        oldWidget.clip?.maskIntensity != widget.clip?.maskIntensity) {
      _syncDrafts();
    }
  }

  void _syncDrafts() {
    final clip = widget.clip;
    _x = widget.currentX;
    _y = widget.currentY;
    _width = clip?.maskWidth ?? 0.32;
    _height = clip?.maskHeight ?? 0.32;
    _feather = clip?.maskFeather ?? 0.08;
    _intensity = clip?.maskIntensity ?? 0.7;
  }

  @override
  Widget build(BuildContext context) {
    final clip = widget.clip;
    if (clip == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(TgiSpacing.xl),
          child: Text(
            'Selecione um clipe de video para criar uma mascara.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final trackingPoints = clip.keyframesFor(ClipKeyframeProperty.maskX).length;
    return ListView(
      padding: const EdgeInsets.all(TgiSpacing.md),
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: TgiColors.surfacePressed,
            border: Border.all(color: TgiColors.accentMuted),
            borderRadius: BorderRadius.circular(TgiRadii.md),
          ),
          child: Padding(
            padding: const EdgeInsets.all(TgiSpacing.sm),
            child: Row(
              children: [
                Icon(Icons.gesture, color: TgiColors.accentSoft),
                const SizedBox(width: TgiSpacing.sm),
                Expanded(
                  child: Text(
                    widget.mediaName ?? 'Clipe selecionado',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (trackingPoints > 0)
                  Text(
                    '$trackingPoints pontos',
                    style: TextStyle(color: TgiColors.accentSoft),
                  ),
              ],
            ),
          ),
        ),
        SwitchListTile(
          key: const ValueKey('mask_enabled_switch'),
          contentPadding: EdgeInsets.zero,
          value: clip.maskEnabled,
          title: const Text('Ativar mascara'),
          subtitle: const Text('Arraste a area diretamente no preview.'),
          onChanged: widget.isTracking ? null : widget.onEnabledChanged,
        ),
        AnimatedOpacity(
          opacity: clip.maskEnabled ? 1 : 0.45,
          duration: const Duration(milliseconds: 160),
          child: IgnorePointer(
            ignoring: !clip.maskEnabled || widget.isTracking,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<VideoMaskShape>(
                  key: const ValueKey('mask_shape_selector'),
                  segments: const [
                    ButtonSegment(
                      value: VideoMaskShape.ellipse,
                      icon: Icon(Icons.circle_outlined),
                      label: Text('Elipse'),
                    ),
                    ButtonSegment(
                      value: VideoMaskShape.rectangle,
                      icon: Icon(Icons.crop_square),
                      label: Text('Retangulo'),
                    ),
                  ],
                  selected: {clip.maskShape},
                  onSelectionChanged: (value) =>
                      widget.onShapeChanged(value.first),
                ),
                const SizedBox(height: TgiSpacing.md),
                DropdownButtonFormField<VideoMaskEffect>(
                  key: const ValueKey('mask_effect_selector'),
                  initialValue: clip.maskEffect,
                  decoration: const InputDecoration(labelText: 'Efeito'),
                  items: const [
                    DropdownMenuItem(
                      value: VideoMaskEffect.blur,
                      child: Text('Desfoque'),
                    ),
                    DropdownMenuItem(
                      value: VideoMaskEffect.pixelate,
                      child: Text('Pixelar / censurar'),
                    ),
                    DropdownMenuItem(
                      value: VideoMaskEffect.darken,
                      child: Text('Escurecer'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) widget.onEffectChanged(value);
                  },
                ),
                const SizedBox(height: TgiSpacing.md),
                _MaskSlider(
                  label: 'Posicao X',
                  value: _x,
                  onChanged: (value) => setState(() => _x = value),
                  onChangeEnd: (value) => widget.onGeometryChanged(x: value),
                ),
                _MaskSlider(
                  label: 'Posicao Y',
                  value: _y,
                  onChanged: (value) => setState(() => _y = value),
                  onChangeEnd: (value) => widget.onGeometryChanged(y: value),
                ),
                _MaskSlider(
                  label: 'Largura',
                  value: _width,
                  min: 0.04,
                  onChanged: (value) => setState(() => _width = value),
                  onChangeEnd: (value) =>
                      widget.onGeometryChanged(width: value),
                ),
                _MaskSlider(
                  label: 'Altura',
                  value: _height,
                  min: 0.04,
                  onChanged: (value) => setState(() => _height = value),
                  onChangeEnd: (value) =>
                      widget.onGeometryChanged(height: value),
                ),
                _MaskSlider(
                  label: 'Suavidade da borda',
                  value: _feather,
                  max: 0.5,
                  onChanged: (value) => setState(() => _feather = value),
                  onChangeEnd: widget.onFeatherChanged,
                ),
                _MaskSlider(
                  label: 'Intensidade',
                  value: _intensity,
                  min: 0.05,
                  onChanged: (value) => setState(() => _intensity = value),
                  onChangeEnd: widget.onIntensityChanged,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: clip.maskInverted,
                  title: const Text('Inverter mascara'),
                  subtitle: const Text('Aplica o efeito fora da area.'),
                  onChanged: widget.onInvertedChanged,
                ),
                const SizedBox(height: TgiSpacing.sm),
                OutlinedButton.icon(
                  key: const ValueKey('mask_save_point_button'),
                  onPressed: widget.onSavePoint,
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('Salvar ponto no playhead'),
                ),
                const SizedBox(height: TgiSpacing.sm),
                FilledButton.icon(
                  key: const ValueKey('mask_track_button'),
                  onPressed: widget.onTrack,
                  icon: const Icon(Icons.track_changes),
                  label: const Text('Rastrear automaticamente'),
                ),
                if (trackingPoints > 0) ...[
                  const SizedBox(height: TgiSpacing.sm),
                  FilledButton.tonalIcon(
                    key: const ValueKey('mask_attach_image_button'),
                    onPressed: widget.onAttachImage,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('Colocar imagem no rastreamento'),
                  ),
                  const SizedBox(height: TgiSpacing.xs),
                  const Text(
                    'A imagem entra na timeline e acompanha o caminho rastreado. Depois voce pode seleciona-la para mudar o tamanho.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: TgiColors.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: TgiSpacing.sm),
                  TextButton.icon(
                    onPressed: widget.onClearTracking,
                    icon: const Icon(Icons.layers_clear_outlined),
                    label: const Text('Limpar rastreamento'),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (widget.isTracking) ...[
          const SizedBox(height: TgiSpacing.md),
          LinearProgressIndicator(value: widget.trackingProgress),
          const SizedBox(height: TgiSpacing.xs),
          Text(
            'Analisando movimento... ${(widget.trackingProgress * 100).round()}%',
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: TgiSpacing.md),
        Text(
          'Dica: posicione a mascara sobre um objeto com contraste e deixe o playhead em um quadro bem definido antes de rastrear.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: TgiColors.textMuted),
        ),
      ],
    );
  }
}

class _MaskSlider extends StatelessWidget {
  const _MaskSlider({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
    this.min = 0,
    this.max = 1,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text('${(value * 100).round()}%'),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ],
    );
  }
}
