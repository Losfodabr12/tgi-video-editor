import '../../domain/models/project.dart';
import 'command_engine.dart';

/// Evaluate immutable snapshots before publishing any change.
class CommandTransaction {
  const CommandTransaction();
  TgiProject evaluate(
    TgiProject project,
    List<EditorCommand> commands, {
    required int revision,
  }) {
    if (commands.isEmpty || commands.length > 500) {
      throw const CommandError(
        'invalid_batch',
        'Uma transação aceita de 1 a 500 comandos.',
      );
    }
    var next = project;
    for (var index = 0; index < commands.length; index++) {
      final command = commands[index];
      if (command.name == 'undo' || command.name == 'redo') {
        throw const CommandError(
          'invalid_batch',
          'Undo/redo precisam ser chamadas individuais.',
        );
      }
      if (command.baseRevision != null) {
        checkRevision(command.baseRevision, revision);
      }
      try {
        next = const CommandEngine().apply(next, command);
      } on CommandError catch (e) {
        throw CommandError(e.code, e.message, {
          ...e.details,
          'command_index': index,
          'command': command.name,
        });
      }
    }
    return next;
  }
}
