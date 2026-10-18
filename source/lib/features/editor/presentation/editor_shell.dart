part of 'editor_screen.dart';

class _EditorHeader extends StatelessWidget {
  const _EditorHeader({
    required this.projectName,
    required this.isImporting,
    required this.isExporting,
    required this.exportProgress,
    required this.exportRemaining,
    required this.isGeneratingCaptions,
    required this.captionProgress,
    required this.captionProgressMessage,
    required this.isOptimizingPreview,
    required this.previewOptimizationProgress,
    required this.previewOptimizationRemaining,
    required this.previewOptimizationAutomatic,
    required this.onCancelPreviewOptimization,
    required this.canExport,
    required this.canUndo,
    required this.canRedo,
    required this.canCopy,
    required this.canPaste,
    required this.canDuplicate,
    required this.onBack,
    required this.onSaveProject,
    this.onProjectTools,
    required this.onLoadProject,
    required this.onUndo,
    required this.onRedo,
    required this.onCopy,
    required this.onPaste,
    required this.onDuplicate,
    required this.onImportVideo,
    required this.onOpenKeyboardSettings,
    required this.onResetWorkspaceLayout,
    required this.onWatermarkSettings,
    required this.exportLabel,
    required this.onExport,
    required this.onCancelExport,
  });

  final String projectName;
  final bool isImporting;
  final bool isExporting;
  final double exportProgress;
  final Duration? exportRemaining;
  final bool isGeneratingCaptions;
  final double captionProgress;
  final String? captionProgressMessage;
  final bool isOptimizingPreview;
  final double previewOptimizationProgress;
  final Duration? previewOptimizationRemaining;
  final bool previewOptimizationAutomatic;
  final VoidCallback onCancelPreviewOptimization;
  final bool canExport;
  final bool canUndo;
  final bool canRedo;
  final bool canCopy;
  final bool canPaste;
  final bool canDuplicate;
  final VoidCallback onBack;
  final VoidCallback onSaveProject;
  final VoidCallback? onProjectTools;
  final VoidCallback onLoadProject;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onCopy;
  final VoidCallback onPaste;
  final VoidCallback onDuplicate;
  final VoidCallback onImportVideo;
  final VoidCallback onOpenKeyboardSettings;
  final VoidCallback onResetWorkspaceLayout;
  final VoidCallback onWatermarkSettings;
  final String exportLabel;
  final VoidCallback onExport;
  final VoidCallback onCancelExport;

