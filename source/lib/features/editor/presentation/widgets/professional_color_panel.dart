import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../../../domain/models/clip.dart';
import 'preview_entries.dart';

class ProfessionalColorPanel extends StatefulWidget {
  const ProfessionalColorPanel({
    required this.clip,
    required this.mediaName,
    required this.analysis,
    required this.analysisLoading,
    required this.compareOriginal,
    required this.whiteBalancePickerActive,
    required this.onRefreshAnalysis,
    required this.onCompareOriginalChanged,
    required this.onWhiteBalancePickerChanged,
    required this.onBrightnessChanged,
    required this.onContrastChanged,
    required this.onSaturationChanged,
    required this.onExposureChanged,
    required this.onHueChanged,
    required this.onTemperatureChanged,
    required this.onTintChanged,
    required this.onShadowsChanged,
    required this.onHighlightsChanged,
    required this.onCurvesChanged,
    required this.onInteractionStart,
    required this.onInteractionEnd,
    required this.onReset,
    super.key,
  });

  final Clip? clip;
  final String? mediaName;
  final VideoColorAnalysis? analysis;
  final bool analysisLoading;
  final bool compareOriginal;
  final bool whiteBalancePickerActive;
  final VoidCallback onRefreshAnalysis;
  final ValueChanged<bool> onCompareOriginalChanged;
  final ValueChanged<bool> onWhiteBalancePickerChanged;
  final ValueChanged<double> onBrightnessChanged;
  final ValueChanged<double> onContrastChanged;
  final ValueChanged<double> onSaturationChanged;
  final ValueChanged<double> onExposureChanged;
  final ValueChanged<double> onHueChanged;
  final ValueChanged<double> onTemperatureChanged;
  final ValueChanged<double> onTintChanged;
  final ValueChanged<double> onShadowsChanged;
  final ValueChanged<double> onHighlightsChanged;
  final void Function(double shadows, double midtones, double highlights)
  onCurvesChanged;
  final VoidCallback onInteractionStart;
  final VoidCallback onInteractionEnd;
  final VoidCallback onReset;

  @override
  State<ProfessionalColorPanel> createState() => _ProfessionalColorPanelState();
}

