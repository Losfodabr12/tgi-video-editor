import 'package:flutter/material.dart';

import '../../../../app/theme/design_tokens.dart';
import '../duration_formatter.dart';

class TimelineZoomControls extends StatelessWidget {
  const TimelineZoomControls({
    required this.zoom,
    required this.playheadPosition,
    required this.duration,
    required this.onAudioInventoryOpen,
    required this.onMarkerAdd,
    required this.onZoomOut,
    required this.onZoomIn,
    super.key,
  });

  final double zoom;
  final Duration playheadPosition;
  final Duration duration;
  final VoidCallback? onAudioInventoryOpen;
  final VoidCallback? onMarkerAdd;
  final VoidCallback? onZoomOut;
  final VoidCallback? onZoomIn;

  @override
  Widget build(BuildContext context) {
    final percent = (zoom * 100).round();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TgiColors.backgroundDeep.withValues(alpha: 0.42),
        border: Border.all(
          color: TgiColors.accentMuted.withValues(alpha: 0.52),
        ),
        borderRadius: BorderRadius.circular(TgiRadii.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TimelineTimecodeBadge(current: playheadPosition, total: duration),
            const SizedBox(width: 4),
            _TimelineZoomButton(
              tooltip: 'Audio Pick / inventario de audio',
              icon: Icons.library_music_outlined,
              label: 'Audio',
              onPressed: onAudioInventoryOpen,
            ),
            const SizedBox(width: 4),
            _TimelineZoomButton(
              tooltip: 'Adicionar marcador',
              icon: Icons.flag_outlined,
              label: 'Marcador',
              onPressed: onMarkerAdd,
            ),
            const SizedBox(width: 4),
            _TimelineZoomButton(
              tooltip: 'Diminuir zoom',
              icon: Icons.zoom_out,
              label: 'Zoom -',
              onPressed: onZoomOut,
            ),
            SizedBox(
              width: 46,
              child: Text(
                '$percent%',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TgiColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _TimelineZoomButton(
              tooltip: 'Aumentar zoom',
              icon: Icons.zoom_in,
              label: 'Zoom +',
              onPressed: onZoomIn,
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineTimecodeBadge extends StatelessWidget {
  const _TimelineTimecodeBadge({required this.current, required this.total});

  final Duration current;
  final Duration total;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Tempo atual / duracao da timeline',
      child: Container(
        height: 28,
        constraints: const BoxConstraints(minWidth: 116),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: TgiColors.surfacePressed.withValues(alpha: 0.86),
          border: Border.all(color: TgiColors.accent.withValues(alpha: 0.62)),
          borderRadius: BorderRadius.circular(TgiRadii.pill),
        ),
        alignment: Alignment.center,
        child: Text(
          '${formatDuration(current)} / ${formatDuration(total)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: TgiColors.textMuted,
            fontFeatures: const [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _TimelineZoomButton extends StatelessWidget {
  const _TimelineZoomButton({
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: enabled ? 1 : 0.48,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(TgiRadii.pill),
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: enabled
                  ? Color.lerp(TgiColors.surfaceRaised, TgiColors.accent, 0.035)
                  : TgiColors.surface.withValues(alpha: 0.58),
              border: Border.all(
                color: enabled
                    ? TgiColors.borderStrong
                    : TgiColors.borderSubtle,
              ),
              borderRadius: BorderRadius.circular(TgiRadii.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                enabled
                    ? TgiAccentIcon(icon, size: 15)
                    : Icon(icon, size: 15, color: TgiColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: TgiColors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