  @override
  Widget build(BuildContext context) {
    final percent = (exportProgress.clamp(0.0, 1.0) * 100).round();
    final previewPercent = (previewOptimizationProgress.clamp(0.0, 1.0) * 100)
        .round();
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compactActions = screenWidth < 1180;
    final veryCompact = screenWidth < 760;
    final busy =
        isImporting ||
        isExporting ||
        isGeneratingCaptions ||
        isOptimizingPreview;

    Widget compactAction({
      required String tooltip,
      required IconData icon,
      required VoidCallback? onPressed,
      bool accent = false,
    }) {
      return IconButton(
        tooltip: tooltip,
        onPressed: busy ? null : onPressed,
        style: IconButton.styleFrom(
          backgroundColor: accent
              ? TgiColors.surfacePressed
              : TgiColors.transparent,
          foregroundColor: TgiColors.textPrimary,
          disabledBackgroundColor: TgiColors.transparent,
          disabledForegroundColor: TgiColors.textSecondary,
          side: accent
              ? BorderSide(color: Theme.of(context).colorScheme.primary)
              : BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TgiRadii.xs),
          ),
        ),
        icon: Icon(icon),
      );
    }

    Widget compactToolbar() {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (Navigator.of(context).canPop())
              compactAction(
                tooltip: 'Voltar',
                icon: Icons.arrow_back_rounded,
                onPressed: onBack,
              ),
            const SizedBox(width: TgiSpacing.sm),
            const _TgiEditorWordmark(),
            const SizedBox(width: TgiSpacing.md),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                projectName,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TgiColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const _HeaderDivider(),
            compactAction(
              tooltip: 'Projeto e modelos',
              icon: Icons.workspaces_outline,
              onPressed: onProjectTools,
            ),
            compactAction(
              tooltip: 'Salvar projeto',
              icon: Icons.save_outlined,
              onPressed: onSaveProject,
            ),
            const SizedBox(width: 8),
            compactAction(
              tooltip: 'Carregar projeto',
              icon: Icons.folder_open_outlined,
              onPressed: onLoadProject,
            ),
            const SizedBox(width: 8),
            compactAction(
              tooltip: 'Importar arquivo',
              icon: Icons.file_upload_outlined,
              onPressed: onImportVideo,
            ),
            const SizedBox(width: 8),
            compactAction(
              tooltip: exportLabel,
              icon: Icons.file_download_outlined,
              onPressed: canExport ? onExport : null,
              accent: true,
            ),
          ],
        ),
      );
    }

    return DecoratedBox(
      decoration: TgiDecorations.appHeader(),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TgiSpacing.lg,
          vertical: TgiSpacing.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (veryCompact)
              compactToolbar()
            else
              Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          if (Navigator.of(context).canPop())
                            IconButton(
                              tooltip: 'Voltar',
                              onPressed:
                                  isImporting ||
                                      isExporting ||
                                      isGeneratingCaptions ||
                                      isOptimizingPreview
                                  ? null
                                  : onBack,
                              style: IconButton.styleFrom(
                                backgroundColor: TgiColors.transparent,
                                foregroundColor: TgiColors.textPrimary,
                                disabledBackgroundColor: TgiColors.transparent,
                                disabledForegroundColor:
                                    TgiColors.textSecondary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    TgiRadii.xs,
                                  ),
                                ),
                              ),
                              icon: const Icon(Icons.arrow_back_rounded),
                            ),
                          const SizedBox(width: TgiSpacing.sm),
                          const _TgiEditorWordmark(),
                          const SizedBox(width: TgiSpacing.lg),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 260),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: TgiColors.surface,
                                border: Border.all(
                                  color: TgiColors.borderStrong,
                                ),
                                borderRadius: BorderRadius.circular(
                                  TgiRadii.md,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: TgiSpacing.md,
                                  vertical: TgiSpacing.sm,
                                ),
                                child: Text(
                                  projectName,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: TgiColors.textPrimary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              ),
                            ),
                          ),
                          const _HeaderDivider(),
                          IconButton(
                            tooltip: 'Projeto e modelos',
                            onPressed: busy ? null : onProjectTools,
                            icon: const Icon(Icons.workspaces_outline),
                          ),
                          IconButton(
                            tooltip: 'Salvar projeto',
                            onPressed:
                                isImporting ||
                                    isExporting ||
                                    isGeneratingCaptions ||
                                    isOptimizingPreview
                                ? null
                                : onSaveProject,
                            style: IconButton.styleFrom(
                              backgroundColor: TgiColors.transparent,
                              foregroundColor: TgiColors.textPrimary,
                              disabledBackgroundColor: TgiColors.transparent,
                              disabledForegroundColor: TgiColors.textSecondary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  TgiRadii.xs,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.save_outlined),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Carregar projeto',
                            onPressed:
                                isImporting ||
                                    isExporting ||
                                    isGeneratingCaptions ||
                                    isOptimizingPreview
                                ? null
                                : onLoadProject,
                            style: IconButton.styleFrom(
                              backgroundColor: TgiColors.transparent,
                              foregroundColor: TgiColors.textPrimary,
                              disabledBackgroundColor: TgiColors.transparent,
                              disabledForegroundColor: TgiColors.textSecondary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  TgiRadii.xs,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.folder_open_outlined),
                          ),
                          const _HeaderDivider(),
                          IconButton(
                            tooltip: 'Desfazer',
                            onPressed:
                                isImporting ||
                                    isExporting ||
                                    isGeneratingCaptions ||
                                    !canUndo
                                ? null
                                : onUndo,
                            style: IconButton.styleFrom(
                              backgroundColor: TgiColors.transparent,
                              foregroundColor: TgiColors.textPrimary,
                              disabledBackgroundColor: TgiColors.transparent,
                              disabledForegroundColor: TgiColors.textSecondary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  TgiRadii.xs,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.undo),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Refazer',
                            onPressed:
                                isImporting ||
                                    isExporting ||
                                    isGeneratingCaptions ||
                                    !canRedo
                                ? null
                                : onRedo,
                            style: IconButton.styleFrom(
                              backgroundColor: TgiColors.transparent,
                              foregroundColor: TgiColors.textPrimary,
                              disabledBackgroundColor: TgiColors.transparent,
                              disabledForegroundColor: TgiColors.textSecondary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  TgiRadii.xs,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.redo),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Copiar clips',
                            onPressed:
                                isImporting ||
                                    isExporting ||
                                    isGeneratingCaptions ||
                                    !canCopy
                                ? null
                                : onCopy,
                            style: IconButton.styleFrom(
                              backgroundColor: TgiColors.transparent,
                              foregroundColor: TgiColors.textPrimary,
                              disabledBackgroundColor: TgiColors.transparent,
                              disabledForegroundColor: TgiColors.textSecondary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  TgiRadii.xs,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.copy_outlined),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Colar clips',
                            onPressed:
                                isImporting ||
                                    isExporting ||
                                    isGeneratingCaptions ||
                                    !canPaste
                                ? null
                                : onPaste,
                            style: IconButton.styleFrom(
                              backgroundColor: TgiColors.transparent,
                              foregroundColor: TgiColors.textPrimary,
                              disabledBackgroundColor: TgiColors.transparent,
                              disabledForegroundColor: TgiColors.textSecondary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  TgiRadii.xs,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.content_paste_outlined),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Duplicar clips',
                            onPressed:
                                isImporting ||
                                    isExporting ||
                                    isGeneratingCaptions ||
                                    !canDuplicate
                                ? null
                                : onDuplicate,
                            style: IconButton.styleFrom(
                              backgroundColor: TgiColors.transparent,
                              foregroundColor: TgiColors.textPrimary,
                              disabledBackgroundColor: TgiColors.transparent,
                              disabledForegroundColor: TgiColors.textSecondary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  TgiRadii.xs,
                                ),
                              ),
                            ),
                            icon: const Icon(
                              Icons.control_point_duplicate_outlined,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: TgiSpacing.sm),
                  IconButton(
                    tooltip: 'Restaurar layout',
                    onPressed:
                        isImporting ||
                            isExporting ||
                            isGeneratingCaptions ||
                            isOptimizingPreview
                        ? null
                        : onResetWorkspaceLayout,
                    style: IconButton.styleFrom(
                      backgroundColor: TgiColors.transparent,
                      foregroundColor: TgiColors.textPrimary,
                      disabledBackgroundColor: TgiColors.transparent,
                      disabledForegroundColor: TgiColors.textSecondary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(TgiRadii.xs),
                      ),
                    ),
                    icon: const Icon(Icons.restart_alt_outlined),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Configurações de teclas',
                    onPressed:
                        isImporting ||
                            isExporting ||
                            isGeneratingCaptions ||
                            isOptimizingPreview
                        ? null
                        : onOpenKeyboardSettings,
                    style: IconButton.styleFrom(
                      backgroundColor: TgiColors.transparent,
                      foregroundColor: TgiColors.textPrimary,
                      disabledBackgroundColor: TgiColors.transparent,
                      disabledForegroundColor: TgiColors.textSecondary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(TgiRadii.xs),
                      ),
                    ),
                    icon: const Icon(Icons.settings_outlined),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Marca dagua',
                    onPressed:
                        isImporting ||
                            isExporting ||
                            isGeneratingCaptions ||
                            isOptimizingPreview
                        ? null
                        : onWatermarkSettings,
                    style: IconButton.styleFrom(
                      backgroundColor: TgiColors.transparent,
                      foregroundColor: TgiColors.textPrimary,
                      disabledBackgroundColor: TgiColors.transparent,
                      disabledForegroundColor: TgiColors.textSecondary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(TgiRadii.xs),
                      ),
                    ),
                    icon: const Icon(Icons.branding_watermark_outlined),
                  ),
                  const SizedBox(width: TgiSpacing.sm),
                  if (compactActions) ...[
                    IconButton(
                      tooltip: 'Importar arquivo',
                      onPressed:
                          isImporting ||
                              isExporting ||
                              isGeneratingCaptions ||
                              isOptimizingPreview
                          ? null
                          : onImportVideo,
                      style: IconButton.styleFrom(
                        backgroundColor: TgiColors.transparent,
                        foregroundColor: TgiColors.textPrimary,
                        disabledBackgroundColor: TgiColors.transparent,
                        disabledForegroundColor: TgiColors.textSecondary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(TgiRadii.xs),
                        ),
                      ),
                      icon: isImporting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.file_upload_outlined),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: exportLabel,
                      onPressed:
                          isImporting ||
                              isExporting ||
                              isGeneratingCaptions ||
                              isOptimizingPreview ||
                              !canExport
                          ? null
                          : onExport,
                      style: IconButton.styleFrom(
                        backgroundColor: TgiColors.surfacePressed,
                        foregroundColor: TgiColors.textPrimary,
                        disabledBackgroundColor: TgiColors.surfaceAlt,
                        disabledForegroundColor: TgiColors.textSecondary,
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(TgiRadii.xs),
                        ),
                      ),
                      icon: isExporting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.file_download_outlined),
                    ),
                  ] else ...[
                    OutlinedButton(
                      onPressed:
                          isImporting ||
                              isExporting ||
                              isGeneratingCaptions ||
                              isOptimizingPreview
                          ? null
                          : onImportVideo,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isImporting)
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            const Icon(Icons.file_upload_outlined),
                          const SizedBox(width: 10),
                          Text(isImporting ? 'Importando' : 'Importar mídia'),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed:
                          isImporting ||
                              isExporting ||
                              isGeneratingCaptions ||
                              isOptimizingPreview ||
                              !canExport
                          ? null
                          : onExport,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isExporting)
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            const Icon(Icons.file_download_outlined),
                          const SizedBox(width: 10),
                          Text(
                            isExporting ? 'Exportando $percent%' : exportLabel,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            if (isExporting) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: exportProgress > 0
                        ? TgiProgressBar(value: exportProgress, height: 4)
                        : const LinearProgressIndicator(),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 46,
                    child: Text(
                      '$percent%',
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (exportRemaining != null) ...[
                    const SizedBox(width: 10),
                    Text(
                      'Faltam ~${_shortDurationLabel(exportRemaining!)}',
                      key: const ValueKey('export_remaining_time'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: TgiColors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  TextButton.icon(
                    key: const ValueKey('cancel_export_button'),
                    onPressed: onCancelExport,
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Cancelar'),
                  ),
                ],
              ),
            ],
            if (isImporting) ...[
              const SizedBox(height: 8),
              Row(
                key: const ValueKey('media_import_progress'),
                children: [
                  const Expanded(child: LinearProgressIndicator()),
                  const SizedBox(width: 10),
                  Text(
                    'Preparando midia...',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: TgiColors.textMuted),
                  ),
                ],
              ),
            ],
            if (isOptimizingPreview) ...[
              const SizedBox(height: 8),
              Row(
                key: const ValueKey('preview_optimization_progress'),
                children: [
                  Expanded(
                    child: previewOptimizationProgress > 0
                        ? TgiProgressBar(
                            value: previewOptimizationProgress,
                            height: 4,
                          )
                        : const LinearProgressIndicator(),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${previewOptimizationAutomatic ? 'Otimizando em segundo plano' : 'Otimizando preview'} $previewPercent%',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: TgiColors.textMuted),
                  ),
                  if (previewOptimizationRemaining != null &&
                      previewOptimizationRemaining != Duration.zero) ...[
                    const SizedBox(width: 8),
                    Text(
                      '~${_shortDurationLabel(previewOptimizationRemaining!)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: TgiColors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: onCancelPreviewOptimization,
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Cancelar'),
                  ),
                ],
              ),
            ],
            if (isGeneratingCaptions) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: captionProgress > 0
                        ? TgiProgressBar(value: captionProgress, height: 4)
                        : const LinearProgressIndicator(),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    captionProgressMessage ?? 'Gerando legendas',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: TgiColors.textMuted),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResponsiveEditorWorkspace extends StatelessWidget {
  const _ResponsiveEditorWorkspace({
    required this.rail,
    required this.workspace,
  });

  final Widget rail;
  final Widget workspace;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                key: const ValueKey('editor_mobile_tool_rail'),
                height: 64,
                child: rail,
              ),
              const SizedBox(height: TgiSpacing.sm),
              Expanded(child: workspace),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            rail,
            const SizedBox(width: TgiSpacing.md),
            Expanded(child: workspace),
          ],
        );
      },
    );
  }
}

