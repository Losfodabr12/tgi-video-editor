import 'dart:convert';
import '../source/lib/mcp/mcp_tool_catalog.dart';

void main() {
  int bytes(Object? value) => utf8.encode(jsonEncode(value)).length;
  final tools = mcpRuntimeToolCatalog.values.map((t) => t.toJson()).toList();
  final catalog = bytes({
    'jsonrpc': '2.0',
    'id': 1,
    'result': {'tools': tools},
  });
  final schemas = [for (final t in tools) (t['name'], bytes(t['inputSchema']))]
    ..sort((a, b) => b.$2.compareTo(a.$2));
  if (catalog >= 30000 || schemas.any((s) => s.$2 >= 4000)) {
    throw StateError('MCP budget exceeded: $catalog bytes; schemas: $schemas');
  }
  print(
    jsonEncode({
      'tool_count': tools.length,
      'catalog_utf8_bytes': catalog,
      'largest_schema': schemas.first.$1,
      'largest_schema_utf8_bytes': schemas.first.$2,
    }),
  );
}
