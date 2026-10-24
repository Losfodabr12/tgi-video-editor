import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/features/editor/application/editor_controller.dart';
import 'package:tgi_video_editor/mcp/editor_read_service.dart';
import 'package:tgi_video_editor/mcp/editor_plans.dart';
import 'package:tgi_video_editor/mcp/editor_mcp_server.dart';
import 'package:tgi_video_editor/mcp/mcp_tool_router.dart';
import 'package:tgi_video_editor/services/media_import_service.dart';
import 'package:tgi_video_editor/services/ffmpeg_service.dart';
import 'package:tgi_video_editor/services/project_io_service.dart';
import 'command_engine_test.dart' show commandFixture;
import 'support/mcp_test_client.dart';

void main() {
  late EditorController c;
  late EditorReadService reads;
  late EditorPlans plans;
  late EditorMcpServer server;
  late McpTestClient client;
  setUp(() async {
    // This contract suite deliberately exercises a real loopback HTTP socket.
    HttpOverrides.global = null;
    c = EditorController(
      mediaImportService: MediaImportService(ffmpegService: FfmpegService()),
      initialProject: commandFixture(),
    );
    reads = EditorReadService(c);
    plans = EditorPlans(c, reads);
    server = EditorMcpServer(
      McpToolRouter(reads, plans),
      token: randomMcpToken(),
      port: 0,
    );
    await server.start();
    client = McpTestClient(server.boundPort, server.token);
  });
  tearDown(() async {
    client.close();
    await server.stop();
    await reads.dispose();
    c.dispose();
  });
  test('wire lifecycle, tools/list, read tool and project resource', () async {
    await client.initialize();
    expect(server.connectedClients, 1);
    final list = await client.request('tools/list', {});
    final tools = (list.$2['result'] as Map)['tools'] as List;
    expect(tools.length, greaterThanOrEqualTo(30));
    for (final tool in tools) {
      expect(tool['inputSchema']['additionalProperties'], isFalse);
      expect(tool['annotations']['openWorldHint'], isFalse);
    }
    final project = await client.call('get_project', {'limit': 1});
    expect(project['isError'], isFalse);
    expect(project['structuredContent']['revision'], 0);
    final resource = await client.request('resources/read', {
      'uri': 'editor://project/summary',
    });
    final contents = (resource.$2['result'] as Map)['contents'] as List;
    expect(jsonDecode(contents.first['text'] as String)['format_version'], 14);
    expect(
      (await client.request(
        '',
        {},
        verb: 'GET',
        accept: 'application/json',
      )).$1,
      406,
    );
    expect((await client.request('', {}, verb: 'DELETE')).$1, 200);
    expect(server.connectedClients, 0);
  });
  test(
    'authenticated SSE refreshes tools and closes on session deletion',
    () async {
      await client.initialize();
      final response = await client.events();
      expect(response.statusCode, 200);
      expect(response.headers.contentType?.mimeType, 'text/event-stream');
      final lines = StreamIterator(
        utf8.decoder.bind(response).transform(const LineSplitter()),
      );
      Future<Map> next() async {
        while (await lines.moveNext()) {
          if (lines.current.startsWith('data: ')) {
            return jsonDecode(lines.current.substring(6)) as Map;
          }
        }
        throw StateError('SSE closed before notification.');
      }

      expect(
        (await next().timeout(const Duration(seconds: 5)))['method'],
        'notifications/tools/list_changed',
      );
      for (var i = 0; i < 20; i++) {
        server.notifyToolsChanged();
      }
      for (var i = 0; i < 20; i++) {
        expect(
          (await next().timeout(const Duration(seconds: 5)))['method'],
          'notifications/tools/list_changed',
          reason: 'Notification $i must survive queued writes.',
        );
      }
      final catalog =
          (await client.request('tools/list', {})).$2['result']['tools']
              as List;
      expect(
        catalog.map((t) => t['name']),
        containsAll([
          'browse_media_files',
          'import_media',
          'add_clip',
          'list_library',
          'add_library_asset',
        ]),
      );
      expect((await client.request('', {}, verb: 'DELETE')).$1, 200);
      while (await lines.moveNext().timeout(const Duration(seconds: 5))) {}
      await lines.cancel();
    },
  );

  test('SSE enforces authentication, session, protocol and origin', () async {
    await client.initialize();
    for (final (future, status) in [
      (client.events(bearer: 'bad'), 401),
      (client.events(useSession: false), 400),
      (client.events(protocolVersion: 'bad'), 400),
      (client.events(origin: 'https://attacker.example'), 403),
    ]) {
      final response = await future;
      expect(response.statusCode, status);
      await response.drain<void>();
    }
  });

  test('eight notification streams leave the POST budget available', () async {
    final observers = <McpTestClient>[];
    addTearDown(() {
      for (final observer in observers) {
        observer.close();
      }
    });
    for (var i = 0; i < 8; i++) {
      final observer = McpTestClient(server.boundPort, server.token);
      observers.add(observer);
      await observer.initialize();
      expect((await observer.events()).statusCode, 200);
    }
    await client.initialize();
    expect((await client.call('get_project', {}))['isError'], false);
    await server.stop().timeout(const Duration(seconds: 5));
    expect(server.connectedClients, 0);
  });
  test(
    'wire preview/apply and stale revision; one shared undo restores project',
    () async {
      plans.requireApproval = false;
      await client.initialize();
      final before = jsonEncode(ProjectIOService().serializeProject(c.project));
      final preview = await client.call('preview_plan', {
        'base_revision': 0,
        'commands': [
          {
            'command': 'add_marker',
            'arguments': {'at': 2, 'name': 'IA'},
          },
          {
            'command': 'set_volume',
            'arguments': {
              'clip_id': c.project.tracks.expand((t) => t.clips).first.id,
              'volume': 0.2,
            },
          },
        ],
      });
      expect(preview['isError'], isFalse, reason: preview.toString());
      expect(c.project.markers, isEmpty);
      final applied = await client.call('apply_plan', {
        'base_revision': 0,
        'plan_id': preview['structuredContent']['plan_id'],
      });
      expect(applied['structuredContent']['revision'], 1);
      final stale = await client.call('add_marker', {
        'base_revision': 0,
        'at': 1,
        'name': 'old',
      });
      expect(stale['isError'], isTrue);
      expect(stale['structuredContent']['error']['code'], 'revision_conflict');
      final undo = await client.call('undo', {'base_revision': 1});
      expect(undo['isError'], isFalse);
      expect(
        jsonEncode(ProjectIOService().serializeProject(c.project)),
        before,
      );
    },
  );
  test(
    'invalid token, Host, Origin and missing lifecycle are rejected over HTTP',
    () async {
      expect((await client.request('tools/list', {}, bearer: 'bad')).$1, 401);
      expect(
        (await client.request('tools/list', {}, host: 'attacker.example')).$1,
        403,
      );
      expect(
        (await client.request(
          'tools/list',
          {},
          origin: 'https://attacker.example',
        )).$1,
        403,
      );
      expect((await client.request('tools/list', {})).$1, 400);
      await client.initialize();
      final invalid = await client.call('get_clip', {'clip_id': 'missing'});
      expect(invalid['isError'], isTrue);
      final unknown = await client.call('get_project', {'path': 'C:/Windows'});
      expect(unknown['structuredContent']['error']['code'], 'invalid_argument');
    },
  );
}
