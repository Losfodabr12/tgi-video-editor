import 'package:flutter/material.dart';
import '../../../../services/whisper_runtime.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../../../domain/models/clip.dart';
import '../duration_formatter.dart';

class CaptionsPanel extends StatelessWidget {
  const CaptionsPanel({
    required this.captions,
    required this.selectedTimelineGroupId,
    required this.canGenerate,
    required this.canExport,
    required this.isGenerating,
    required this.onGenerate,
    required this.onAddQuickCaption,
    required this.onExportSrt,
    required this.onExportVtt,
    required this.onCaptionSelected,
    required this.onCaptionChanged,
    this.onImportSrt,
    this.onEditStyle,
    super.key,
  });

  final VoidCallback? onImportSrt, onEditStyle;
  final List<Clip> captions;
  final String? selectedTimelineGroupId;
  final bool canGenerate;
  final bool canExport;
  final bool isGenerating;
  final VoidCallback onGenerate;
  final VoidCallback onAddQuickCaption;
  final VoidCallback onExportSrt;
  final VoidCallback onExportVtt;
  final ValueChanged<Clip> onCaptionSelected;
  final void Function(String clipId, String text) onCaptionChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ValueListenableBuilder<String>(
          valueListenable: WhisperRuntime.backend,
          builder: (context, value, _) => Text(
            'Transcritor: $value',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Wrap(
          spacing: TgiSpacing.sm,
          runSpacing: TgiSpacing.sm,
          children: [
            if (onImportSrt != null)
              OutlinedButton.icon(
                key: const ValueKey('captions_import_srt'),
                onPressed: onImportSrt,
                icon: const Icon(Icons.file_open_outlined, size: 18),
                label: const Text('Importar SRT'),
              ),
            if (onEditStyle != null)
              OutlinedButton.icon(
                key: const ValueKey('captions_edit_style'),
                onPressed: captions.isEmpty ? null : onEditStyle,
                icon: const Icon(Icons.format_paint_outlined, size: 18),
                label: const Text('Estilo'),
              ),
            ElevatedButton.icon(
              key: const ValueKey('captions_generate_button'),
              onPressed: canGenerate && !isGenerating ? onGenerate : null,
              icon: isGenerating
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome, size: 18),
              label: Text(isGenerating ? 'Gerando' : 'Gerar automática'),
            ),
            OutlinedButton.icon(
              onPressed: onAddQuickCaption,
              icon: const Icon(Icons.add_comment_outlined, size: 18),
              label: const Text('Legenda manual'),
            ),
          ],
        ),
        const SizedBox(height: TgiSpacing.md),
        Row(
          children: [
            Expanded(
              child: Text(
                'Exportar legendas',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: TgiColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            OutlinedButton(
              key: const ValueKey('captions_export_srt_button'),
              onPressed: canExport ? onExportSrt : null,
              child: const Text('SRT'),
            ),
            const SizedBox(width: TgiSpacing.xs),
            OutlinedButton(
              key: const ValueKey('captions_export_vtt_button'),
              onPressed: canExport ? onExportVtt : null,
              child: const Text('VTT'),
            ),
          ],
        ),
        const SizedBox(height: TgiSpacing.md),
        Row(
          children: [
            Icon(
              Icons.subtitles_outlined,
              size: 18,
              color: TgiColors.accentSoft,
            ),
            const SizedBox(width: TgiSpacing.sm),
            Expanded(
              child: Text(
                'Todas as legendas (${captions.length})',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: TgiSpacing.sm),
        Expanded(
          child: captions.isEmpty
              ? const _EmptyCaptions()
              : ListView.separated(
                  key: const ValueKey('captions_edit_list'),
                  itemCount: captions.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: TgiSpacing.sm),
                  itemBuilder: (context, index) {
                    final caption = captions[index];
                    return _CaptionRow(
                      key: ValueKey('caption_row_${caption.id}'),
                      caption: caption,
                      selected:
                          caption.timelineGroupId == selectedTimelineGroupId,
                      onSelected: () => onCaptionSelected(caption),
                      onChanged: (text) => onCaptionChanged(caption.id, text),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _EmptyCaptions extends StatelessWidget {
  const _EmptyCaptions();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 96;
        return Center(
          child: Padding(
            padding: EdgeInsets.all(compact ? TgiSpacing.xs : TgiSpacing.lg),
            child: compact
                ? Text(
                    'Nenhuma legenda. Clique em Gerar automática.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: TgiColors.textMuted),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.closed_caption_disabled_outlined,
                        size: 34,
                        color: TgiColors.textMuted,
                      ),
                      const SizedBox(height: TgiSpacing.sm),
                      Text(
                        'Gere legendas para revisar e editar cada trecho aqui.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: TgiColors.textMuted,
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _CaptionRow extends StatefulWidget {
  const _CaptionRow({
    required this.caption,
    required this.selected,
    required this.onSelected,
    required this.onChanged,
    super.key,
  });

  final Clip caption;
  final bool selected;
  final VoidCallback onSelected;
  final ValueChanged<String> onChanged;

  @override
  State<_CaptionRow> createState() => _CaptionRowState();
}

class _CaptionRowState extends State<_CaptionRow> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.caption.textContent);
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _CaptionRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus &&
        widget.caption.textContent != _controller.text) {
      _controller.text = widget.caption.textContent;
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) _commit();
  }

  void _commit() {
    final value = _controller.text.trim();
    if (value.isEmpty || value == widget.caption.textContent.trim()) return;
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final caption = widget.caption;
    return Material(
      color: widget.selected
          ? TgiColors.surfacePressed
          : TgiColors.surfaceAlt.withValues(alpha: 0.72),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TgiRadii.md),
        side: BorderSide(
          color: widget.selected ? TgiColors.accentMuted : TgiColors.border,
        ),
      ),
      child: InkWell(
        onTap: widget.onSelected,
        borderRadius: BorderRadius.circular(TgiRadii.md),
        child: Padding(
          padding: const EdgeInsets.all(TgiSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${formatDuration(caption.timelineStart)}  →  '
                '${formatDuration(caption.timelineEnd)}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: TgiColors.accentSoft,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              TextField(
                key: ValueKey('caption_text_${caption.id}'),
                controller: _controller,
                focusNode: _focusNode,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.done,
                onTap: widget.onSelected,
                onSubmitted: (_) {
                  _commit();
                  _focusNode.unfocus();
                },
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Texto da legenda',
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
