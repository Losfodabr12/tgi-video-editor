// Explicit external-client harness; not included in `flutter test`'s test/ scan.
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/domain/models/project.dart';
import 'package:tgi_video_editor/features/editor/application/editor_controller.dart';
import 'package:tgi_video_editor/mcp/editor_read_service.dart';
import 'package:tgi_video_editor/mcp/editor_plans.dart';
import 'package:tgi_video_editor/mcp/editor_mcp_server.dart';
import 'package:tgi_video_editor/mcp/mcp_tool_router.dart';
import 'package:tgi_video_editor/mcp/mcp_path_policy.dart';
import 'package:tgi_video_editor/services/media_import_service.dart';
import 'package:tgi_video_editor/services/project_io_service.dart';
import '../test/support/render_fixture.dart';

void main() {
  test('external MCP validation host', () async {
    final root = Platform.environment['MCP_VALIDATION_DIR'];
    if (root == null || !await Directory(root).exists()) {
      fail('Defina MCP_VALIDATION_DIR para uma pasta de teste existente.');
    }
    final fixture = RenderFixture();
    await fixture.open();
    addTearDown(fixture.close);
    final media = await fixture.color('red', seconds: 4, audio: '440');
    final importer = MediaImportService(ffmpegService: fixture.service);
    var project = TgiProject.empty(name: 'MCP external client')
        .addMediaItem(media)
        .addMediaItemToTimeline(media, timelineStart: Duration.zero);
    final speechFile = Platform.environment['MCP_SPEECH_FILE'];
    if (speechFile != null) {
      project = project.addMediaItem(await importer.importFile(speechFile));
    }
    final c = EditorController(
      mediaImportService: importer,
      initialProject: project,
    );
    c.synchronizeCommandExportSettings(RenderFixture.settings);
    final policy = McpPathPolicy(
      projectDirectory: fixture.directory.path,
      exportDirectory: root,
    );
    await policy.trustProject(project);
    final reads = EditorReadService(c, checkMedia: policy.authorizeMedia);
    final plans = EditorPlans(c, reads)..requireApproval = false;
    final server = EditorMcpServer(
      McpToolRouter(
        reads,
        plans,
        resolveExport: policy.resolveExport,
        authorizeExport: (p, path) async {
          await policy.authorizeExport(path);
          await policy.authorizeProject(p);
        },
      ),
      token: randomMcpToken(),
      port: 0,
    );
    await server.start();
    addTearDown(() async {
      await server.stop();
      await reads.dispose();
      c.dispose();
    });
    final before = ProjectIOService().serializeProject(c.project);
    final io = ProjectIOService();
    await io.saveToFile(
      c.project,
      '$root/project-before.json',
      exportSettings: c.commandExportSettings,
    );
    final beforeBytes = await File('$root/project-before.json').readAsBytes();
    await File('$root/session.json').writeAsString(
      jsonEncode({
        'url': 'http://127.0.0.1:${server.boundPort}/mcp',
        'test_token': server.token,
        'project_revision': c.projectRevision,
      }),
      flush: true,
    );
    stdout.writeln(
      'MCP validation host ready on loopback; ephemeral test credentials written in validation directory.',
    );
    for (var i = 0; i < 6000 && !await File('$root/stop').exists(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(
      await File('$root/stop').exists(),
      isTrue,
      reason: 'Cliente externo não sinalizou conclusão em 5 minutos.',
    );
    // External smoke script undoes its transaction before signaling completion.
    expect(ProjectIOService().serializeProject(c.project), before);
    await io.saveToFile(
      c.project,
      '$root/project-after-undo.json',
      exportSettings: c.commandExportSettings,
    );
    final afterBytes = await File(
      '$root/project-after-undo.json',
    ).readAsBytes();
    await File('$root/roundtrip.json').writeAsString(
      jsonEncode({
        'format_version': jsonDecode(utf8.decode(afterBytes))['version'],
        'before_bytes': beforeBytes.length,
        'after_bytes': afterBytes.length,
        'before_sha256': sha256.convert(beforeBytes).toString(),
        'after_sha256': sha256.convert(afterBytes).toString(),
        'byte_identical':
            sha256.convert(beforeBytes).toString() ==
            sha256.convert(afterBytes).toString(),
        'project_revision_after_undo': c.projectRevision,
        'fixture':
            'isolated Flutter host, real FFmpeg media, production MCP/router/controller and ProjectIOService',
      }),
    );
    expect(
      afterBytes,
      beforeBytes,
      reason: 'Saved v14 file must be byte-identical after SDK undo.',
    );
  }, timeout: const Timeout(Duration(minutes: 6)));
}
