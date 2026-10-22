import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/mcp/mcp_tool_catalog.dart';

void main() {
  final tools = mcpRuntimeToolCatalog.values
      .map((tool) => tool.toJson())
      .toList();
  final envelope = {
    'jsonrpc': '2.0',
    'id': 3,
    'result': {'tools': tools},
  };
  int bytes(Object? value) => utf8.encode(jsonEncode(value)).length;

  test(
    'wire catalog stays within 30 KB, 4 KB/schema and 300 bytes/description',
    () {
      expect(
        bytes(envelope),
        lessThanOrEqualTo(30000),
        reason: 'tools/list UTF-8 JSON-RPC response',
      );
      for (final tool in tools) {
        expect(
          bytes(tool['inputSchema']),
          lessThanOrEqualTo(4000),
          reason: '${tool['name']} inputSchema',
        );
        expect(
          utf8.encode(tool['description'] as String).length,
          lessThan(300),
          reason: '${tool['name']} description',
        );
      }
    },
  );

  test(
    'compact release targets stay below 25 KB and 3 KB for batch schemas',
    () {
      expect(bytes(envelope), lessThan(25000));
      for (final name in ['preview_plan', 'apply_commands']) {
        final tool = tools.singleWhere((tool) => tool['name'] == name);
        expect(bytes(tool['inputSchema']), lessThan(3000), reason: name);
      }
    },
  );
}
