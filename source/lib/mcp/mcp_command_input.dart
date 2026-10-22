import '../core/commands/command_engine.dart';

/// Batch arguments use the same command schemas as individual edits/the engine.
List<EditorCommand> parseMcpCommands(List values) {
  final commands = <EditorCommand>[];
  for (var index = 0; index < values.length; index++) {
    final command = EditorCommand.fromJson(
      Map<String, dynamic>.from(values[index] as Map),
    );
    final definition = commandCatalog[command.name];
    if (definition == null || ['undo', 'redo'].contains(command.name)) {
      throw CommandError(
        'invalid_command',
        'Tool de edição inválida no lote.',
        {
          'command_index': index,
          'tool': command.name,
          'valid_tools': commandCatalog.keys
              .where((n) => !['undo', 'redo', 'remap_timeline'].contains(n))
              .toList(),
        },
      );
    }
    try {
      validateArguments(command.arguments, definition.schema);
    } on CommandError catch (error) {
      throw commandInputError(error, command.name, index: index);
    }
    commands.add(command);
  }
  return commands;
}

CommandError commandInputError(CommandError error, String name, {int? index}) {
  final definition = commandCatalog[name];
  if (definition == null) return error;
  return CommandError(error.code, error.message, {
    ...error.details,
    'tool': name,
    'command_index': ?index,
    'expected_schema': definition.schema,
    'example': {'tool': name, 'arguments': _minimalValue(definition.schema)},
  });
}

/// Envelope validation may fail before a batch item can be parsed (for example,
/// arguments is a string). Keep that error and attach the selected tool's help.
CommandError mcpInputError(
  CommandError error,
  String tool,
  Map<String, Object?> arguments,
) {
  var name = error.details['command'] as String? ?? tool;
  var index = error.details['command_index'] as int?;
  if (['preview_plan', 'apply_commands'].contains(tool)) {
    final path = RegExp(
      r'arguments\.commands\[(\d+)\]',
    ).firstMatch(error.message);
    index ??= path == null ? null : int.tryParse(path.group(1)!);
    final commands = arguments['commands'];
    if (commands is List && index != null && index < commands.length) {
      final item = commands[index];
      if (item is Map) {
        final selected = item['tool'] ?? item['command'];
        if (selected is String && !['undo', 'redo'].contains(selected)) {
          name = selected;
        }
      }
    }
  }
  return commandInputError(error, name, index: index);
}

Object? _minimalValue(Map<String, dynamic> schema) {
  if (schema['enum'] is List) return (schema['enum'] as List).first;
  return switch (schema['type']) {
    'object' => {
      for (final key in schema['required'] as List? ?? const [])
        key as String: _minimalValue(
          (schema['properties'] as Map)[key] as Map<String, dynamic>,
        ),
    },
    'array' => List.generate(
      schema['minItems'] as int? ?? 0,
      (_) => _minimalValue(schema['items'] as Map<String, dynamic>),
    ),
    'number' || 'integer' => schema['minimum'] ?? 0,
    'boolean' => false,
    _ => 'id_ou_texto',
  };
}
