import 'dart:convert';
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
    expect((await client.request('', {}, verb: 'GET')).$1, 405);
    expect((await client.request('', {}, verb: 'DELETE')).$1, 200);
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
