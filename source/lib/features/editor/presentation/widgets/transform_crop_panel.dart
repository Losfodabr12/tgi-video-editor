import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../../../domain/models/clip.dart';

typedef ClipTransformChanged =
    void Function({
      double? offsetX,
      double? offsetY,
      double? scale,
      double? rotationDegrees,
      bool? flipHorizontal,
      bool? flipVertical,
    });

typedef ClipCropChanged =
    void Function({double? left, double? top, double? right, double? bottom});

class TransformCropPanel extends StatefulWidget {
  const TransformCropPanel({
    required this.clip,
    required this.mediaName,
    required this.cropModeActive,
    required this.onCropModeChanged,
    required this.onTransformChanged,
    required this.onCropChanged,
    required this.onRotateLeft,
    required this.onRotateRight,
    required this.onAspectRatioSelected,
    required this.onReset,
    required this.onInteractionStart,
    required this.onInteractionEnd,
    super.key,
  });

  final Clip? clip;
  final String? mediaName;
  final bool cropModeActive;
  final ValueChanged<bool> onCropModeChanged;
  final ClipTransformChanged onTransformChanged;
  final ClipCropChanged onCropChanged;
  final VoidCallback onRotateLeft;
  final VoidCallback onRotateRight;
  final ValueChanged<double> onAspectRatioSelected;
  final VoidCallback onReset;
  final VoidCallback onInteractionStart;
  final VoidCallback onInteractionEnd;

  @override
  State<TransformCropPanel> createState() => _TransformCropPanelState();
}

class _TransformCropPanelState extends State<TransformCropPanel> {
  double _offsetX = 0;
  double _offsetY = 0;
  double _scale = 1;
  double _rotation = 0;
  double _cropLeft = 0;
  double _cropTop = 0;
  double _cropRight = 0;
  double _cropBottom = 0;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant TransformCropPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.clip;
    final next = widget.clip;
    if (old?.id != next?.id ||
        old?.transformOffsetX != next?.transformOffsetX ||
        old?.transformOffsetY != next?.transformOffsetY ||
        old?.transformScale != next?.transformScale ||
        old?.rotationDegrees != next?.rotationDegrees ||
        old?.cropLeft != next?.cropLeft ||
        old?.cropTop != next?.cropTop ||
        old?.cropRight != next?.cropRight ||
        old?.cropBottom != next?.cropBottom) {
      _sync();
    }
  }

  void _sync() {
    final clip = widget.clip;
    _offsetX = clip?.transformOffsetX ?? 0;
    _offsetY = clip?.transformOffsetY ?? 0;
    _scale = clip?.transformScale ?? 1;
    _rotation = clip?.rotationDegrees ?? 0;
    _cropLeft = clip?.cropLeft ?? 0;
    _cropTop = clip?.cropTop ?? 0;
    _cropRight = clip?.cropRight ?? 0;
    _cropBottom = clip?.cropBottom ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final clip = widget.clip;
    if (clip == null) {
      return const _EmptyTransformPanel();
    }
    return ListView(
      padding: const EdgeInsets.all(TgiSpacing.md),
      children: [
        _MediaCard(name: widget.mediaName ?? 'Clipe selecionado'),
        const SizedBox(height: TgiSpacing.md),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              icon: Icon(Icons.open_with_outlined),
              label: Text('Mover'),
            ),
            ButtonSegment(
              value: true,
              icon: Icon(Icons.crop_outlined),
              label: Text('Recortar'),
            ),
          ],
          selected: {widget.cropModeActive},
          onSelectionChanged: (values) =>
              widget.onCropModeChanged(values.first),
        ),
        const SizedBox(height: TgiSpacing.lg),
        const _SectionTitle('Transformar'),
        _ToolSlider(
          label: 'Posição horizontal',
          value: _offsetX,
          min: -1,
          max: 1,
          divisions: 200,
          valueText: '${(_offsetX * 100).round()}%',
          onChangeStart: (_) => widget.onInteractionStart(),
          onChanged: (value) {
            setState(() => _offsetX = value);
            widget.onTransformChanged(offsetX: value);
          },
          onChangeEnd: (_) => widget.onInteractionEnd(),
        ),
        _ToolSlider(
          label: 'Posição vertical',
          value: _offsetY,
          min: -1,
          max: 1,
          divisions: 200,
          valueText: '${(_offsetY * 100).round()}%',
          onChangeStart: (_) => widget.onInteractionStart(),
          onChanged: (value) {
            setState(() => _offsetY = value);
            widget.onTransformChanged(offsetY: value);
          },
          onChangeEnd: (_) => widget.onInteractionEnd(),
        ),
        _ToolSlider(
          label: 'Escala',
          value: _scale,
          min: 0.1,
          max: 4,
          divisions: 195,
          valueText: '${(_scale * 100).round()}%',
          onChangeStart: (_) => widget.onInteractionStart(),
          onChanged: (value) {
            setState(() => _scale = value);
            widget.onTransformChanged(scale: value);
          },
          onChangeEnd: (_) => widget.onInteractionEnd(),
        ),
        _ToolSlider(
          label: 'Rotação',
          value: _rotation.clamp(-180, 180),
          min: -180,
          max: 180,
          divisions: 360,
          valueText: '${_rotation.round()}°',
          onChangeStart: (_) => widget.onInteractionStart(),
          onChanged: (value) {
            setState(() => _rotation = value);
            widget.onTransformChanged(rotationDegrees: value);
          },
          onChangeEnd: (_) => widget.onInteractionEnd(),
        ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: widget.onRotateLeft,
                icon: const Icon(Icons.rotate_90_degrees_ccw_outlined),
                label: const Text('-90°'),
              ),
            ),
            const SizedBox(width: TgiSpacing.sm),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: widget.onRotateRight,
                icon: const Icon(Icons.rotate_90_degrees_cw_outlined),
                label: const Text('+90°'),
              ),
            ),
          ],
        ),
        const SizedBox(height: TgiSpacing.sm),
        Row(
          children: [
            Expanded(
              child: FilterChip(
                selected: clip.flipHorizontal,
                avatar: const Icon(Icons.flip_outlined, size: 18),
                label: const Text('Espelhar H'),
                onSelected: (value) =>
                    widget.onTransformChanged(flipHorizontal: value),
              ),
            ),
            const SizedBox(width: TgiSpacing.sm),
            Expanded(
              child: FilterChip(
                selected: clip.flipVertical,
                avatar: const RotatedBox(
                  quarterTurns: 1,
                  child: Icon(Icons.flip_outlined, size: 18),
                ),
                label: const Text('Espelhar V'),
                onSelected: (value) =>
                    widget.onTransformChanged(flipVertical: value),
              ),
            ),
          ],
        ),
        const SizedBox(height: TgiSpacing.lg),
        const _SectionTitle('Recorte e proporção'),
        Wrap(
          spacing: TgiSpacing.xs,
          runSpacing: TgiSpacing.xs,
          children: [
            for (final preset in const [
              (label: '16:9', value: 16 / 9),
              (label: '9:16', value: 9 / 16),
              (label: '1:1', value: 1.0),
              (label: '4:3', value: 4 / 3),
              (label: '3:2', value: 3 / 2),
              (label: '4:5', value: 4 / 5),
            ])
              ActionChip(
                label: Text(preset.label),
                onPressed: () => widget.onAspectRatioSelected(preset.value),
              ),
          ],
        ),
        const SizedBox(height: TgiSpacing.sm),
        _CropSlider(
          label: 'Esquerda',
          value: _cropLeft,
          other: _cropRight,
          onInteractionStart: widget.onInteractionStart,
          onInteractionEnd: widget.onInteractionEnd,
          onChanged: (value) => setState(() => _cropLeft = value),
          onChangeEnd: (value) => widget.onCropChanged(left: value),
        ),
        _CropSlider(
          label: 'Direita',
          value: _cropRight,
          other: _cropLeft,
          onInteractionStart: widget.onInteractionStart,
          onInteractionEnd: widget.onInteractionEnd,
          onChanged: (value) => setState(() => _cropRight = value),
          onChangeEnd: (value) => widget.onCropChanged(right: value),
        ),
        _CropSlider(
          label: 'Topo',
          value: _cropTop,
          other: _cropBottom,
          onInteractionStart: widget.onInteractionStart,
          onInteractionEnd: widget.onInteractionEnd,
          onChanged: (value) => setState(() => _cropTop = value),
          onChangeEnd: (value) => widget.onCropChanged(top: value),
        ),
        _CropSlider(
          label: 'Base',
          value: _cropBottom,
          other: _cropTop,
          onInteractionStart: widget.onInteractionStart,
          onInteractionEnd: widget.onInteractionEnd,
          onChanged: (value) => setState(() => _cropBottom = value),
          onChangeEnd: (value) => widget.onCropChanged(bottom: value),
        ),
        const SizedBox(height: TgiSpacing.md),
        FilledButton.tonalIcon(
          onPressed: widget.onReset,
          icon: const Icon(Icons.restart_alt_outlined),
          label: const Text('Restaurar enquadramento'),
        ),
        const SizedBox(height: TgiSpacing.sm),
        Text(
          widget.cropModeActive
              ? 'Arraste as bordas no preview para recortar com precisão.'
              : 'Arraste o preview para mover. Use a roda do mouse para alterar a escala.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: TgiColors.textMuted),
        ),
      ],
    );
  }
}

