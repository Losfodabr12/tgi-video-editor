import 'package:flutter/material.dart';

import '../../../../app/theme/decorations.dart';
import '../../../../app/theme/design_tokens.dart';
import '../../../../domain/models/timeline_transition.dart';

class TransitionLibraryPanel extends StatelessWidget {
  const TransitionLibraryPanel({
    required this.onInsertTransitionPreset,
    super.key,
  });

  final ValueChanged<TimelineTransitionAsset> onInsertTransitionPreset;

  static const presetAssets = [
    TimelineTransitionAsset(
      id: 'preset_fade_black',
      name: 'Fade para preto',
      preset: TimelineTransitionPreset.fade,
      color: 0xFF000000,
      duration: Duration(milliseconds: 800),
    ),
    TimelineTransitionAsset(
      id: 'preset_flash_white',
      name: 'Flash branco',
      preset: TimelineTransitionPreset.flash,
      color: 0xFFFFFFFF,
      intensity: 0.95,
      duration: Duration(milliseconds: 420),
    ),
    TimelineTransitionAsset(
      id: 'preset_dissolve',
      name: 'Dissolve suave',
      preset: TimelineTransitionPreset.dissolve,
      duration: Duration(milliseconds: 900),
    ),
    TimelineTransitionAsset(
      id: 'preset_blur',
      name: 'Desfoque cinema',
      preset: TimelineTransitionPreset.blur,
      intensity: 0.86,
      duration: Duration(milliseconds: 720),
    ),
    TimelineTransitionAsset(
      id: 'preset_glitch',
      name: 'Glitch RGB',
      preset: TimelineTransitionPreset.glitch,
      color: 0xFFFF2AA3,
      intensity: 0.9,
      duration: Duration(milliseconds: 520),
    ),
    TimelineTransitionAsset(
      id: 'preset_spin',
      name: 'Giro rápido',
      preset: TimelineTransitionPreset.spin,
      duration: Duration(milliseconds: 620),
    ),
    TimelineTransitionAsset(
      id: 'preset_pixelate',
      name: 'Pixelado digital',
      preset: TimelineTransitionPreset.pixelate,
      duration: Duration(milliseconds: 680),
    ),
    TimelineTransitionAsset(
      id: 'preset_zoom',
      name: 'Zoom impacto',
      preset: TimelineTransitionPreset.zoom,
      duration: Duration(milliseconds: 650),
    ),
    TimelineTransitionAsset(
      id: 'preset_wipe',
      name: 'Wipe lateral',
      preset: TimelineTransitionPreset.wipe,
      direction: TimelineTransitionDirection.rightToLeft,
      color: 0xFF05070A,
      intensity: 0.96,
      duration: Duration(milliseconds: 760),
    ),
    TimelineTransitionAsset(
      id: 'preset_light_leak',
      name: 'Light leak quente',
      preset: TimelineTransitionPreset.lightLeak,
      direction: TimelineTransitionDirection.leftToRight,
      color: 0xFFFF8A3D,
      intensity: 0.82,
      duration: Duration(milliseconds: 780),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(TgiSpacing.md),
      children: [
        _TransitionPresetHeader(count: presetAssets.length),
        const SizedBox(height: TgiSpacing.md),
        for (final preset in presetAssets) ...[
          _TransitionPresetTile(
            preset: preset,
            onApply: () => onInsertTransitionPreset(preset),
          ),
          const SizedBox(height: TgiSpacing.sm),
        ],
      ],
    );
  }
}

