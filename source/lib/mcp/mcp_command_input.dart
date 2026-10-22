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