class _CropSlider extends StatelessWidget {
  const _CropSlider({
    required this.label,
    required this.value,
    required this.other,
    required this.onInteractionStart,
    required this.onInteractionEnd,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String label;
  final double value;
  final double other;
  final VoidCallback onInteractionStart;
  final VoidCallback onInteractionEnd;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final max = math.max(0.0, 0.95 - other);
    return _ToolSlider(
      label: label,
      value: value.clamp(0.0, max),
      min: 0,
      max: math.max(0.01, max),
      divisions: math.max(1, (math.max(0.01, max) * 100).round()),
      valueText: '${(value * 100).round()}%',
      onChangeStart: (_) => onInteractionStart(),
      onChanged: (value) {
        onChanged(value);
        onChangeEnd(value);
      },
      onChangeEnd: (_) => onInteractionEnd(),
    );
  }
}

class _ToolSlider extends StatelessWidget {
  const _ToolSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueText,
    required this.onChanged,
    required this.onChangeEnd,
    this.onChangeStart,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueText;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final ValueChanged<double>? onChangeStart;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              valueText,
              style: TextStyle(
                color: TgiColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChangeStart: onChangeStart,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: TgiSpacing.sm),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
    ),
  );
}

class _MediaCard extends StatelessWidget {
  const _MediaCard({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: TgiColors.surfacePressed,
      border: Border.all(color: TgiColors.border),
      borderRadius: BorderRadius.circular(TgiRadii.md),
    ),
    child: Padding(
      padding: const EdgeInsets.all(TgiSpacing.sm),
      child: Row(
        children: [
          Icon(Icons.crop_rotate_outlined, color: TgiColors.textSecondary),
          const SizedBox(width: TgiSpacing.sm),
          Expanded(
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    ),
  );
}

class _EmptyTransformPanel extends StatelessWidget {
  const _EmptyTransformPanel();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(TgiSpacing.xl),
      child: Text(
        'Selecione um vídeo ou imagem na timeline para transformar e recortar.',
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: TgiColors.textMuted),
      ),
    ),
  );
}