class _EditorToolRail extends StatelessWidget {
  const _EditorToolRail({
    required this.kenBurnsToolActive,
    required this.mediaPoolActive,
    required this.transformCropActive,
    required this.audioToolsActive,
    required this.smartCutActive,
    required this.professionalColorActive,
    required this.advancedSpeedActive,
    required this.captionsActive,
    required this.chromaKeyActive,
    required this.maskTrackingActive,
    required this.soundEffectsActive,
    required this.visualMediaActive,
    required this.transitionsActive,
    required this.enabled,
    required this.onMediaPoolSelected,
    required this.onTransformCropToggle,
    required this.onAudioToolsToggle,
    required this.onSmartCutToggle,
    required this.onProfessionalColorToggle,
    required this.onAdvancedSpeedToggle,
    required this.onKenBurnsToolToggle,
    required this.showQuickCaption,
    required this.onAddQuickCaption,
    required this.onCaptionsToggle,
    required this.onChromaKeyToggle,
    required this.onMaskTrackingToggle,
    required this.onSoundEffectsToggle,
    required this.onVisualMediaToggle,
    required this.onTransitionsToggle,
  });

  final bool kenBurnsToolActive;
  final bool mediaPoolActive;
  final bool transformCropActive;
  final bool audioToolsActive;
  final bool smartCutActive;
  final bool professionalColorActive;
  final bool advancedSpeedActive;
  final bool captionsActive;
  final bool chromaKeyActive;
  final bool maskTrackingActive;
  final bool soundEffectsActive;
  final bool visualMediaActive;
  final bool transitionsActive;
  final bool enabled;
  final VoidCallback onMediaPoolSelected;
  final VoidCallback onTransformCropToggle;
  final VoidCallback onAudioToolsToggle;
  final VoidCallback onSmartCutToggle;
  final VoidCallback onProfessionalColorToggle;
  final VoidCallback onAdvancedSpeedToggle;
  final VoidCallback onKenBurnsToolToggle;
  final bool showQuickCaption;
  final VoidCallback onAddQuickCaption;
  final VoidCallback onCaptionsToggle;
  final VoidCallback onChromaKeyToggle;
  final VoidCallback onMaskTrackingToggle;
  final VoidCallback onSoundEffectsToggle;
  final VoidCallback onVisualMediaToggle;
  final VoidCallback onTransitionsToggle;

