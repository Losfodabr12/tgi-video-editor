import 'package:flutter/material.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../../../domain/models/clip.dart';
import '../../application/editor_controller.dart';
import '../duration_formatter.dart';

class SmartCutPanel extends StatelessWidget {
  const SmartCutPanel({
    required this.clip,
    required this.mediaName,
    required this.intensity,
    required this.analysis,
    required this.isAnalyzing,
    required this.canAnalyze,
    required this.canApply,
    required this.onIntensityChanged,
    required this.onAnalyze,
    required this.onApply,
    required this.onDiscard,
    required this.onPreviewSegment,
    super.key,
  });

  final Clip? clip;
  final String? mediaName;
  final SmartCutIntensity intensity;
  final SmartCutAnalysis? analysis;
  final bool isAnalyzing;
  final bool canAnalyze;
  final bool canApply;
  final ValueChanged<SmartCutIntensity> onIntensityChanged;
  final VoidCallback onAnalyze;
  final VoidCallback onApply;
  final VoidCallback onDiscard;
  final ValueChanged<SmartCutSegment> onPreviewSegment;

  @override
  Widget build(BuildContext context) {
    final result = analysis;
    return ListView(
      key: const ValueKey('smart_cut_panel'),
      padding: const EdgeInsets.all(TgiSpacing.md),
      children: [
        _IntroCard(clip: clip, mediaName: mediaName),
        const SizedBox(height: TgiSpacing.md),
        const Text(
          'Intensidade',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: TgiSpacing.xs),
        Wrap(
          spacing: TgiSpacing.xs,
          runSpacing: TgiSpacing.xs,
          children: [
            for (final option in SmartCutIntensity.values)
              ChoiceChip(
                key: ValueKey('smart_cut_intensity_${option.name}'),
                label: Text(option.label),
                selected: intensity == option,
                onSelected: isAnalyzing
                    ? null
                    : (_) => onIntensityChanged(option),
              ),
          ],
        ),
        const SizedBox(height: TgiSpacing.sm),
        Text(
          intensity.description,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: TgiColors.textMuted),
        ),
        const SizedBox(height: TgiSpacing.md),
        FilledButton.icon(
          key: const ValueKey('smart_cut_analyze'),
          onPressed: canAnalyze && !isAnalyzing ? onAnalyze : null,
          icon: isAnalyzing
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.manage_search_outlined),
          label: Text(isAnalyzing ? 'Analisando áudio...' : 'Analisar pausas'),
        ),
        if (isAnalyzing) ...[
          const SizedBox(height: TgiSpacing.sm),
          const LinearProgressIndicator(),
          const SizedBox(height: TgiSpacing.xs),
          const Text(
            'A análise é local e não envia seu vídeo para a internet.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: TgiColors.textMuted),
          ),
        ],
        if (clip == null) ...[
          const SizedBox(height: TgiSpacing.sm),
          const Text(
            'Selecione um clipe de vídeo com áudio na timeline.',
            style: TextStyle(color: TgiColors.textMuted),
          ),
        ],
        if (result != null && !isAnalyzing) ...[
          const SizedBox(height: TgiSpacing.lg),
          _AnalysisSummary(analysis: result),
          const SizedBox(height: TgiSpacing.md),
          if (result.segments.isEmpty)
            const _NoPausesFound()
          else ...[
            const Text(
              'Prévia dos cortes',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: TgiSpacing.xs),
            Text(
              'Use o botão de reprodução para ouvir cada pausa antes de aplicar.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: TgiColors.textMuted),
            ),
            const SizedBox(height: TgiSpacing.sm),
            for (var index = 0; index < result.segments.length; index++)
              _SegmentTile(
                index: index,
                segment: result.segments[index],
                onPreview: () => onPreviewSegment(result.segments[index]),
              ),
            const SizedBox(height: TgiSpacing.md),
            FilledButton.icon(
              key: const ValueKey('smart_cut_apply'),
              onPressed: canApply ? onApply : null,
              icon: const Icon(Icons.content_cut_rounded),
              label: Text(
                'Aplicar ${result.segments.length} '
                '${result.segments.length == 1 ? 'corte' : 'cortes'}',
              ),
            ),
            const SizedBox(height: TgiSpacing.xs),
            OutlinedButton.icon(
              key: const ValueKey('smart_cut_discard'),
              onPressed: onDiscard,
              icon: const Icon(Icons.close_rounded),
              label: const Text('Descartar prévia'),
            ),
            const SizedBox(height: TgiSpacing.xs),
            const Text(
              'Áudio e vídeo permanecem sincronizados. Você pode desfazer '
              'tudo com Ctrl+Z.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: TgiColors.textMuted),
            ),
          ],
        ],
      ],
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.clip, required this.mediaName});

  final Clip? clip;
  final String? mediaName;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TgiColors.accent.withValues(alpha: 0.08),
        border: Border.all(color: TgiColors.accent.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(TgiRadii.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(TgiSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_fix_high_rounded, color: TgiColors.accent),
                SizedBox(width: TgiSpacing.sm),
                Expanded(
                  child: Text(
                    'Corte Inteligente',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: TgiSpacing.xs),
            const Text(
              'Detecta pausas, preserva a respiração natural e fecha os '
              'espaços sem perder a sincronização.',
            ),
            if (clip != null) ...[
              const SizedBox(height: TgiSpacing.sm),
              Text(
                mediaName ?? 'Vídeo selecionado',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: TgiColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AnalysisSummary extends StatelessWidget {
  const _AnalysisSummary({required this.analysis});

  final SmartCutAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(TgiSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Resultado da análise',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: TgiSpacing.sm),
            _SummaryRow(
              label: 'Pausas encontradas',
              value: '${analysis.segments.length}',
            ),
            _SummaryRow(
              label: 'Tempo removido',
              value: formatDuration(analysis.removableDuration),
            ),
            _SummaryRow(
              label: 'Duração estimada',
              value: formatDuration(analysis.estimatedTimelineDuration),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: TgiColors.textSecondary),
            ),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _SegmentTile extends StatelessWidget {
  const _SegmentTile({
    required this.index,
    required this.segment,
    required this.onPreview,
  });

  final int index;
  final SmartCutSegment segment;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: TgiSpacing.xs),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.only(left: TgiSpacing.sm, right: 4),
        leading: CircleAvatar(
          radius: 14,
          child: Text('${index + 1}', style: const TextStyle(fontSize: 11)),
        ),
        title: Text(
          '${formatDuration(segment.start)} – ${formatDuration(segment.end)}',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
        ),
        subtitle: Text(
          '${segment.duration.inMilliseconds / 1000} s',
          style: const TextStyle(fontSize: 11),
        ),
        trailing: IconButton(
          key: ValueKey('smart_cut_preview_$index'),
          tooltip: 'Ouvir esta pausa',
          onPressed: onPreview,
          icon: const Icon(Icons.play_arrow_rounded),
        ),
      ),
    );
  }
}

class _NoPausesFound extends StatelessWidget {
  const _NoPausesFound();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(TgiSpacing.md),
        child: Row(
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              color: TgiColors.accentGreen,
            ),
            const SizedBox(width: TgiSpacing.sm),
            const Expanded(
              child: Text(
                'Nenhuma pausa longa foi encontrada com esta intensidade.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
