import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'mcp_tool_router.dart';

String randomMcpToken() => base64UrlEncode(
  List<int>.generate(32, (_) => Random.secure().nextInt(256)),
).replaceAll('=', '');

class _McpSession {
  _McpSession(this.version);
  final String version;
  bool initialized = false;
  DateTime lastSeen = DateTime.now();
}

/// Streamable HTTP JSON response mode (2025-03-26 / 06-18 / 11-25).
/// GET intentionally returns 405: standalone SSE is optional in this mode.
class EditorMcpServer {
  EditorMcpServer(
    this.router, {
    required this.token,
    this.port = 47321,
    this.onChanged,
    this.onSecurityEvent,
  });
  final McpToolRouter router;
  final String token;
  final int port;
  final void Function()? onChanged;
  final void Function(String reason)? onSecurityEvent;
  HttpServer? _server;
  Timer? _expiry;
  int _generation = 0;
  final Map<String, _McpSession> _sessions = {};
  DateTime _rateStart = DateTime.now();
  int _rateCount = 0;
  bool get running => _server != null;
  int get boundPort => _server?.port ?? port;
  int get connectedClients =>
      _sessions.values.where((s) => s.initialized).length;
  static const versions = ['2025-03-26', '2025-06-18', '2025-11-25'];
  Future<void> start() async {
    if (running) {
      return;
    }
    if (token.length < 32 || port < 0 || port > 65535) {
      throw ArgumentError('Token >=32 caracteres e porta válida obrigatórios.');
    }
    final generation = ++_generation;
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      port,
      shared: false,
    );
    if (generation != _generation) {
      await server.close(force: true);
      return;
    }
    _server = server;
    server.idleTimeout = const Duration(seconds: 15);
    _expiry = Timer.periodic(const Duration(minutes: 1), (_) {
      _sessions.removeWhere(
        (_, s) =>
            DateTime.now().difference(s.lastSeen) > const Duration(minutes: 30),
      );
      onChanged?.call();
    });
    server.listen((r) => unawaited(_handle(r, generation)));
    onChanged?.call();
  }

  Future<void> stop() async {
    ++_generation;
    final server = _server;
    _server = null;
    _expiry?.cancel();
    _expiry = null;
    _sessions.clear();
    router.plans.clear();
    await server?.close(force: true);
    await router.reads.jobs.cancelAll();
    onChanged?.call();
  }

  bool _matchesToken(String supplied) {
    final expected = utf8.encode('Bearer $token'),
        actual = utf8.encode(supplied);
    var diff = expected.length ^ actual.length;
    for (var i = 0; i < expected.length; i++) {
      diff |= expected[i] ^ (i < actual.length ? actual[i] : 0);
    }
    return diff == 0;
  }

  Future<void> _handle(HttpRequest request, int generation) async {
    final response = request.response;
    Future<void> reject(int status, String reason) async {
      onSecurityEvent?.call(reason);
      response.statusCode = status;
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode({'error': reason}));
      await response.close();
    }

    try {
      if (!running || generation != _generation) {
        await reject(503, 'server_stopped');
        return;
      }
      if (request.connectionInfo?.remoteAddress.isLoopback != true) {
        await reject(403, 'loopback_required');
        return;
      }
      if (request.uri.path != '/mcp' || request.uri.hasQuery) {
        await reject(404, 'not_found');
        return;
      }
      final host = request.headers.value(HttpHeaders.hostHeader);
      final allowed = {'127.0.0.1:$boundPort', 'localhost:$boundPort'};
      if (!allowed.contains(host)) {
        await reject(403, 'invalid_host');
        return;
      }
      final origin = request.headers.value('origin');
      if (origin != null && !allowed.map((h) => 'http://$h').contains(origin)) {
        await reject(403, 'invalid_origin');
        return;
      }
      if (DateTime.now().difference(_rateStart) > const Duration(minutes: 1)) {
        _rateStart = DateTime.now();
        _rateCount = 0;
      }
      if (++_rateCount > 120) {
        response.headers.set('Retry-After', '60');
        await reject(429, 'rate_limit');
        return;
      }
      if (!_matchesToken(
        request.headers.value(HttpHeaders.authorizationHeader) ?? '',
      )) {
        response.headers.set(
          'WWW-Authenticate',
          'Bearer realm="FrameStudio MCP"',
        );
        await reject(401, 'invalid_token');
        return;
      }
      final sessionId = request.headers.value('Mcp-Session-Id'),
          session = _sessions[sessionId];
      if (request.method == 'GET') {
        response.headers.set('Allow', 'POST, DELETE');
        await reject(405, 'sse_not_supported');
        return;
      }
      if (request.method == 'DELETE') {
        if (session == null) {
          await reject(404, 'session_not_found');
          return;
        }
        _sessions.remove(sessionId);
        onChanged?.call();
        response.statusCode = 200;
        await response.close();
        return;
      }
      if (request.method != 'POST') {
        response.headers.set('Allow', 'POST, DELETE');
        await reject(405, 'method_not_allowed');
        return;
      }
      if (request.headers.contentType?.mimeType != 'application/json') {
        await reject(415, 'json_required');
        return;
      }
      final accept = request.headers.value('accept') ?? '';
      if (!accept.contains('*/*') &&
          (!accept.contains('application/json') ||
              !accept.contains('text/event-stream'))) {
        await reject(406, 'accept_json_and_sse');
        return;
      }
      if (request.contentLength > 1024 * 1024) {
        await reject(413, 'body_too_large');
        return;
      }
      final bytes = <int>[];
      await for (final chunk in request.timeout(const Duration(seconds: 5))) {
        if (bytes.length + chunk.length > 1024 * 1024) {
          await reject(413, 'body_too_large');
          return;
        }
        bytes.addAll(chunk);
      }
      Object? raw;
      try {
        raw = jsonDecode(utf8.decode(bytes));
      } on FormatException {
        await _rpc(
          response,
          null,
          error: {'code': -32700, 'message': 'Parse error'},
        );
        return;
      }
      if (raw is! Map<String, dynamic> ||
          raw['jsonrpc'] != '2.0' ||
          raw['method'] is! String ||
          (raw.containsKey('id') &&
              raw['id'] is! int &&
              raw['id'] is! String) ||
          (raw['params'] != null && raw['params'] is! Map<String, dynamic>)) {
        await _rpc(
          response,
          null,
          error: {'code': -32600, 'message': 'Invalid Request'},
        );
        return;
      }
      if (!running || generation != _generation) {
        await reject(503, 'server_stopped');
        return;
      }
      final method = raw['method'] as String,
          params = raw['params'] as Map<String, dynamic>? ?? {};
      final id = raw['id'];
      if (method == 'initialize') {
        if (id == null ||
            session != null ||
            params['protocolVersion'] is! String ||
            params['clientInfo'] is! Map ||
            params['capabilities'] is! Map) {
          await _rpc(
            response,
            id,
            error: {'code': -32602, 'message': 'Invalid initialize parameters'},
          );
          return;
        }
        if (_sessions.length >= 16) {
          await reject(429, 'session_limit');
          return;
        }
        final requested = params['protocolVersion'] as String;
        final version = versions.contains(requested)
            ? requested
            : versions.last;
        final sid = randomMcpToken();
        _sessions[sid] = _McpSession(version);
        response.headers.set('Mcp-Session-Id', sid);
        await _rpc(
          response,
          id,
          result: {
            'protocolVersion': version,
            'capabilities': {
              'tools': {'listChanged': false},
              'resources': {'subscribe': false, 'listChanged': false},
            },
            'serverInfo': {'name': 'frame-studio-editor', 'version': '1.0.0'},
            'instructions':
                'Edite apenas o projeto aberto. Leia get_project para obter revisão e IDs. Use preview_plan e apply_plan; aprovação humana pode ser obrigatória. Tempos em segundos.',
          },
        );
        return;
      }
      if (session == null) {
        await reject(sessionId == null ? 400 : 404, 'session_not_found');
        return;
      }
      final versionHeader = request.headers.value('MCP-Protocol-Version');
      if (versionHeader != null && versionHeader != session.version) {
        await reject(400, 'protocol_version_mismatch');
        return;
      }
      session.lastSeen = DateTime.now();
      if (id == null) {
        if (method == 'notifications/initialized') {
          session.initialized = true;
          onChanged?.call();
        }
        response.statusCode = 202;
        await response.close();
        return;
      }
      if (!session.initialized && method != 'ping') {
        await _rpc(
          response,
          id,
          error: {
            'code': -32000,
            'message': 'Send notifications/initialized first',
          },
        );
        return;
      }
      Object? result;
      switch (method) {
        case 'ping':
          result = <String, Object?>{};
        case 'tools/list':
          result = {'tools': router.listTools()};
        case 'tools/call':
          if (params['name'] is! String ||
              (params['arguments'] != null && params['arguments'] is! Map)) {
            await _rpc(
              response,
              id,
              error: {'code': -32602, 'message': 'Invalid tool parameters'},
            );
            return;
          }
          result = await router.call(
            params['name'] as String,
            Map<String, Object?>.from(params['arguments'] as Map? ?? {}),
          );
        case 'resources/list':
          result = {
            'resources': [
              {
                'uri': 'editor://project/summary',
                'name': 'Projeto aberto',
                'description':
                    'Resumo paginado (primeira página) com revisão atual; use get_project para continuar.',
                'mimeType': 'application/json',
              },
            ],
          };
        case 'resources/templates/list':
          result = {'resourceTemplates': []};
        case 'resources/read':
          if (params['uri'] != 'editor://project/summary') {
            await _rpc(
              response,
              id,
              error: {'code': -32002, 'message': 'Resource not found'},
            );
            return;
          }
          result = {
            'contents': [
              {
                'uri': 'editor://project/summary',
                'mimeType': 'application/json',
                'text': jsonEncode(router.reads.getProject()),
              },
            ],
          };
        default:
          await _rpc(
            response,
            id,
            error: {'code': -32601, 'message': 'Method not found'},
          );
          return;
      }
      if (running && generation == _generation) {
        await _rpc(response, id, result: result);
      } else {
        await response.close();
      }
    } catch (_) {
      try {
        response.statusCode = 400;
        await response.close();
      } catch (_) {
        /* Disconnected or emergency stop. */
      }
    }
  }

  Future<void> _rpc(
    HttpResponse response,
    Object? id, {
    Object? result,
    Map<String, Object?>? error,
  }) async {
    response.headers.contentType = ContentType.json;
    response.headers.set('Cache-Control', 'no-store');
    response.write(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        if (error != null) 'error': error else 'result': result,
      }),
    );
    await response.close();
  }
}
