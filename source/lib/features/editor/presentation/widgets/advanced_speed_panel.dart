import 'package:flutter/material.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../../../domain/models/clip.dart';

class AdvancedSpeedPanel extends StatefulWidget {
  const AdvancedSpeedPanel({
    required this.clip,
    required this.mediaName,
    required this.onConstantSpeedChanged,
    required this.onRampSelected,
    required this.onSlowMotion,
    required this.onFreezeFrame,
    required this.onReverseChanged,
    super.key,
  });

  final Clip? clip;
  final String? mediaName;
  final ValueChanged<double> onConstantSpeedChanged;
  final void Function(List<double> multipliers, String label) onRampSelected;
  final VoidCallback onSlowMotion;
  final VoidCallback onFreezeFrame;
  final ValueChanged<bool> onReverseChanged;

  @override
  State<AdvancedSpeedPanel> createState() => _AdvancedSpeedPanelState();
}

class _AdvancedSpeedPanelState extends State<AdvancedSpeedPanel> {
  late double _speed = widget.clip?.playbackSpeed ?? 1;

  @override
  void didUpdateWidget(covariant AdvancedSpeedPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clip?.id != widget.clip?.id ||
        oldWidget.clip?.playbackSpeed != widget.clip?.playbackSpeed) {
      _speed = widget.clip?.playbackSpeed ?? 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final clip = widget.clip;
    if (clip == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(TgiSpacing.xl),
          child: Text(
            'Selecione um clipe de vídeo para editar a velocidade.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(TgiSpacing.md),
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: TgiColors.surfacePressed,
            borderRadius: BorderRadius.circular(TgiRadii.md),
            border: Border.all(color: TgiColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(TgiSpacing.sm),
            child: Row(
              children: [
                Icon(Icons.speed, color: TgiColors.accentSoft),
                const SizedBox(width: TgiSpacing.sm),
                Expanded(
                  child: Text(
                    widget.mediaName ?? 'Clipe selecionado',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${_speed.toStringAsFixed(2)}x',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: TgiColors.accentSoft,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: TgiSpacing.md),
        Text(
          'Velocidade constante',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        Slider(
          key: ValueKey('advanced_speed_slider_${clip.id}'),
          value: _speed.clamp(0.25, 4),
          min: 0.25,
          max: 4,
          divisions: 75,
          onChanged: (value) => setState(() => _speed = value),
          onChangeEnd: widget.onConstantSpeedChanged,
        ),
        Wrap(
          spacing: TgiSpacing.xs,
          runSpacing: TgiSpacing.xs,
          children: [
            for (final speed in const [0.25, 0.5, 1.0, 1.5, 2.0, 4.0])
              ActionChip(
                label: Text('${speed.toStringAsFixed(speed == 0.25 ? 2 : 1)}x'),
                onPressed: () {
                  setState(() => _speed = speed);
                  widget.onConstantSpeedChanged(speed);
                },
              ),
          ],
        ),
        const SizedBox(height: TgiSpacing.lg),
        Text(
          'Rampas de velocidade',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: TgiSpacing.xs),
        Text(
          'A rampa divide vídeo e áudio em segmentos sincronizados e continua editável na timeline.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: TgiColors.textMuted),
        ),
        const SizedBox(height: TgiSpacing.sm),
        _RampCard(
          key: const ValueKey('speed_ramp_accelerate'),
          title: 'Acelerar suave',
          subtitle: 'Começa lento e termina rápido',
          speeds: const [0.65, 0.8, 1.0, 1.5, 3.0],
          color: TgiColors.textSecondary,
          onTap: () => widget.onRampSelected(const [
            0.65,
            0.8,
            1.0,
            1.5,
            3.0,
          ], 'Rampa Acelerar suave'),
        ),
        _RampCard(
          key: const ValueKey('speed_ramp_decelerate'),
          title: 'Desacelerar suave',
          subtitle: 'Começa rápido e termina lento',
          speeds: const [3.0, 1.5, 1.0, 0.8, 0.65],
          color: TgiColors.accentGreen,
          onTap: () => widget.onRampSelected(const [
            3.0,
            1.5,
            1.0,
            0.8,
            0.65,
          ], 'Rampa Desacelerar suave'),
        ),
        _RampCard(
          key: const ValueKey('speed_ramp_punch'),
          title: 'Impacto no meio',
          subtitle: 'Acelera no centro e retorna',
          speeds: const [0.8, 1.0, 2.5, 1.0, 0.8],
          color: TgiColors.accentRose,
          onTap: () => widget.onRampSelected(const [
            0.8,
            1.0,
            2.5,
            1.0,
            0.8,
          ], 'Rampa Impacto no meio'),
        ),
        const SizedBox(height: TgiSpacing.lg),
        Text(
          'Ações',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: TgiSpacing.sm),
        FilledButton.tonalIcon(
          key: const ValueKey('advanced_slow_motion_button'),
          onPressed: widget.onSlowMotion,
          icon: const Icon(Icons.slow_motion_video),
          label: const Text('Câmera lenta 0,5x'),
        ),
        const SizedBox(height: TgiSpacing.sm),
        OutlinedButton.icon(
          key: const ValueKey('advanced_freeze_frame_button'),
          onPressed: widget.onFreezeFrame,
          icon: const Icon(Icons.ac_unit_outlined),
          label: const Text('Congelar quadro no playhead'),
        ),
        SwitchListTile(
          key: const ValueKey('advanced_reverse_switch'),
          contentPadding: EdgeInsets.zero,
          value: clip.reverseVideo,
          title: const Text('Reverter vídeo e áudio'),
          subtitle: const Text(
            'O preview segue o playhead e o export sai invertido.',
          ),
          onChanged: widget.onReverseChanged,
        ),
      ],
    );
  }
}

class _RampCard extends StatelessWidget {
  const _RampCard({
    required this.title,
    required this.subtitle,
    required this.speeds,
    required this.color,
    required this.onTap,
    super.key,
  });

  final String title;
  final String subtitle;
  final List<double> speeds;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: TgiSpacing.sm),
      child: Material(
        color: TgiColors.surfaceAlt,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TgiRadii.md),
          side: const BorderSide(color: TgiColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(TgiRadii.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(TgiSpacing.sm),
            child: Row(
              children: [
                SizedBox(
                  width: 76,
                  height: 44,
                  child: CustomPaint(
                    painter: _SpeedCurvePainter(speeds: speeds, color: color),
                  ),
                ),
                const SizedBox(width: TgiSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: TgiColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SpeedCurvePainter extends CustomPainter {
  const _SpeedCurvePainter({required this.speeds, required this.color});

  final List<double> speeds;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final maxSpeed = speeds.reduce((a, b) => a > b ? a : b);
    final path = Path();
    for (var index = 0; index < speeds.length; index++) {
      final point = Offset(
        index / (speeds.length - 1) * size.width,
        size.height - speeds[index] / maxSpeed * (size.height - 6) - 3,
      );
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawCircle(point, 2.5, Paint()..color = color);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _SpeedCurvePainter oldDelegate) =>
      oldDelegate.speeds != speeds || oldDelegate.color != color;
}
