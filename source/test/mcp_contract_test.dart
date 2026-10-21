import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/features/editor/application/editor_controller.dart';
import 'package:tgi_video_editor/mcp/editor_read_service.dart';
import 'package:tgi_video_editor/mcp/editor_plans.dart';
import 'package:tgi_video_editor/mcp/editor_mcp_server.dart';
import 'package:tgi_video_editor/mcp/mcp_tool_router.dart';
import 'package:tgi_video_editor/mcp/mcp_path_policy.dart';
import 'package:tgi_video_editor/services/media_import_service.dart';
import 'package:tgi_video_editor/services/ffmpeg_service.dart';
import 'support/mcp_test_client.dart';
import 'command_engine_test.dart' show commandFixture;

void main() {
  late EditorController c;
  late EditorReadService reads;
  late EditorPlans plans;
  late EditorMcpServer server;
  late McpTestClient client;
  setUp(() async {
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
    await client.initialize();
  });
  tearDown(() async {
    client.close();
    await server.stop();
    await reads.dispose();
    c.dispose();
  });
  test(
    'remote approval flag cannot bypass local approval and stale plans fail',
    () async {
      final draft = await client.call('add_marker', {
        'at': 1,
        'name': 'aprovar',
        'base_revision': 0,
      });
      final planId = draft['structuredContent']['plan_id'];
      expect(c.project.markers, isEmpty);
      final forbidden = await client.call('apply_plan', {
        'plan_id': planId,
        'base_revision': 0,
        'approved': true,
      });
      expect(
        forbidden['structuredContent']['error']['code'],
        'invalid_argument',
      );
      final pending = await client.call('apply_plan', {
        'plan_id': planId,
        'base_revision': 0,
      });
      expect(
        pending['structuredContent']['error']['code'],
        'approval_required',
      );
      plans.approve(planId as String);
      expect(
        (await client.call('apply_plan', {
          'plan_id': planId,
          'base_revision': 0,
        }))['isError'],
        isFalse,
      );
      expect(
        (await client.call('apply_plan', {
          'plan_id': planId,
          'base_revision': 0,
        }))['structuredContent']['error']['code'],
        'revision_conflict',
      );
      c.undo();
      expect(c.project.markers, isEmpty);
    },
  );
  test('wire rate limit bounds polling and unauthorized attempts', () async {
    var status = 200;
    for (var i = 0; i < 121 && status != 429; i++) {
      status = (await client.request('ping', {})).$1;
    }
    expect(status, 429);
    expect(c.projectRevision, 0);
  });
  test(
    'large body and invalid protocol are rejected without an edit',
    () async {
      final http = HttpClient();
      addTearDown(() => http.close(force: true));
      final request = await http.postUrl(
        Uri.parse('http://127.0.0.1:${server.boundPort}/mcp'),
      );
      request.headers.contentType = ContentType.json;
      request.headers.set('Accept', 'application/json, text/event-stream');
      request.headers.set('Authorization', 'Bearer ${server.token}');
      request.contentLength = 1024 * 1024 + 1;
      request.add(List.filled(1024 * 1024 + 1, 32));
      final response = await request.close();
      await response.drain<void>();
      expect(response.statusCode, 413);
      client.version = '1900-01-01';
      expect((await client.request('tools/list', {})).$1, 400);
      expect(c.projectRevision, 0);
    },
  );
  test(
    'wire jobs can be inspected and cancelled without publishing their result',
    () async {
      final started = Completer<void>(), released = Completer<void>();
      final job = reads.jobs.start('analysis', 0, c.project.id, (ctx) async {
        ctx.onCancel = () => released.complete();
        started.complete();
        await released.future;
        return {'must_not_publish': true};
      });
      await started.future;
      expect(
        (await client.call('get_job', {
          'job_id': job.id,
        }))['structuredContent']['status'],
        'running',
      );
      expect(
        (await client.call('cancel_job', {
          'job_id': job.id,
        }))['structuredContent']['status'],
        'cancelled',
      );
      expect(
        (await client.call('get_job', {
          'job_id': job.id,
        }))['structuredContent'].containsKey('result'),
        isFalse,
      );
      await server.stop();
      expect(plans.all, isEmpty);
      expect(server.connectedClients, 0);
    },
  );
  test(
    'wire accepts only media IDs and rejects arbitrary read paths',
    () async {
      final injected = await client.call('get_frames', {
        'times': [0],
        'path': 'C:/Windows/System32/config/SAM',
      });
      expect(
        injected['structuredContent']['error']['code'],
        'invalid_argument',
      );
      final byPath = await client.call('get_frames', {
        'times': [0],
        'media_id': 'C:/Windows/System32/config/SAM',
      });
      expect(byPath['structuredContent']['error']['code'], 'media_not_found');
    },
  );
  test(
    'canonical project boundary rejects a junction to a different directory',
    () async {
      final temp = await Directory.systemTemp.createTemp('mcp_junction_');
      addTearDown(() => temp.delete(recursive: true));
      final root = await Directory('${temp.path}/project').create(),
          outside = await Directory('${temp.path}/outside').create();
      await File('${outside.path}/private.mp4').writeAsString('private');
      final link = '${root.path}${Platform.pathSeparator}escape'.replaceAll(
        '/',
        Platform.pathSeparator,
      );
      if (Platform.isWindows) {
        final made = await Process.run('cmd.exe', [
          '/c',
          'mklink',
          '/J',
          link,
          outside.path.replaceAll('/', Platform.pathSeparator),
        ]);
        expect(made.exitCode, 0, reason: made.stderr.toString());
      } else {
        await Link(link).create(outside.path);
      }
      final policy = McpPathPolicy(projectDirectory: root.path);
      await expectLater(
        policy.authorizeFile('$link${Platform.pathSeparator}private.mp4'),
        throwsA(anything),
      );
      expect(
        await File('${outside.path}/private.mp4').readAsString(),
        'private',
      );
    },
  );
  test('all advertised tools and schemas are JSON serializable', () {
    final tools = server.router.listTools();
    final decoded = jsonDecode(jsonEncode(tools)) as List;
    expect(decoded.map((t) => t['name']).toSet().length, tools.length);
    expect(
      decoded.where((t) => t['annotations']['readOnlyHint'] == true).length,
      greaterThan(10),
    );
  });
}
