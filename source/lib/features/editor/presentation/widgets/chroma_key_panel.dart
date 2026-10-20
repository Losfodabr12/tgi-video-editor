import 'package:flutter/material.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../../../domain/models/clip.dart';

class ChromaKeyPanel extends StatefulWidget {
  const ChromaKeyPanel({
    required this.videoClip,
    required this.mediaName,
    required this.onEnabledChanged,
    required this.onColorChanged,
    required this.colorPickerActive,
    required this.onColorPickerActiveChanged,
    required this.onSimilarityChanged,
    required this.onBlendChanged,
    required this.transparencyPreview,
    required this.onTransparencyPreviewChanged,
    super.key,
  });

  final Clip? videoClip;
  final String? mediaName;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<int> onColorChanged;
  final bool colorPickerActive;
  final ValueChanged<bool> onColorPickerActiveChanged;
  final ValueChanged<double> onSimilarityChanged;
  final ValueChanged<double> onBlendChanged;
  final bool transparencyPreview;
  final ValueChanged<bool> onTransparencyPreviewChanged;

  @override
  State<ChromaKeyPanel> createState() => _ChromaKeyPanelState();
}

class _ChromaKeyPanelState extends State<ChromaKeyPanel> {
  static const _colors = <({String label, int value})>[
    (label: 'Verde', value: 0xFF00FF00),
    (label: 'Azul', value: 0xFF005DFF),
    (label: 'Magenta', value: 0xFFFF00FF),
  ];

  double _similarity = 0.3;
  double _blend = 0.1;

  @override
  void initState() {
    super.initState();
    _syncDrafts();
  }

  @override
  void didUpdateWidget(covariant ChromaKeyPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoClip?.id != widget.videoClip?.id ||
        oldWidget.videoClip?.chromaKeySimilarity !=
            widget.videoClip?.chromaKeySimilarity ||
        oldWidget.videoClip?.chromaKeyBlend !=
            widget.videoClip?.chromaKeyBlend) {
      _syncDrafts();
    }
  }

  void _syncDrafts() {
    _similarity = widget.videoClip?.chromaKeySimilarity ?? 0.3;
    _blend = widget.videoClip?.chromaKeyBlend ?? 0.1;
  }

  @override
  Widget build(BuildContext context) {
    final clip = widget.videoClip;
    if (clip == null) return const _NoVideoSelected();

    return ListView(
      padding: const EdgeInsets.all(TgiSpacing.md),
      children: [
        _SelectedVideoCard(name: widget.mediaName ?? 'Clipe selecionado'),
        const SizedBox(height: TgiSpacing.md),
        SwitchListTile(
          key: const ValueKey('chroma_enabled_switch'),
          contentPadding: EdgeInsets.zero,
          value: clip.chromaKeyEnabled,
          title: const Text('Ativar Chroma Key'),
          subtitle: const Text('Remove a cor escolhida do clipe.'),
          onChanged: widget.onEnabledChanged,
        ),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: clip.chromaKeyEnabled ? 1 : 0.48,
          child: IgnorePointer(
            ignoring: !clip.chromaKeyEnabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: TgiSpacing.sm),
                Text(
                  'Cor do fundo',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: TgiSpacing.sm),
                Wrap(
                  spacing: TgiSpacing.sm,
                  runSpacing: TgiSpacing.sm,
                  children: [
                    for (final option in _colors)
                      ChoiceChip(
                        key: ValueKey('chroma_color_${option.label}'),
                        avatar: CircleAvatar(
                          radius: 8,
                          backgroundColor: Color(option.value),
                        ),
                        label: Text(option.label),
                        selected: clip.chromaKeyColor == option.value,
                        onSelected: (_) => widget.onColorChanged(option.value),
                      ),
                  ],
                ),
                const SizedBox(height: TgiSpacing.md),
                _ColorPickerControl(
                  color: clip.chromaKeyColor,
                  active: widget.colorPickerActive,
                  onActiveChanged: widget.onColorPickerActiveChanged,
                ),
                const SizedBox(height: TgiSpacing.lg),
                _ChromaSlider(
                  key: ValueKey('chroma_similarity_${clip.id}'),
                  label: 'Similaridade',
                  description: 'Aumente até todo o fundo desaparecer.',
                  value: _similarity,
                  onChanged: (value) => setState(() => _similarity = value),
                  onChangeEnd: widget.onSimilarityChanged,
                ),
                const SizedBox(height: TgiSpacing.md),
                _ChromaSlider(
                  key: ValueKey('chroma_blend_${clip.id}'),
                  label: 'Suavidade da borda',
                  description: 'Suaviza recortes duros em cabelo e objetos.',
                  value: _blend,
                  onChanged: (value) => setState(() => _blend = value),
                  onChangeEnd: widget.onBlendChanged,
                ),
                const SizedBox(height: TgiSpacing.sm),
                SwitchListTile(
                  key: const ValueKey('chroma_transparency_preview_switch'),
                  contentPadding: EdgeInsets.zero,
                  value: widget.transparencyPreview,
                  title: const Text('Mostrar transparência'),
                  subtitle: const Text(
                    'Exibe um quadriculado nas áreas removidas do preview.',
                  ),
                  onChanged: widget.onTransparencyPreviewChanged,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: TgiSpacing.lg),
        DecoratedBox(
          decoration: BoxDecoration(
            color: TgiColors.surfaceAlt,
            border: Border.all(color: TgiColors.border),
            borderRadius: BorderRadius.circular(TgiRadii.md),
          ),
          child: Padding(
            padding: const EdgeInsets.all(TgiSpacing.sm),
            child: Text(
              'Dica: use Similaridade primeiro. Depois aumente a Suavidade só o necessário para preservar os detalhes.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: TgiColors.textSecondary),
            ),
          ),
        ),
      ],
    );
  }
}

