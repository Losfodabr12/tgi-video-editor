import 'dart:convert';
import 'dart:io';
import '../source/lib/mcp/mcp_tool_catalog.dart';

void main(List<String> arguments) {
  if (arguments.length != 3) {
    throw ArgumentError(
      'Usage: dart tool/mcp_catalog_sizes.dart <before.json> <after.json> <metrics.json>',
    );
  }
  int bytes(Object? value) => utf8.encode(jsonEncode(value)).length;
  List<Map<String, dynamic>> tools(File file) =>
      ((jsonDecode(file.readAsStringSync()) as Map)['result']['tools'] as List)
          .cast<Map<String, dynamic>>();
  final beforeFile = File(arguments[0]), afterFile = File(arguments[1]);
  final before = tools(beforeFile), after = tools(afterFile);
  final emitted = mcpRuntimeToolCatalog.values
      .map((tool) => tool.toJson())
      .toList();
  if (jsonEncode(after) != jsonEncode(emitted)) {
    throw StateError(
      'Captured tools/list does not match the current source catalog.',
    );
  }
  final previous = {for (final tool in before) tool['name'] as String: tool};
  if (previous.length != after.length ||
      after.any((tool) => !previous.containsKey(tool['name']))) {
    throw StateError(
      'The tool set changed; compare compatibility before reporting sizes.',
    );
  }
  final beforeBytes = beforeFile.lengthSync(),
      afterBytes = afterFile.lengthSync();
  final result = {
    'unit':
        'UTF-8 bytes; JSON compacted with Dart jsonEncode for each tool/schema',
    'envelope':
        'raw JSON-RPC tools/list response saved from HTTP, one-digit request id',
    'tool_count': after.length,
    'before_bytes': beforeBytes,
    'after_bytes': afterBytes,
    'reduction_percent': double.parse(
      ((1 - afterBytes / beforeBytes) * 100).toStringAsFixed(2),
    ),
    'first_eight': after.take(8).map((tool) => tool['name']).toList(),
    'tools': [
      for (final tool in after)
        {
          'name': tool['name'],
          'before_bytes': bytes(previous[tool['name']]),
          'after_bytes': bytes(tool),
          'before_description_bytes': utf8
              .encode(previous[tool['name']]!['description'] as String)
              .length,
          'after_description_bytes': utf8
              .encode(tool['description'] as String)
              .length,
          'before_input_schema_bytes': bytes(
            previous[tool['name']]!['inputSchema'],
          ),
          'after_input_schema_bytes': bytes(tool['inputSchema']),
        },
    ],
  };
  final output = File(arguments[2]);
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(result)}\n',
  );
  stdout.writeln(
    jsonEncode({
      'tool_count': after.length,
      'before_bytes': beforeBytes,
      'after_bytes': afterBytes,
      'output': output.path,
    }),
  );
}