  @override
  Widget build(BuildContext context) {
    final horizontal = MediaQuery.sizeOf(context).width < 600;
    return SizedBox(
      width: horizontal ? double.infinity : 92,
      height: horizontal ? 64 : null,
      child: DecoratedBox(
        decoration: TgiDecorations.toolRail(),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compactRail = !horizontal && constraints.maxHeight < 840;
            final buttonHeight = horizontal
                ? 46.0
                : compactRail
                ? 34.0
                : 50.0;
            final gap = horizontal
                ? 6.0
                : compactRail
                ? 3.0
                : TgiSpacing.sm;
            final railButtons = <Widget>[
              _RailButton(
                tooltip: 'Inventario de midias',
                icon: Icons.video_library_outlined,
                label: 'Midias',
                active: mediaPoolActive,
                enabled: enabled,
                height: buttonHeight,
                onPressed: onMediaPoolSelected,
              ),
              SizedBox(height: gap),
              _RailButton(
                tooltip: 'Audio Pick / inventario de audio',
                icon: Icons.library_music_outlined,
                label: 'Sons',
                active: soundEffectsActive,
                enabled: enabled,
                height: buttonHeight,
                onPressed: onSoundEffectsToggle,
              ),
              SizedBox(height: gap),
              const _RailDivider(),
              SizedBox(height: gap),
              _RailButton(
                tooltip: 'Transformar, girar, espelhar e recortar',
                icon: Icons.crop_rotate_outlined,
                label: 'Transform.',
                active: transformCropActive,
                enabled: enabled,
                height: buttonHeight,
                onPressed: onTransformCropToggle,
              ),
              SizedBox(height: gap),
              _RailButton(
                tooltip: 'Volume, fades, ruído e mixer de trilhas',
                icon: Icons.tune_outlined,
                label: 'Áudio',
                active: audioToolsActive,
                enabled: enabled,
                height: buttonHeight,
                onPressed: onAudioToolsToggle,
              ),
              SizedBox(height: gap),
              _RailButton(
                key: const ValueKey('smart_cut_rail_button'),
                tooltip: 'Detectar pausas e fechar os espaços automaticamente',
                icon: Icons.auto_fix_high_rounded,
                label: 'Corte IA',
                active: smartCutActive,
                enabled: enabled,
                height: buttonHeight,
                onPressed: onSmartCutToggle,
              ),
              SizedBox(height: gap),
              _RailButton(
                tooltip: 'Correção profissional, curvas e histograma',
                icon: Icons.gradient_outlined,
                label: 'Cor',
                active: professionalColorActive,
                enabled: enabled,
                height: buttonHeight,
                onPressed: onProfessionalColorToggle,
              ),
              SizedBox(height: gap),
              _RailButton(
                tooltip: 'Rampas, câmera lenta, congelar e reverso',
                icon: Icons.speed_outlined,
                label: 'Velocid.',
                active: advancedSpeedActive,
                enabled: enabled,
                height: buttonHeight,
                onPressed: onAdvancedSpeedToggle,
              ),
              SizedBox(height: gap),
              _RailButton(
                tooltip: kenBurnsToolActive
                    ? 'Clique no preview para marcar inicio/fim'
                    : 'Ferramenta de animacao de zoom',
                icon: Icons.center_focus_strong_outlined,
                label: 'Anim.',
                active: kenBurnsToolActive,
                enabled: enabled,
                height: buttonHeight,
                onPressed: onKenBurnsToolToggle,
              ),
              SizedBox(height: gap),
              _RailButton(
                tooltip: 'Ferramenta Chroma Key',
                icon: Icons.colorize_outlined,
                label: 'Chroma',
                active: chromaKeyActive,
                enabled: enabled,
                height: buttonHeight,
                onPressed: onChromaKeyToggle,
              ),
              SizedBox(height: gap),
              _RailButton(
                key: const ValueKey('mask_tracking_rail_button'),
                tooltip: 'Mascaras e rastreamento de movimento',
                icon: Icons.track_changes,
                label: 'Mascara',
                active: maskTrackingActive,
                enabled: enabled,
                height: buttonHeight,
                onPressed: onMaskTrackingToggle,
              ),
              SizedBox(height: gap),
              if (showQuickCaption) ...[
                _RailButton(
                  tooltip: 'Legenda r\u00E1pida',
                  icon: Icons.closed_caption_outlined,
                  label: 'Legenda',
                  enabled: enabled,
                  height: buttonHeight,
                  onPressed: onAddQuickCaption,
                ),
              ],
              SizedBox(height: gap),
              _RailButton(
                tooltip: 'Legendas automáticas',
                icon: Icons.subtitles_outlined,
                label: 'Legendas',
                active: captionsActive,
                enabled: enabled,
                height: buttonHeight,
                onPressed: onCaptionsToggle,
              ),
              SizedBox(height: gap),
              _RailButton(
                tooltip: 'Biblioteca visual',
                icon: Icons.collections_outlined,
                label: 'Visual',
                active: visualMediaActive,
                enabled: enabled,
                height: buttonHeight,
                onPressed: onVisualMediaToggle,
              ),
              SizedBox(height: gap),
              _RailButton(
                tooltip: 'Transicoes',
                icon: Icons.movie_filter_outlined,
                label: 'Trans.',
                active: transitionsActive,
                enabled: enabled,
                height: buttonHeight,
                onPressed: onTransitionsToggle,
              ),
              SizedBox(height: gap),
              const _RailDivider(),
            ];
            final content = horizontal
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final item in railButtons)
                          if (item is _RailButton) ...[
                            item,
                            SizedBox(width: gap),
                          ],
                      ],
                    ),
                  )
                : compactRail
                ? SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: railButtons,
                    ),
                  )
                : Column(
                    children: [
                      ...railButtons,
                      const Spacer(),
                      const _RailBadge(),
                    ],
                  );
            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: horizontal ? 6 : 0,
                vertical: horizontal || compactRail ? 6 : 8,
              ),
              child: content,
            );
          },
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onPressed,
    this.active = false,
    this.height = 50,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;
  final bool active;
  final double height;

  @override
  Widget build(BuildContext context) {
    final veryCompact = height < 38;
    final showLabel = MediaQuery.textScalerOf(context).scale(10) < 15;
    final iconSize = veryCompact ? 16.0 : (height < 46 ? 18.0 : 20.0);
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: active ? TgiColors.accentSoft : TgiColors.textMuted,
      fontSize: veryCompact ? 9 : 10,
      fontWeight: FontWeight.w800,
      height: 1,
    );
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(TgiRadii.lg),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 76,
          height: height,
          padding: EdgeInsets.symmetric(
            horizontal: 6,
            vertical: veryCompact ? 2 : 5,
          ),
          decoration: active
              ? TgiDecorations.activeControl(radius: TgiRadii.lg)
              : BoxDecoration(
                  color: TgiColors.surface.withValues(alpha: 0.78),
                  border: Border.all(color: TgiColors.borderSubtle),
                  borderRadius: BorderRadius.circular(TgiRadii.lg),
                ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              active
                  ? TgiAccentIcon(icon, size: iconSize)
                  : Icon(icon, size: iconSize, color: TgiColors.textMuted),
              if (showLabel) ...[
                SizedBox(height: veryCompact ? 1 : 2),
                active
                    ? TgiAccentText(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: labelStyle ?? const TextStyle(fontSize: 10),
                      )
                    : Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: labelStyle,
                      ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RailDivider extends StatelessWidget {
  const _RailDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 28, height: 1, color: TgiColors.borderStrong);
  }
}