class _ProfessionalColorPanelState extends State<ProfessionalColorPanel> {
  @override
  Widget build(BuildContext context) {
    final clip = widget.clip;
    if (clip == null) {
      return const _NoColorClipSelected();
    }
    return Listener(
      onPointerDown: (_) => widget.onInteractionStart(),
      onPointerUp: (_) => widget.onInteractionEnd(),
      onPointerCancel: (_) => widget.onInteractionEnd(),
      child: ListView(
        padding: const EdgeInsets.all(TgiSpacing.md),
        children: [
          _ColorHeader(
            mediaName: widget.mediaName ?? 'Clipe selecionado',
            compareOriginal: widget.compareOriginal,
            onCompareOriginalChanged: widget.onCompareOriginalChanged,
            onReset: widget.onReset,
          ),
          const SizedBox(height: TgiSpacing.md),
          _HistogramCard(
            analysis: widget.analysis,
            loading: widget.analysisLoading,
            onRefresh: widget.onRefreshAnalysis,
          ),
          const SizedBox(height: TgiSpacing.md),
          _sectionTitle(context, 'Balanço de branco'),
          const SizedBox(height: TgiSpacing.xs),
          FilledButton.tonalIcon(
            key: const ValueKey('white_balance_picker_button'),
            onPressed: () => widget.onWhiteBalancePickerChanged(
              !widget.whiteBalancePickerActive,
            ),
            icon: Icon(
              widget.whiteBalancePickerActive
                  ? Icons.close
                  : Icons.colorize_outlined,
            ),
            label: Text(
              widget.whiteBalancePickerActive
                  ? 'Cancelar conta-gotas'
                  : 'Escolher ponto neutro no vídeo',
            ),
          ),
          if (widget.whiteBalancePickerActive)
            Padding(
              padding: const EdgeInsets.only(top: TgiSpacing.xs),
              child: Text(
                'Clique em algo que deveria ser branco ou cinza no preview.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TgiColors.accentSoft,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          _ColorSlider(
            key: ValueKey('color_temperature_${clip.id}'),
            label: 'Temperatura',
            lowLabel: 'Frio',
            highLabel: 'Quente',
            value: clip.temperature,
            min: -1,
            max: 1,
            onChanged: widget.onTemperatureChanged,
          ),
          _ColorSlider(
            key: ValueKey('color_tint_${clip.id}'),
            label: 'Matiz verde/magenta',
            lowLabel: 'Verde',
            highLabel: 'Magenta',
            value: clip.tint,
            min: -1,
            max: 1,
            onChanged: widget.onTintChanged,
          ),
          const SizedBox(height: TgiSpacing.md),
          _sectionTitle(context, 'Luz'),
          _ColorSlider(
            key: ValueKey('color_exposure_${clip.id}'),
            label: 'Exposição',
            value: clip.exposure,
            min: -1,
            max: 1,
            onChanged: widget.onExposureChanged,
          ),
          _ColorSlider(
            key: ValueKey('color_brightness_${clip.id}'),
            label: 'Brilho',
            value: clip.brightness,
            min: -1,
            max: 1,
            onChanged: widget.onBrightnessChanged,
          ),
          _ColorSlider(
            key: ValueKey('color_contrast_${clip.id}'),
            label: 'Contraste',
            value: clip.contrast,
            min: 0,
            max: 3,
            neutral: 1,
            onChanged: widget.onContrastChanged,
          ),
          _ColorSlider(
            key: ValueKey('color_shadows_${clip.id}'),
            label: 'Sombras',
            value: clip.shadows,
            min: -1,
            max: 1,
            onChanged: widget.onShadowsChanged,
          ),
          _ColorSlider(
            key: ValueKey('color_highlights_${clip.id}'),
            label: 'Realces',
            value: clip.highlights,
            min: -1,
            max: 1,
            onChanged: widget.onHighlightsChanged,
          ),
          const SizedBox(height: TgiSpacing.md),
          _sectionTitle(context, 'Cor'),
          _ColorSlider(
            key: ValueKey('color_saturation_${clip.id}'),
            label: 'Saturação',
            value: clip.saturation,
            min: 0,
            max: 3,
            neutral: 1,
            onChanged: widget.onSaturationChanged,
          ),
          _ColorSlider(
            key: ValueKey('color_hue_${clip.id}'),
            label: 'Matiz',
            value: clip.hue,
            min: -180,
            max: 180,
            suffix: '°',
            onChanged: widget.onHueChanged,
          ),
          const SizedBox(height: TgiSpacing.md),
          _sectionTitle(context, 'Curva de luminância'),
          const SizedBox(height: TgiSpacing.sm),
          _ToneCurveEditor(
            key: ValueKey('color_curves_${clip.id}'),
            shadows: clip.curveShadows,
            midtones: clip.curveMidtones,
            highlights: clip.curveHighlights,
            onChanged: widget.onCurvesChanged,
          ),
          const SizedBox(height: TgiSpacing.md),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) => Text(
    title,
    style: Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
  );
}

class _ColorHeader extends StatelessWidget {
  const _ColorHeader({
    required this.mediaName,
    required this.compareOriginal,
    required this.onCompareOriginalChanged,
    required this.onReset,
  });

  final String mediaName;
  final bool compareOriginal;
  final ValueChanged<bool> onCompareOriginalChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TgiColors.surfacePressed,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TgiRadii.md),
        side: const BorderSide(color: TgiColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(TgiSpacing.sm),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.gradient_outlined, color: TgiColors.accentSoft),
                const SizedBox(width: TgiSpacing.sm),
                Expanded(
                  child: Text(
                    mediaName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Restaurar cor',
                  onPressed: onReset,
                  icon: const Icon(Icons.restart_alt),
                ),
              ],
            ),
            SwitchListTile(
              key: const ValueKey('color_before_after_switch'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: compareOriginal,
              title: const Text('Mostrar antes'),
              subtitle: const Text(
                'Segure a comparação sem alterar o projeto.',
              ),
              onChanged: onCompareOriginalChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _HistogramCard extends StatelessWidget {
  const _HistogramCard({
    required this.analysis,
    required this.loading,
    required this.onRefresh,
  });

  final VideoColorAnalysis? analysis;
  final bool loading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TgiColors.black,
        borderRadius: BorderRadius.circular(TgiRadii.md),
        border: Border.all(color: TgiColors.borderStrong),
      ),
      child: SizedBox(
        height: 142,
        child: Stack(
          children: [
            Positioned.fill(
              child: analysis == null
                  ? Center(
                      child: Text(
                        loading
                            ? 'Analisando quadro...'
                            : 'Histograma do quadro',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: TgiColors.textMuted,
                        ),
                      ),
                    )
                  : CustomPaint(
                      key: const ValueKey('professional_color_histogram'),
                      painter: _HistogramPainter(analysis!),
                    ),
            ),
            Positioned(
              right: 4,
              top: 4,
              child: IconButton(
                tooltip: 'Atualizar histograma',
                onPressed: loading ? null : onRefresh,
                icon: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 19),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistogramPainter extends CustomPainter {
  const _HistogramPainter(this.analysis);

  final VideoColorAnalysis analysis;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = TgiColors.white.withValues(alpha: 0.09)
      ..strokeWidth = 1;
    for (final fraction in const [0.25, 0.5, 0.75]) {
      canvas.drawLine(
        Offset(size.width * fraction, 0),
        Offset(size.width * fraction, size.height),
        grid,
      );
      canvas.drawLine(
        Offset(0, size.height * fraction),
        Offset(size.width, size.height * fraction),
        grid,
      );
    }
    _drawChannel(canvas, size, analysis.luma, TgiColors.white, 0.52);
    _drawChannel(canvas, size, analysis.red, const Color(0xFFFF5A67), 0.70);
    _drawChannel(canvas, size, analysis.green, const Color(0xFF55E88B), 0.66);
    _drawChannel(canvas, size, analysis.blue, const Color(0xFF5EA4FF), 0.72);
  }

  void _drawChannel(
    Canvas canvas,
    Size size,
    List<double> values,
    Color color,
    double opacity,
  ) {
    if (values.isEmpty) return;
    final path = Path()..moveTo(0, size.height);
    for (var index = 0; index < values.length; index++) {
      final x = index / math.max(1, values.length - 1) * size.width;
      final y = size.height * (1 - values[index].clamp(0.0, 1.0));
      path.lineTo(x, y);
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: opacity));
  }

  @override
  bool shouldRepaint(covariant _HistogramPainter oldDelegate) =>
      oldDelegate.analysis != analysis;
}

class _ColorSlider extends StatefulWidget {
  const _ColorSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.neutral = 0,
    this.lowLabel,
    this.highLabel,
    this.suffix = '%',
    super.key,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final double neutral;
  final String? lowLabel;
  final String? highLabel;
  final String suffix;
  final ValueChanged<double> onChanged;

  @override
  State<_ColorSlider> createState() => _ColorSliderState();
}

class _ColorSliderState extends State<_ColorSlider> {
  late double _value = widget.value;

  @override
  void didUpdateWidget(covariant _ColorSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    final display = widget.suffix == '°'
        ? '${_value.round()}°'
        : '${((_value - widget.neutral) * 100).round().toStringAsFixed(0)}%';
    return Padding(
      padding: const EdgeInsets.only(top: TgiSpacing.sm),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              Text(
                display,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: TgiColors.accentSoft,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          Slider(
            value: _value.clamp(widget.min, widget.max),
            min: widget.min,
            max: widget.max,
            divisions: widget.suffix == '°' ? 72 : 80,
            onChanged: (value) {
              setState(() => _value = value);
              widget.onChanged(value);
            },
          ),
          if (widget.lowLabel != null || widget.highLabel != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(widget.lowLabel ?? ''),
                Text(widget.highLabel ?? ''),
              ],
            ),
        ],
      ),
    );
  }
}

class _ToneCurveEditor extends StatefulWidget {
  const _ToneCurveEditor({
    required this.shadows,
    required this.midtones,
    required this.highlights,
    required this.onChanged,
    super.key,
  });

  final double shadows;
  final double midtones;
  final double highlights;
  final void Function(double shadows, double midtones, double highlights)
  onChanged;

  @override
  State<_ToneCurveEditor> createState() => _ToneCurveEditorState();
}

class _ToneCurveEditorState extends State<_ToneCurveEditor> {
  late double _shadows = widget.shadows;
  late double _midtones = widget.midtones;
  late double _highlights = widget.highlights;

  @override
  void didUpdateWidget(covariant _ToneCurveEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shadows != widget.shadows ||
        oldWidget.midtones != widget.midtones ||
        oldWidget.highlights != widget.highlights) {
      _shadows = widget.shadows;
      _midtones = widget.midtones;
      _highlights = widget.highlights;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.45,
      child: LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (details) =>
              _update(details.localPosition, constraints.biggest),
          onPanUpdate: (details) =>
              _update(details.localPosition, constraints.biggest),
          onPanEnd: (_) => widget.onChanged(_shadows, _midtones, _highlights),
          onTapUp: (_) => widget.onChanged(_shadows, _midtones, _highlights),
          child: CustomPaint(
            painter: _ToneCurvePainter(
              shadows: _shadows,
              midtones: _midtones,
              highlights: _highlights,
            ),
          ),
        ),
      ),
    );
  }

  void _update(Offset position, Size size) {
    if (size.isEmpty) return;
    final normalizedX = (position.dx / size.width).clamp(0.0, 1.0);
    final normalizedY = 1 - (position.dy / size.height).clamp(0.0, 1.0);
    setState(() {
      if (normalizedX < 0.375) {
        _shadows = ((normalizedY - 0.25) / 0.18).clamp(-1.0, 1.0);
      } else if (normalizedX < 0.625) {
        _midtones = ((normalizedY - 0.5) / 0.22).clamp(-1.0, 1.0);
      } else {
        _highlights = ((normalizedY - 0.75) / 0.18).clamp(-1.0, 1.0);
      }
    });
    widget.onChanged(_shadows, _midtones, _highlights);
  }
}

class _ToneCurvePainter extends CustomPainter {
  const _ToneCurvePainter({
    required this.shadows,
    required this.midtones,
    required this.highlights,
  });

