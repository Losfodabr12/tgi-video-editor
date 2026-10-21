import 'dart:convert';
import 'dart:io';

/// Independent wire client: does not call router methods in-process.
class McpTestClient {
  McpTestClient(this.port, this.token);
  final int port;
  final String token;
  final http = HttpClient();
  int _id = 0;
  String? session;
  String version = '2025-11-25';
  Future<(int, Map<String, dynamic>)> request(
    String method,
    Map<String, Object?> params, {
    String? bearer,
    String? origin,
    String? host,
    bool notification = false,
    String verb = 'POST',
    bool useSession = true,
  }) async {
    final request = await http.openUrl(
      verb,
      Uri.parse('http://127.0.0.1:$port/mcp'),
    );
    request.headers.set('Authorization', 'Bearer ${bearer ?? token}');
    request.headers.set('Accept', 'application/json, text/event-stream');
    request.headers.contentType = ContentType.json;
    if (origin != null) {
      request.headers.set('Origin', origin);
    }
    if (host != null) {
      request.headers.set('Host', host);
    }
    if (useSession && session != null) {
      request.headers.set('Mcp-Session-Id', session!);
      request.headers.set('MCP-Protocol-Version', version);
    }
    if (verb == 'POST') {
      request.write(
        jsonEncode({
          'jsonrpc': '2.0',
          if (!notification) 'id': ++_id,
          'method': method,
          'params': params,
        }),
      );
    }
    final response = await request.close();
    session = response.headers.value('Mcp-Session-Id') ?? session;
    final text = await utf8.decoder.bind(response).join();
    return (
      response.statusCode,
      text.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(text) as Map<String, dynamic>,
    );
  }

  Future<void> initialize() async {
    final response = await request('initialize', {
      'protocolVersion': version,
      'capabilities': {},
      'clientInfo': {'name': 'editor-contract-client', 'version': '1.0'},
    });
    if (response.$1 != 200 || response.$2['result'] == null) {
      throw StateError('Initialize failed: $response');
    }
    version = (response.$2['result'] as Map)['protocolVersion'] as String;
    await request('notifications/initialized', {}, notification: true);
  }

  Future<Map<String, dynamic>> call(
    String tool,
    Map<String, Object?> args,
  ) async {
    final response = await request('tools/call', {
      'name': tool,
      'arguments': args,
    });
    if (response.$1 != 200) {
      throw StateError('HTTP ${response.$1}: ${response.$2}');
    }
    return response.$2['result'] as Map<String, dynamic>;
  }

  void close() => http.close(force: true);
}