class _RailBadge extends StatelessWidget {
  const _RailBadge();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: TgiSpacing.xs),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: TgiColors.accentMuted),
          borderRadius: BorderRadius.circular(TgiRadii.sm),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: TgiAccentText(
            'TGI',
            style: TgiTextStyles.display(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderDivider extends StatelessWidget {
  const _HeaderDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: TgiSpacing.sm),
      child: Container(width: 1, height: 28, color: TgiColors.borderStrong),
    );
  }
}

const _playbackSpeedOptions = <double>[0.25, 0.5, 1, 1.5, 2, 3, 4];
const _customPlaybackSpeedMenuValue = -1.0;

class _PreviewEditingActions extends StatelessWidget {
  const _PreviewEditingActions({
    required this.speed,
    required this.speedEnabled,
    required this.cutActive,
    required this.enabled,
    required this.deleteEnabled,
    required this.onSpeedChanged,
    required this.onCutPressed,
    required this.onDeletePressed,
    required this.onTextPressed,
  });

  final double speed;
  final bool speedEnabled;
  final bool cutActive;
  final bool enabled;
  final bool deleteEnabled;
  final ValueChanged<double> onSpeedChanged;
  final VoidCallback onCutPressed;
  final VoidCallback onDeletePressed;
  final VoidCallback onTextPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PlaybackSpeedMenu(
          speed: speed,
          enabled: speedEnabled,
          onChanged: onSpeedChanged,
        ),
        const SizedBox(width: 4),
        _PreviewToolButton(
          tooltip: cutActive ? 'Sair do modo corte' : 'Ferramenta de corte',
          icon: Icons.content_cut,
          label: 'Corte',
          active: cutActive,
          enabled: enabled,
          onPressed: onCutPressed,
        ),
        const SizedBox(width: 4),
        _PreviewToolButton(
          tooltip: 'Excluir partes selecionadas',
          icon: Icons.delete_outline,
          label: 'Excluir',
          enabled: deleteEnabled,
          onPressed: onDeletePressed,
        ),
        const SizedBox(width: 4),
        _PreviewToolButton(
          tooltip: 'Adicionar texto',
          icon: Icons.title,
          label: 'Texto',
          enabled: enabled,
          onPressed: onTextPressed,
        ),
      ],
    );
  }
}

