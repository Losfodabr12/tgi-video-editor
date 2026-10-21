import 'dart:convert';

/// Wire errors are deliberately independent of widgets and HTTP.
class CommandError implements Exception {
  const CommandError(this.code, this.message, [this.details = const {}]);
  final String code;
  final String message;
  final Map<String, Object?> details;
  Map<String, Object?> toJson() => {
    'code': code,
    'message': message,
    'details': details,
  };
  @override
  String toString() => '$code: $message';
}

class EditorCommand {
  EditorCommand(this.name, Map<String, Object?> arguments, {this.baseRevision})
    : arguments = Map.unmodifiable(
        jsonDecode(jsonEncode(arguments)) as Map<String, dynamic>,
      );
  factory EditorCommand.fromJson(Map<String, dynamic> json) {
    if (json['command'] is! String ||
        json['arguments'] is! Map ||
        (json['base_revision'] != null && json['base_revision'] is! int)) {
      throw const CommandError(
        'invalid_command',
        'Use command (string), arguments (object) e base_revision (integer).',
      );
    }
    return EditorCommand(
      json['command'] as String,
      Map<String, Object?>.from(json['arguments'] as Map),
      baseRevision: json['base_revision'] as int?,
    );
  }
  final String name;
  final Map<String, Object?> arguments;
  final int? baseRevision;
  Map<String, Object?> toJson() => {
    'command': name,
    'arguments': arguments,
    if (baseRevision != null) 'base_revision': baseRevision,
  };
}

void checkRevision(int? base, int current) {
  if (base != current) {
    throw CommandError(
      'revision_conflict',
      'Leia get_project e refaça o plano usando a revisão atual.',
      {'base_revision': base, 'current_revision': current},
    );
  }
}

/// Small JSON-schema subset used by both the engine and tool catalogue.
/// Rejecting unknown properties avoids silently ignoring misspelled edits.
void validateArguments(
  Map<String, Object?> values,
  Map<String, dynamic> schema, [
  String path = 'arguments',
]) {
  final properties = schema['properties'] as Map<String, dynamic>? ?? {};
  for (final key in schema['required'] as List? ?? const []) {
    if (!values.containsKey(key)) {
      throw CommandError('invalid_argument', 'Falta $path.$key.', {
        'required': schema['required'],
      });
    }
  }
  for (final entry in values.entries) {
    final field = properties[entry.key] as Map<String, dynamic>?;
    if (field == null) {
      throw CommandError(
        'invalid_argument',
        'Campo desconhecido: $path.${entry.key}.',
        {'valid_fields': properties.keys.toList()},
      );
    }
    validateValue(entry.value, field, '$path.${entry.key}');
  }
}

void validateValue(Object? value, Map<String, dynamic> field, String path) {
  if (field['oneOf'] is List) {
    var matched = 0;
    for (final alternative in field['oneOf'] as List) {
      try {
        validateValue(value, alternative as Map<String, dynamic>, path);
        matched++;
      } on CommandError {
        /* Report the union rather than one arbitrary branch. */
      }
    }
    if (matched != 1) {
      throw CommandError(
        'invalid_argument',
        'Comando inválido em $path. Consulte tools/list para o schema exato.',
        {'matching_schemas': matched},
      );
    }
    return;
  }
  final valid = switch (field['type']) {
    'string' => value is String,
    'integer' => value is int,
    'number' => value is num && value.isFinite,
    'boolean' => value is bool,
    'array' => value is List,
    'object' => value is Map<String, Object?>,
    _ => false,
  };
  if (!valid) {
    throw CommandError('invalid_argument', 'Tipo inválido em $path.', {
      'schema': field,
      'received': value,
    });
  }
  if (field['enum'] is List && !(field['enum'] as List).contains(value)) {
    throw CommandError('invalid_argument', 'Valor inválido em $path.', {
      'valid_values': field['enum'],
      'received': value,
    });
  }
  if (value is num &&
      ((field['minimum'] is num && value < (field['minimum'] as num)) ||
          (field['maximum'] is num && value > (field['maximum'] as num)))) {
    throw CommandError('out_of_range', 'Valor fora do intervalo em $path.', {
      'schema': field,
      'received': value,
    });
  }
  if (value is String &&
      (value.trim().length < (field['minLength'] as int? ?? 0) ||
          value.length > (field['maxLength'] as int? ?? 100000))) {
    throw CommandError('invalid_argument', 'Comprimento inválido em $path.', {
      'schema': field,
    });
  }
  if (value is List) {
    if (value.length < (field['minItems'] as int? ?? 0) ||
        value.length > (field['maxItems'] as int? ?? 1000)) {
      throw CommandError('invalid_argument', 'Quantidade inválida em $path.', {
        'schema': field,
      });
    }
    for (var i = 0; i < value.length; i++) {
      validateValue(
        value[i],
        field['items'] as Map<String, dynamic>,
        '$path[$i]',
      );
    }
  }
  if (value is Map<String, Object?>) validateArguments(value, field, path);
}