  final double shadows;
  final double midtones;
  final double highlights;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = TgiColors.black.withValues(alpha: 0.72),
    );
    final grid = Paint()
      ..color = TgiColors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    for (final fraction in const [0.25, 0.5, 0.75]) {
      canvas.drawLine(
        Offset(size.width * fraction, 0),
        Offset(size.width * fraction, size.height),
        grid,
      );
      canvas.drawLine(
        Offset(0, size.height * fraction),
        Offset(size.width, size.height * fraction),
        grid,
      );
    }
    final points = [
      Offset(0, size.height),
      Offset(size.width * 0.25, size.height * (0.75 - shadows * 0.18)),
      Offset(size.width * 0.5, size.height * (0.5 - midtones * 0.22)),
      Offset(size.width * 0.75, size.height * (0.25 - highlights * 0.18)),
      Offset(size.width, 0),
    ];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var index = 1; index < points.length; index++) {
      final previous = points[index - 1];
      final point = points[index];
      final middleX = (previous.dx + point.dx) / 2;
      path.cubicTo(middleX, previous.dy, middleX, point.dy, point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = TgiColors.accentSoft
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
    for (final point in points.skip(1).take(3)) {
      canvas
        ..drawCircle(point, 6, Paint()..color = TgiColors.black)
        ..drawCircle(
          point,
          5,
          Paint()
            ..color = TgiColors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _ToneCurvePainter oldDelegate) =>
      oldDelegate.shadows != shadows ||
      oldDelegate.midtones != midtones ||
      oldDelegate.highlights != highlights;
}

class _NoColorClipSelected extends StatelessWidget {
  const _NoColorClipSelected();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(TgiSpacing.xl),
        child: Text(
          'Selecione um clipe de vídeo na timeline para corrigir a cor.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: TgiColors.textMuted),
        ),
      ),
    );
  }
}
