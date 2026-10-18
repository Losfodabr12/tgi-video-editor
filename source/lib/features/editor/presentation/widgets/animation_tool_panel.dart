import 'package:flutter/material.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../../../domain/models/clip.dart';
import '../../../../domain/models/track.dart';

enum AnimationMotionPreset {
  zoomIn,
  zoomOut,
  leftToRight,
  rightToLeft,
  topToBottom,
  bottomToTop,
}

enum AnimationIntensity { subtle, normal, strong }

enum AnimationSpeed { slow, normal, fast }

class AnimationToolPanel extends StatelessWidget {
  const AnimationToolPanel({
    super.key,
    required this.clip,
    required this.mediaName,
    required this.editingStart,
    required this.onEditingStartChanged,
    required this.onEnabledChanged,
    required this.onPresetSelected,
    required this.intensity,
    required this.onIntensityChanged,
    required this.speed,
    required this.onSpeedChanged,
    required this.onFocusPointSelected,
    required this.onStartScaleChanged,
    required this.onEndScaleChanged,
    required this.onTimingChanged,
    required this.onSwap,
    required this.onReset,
    required this.onPreview,
    required this.onInteractionStart,
    required this.onInteractionEnd,
  });

  final Clip? clip;
  final String? mediaName;
  final bool editingStart;
  final ValueChanged<bool> onEditingStartChanged;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<AnimationMotionPreset> onPresetSelected;
  final AnimationIntensity intensity;
  final ValueChanged<AnimationIntensity> onIntensityChanged;
  final AnimationSpeed speed;
  final ValueChanged<AnimationSpeed> onSpeedChanged;
  final void Function(double x, double y) onFocusPointSelected;
  final ValueChanged<double> onStartScaleChanged;
  final ValueChanged<double> onEndScaleChanged;
  final void Function(double start, double end) onTimingChanged;
  final VoidCallback onSwap;
  final VoidCallback onReset;
  final VoidCallback onPreview;
  final VoidCallback onInteractionStart;
  final VoidCallback onInteractionEnd;

  bool get _supported =>
      clip != null &&
      (clip!.trackType == TrackType.video ||
          clip!.trackType == TrackType.image);

