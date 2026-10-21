part of 'editor_controller.dart';

extension EditorCommandDispatch on EditorController {
  String? get undoLabel => _history.undoLabel;
  String? get redoLabel => _history.redoLabel;
  TgiProject previewHistoryCommand(String name) {
    final stack = name == 'undo' ? _history.undoStack : _history.redoStack;
    if (stack.isEmpty) {
      throw const CommandError('empty_history', 'Histórico vazio.');
    }
    return stack.last;
  }

  bool get isCommandEditBusy =>
      _disposed ||
      _trimPreviewBaseProject != null ||
      _interactiveEditBaseProject != null;

  /// Synchronous commit serializes requests on the app isolate.
  Map<String, Object?> executeCommands(
    List<EditorCommand> commands, {
    required int baseRevision,
    String label = 'IA: edição',
  }) {
    checkRevision(baseRevision, projectRevision);
    if (isCommandEditBusy) {
      throw const CommandError(
        'editor_busy',
        'Aguarde o fim do gesto de edição ou reabra o editor.',
      );
    }
    if (commands.length == 1 &&
        (commands.single.name == 'undo' || commands.single.name == 'redo')) {
      final command = commands.single;
      validateArguments(
        command.arguments,
        commandCatalog[command.name]!.schema,
      );
      if (command.baseRevision != null) {
        checkRevision(command.baseRevision, projectRevision);
      }
      if (command.name == 'undo' ? !canUndo : !canRedo) {
        throw CommandError(
          'empty_history',
          'Não há ação para ${command.name}.',
        );
      }
      command.name == 'undo' ? undo() : redo();
      return {'revision': projectRevision, 'label': label, 'command_count': 1};
    }
    final next = const CommandTransaction().evaluate(
      _project,
      commands,
      revision: projectRevision,
    );
    return commitCommandProject(
      next,
      baseRevision: baseRevision,
      label: label,
      commandCount: commands.length,
    );
  }

  Map<String, Object?> commitCommandProject(
    TgiProject next, {
    required int baseRevision,
    required String label,
    int commandCount = 1,
    FfmpegExportSettings? exportSettings,
  }) {
    checkRevision(baseRevision, projectRevision);
    if (isCommandEditBusy) {
      throw const CommandError(
        'editor_busy',
        'Aguarde o fim do gesto de edição.',
      );
    }
    if (next.id != _project.id) {
      throw const CommandError(
        'project_changed',
        'O projeto aberto mudou. Gere outro plano.',
      );
    }
    final changed = !identical(next, _project);
    if (changed) {
      _history.record(_project, label: label);
      _project = next;
      if (exportSettings != null) {
        _commandExportSettings = exportSettings;
        _snapshotExportSettings[next] = exportSettings;
      }
      _resetTransientTimelineState();
      _statusMessage = label;
      notifyListeners();
    }
    return {
      'revision': projectRevision,
      'label': label,
      'command_count': commandCount,
      'changed': changed,
    };
  }
}