class _TransitionPresetHeader extends StatelessWidget {
  const _TransitionPresetHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TgiColors.background.withValues(alpha: 0.62),
        border: Border.all(color: TgiColors.borderStrong),
        borderRadius: BorderRadius.circular(TgiRadii.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(TgiSpacing.sm),
        child: Row(
          children: [
            TgiFramedBox(
              radius: TgiRadii.md,
              strokeWidth: 1.2,
              child: const SizedBox(
                width: 38,
                height: 38,
                child: TgiAccentIcon(Icons.movie_filter_outlined, size: 20),
              ),
            ),
            const SizedBox(width: TgiSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$count transicoes reais',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: TgiColors.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    'Arraste para o inicio do video ou para uma emenda',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: TgiColors.textSecondary,
                      fontSize: 11,
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

class _TransitionPresetTile extends StatelessWidget {
  const _TransitionPresetTile({required this.preset, required this.onApply});

  final TimelineTransitionAsset preset;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final tile = _buildTile(context);
    return Draggable<TimelineTransitionAsset>(
      data: preset,
      feedback: Material(
        color: TgiColors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Opacity(opacity: 0.92, child: tile),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.45, child: tile),
      child: tile,
    );
  }

  Widget _buildTile(BuildContext context) {
    return DecoratedBox(
      decoration: TgiDecorations.panel(),
      child: Padding(
        padding: const EdgeInsets.all(TgiSpacing.sm),
        child: Row(
          children: [
            _TransitionPresetPreview(preset: preset),
            const SizedBox(width: TgiSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    preset.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: TgiColors.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _presetSubtitle(preset),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: TgiColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: TgiSpacing.sm),
            Tooltip(
              message: 'Aplicar no inicio ou na emenda',
              child: SizedBox(
                width: 34,
                height: 34,
                child: IconButton(
                  key: ValueKey('apply_transition_${preset.id}'),
                  onPressed: onApply,
                  padding: EdgeInsets.zero,
                  icon: const TgiAccentIcon(Icons.add, size: TgiIconSizes.md),
                  style: IconButton.styleFrom(
                    foregroundColor: TgiColors.textSecondary,
                    backgroundColor: TgiColors.surfacePressed,
                    side: const BorderSide(color: TgiColors.borderStrong),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(TgiRadii.md),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _presetSubtitle(TimelineTransitionAsset preset) {
    final ms = preset.duration.inMilliseconds;
    return switch (preset.preset) {
      TimelineTransitionPreset.fade => '$ms ms - ${_colorEffect(preset)}',
      TimelineTransitionPreset.flash => '$ms ms - flash branco',
      TimelineTransitionPreset.wipe => '$ms ms - ${_directionLabel(preset)}',
      TimelineTransitionPreset.dissolve => '$ms ms - mistura temporal',
      TimelineTransitionPreset.blur => '$ms ms - desfoque gaussiano',
      TimelineTransitionPreset.glitch => '$ms ms - canais RGB e ruído',
      TimelineTransitionPreset.spin => '$ms ms - giro de impacto',
      TimelineTransitionPreset.pixelate => '$ms ms - blocos digitais',
      TimelineTransitionPreset.zoom => '$ms ms - distorção de lente',
      TimelineTransitionPreset.lightLeak => '$ms ms - vazamento de luz',
      null => '$ms ms',
    };
  }

  String _colorEffect(TimelineTransitionAsset preset) {
    return switch (preset.color & 0x00FFFFFF) {
      0x000000 => 'passagem pelo preto',
      0xFFFFFF => 'passagem pelo branco',
      0xFF8A3D => 'clarão laranja',
      _ => 'passagem colorida',
    };
  }

  String _directionLabel(TimelineTransitionAsset preset) {
    return switch (preset.direction) {
      TimelineTransitionDirection.leftToRight => 'esquerda → direita',
      TimelineTransitionDirection.rightToLeft => 'direita → esquerda',
      TimelineTransitionDirection.topToBottom => 'cima → baixo',
      TimelineTransitionDirection.bottomToTop => 'baixo → cima',
    };
  }
}

class _TransitionPresetPreview extends StatelessWidget {
  const _TransitionPresetPreview({required this.preset});

  final TimelineTransitionAsset preset;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 74,
      height: 46,
      decoration: BoxDecoration(
        color: TgiColors.backgroundDeep,
        border: Border.all(color: TgiColors.accentMuted),
        borderRadius: BorderRadius.circular(TgiRadii.md),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(painter: _TransitionPresetPainter(preset)),
    );
  }
}

class _TransitionPresetPainter extends CustomPainter {
  const _TransitionPresetPainter(this.asset);

  final TimelineTransitionAsset asset;

  @override
  void paint(Canvas canvas, Size size) {
    final basePaint = Paint()..color = TgiColors.border;
    canvas.drawRect(Offset.zero & size, basePaint);
    final effectColor = Color(
      asset.color,
    ).withValues(alpha: asset.intensity.clamp(0.0, 1.0).toDouble());
    final accentPaint = Paint()..color = effectColor;
    switch (asset.preset) {
      case TimelineTransitionPreset.fade:
        canvas.drawRect(Offset.zero & size, accentPaint);
        canvas.drawRect(
          Rect.fromLTWH(size.width * 0.42, 0, size.width * 0.16, size.height),
          Paint()..color = TgiColors.white.withValues(alpha: 0.18),
        );
        break;
      case TimelineTransitionPreset.flash:
        canvas.drawRect(
          Offset.zero & size,
          Paint()..color = TgiColors.white.withValues(alpha: 0.78),
        );
        break;
      case TimelineTransitionPreset.wipe:
        final rect = switch (asset.direction) {
          TimelineTransitionDirection.leftToRight => Rect.fromLTWH(
            0,
            0,
            size.width * 0.58,
            size.height,
          ),
          TimelineTransitionDirection.rightToLeft => Rect.fromLTWH(
            size.width * 0.42,
            0,
            size.width * 0.58,
            size.height,
          ),
          TimelineTransitionDirection.topToBottom => Rect.fromLTWH(
            0,
            0,
            size.width,
            size.height * 0.58,
          ),
          TimelineTransitionDirection.bottomToTop => Rect.fromLTWH(
            0,
            size.height * 0.42,
            size.width,
            size.height * 0.58,
          ),
        };
        canvas.drawRect(rect, accentPaint);
        break;
      case TimelineTransitionPreset.dissolve:
        canvas.drawRect(
          Rect.fromLTWH(0, 0, size.width * 0.62, size.height),
          Paint()..color = TgiColors.clipEffect.withValues(alpha: 0.48),
        );
        canvas.drawRect(
          Rect.fromLTWH(size.width * 0.38, 0, size.width * 0.62, size.height),
          Paint()..color = TgiColors.accentRose.withValues(alpha: 0.48),
        );
        break;
      case TimelineTransitionPreset.blur:
        for (var index = 0; index < 4; index++) {
          canvas.drawCircle(
            Offset(size.width * (0.2 + index * 0.2), size.height * 0.5),
            13,
            Paint()
              ..color = TgiColors.accentSoft.withValues(
                alpha: 0.16 + index * 0.08,
              ),
          );
        }
        break;
      case TimelineTransitionPreset.glitch:
        canvas.drawRect(
          Rect.fromLTWH(5, 7, size.width - 12, 9),
          Paint()..color = const Color(0xAAFF2A73),
        );
        canvas.drawRect(
          Rect.fromLTWH(12, 20, size.width - 15, 8),
          Paint()..color = const Color(0xAA2AC8FF),
        );
        canvas.drawRect(
          Rect.fromLTWH(3, 33, size.width - 20, 6),
          Paint()..color = const Color(0xAA55FF8A),
        );
        break;
      case TimelineTransitionPreset.spin:
        canvas.save();
        canvas.translate(size.width / 2, size.height / 2);
        canvas.rotate(0.32);
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset.zero,
            width: size.width * 0.72,
            height: size.height * 0.72,
          ),
          Paint()..color = TgiColors.clipEffect.withValues(alpha: 0.62),
        );
        canvas.restore();
        break;
      case TimelineTransitionPreset.pixelate:
        const block = 9.0;
        for (var y = 0.0; y < size.height; y += block) {
          for (var x = 0.0; x < size.width; x += block) {
            if (((x / block).floor() + (y / block).floor()).isEven) {
              canvas.drawRect(
                Rect.fromLTWH(x, y, block - 1, block - 1),
                Paint()..color = TgiColors.clipEffect.withValues(alpha: 0.58),
              );
            }
          }
        }
        break;
      case TimelineTransitionPreset.zoom:
        for (var index = 0; index < 3; index++) {
          final inset = 5.0 + index * 7;
          canvas.drawRect(
            Rect.fromLTRB(
              inset,
              inset,
              size.width - inset,
              size.height - inset,
            ),
            Paint()
              ..color = TgiColors.transparent
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = TgiColors.accentSoft.withValues(
                alpha: 0.82 - index * 0.2,
              ),
          );
        }
        break;
      case TimelineTransitionPreset.lightLeak:
        canvas.drawRect(
          Offset.zero & size,
          Paint()
            ..shader = const LinearGradient(
              colors: [
                Color(0x00FF5B21),
                Color(0xCCFF8A3D),
                Color(0xCCFFF2B2),
                Color(0x00FF5B21),
              ],
            ).createShader(Offset.zero & size),
        );
        break;
      case null:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _TransitionPresetPainter oldDelegate) {
    return oldDelegate.asset != asset;
  }
}
