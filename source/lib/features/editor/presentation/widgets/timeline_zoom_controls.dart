import 'dart:math' as math;
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
    required this.onZoomChanged,
    super.key,
  });
  final double zoom;
  final Duration playheadPosition, duration;
  final VoidCallback? onAudioInventoryOpen, onMarkerAdd;
  final ValueChanged<double> onZoomChanged;
  static const minZoom = 0.005;
  static const maxZoom = 32.0;

  @override
  Widget build(BuildContext context) {
    final range = math.log(maxZoom / minZoom);
    final value = (math.log(zoom.clamp(minZoom, maxZoom) / minZoom) / range)
        .clamp(0.0, 1.0);
    final percent = '${(zoom * 100).toStringAsFixed(zoom < .1 ? 1 : 0)}%';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Tempo atual / duração real do projeto',
          child: Container(
            key: const ValueKey('timeline-timecode'),
            height: 28,
            constraints: const BoxConstraints(minWidth: 124),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: TgiColors.surfaceRaised,
              border: Border.all(color: TgiColors.border),
              borderRadius: BorderRadius.circular(TgiRadii.sm),
            ),
            alignment: Alignment.center,
            child: Text(
              '${formatDuration(playheadPosition)} / ${formatDuration(duration)}',
              style: const TextStyle(
                color: TgiColors.textSecondary,
                fontSize: 12,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: onAudioInventoryOpen,
          icon: const Icon(Icons.library_music_outlined, size: 16),
          label: const Text('Áudio'),
        ),
        IconButton(
          tooltip: 'Adicionar marcador',
          onPressed: onMarkerAdd,
          icon: const Icon(Icons.flag_outlined, size: 18),
        ),
        const Icon(Icons.zoom_in, size: 18, color: TgiColors.textSecondary),
        Tooltip(
          message: 'Zoom da timeline · Ctrl + roda do mouse',
          child: SizedBox(
            width: 144,
            height: 32,
            child: Slider(
              key: const ValueKey('timeline-zoom-slider'),
              value: value,
              semanticFormatterCallback: (t) {
                final percent = minZoom * math.exp(t * range) * 100;
                return '${percent.toStringAsFixed(percent < 10 ? 1 : 0)}%';
              },
              onChanged: (t) => onZoomChanged(minZoom * math.exp(t * range)),
            ),
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            percent,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: TgiColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}