  @override
  Widget build(BuildContext context) {
    if (!_supported) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(TgiSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.animation_outlined,
                size: 42,
                color: TgiColors.textMuted,
              ),
              SizedBox(height: TgiSpacing.md),
              Text(
                'Selecione um video ou uma imagem na timeline para animar.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final selectedClip = clip!;
    final timing = RangeValues(
      selectedClip.kenBurnsStart,
      selectedClip.kenBurnsEnd,
    );
    return Listener(
      onPointerDown: (_) => onInteractionStart(),
      onPointerUp: (_) => onInteractionEnd(),
      onPointerCancel: (_) => onInteractionEnd(),
      child: ListView(
        key: const ValueKey('animation_tool_panel'),
        padding: const EdgeInsets.all(TgiSpacing.md),
        children: [
          _AnimationHeader(
            mediaName: mediaName ?? 'Parte selecionada',
            enabled: selectedClip.kenBurnsEnabled,
            onEnabledChanged: onEnabledChanged,
          ),
          const SizedBox(height: TgiSpacing.md),
          const _SectionTitle(
            icon: Icons.auto_awesome,
            title: 'Animacoes prontas',
            subtitle: 'Clique em uma opcao e dê play para conferir.',
          ),
          const SizedBox(height: TgiSpacing.sm),
          Text(
            'Intensidade',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          SegmentedButton<AnimationIntensity>(
            key: const ValueKey('animation_intensity_selector'),
            segments: const [
              ButtonSegment(
                value: AnimationIntensity.subtle,
                label: Text('Leve'),
              ),
              ButtonSegment(
                value: AnimationIntensity.normal,
                label: Text('Normal'),
              ),
              ButtonSegment(
                value: AnimationIntensity.strong,
                label: Text('Forte'),
              ),
            ],
            selected: {intensity},
            onSelectionChanged: (values) => onIntensityChanged(values.first),
          ),
          const SizedBox(height: TgiSpacing.sm),
          Text(
            'Velocidade do movimento',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          SegmentedButton<AnimationSpeed>(
            key: const ValueKey('animation_speed_selector'),
            segments: const [
              ButtonSegment(value: AnimationSpeed.slow, label: Text('Lenta')),
              ButtonSegment(
                value: AnimationSpeed.normal,
                label: Text('Normal'),
              ),
              ButtonSegment(value: AnimationSpeed.fast, label: Text('Rapida')),
            ],
            selected: {speed},
            onSelectionChanged: (values) => onSpeedChanged(values.first),
          ),
          const SizedBox(height: TgiSpacing.md),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 1.75,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              _PresetButton(
                key: const ValueKey('animation_preset_zoom_in'),
                preset: AnimationMotionPreset.zoomIn,
                icon: Icons.zoom_in,
                label: 'Aproximar',
                onPressed: () => onPresetSelected(AnimationMotionPreset.zoomIn),
              ),
              _PresetButton(
                key: const ValueKey('animation_preset_zoom_out'),
                preset: AnimationMotionPreset.zoomOut,
                icon: Icons.zoom_out,
                label: 'Afastar',
                onPressed: () =>
                    onPresetSelected(AnimationMotionPreset.zoomOut),
              ),
              _PresetButton(
                preset: AnimationMotionPreset.leftToRight,
                icon: Icons.arrow_forward,
                label: 'Esq. → Dir.',
                onPressed: () =>
                    onPresetSelected(AnimationMotionPreset.leftToRight),
              ),
              _PresetButton(
                preset: AnimationMotionPreset.rightToLeft,
                icon: Icons.arrow_back,
                label: 'Dir. → Esq.',
                onPressed: () =>
                    onPresetSelected(AnimationMotionPreset.rightToLeft),
              ),
              _PresetButton(
                preset: AnimationMotionPreset.topToBottom,
                icon: Icons.arrow_downward,
                label: 'Cima → Baixo',
                onPressed: () =>
                    onPresetSelected(AnimationMotionPreset.topToBottom),
              ),
              _PresetButton(
                preset: AnimationMotionPreset.bottomToTop,
                icon: Icons.arrow_upward,
                label: 'Baixo → Cima',
                onPressed: () =>
                    onPresetSelected(AnimationMotionPreset.bottomToTop),
              ),
            ],
          ),
          const SizedBox(height: TgiSpacing.lg),
          const _SectionTitle(
            icon: Icons.center_focus_strong,
            title: 'Ajuste manual',
            subtitle: 'Escolha Inicio ou Final e marque o foco.',
          ),
          const SizedBox(height: TgiSpacing.sm),
          SegmentedButton<bool>(
            key: const ValueKey('animation_edit_target'),
            segments: const [
              ButtonSegment(
                value: true,
                icon: Icon(Icons.first_page),
                label: Text('Inicio'),
              ),
              ButtonSegment(
                value: false,
                icon: Icon(Icons.last_page),
                label: Text('Final'),
              ),
            ],
            selected: {editingStart},
            onSelectionChanged: (values) => onEditingStartChanged(values.first),
          ),
          const SizedBox(height: TgiSpacing.sm),
          DecoratedBox(
            decoration: BoxDecoration(
              color: TgiColors.surfaceRaised,
              borderRadius: BorderRadius.circular(TgiRadii.md),
            ),
            child: Padding(
              padding: const EdgeInsets.all(TgiSpacing.sm),
              child: Text(
                editingStart
                    ? 'Marcando onde a animacao começa. Clique no preview ou use a grade abaixo.'
                    : 'Marcando onde a animacao termina. Clique no preview ou use a grade abaixo.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: TgiColors.textSecondary),
              ),
            ),
          ),
          const SizedBox(height: TgiSpacing.sm),
          _FocusGrid(onSelected: onFocusPointSelected),
          const SizedBox(height: TgiSpacing.md),
          _LabeledSlider(
            key: const ValueKey('animation_start_zoom'),
            label: 'Zoom no inicio',
            value: selectedClip.startOverlayScale,
            onChanged: onStartScaleChanged,
          ),
          _LabeledSlider(
            key: const ValueKey('animation_end_zoom'),
            label: 'Zoom no final',
            value: selectedClip.overlayScale,
            onChanged: onEndScaleChanged,
          ),
          const SizedBox(height: TgiSpacing.sm),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Trecho da animacao',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '${(timing.start * 100).round()}% – ${(timing.end * 100).round()}%',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TgiColors.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          RangeSlider(
            key: const ValueKey('animation_timing_range'),
            values: timing,
            min: 0,
            max: 1,
            divisions: 20,
            labels: RangeLabels(
              '${(timing.start * 100).round()}%',
              '${(timing.end * 100).round()}%',
            ),
            onChanged: (values) => onTimingChanged(values.start, values.end),
          ),
          Text(
            '100% usa o clipe inteiro. Aproxime as pontas para a animacao começar depois ou terminar antes.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: TgiColors.textMuted),
          ),
          const SizedBox(height: TgiSpacing.lg),
          FilledButton.icon(
            key: const ValueKey('animation_preview_button'),
            onPressed: onPreview,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Testar animacao'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onSwap,
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: const Text('Inverter'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onReset,
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: const Text('Remover'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnimationHeader extends StatelessWidget {
  const _AnimationHeader({
    required this.mediaName,
    required this.enabled,
    required this.onEnabledChanged,
  });

  final String mediaName;
  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TgiColors.surfaceRaised,
      borderRadius: BorderRadius.circular(TgiRadii.lg),
      child: SwitchListTile(
        key: const ValueKey('animation_enabled_switch'),
        value: enabled,
        onChanged: onEnabledChanged,
        title: const Text(
          'Animacao de camera',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(mediaName, maxLines: 1, overflow: TextOverflow.ellipsis),
        secondary: const Icon(Icons.animation_outlined),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: TgiColors.accentRose, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              Text(
                subtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: TgiColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PresetButton extends StatefulWidget {
  const _PresetButton({
    super.key,
    required this.preset,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final AnimationMotionPreset preset;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  State<_PresetButton> createState() => _PresetButtonState();
}

class _PresetButtonState extends State<_PresetButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: widget.onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final progress = Curves.easeInOut.transform(_controller.value);
              final transform = switch (widget.preset) {
                AnimationMotionPreset.zoomIn => Matrix4.diagonal3Values(
                  0.82 + progress * 0.28,
                  0.82 + progress * 0.28,
                  1,
                ),
                AnimationMotionPreset.zoomOut => Matrix4.diagonal3Values(
                  1.1 - progress * 0.28,
                  1.1 - progress * 0.28,
                  1,
                ),
                AnimationMotionPreset.leftToRight => Matrix4.translationValues(
                  -7 + progress * 14,
                  0,
                  0,
                ),
                AnimationMotionPreset.rightToLeft => Matrix4.translationValues(
                  7 - progress * 14,
                  0,
                  0,
                ),
                AnimationMotionPreset.topToBottom => Matrix4.translationValues(
                  0,
                  -5 + progress * 10,
                  0,
                ),
                AnimationMotionPreset.bottomToTop => Matrix4.translationValues(
                  0,
                  5 - progress * 10,
                  0,
                ),
              };
              return Transform(
                alignment: Alignment.center,
                transform: transform,
                child: child,
              );
            },
            child: Icon(widget.icon, size: 21),
          ),
          const SizedBox(height: 4),
          Text(
            widget.label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _FocusGrid extends StatelessWidget {
  const _FocusGrid({required this.onSelected});

  final void Function(double x, double y) onSelected;

  @override
  Widget build(BuildContext context) {
    const points = [0.2, 0.5, 0.8];
    return AspectRatio(
      aspectRatio: 2.25,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: TgiColors.surfaceRaised,
          border: Border.all(color: TgiColors.borderSubtle),
          borderRadius: BorderRadius.circular(TgiRadii.md),
        ),
        child: GridView.count(
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          childAspectRatio: 1.5,
          children: [
            for (final y in points)
              for (final x in points)
                IconButton(
                  tooltip: 'Foco ${(x * 100).round()}%, ${(y * 100).round()}%',
                  onPressed: () => onSelected(x, y),
                  icon: Icon(
                    x == 0.5 && y == 0.5
                        ? Icons.adjust
                        : Icons.add_circle_outline,
                    size: 19,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              '${(value * 100).round()}%',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: TgiColors.textSecondary),
            ),
          ],
        ),
        Slider(
          value: value.clamp(0.35, 3),
          min: 0.35,
          max: 3,
          divisions: 53,
          label: '${(value * 100).round()}%',
          onChanged: onChanged,
        ),
      ],
    );
  }
}
