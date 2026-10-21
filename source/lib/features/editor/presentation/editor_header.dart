part of 'editor_screen.dart';

class _EditorHeader extends StatelessWidget {
  const _EditorHeader({
    this.onOpenMcpSettings,
    this.onEmergencyStop,
    this.aiRunning = false,
    this.aiConnected = false,
    this.onToggleLibrary,
    this.onToggleInspector,
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

  final VoidCallback? onOpenMcpSettings, onEmergencyStop;
  final bool aiRunning, aiConnected;
  final VoidCallback? onToggleLibrary, onToggleInspector;
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
    final busy =
        isImporting ||
        isExporting ||
        isGeneratingCaptions ||
        isOptimizingPreview;
    Widget command(String tooltip, IconData icon, VoidCallback? action) =>
        SizedBox(
          width: 32,
          height: 30,
          child: IconButton(
            tooltip: tooltip,
            padding: EdgeInsets.zero,
            icon: Icon(icon, size: 17),
            onPressed: action,
          ),
        );
    PopupMenuEntry<String> item(
      String value,
      String title, [
      String shortcut = '',
      bool enabled = true,
    ]) => PopupMenuItem(
      value: value,
      enabled: enabled,
      height: 34,
      child: Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 12))),
          if (shortcut.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Text(
                shortcut,
                style: const TextStyle(
                  fontSize: 10,
                  color: TgiColors.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
    Widget menu(
      String title,
      List<PopupMenuEntry<String>> items,
      void Function(String) action,
    ) => PopupMenuButton<String>(
      tooltip: title,
      onSelected: action,
      itemBuilder: (_) => items,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Text(
          title,
          style: const TextStyle(fontSize: 12, color: TgiColors.textSecondary),
        ),
      ),
    );
    return ColoredBox(
      color: TgiColors.surfacePanel,
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  if (Navigator.of(context).canPop())
                    command('Voltar', Icons.arrow_back, onBack),
                  const Text(
                    AppIdentity.shortName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (MediaQuery.sizeOf(context).width >= 880)
                    const Text(
                      AppIdentity.tagline,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.1,
                        color: TgiColors.textMuted,
                      ),
                    ),
                  const SizedBox(width: 16),
                  menu(
                    'Arquivo',
                    [
                      item('open', 'Abrir projeto', 'Ctrl+O', !busy),
                      item('save', 'Salvar projeto', 'Ctrl+S', !busy),
                      item('projects', 'Projeto, versões e modelos'),
                      item('watermark', 'Marca-d’água'),
                      item('shortcuts', 'Atalhos do teclado'),
                      item('mcp', 'Configurações de IA (MCP)'),
                    ],
                    (value) {
                      switch (value) {
                        case 'open':
                          onLoadProject();
                        case 'save':
                          onSaveProject();
                        case 'projects':
                          onProjectTools?.call();
                        case 'watermark':
                          onWatermarkSettings();
                        case 'shortcuts':
                          onOpenKeyboardSettings();
                        case 'mcp':
                          onOpenMcpSettings?.call();
                      }
                    },
                  ),
                  if (MediaQuery.sizeOf(context).width >= 880)
                    menu(
                      'Editar',
                      [
                        item('undo', 'Desfazer', 'Ctrl+Z', canUndo && !busy),
                        item(
                          'redo',
                          'Refazer',
                          'Ctrl+Shift+Z',
                          canRedo && !busy,
                        ),
                        item('copy', 'Copiar', 'Ctrl+C', canCopy),
                        item('paste', 'Colar', 'Ctrl+V', canPaste),
                        item('duplicate', 'Duplicar', 'Ctrl+D', canDuplicate),
                      ],
                      (value) {
                        switch (value) {
                          case 'undo':
                            onUndo();
                          case 'redo':
                            onRedo();
                          case 'copy':
                            onCopy();
                          case 'paste':
                            onPaste();
                          case 'duplicate':
                            onDuplicate();
                        }
                      },
                    ),
                  menu(
                    'Exibir',
                    [
                      item('library', 'Mostrar / ocultar biblioteca'),
                      item('inspector', 'Mostrar / ocultar inspetor'),
                      item('reset', 'Restaurar layout'),
                    ],
                    (value) {
                      switch (value) {
                        case 'library':
                          onToggleLibrary?.call();
                        case 'inspector':
                          onToggleInspector?.call();
                        case 'reset':
                          onResetWorkspaceLayout();
                      }
                    },
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        projectName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: TgiColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  if (aiRunning) ...[
                    TextButton.icon(
                      onPressed: onOpenMcpSettings,
                      icon: Icon(
                        Icons.smart_toy_outlined,
                        size: 15,
                        color: aiConnected ? Colors.green : null,
                      ),
                      label: Text(
                        aiConnected ? 'IA conectada' : 'IA aguardando',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Desligar IA agora',
                      onPressed: onEmergencyStop,
                      icon: const Icon(
                        Icons.stop_circle_outlined,
                        size: 18,
                        color: Colors.redAccent,
                      ),
                    ),
                  ],
                  command(
                    'Desfazer · Ctrl+Z',
                    Icons.undo,
                    canUndo && !busy ? onUndo : null,
                  ),
                  command(
                    'Refazer · Ctrl+Shift+Z',
                    Icons.redo,
                    canRedo && !busy ? onRedo : null,
                  ),
                  command(
                    'Salvar projeto',
                    Icons.save_outlined,
                    busy ? null : onSaveProject,
                  ),
                  if (MediaQuery.sizeOf(context).width >= 900)
                    command(
                      'Biblioteca',
                      Icons.video_library_outlined,
                      onToggleLibrary,
                    ),
                  if (MediaQuery.sizeOf(context).width >= 900)
                    command('Inspetor', Icons.tune, onToggleInspector),
                  const SizedBox(width: 8),
                  if (MediaQuery.sizeOf(context).width >= 900)
                    TextButton.icon(
                      onPressed: busy ? null : onImportVideo,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Importar'),
                    )
                  else
                    command(
                      'Importar mídia',
                      Icons.add,
                      busy ? null : onImportVideo,
                    ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: canExport && !busy ? onExport : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      minimumSize: const Size(0, 30),
                      textStyle: TgiTextStyles.control,
                    ),
                    icon: const Icon(Icons.upload_rounded, size: 16),
                    label: Text(exportLabel),
                  ),
                ],
              ),
            ),
          ),
          if (busy)
            SizedBox(
              height: 28,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Text(
                    isImporting
                        ? 'Importando mídia…'
                        : isExporting
                        ? 'Exportando · ${(exportProgress * 100).round()}%'
                        : isOptimizingPreview
                        ? 'Preparando preview…'
                        : captionProgressMessage ?? 'Gerando legendas…',
                    style: const TextStyle(
                      fontSize: 11,
                      color: TgiColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      value: isImporting
                          ? null
                          : isExporting
                          ? exportProgress
                          : isOptimizingPreview
                          ? previewOptimizationProgress
                          : captionProgress,
                    ),
                  ),
                  if (isExporting)
                    TextButton(
                      key: const ValueKey('cancel_export_button'),
                      onPressed: onCancelExport,
                      child: const Text('Cancelar'),
                    ),
                  if (isOptimizingPreview)
                    TextButton(
                      onPressed: onCancelPreviewOptimization,
                      child: const Text('Cancelar'),
                    ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          const Divider(height: 1, color: TgiColors.borderSubtle),
        ],
      ),
    );
  }
}
