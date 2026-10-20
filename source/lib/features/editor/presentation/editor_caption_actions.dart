part of 'editor_screen.dart';

extension _CaptionActions on _EditorScreenState {
  Future<void> _importSrt() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Importar legendas SRT',
      type: FileType.custom,
      allowedExtensions: const ['srt'],
    );
    if (!mounted || result == null || result.files.single.path == null) return;
    try {
      final source = await File(result.files.single.path!).readAsString();
      if (mounted) _controller.importSrt(source);
    } catch (error) {
      if (mounted) {
        _showEditorNotification(
          'Falha ao importar SRT: $error',
          tone: TgiNotificationTone.error,
        );
      }
    }
    _restoreEditorShortcutFocus();
  }

  Future<void> _editCaptionStyle() async {
    final captions = _controller.generatedCaptionClips;
    if (captions.isEmpty) return;
    final style = await showDialog<CaptionStyle>(
      context: context,
      builder: (_) =>
          CaptionStyleDialog(initial: CaptionStyle.fromClip(captions.first)),
    );
    if (mounted && style != null) _controller.applyCaptionStyle(style);
    _restoreEditorShortcutFocus();
  }
}
