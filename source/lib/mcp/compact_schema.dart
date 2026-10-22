import 'dart:convert';

/// Intern repeated schema nodes locally. Two color fields share a definition
/// even when its overhead exceeds the saving; other nodes must save bytes.
/// References never leave this inputSchema; command validators stay unchanged.
Map<String, dynamic> compactSchema(Map<String, dynamic> schema) {
  var result = jsonDecode(jsonEncode(schema)) as Map<String, dynamic>;
  final definitions = <String, dynamic>{};
  while (true) {
    final counts = <String, int>{};
    void count(Object? node, {bool root = false}) {
      if (node is Map<String, dynamic>) {
        if (!root && node.containsKey('type') && !node.containsKey(r'$ref')) {
          final key = jsonEncode(node);
          counts[key] = (counts[key] ?? 0) + 1;
        }
        for (final entry in node.entries) {
          if (entry.key != r'$defs') count(entry.value);
        }
      } else if (node is List) {
        for (final child in node) {
          count(child);
        }
      }
    }

    count(result, root: true);
    final candidates = counts.keys.where((key) => counts[key]! > 1).toList()
      ..sort((a, b) {
        int saving(String key) =>
            (utf8.encode(key).length - 25) * (counts[key]! - 1);
        return saving(b).compareTo(saving(a));
      });
    Map<String, dynamic>? smaller;
    for (final key in candidates) {
      final name = 's${definitions.length}';
      final reference = {r'$ref': '#/\$defs/$name'};
      Object? replace(Object? node) {
        if (node is Map<String, dynamic>) {
          if (jsonEncode(node) == key) return reference;
          return {
            for (final entry in node.entries)
              entry.key: entry.key == r'$defs'
                  ? entry.value
                  : replace(entry.value),
          };
        }
        if (node is List) return node.map(replace).toList();
        return node;
      }

      final proposed = replace(result) as Map<String, dynamic>;
      proposed[r'$defs'] = {...definitions, name: jsonDecode(key)};
      final candidate = jsonDecode(key) as Map;
      final sharedColor =
          candidate['type'] == 'integer' && candidate['maximum'] == 0xFFFFFFFF;
      if (sharedColor ||
          utf8.encode(jsonEncode(proposed)).length <
              utf8.encode(jsonEncode(result)).length) {
        definitions[name] = jsonDecode(key);
        smaller = proposed;
        break;
      }
    }
    if (smaller == null) return result;
    result = smaller;
  }
}