class _PreviewToolButton extends StatelessWidget {
  const _PreviewToolButton({
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onPressed,
    this.active = false,
  });

  final String tooltip;
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        height: 32,
        child: OutlinedButton.icon(
          onPressed: enabled ? onPressed : null,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            backgroundColor: active
                ? TgiColors.surfacePressed
                : TgiColors.surfaceAlt,
            foregroundColor: active
                ? TgiColors.accentSoft
                : TgiColors.textPrimary,
            side: BorderSide(
              color: active ? TgiColors.accentMuted : TgiColors.border,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          icon: Icon(icon, size: 15),
          label: Text(label, style: const TextStyle(fontSize: 12)),
        ),
      ),
    );
  }
}

class _PreviewOptimizeButton extends StatelessWidget {
  const _PreviewOptimizeButton({
    required this.isImporting,
    required this.isExporting,
    required this.isOptimizingPreview,
    required this.progress,
    required this.remaining,
    required this.isAutomatic,
    required this.usesProxy,
    required this.canOptimizePreview,
    required this.onPressed,
    required this.onCancel,
  });

  final bool isImporting;
  final bool isExporting;
  final bool isOptimizingPreview;
  final double progress;
  final Duration? remaining;
  final bool isAutomatic;
  final bool usesProxy;
  final bool canOptimizePreview;
  final VoidCallback onPressed;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final percent = (progress.clamp(0.0, 1.0) * 100).round();
    final remainingLabel = remaining == null || remaining == Duration.zero
        ? ''
        : ' · ~${formatDuration(remaining!)}';
    final label = isOptimizingPreview
        ? '${isAutomatic ? 'AUTO ' : ''}$percent%'
        : usesProxy
        ? 'PROXY'
        : 'ORIGINAL';
    return Tooltip(
      message: isOptimizingPreview
          ? 'Criando proxy $percent%$remainingLabel · clique para cancelar'
          : usesProxy
          ? 'Preview usando proxy leve · clique para recriar'
          : 'Preview usando arquivo original · clique para otimizar',
      child: SizedBox(
        height: 32,
        child: OutlinedButton.icon(
          key: const Key('preview_proxy_control'),
          onPressed: isOptimizingPreview
              ? onCancel
              : isImporting || isExporting || !canOptimizePreview
              ? null
              : onPressed,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            backgroundColor: TgiColors.surfaceAlt,
            foregroundColor: isOptimizingPreview || usesProxy
                ? TgiColors.accentSoft
                : TgiColors.textSecondary,
            side: BorderSide(
              color: isOptimizingPreview || usesProxy
                  ? TgiColors.accentMuted
                  : TgiColors.border,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          icon: isOptimizingPreview
              ? SizedBox.square(
                  dimension: 15,
                  child: CircularProgressIndicator(
                    value: progress > 0 ? progress : null,
                    strokeWidth: 2,
                  ),
                )
              : Icon(
                  usesProxy ? Icons.bolt_rounded : Icons.speed_outlined,
                  size: 16,
                ),
          label: Text(
            label,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}

class _PlaybackSpeedMenu extends StatelessWidget {
  const _PlaybackSpeedMenu({
    required this.speed,
    required this.enabled,
    required this.onChanged,
  });

  final double speed;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = _playbackSpeedLabel(speed);
    return PopupMenuButton<double>(
      enabled: enabled,
      tooltip: enabled ? 'Velocidade do clipe' : 'Selecione um clipe de video',
      onSelected: (value) {
        if (value == _customPlaybackSpeedMenuValue) {
          unawaited(_showCustomSpeedDialog(context));
          return;
        }
        onChanged(value);
      },
      itemBuilder: (context) => [
        for (final option in _playbackSpeedOptions)
          PopupMenuItem<double>(
            value: option,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 22,
                  child: option == speed
                      ? const Icon(Icons.check, size: 18)
                      : const SizedBox.shrink(),
                ),
                const SizedBox(width: 8),
                Text(_playbackSpeedLabel(option)),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<double>(
          value: _customPlaybackSpeedMenuValue,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune, size: 18),
              SizedBox(width: 10),
              Text('Personalizada...'),
            ],
          ),
        ),
      ],
      child: Opacity(
        opacity: enabled ? 1 : 0.55,
        child: Container(
          height: 32,
          constraints: const BoxConstraints(minWidth: 70),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: TgiColors.surfaceAlt,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: TgiColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.speed_outlined,
                size: 16,
                color: enabled
                    ? TgiColors.textPrimary
                    : TgiColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: enabled
                      ? TgiColors.textPrimary
                      : TgiColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCustomSpeedDialog(BuildContext context) async {
    final controller = TextEditingController(text: _speedInputValue(speed));
    String? errorText;
    final result = await showDialog<double>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Velocidade'),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
              ],
              decoration: InputDecoration(
                labelText: 'Multiplicador',
                suffixText: 'x',
                errorText: errorText,
              ),
              onSubmitted: (_) {
                final parsed = _parsePlaybackSpeed(controller.text);
                if (parsed == null) {
                  setState(() => errorText = 'Use um valor entre 0.25 e 4.');
                  return;
                }
                Navigator.of(context).pop(parsed);
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  final parsed = _parsePlaybackSpeed(controller.text);
                  if (parsed == null) {
                    setState(() => errorText = 'Use um valor entre 0.25 e 4.');
                    return;
                  }
                  Navigator.of(context).pop(parsed);
                },
                child: const Text('Aplicar'),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    if (result != null) {
      onChanged(result);
    }
  }
}

String _playbackSpeedLabel(double speed) {
  if (speed == 0.25) return '0.25x';
  if (speed == 0.5) return '0.5x';
  if (speed == 1.5) return '1.5x';
  if (speed == speed.roundToDouble()) {
    return '${speed.toStringAsFixed(0)}x';
  }
  return '${speed.toStringAsFixed(2)}x';
}

Duration _panelTimelineMax(Duration timelineDuration, domain.Clip clip) {
  final maxMs = math.max(
    math.max(
      const Duration(seconds: 30).inMilliseconds,
      timelineDuration.inMilliseconds,
    ),
    clip.timelineEnd.inMilliseconds + const Duration(seconds: 5).inMilliseconds,
  );
  return Duration(milliseconds: maxMs);
}

String _formatPanelDuration(Duration duration) {
  final milliseconds = duration.inMilliseconds.remainder(1000);
  if (milliseconds == 0) {
    return formatDuration(duration);
  }
  return '${formatDuration(duration)}.${milliseconds.toString().padLeft(3, '0')}';
}

String _shortDurationLabel(Duration duration) {
  final totalSeconds = math.max(0, duration.inSeconds);
  if (totalSeconds < 60) return '${math.max(1, totalSeconds)}s';
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  if (minutes < 60) return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  final hours = minutes ~/ 60;
  return '${hours}h ${minutes % 60}m';
}

IconData _clipTypeIcon(TrackType type) {
  switch (type) {
    case TrackType.video:
      return Icons.movie_outlined;
    case TrackType.audio:
      return Icons.volume_up_outlined;
    case TrackType.image:
      return Icons.image_outlined;
    case TrackType.text:
      return Icons.title;
  }
}

String _clipTypeLabel(TrackType type) {
  switch (type) {
    case TrackType.video:
      return 'Video';
    case TrackType.audio:
      return 'Audio';
    case TrackType.image:
      return 'Imagem';
    case TrackType.text:
      return 'Texto';
  }
}

String _speedInputValue(double speed) {
  if (speed == speed.roundToDouble()) {
    return speed.toStringAsFixed(0);
  }
  return speed
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

double? _parsePlaybackSpeed(String value) {
  final parsed = double.tryParse(value.replaceAll(',', '.'));
  if (parsed == null || parsed < 0.25 || parsed > 4) {
    return null;
  }
  return parsed;
}

class _TgiEditorWordmark extends StatelessWidget {
  const _TgiEditorWordmark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TgiAccentText(
          'TGI',
          style: TgiTextStyles.display(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(width: 7),
        Text(
          'EDITOR',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TgiTextStyles.display(
            color: TgiColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

class _WorkspaceDivider extends StatelessWidget {
  const _WorkspaceDivider({
    required this.axis,
    required this.onDragUpdate,
    required this.onReset,
  });

  final Axis axis;
  final GestureDragUpdateCallback onDragUpdate;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final vertical = axis == Axis.vertical;
    return Tooltip(
      message: 'Arraste para redimensionar. Duplo clique para restaurar.',
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: vertical
            ? SystemMouseCursors.resizeColumn
            : SystemMouseCursors.resizeRow,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: vertical ? onDragUpdate : null,
          onVerticalDragUpdate: vertical ? null : onDragUpdate,
          onDoubleTap: onReset,
          child: SizedBox(
            width: vertical ? _workspaceDividerExtent : double.infinity,
            height: vertical ? double.infinity : _workspaceDividerExtent,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: vertical ? 2 : 28,
                height: vertical ? 28 : 2,
                decoration: BoxDecoration(
                  color: TgiColors.borderStrong,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.child,
    this.icon,
    this.glow = false,
    this.showHeader = true,
    this.accentColor,
  });

  final String title;
  final Widget child;
  final IconData? icon;
  final bool glow;
  final bool showHeader;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final accentColor = this.accentColor ?? TgiColors.accent;
    return Container(
      decoration: BoxDecoration(
        color: TgiColors.surfacePanel,
        border: Border.all(color: glow ? TgiColors.accent : TgiColors.border),
        borderRadius: BorderRadius.circular(TgiRadii.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader)
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: TgiSpacing.md),
              decoration: BoxDecoration(
                color: TgiColors.surfaceRail,
                border: const Border(
                  bottom: BorderSide(color: TgiColors.borderStrong),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 22,
                    decoration: BoxDecoration(
                      color: TgiColors.accent,
                      borderRadius: BorderRadius.circular(TgiRadii.pill),
                    ),
                  ),
                  const SizedBox(width: TgiSpacing.sm),
                  if (icon != null) ...[
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.12),
                        border: Border.all(
                          color: accentColor.withValues(alpha: 0.48),
                        ),
                        borderRadius: BorderRadius.circular(TgiRadii.sm),
                      ),
                      child: TgiAccentIcon(icon!, size: TgiIconSizes.sm),
                    ),
                    const SizedBox(width: TgiSpacing.sm),
                  ],
                  Expanded(
                    child: TgiAccentText(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TgiTextStyles.display(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