class _ColorPickerControl extends StatelessWidget {
  const _ColorPickerControl({
    required this.color,
    required this.active,
    required this.onActiveChanged,
  });

  final int color;
  final bool active;
  final ValueChanged<bool> onActiveChanged;

  @override
  Widget build(BuildContext context) {
    final colorHex =
        '#${(color & 0x00FFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.all(TgiSpacing.sm),
      decoration: BoxDecoration(
        color: active ? TgiColors.accentMuted : TgiColors.surfaceAlt,
        border: Border.all(
          color: active ? TgiColors.accentSoft : TgiColors.border,
        ),
        borderRadius: BorderRadius.circular(TgiRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                key: const ValueKey('chroma_current_color'),
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Color(color),
                  shape: BoxShape.circle,
                  border: Border.all(color: TgiColors.white, width: 1.5),
                ),
              ),
              const SizedBox(width: TgiSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cor atual',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: TgiColors.textMuted,
                      ),
                    ),
                    Text(
                      colorHex,
                      key: const ValueKey('chroma_current_color_hex'),
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: TgiSpacing.sm),
          FilledButton.tonalIcon(
            key: const ValueKey('chroma_color_picker_button'),
            onPressed: () => onActiveChanged(!active),
            icon: Icon(active ? Icons.close : Icons.colorize_outlined),
            label: Text(
              active ? 'Cancelar conta-gotas' : 'Escolher cor no vídeo',
            ),
          ),
          if (active) ...[
            const SizedBox(height: TgiSpacing.xs),
            Text(
              'Clique na cor desejada dentro do preview. O quadro será analisado automaticamente.',
              key: const ValueKey('chroma_color_picker_instruction'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: TgiColors.accentSoft,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SelectedVideoCard extends StatelessWidget {
  const _SelectedVideoCard({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TgiColors.surfacePressed,
        border: Border.all(color: TgiColors.accentMuted),
        borderRadius: BorderRadius.circular(TgiRadii.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(TgiSpacing.sm),
        child: Row(
          children: [
            Icon(Icons.movie_outlined, color: TgiColors.accentSoft),
            const SizedBox(width: TgiSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Clipe selecionado',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: TgiColors.textMuted,
                    ),
                  ),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
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

class _NoVideoSelected extends StatelessWidget {
  const _NoVideoSelected();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(TgiSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.colorize_outlined,
              size: 38,
              color: TgiColors.textMuted,
            ),
            const SizedBox(height: TgiSpacing.sm),
            Text(
              'Selecione um clipe de vídeo na timeline para usar o Chroma Key.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: TgiColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChromaSlider extends StatelessWidget {
  const _ChromaSlider({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
    super.key,
  });

  final String label;
  final String description;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              '${(value * 100).round()}%',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: TgiColors.accentSoft,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(0.0, 1.0),
          min: 0,
          max: 1,
          divisions: 100,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
        Text(
          description,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: TgiColors.textMuted),
        ),
      ],
    );
  }
}
