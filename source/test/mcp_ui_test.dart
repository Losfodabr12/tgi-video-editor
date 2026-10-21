import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/core/commands/editor_command.dart';
import 'package:tgi_video_editor/features/editor/application/editor_controller.dart';
import 'package:tgi_video_editor/features/editor/presentation/widgets/mcp_settings_dialog.dart';
import 'package:tgi_video_editor/mcp/editor_automation.dart';
import 'package:tgi_video_editor/mcp/mcp_audit.dart';
import 'package:tgi_video_editor/mcp/mcp_settings.dart';
import 'package:tgi_video_editor/services/media_import_service.dart';
import 'package:tgi_video_editor/services/ffmpeg_service.dart';
import 'command_engine_test.dart' show commandFixture;

class _Tokens implements McpTokenStore {
  @override
  Future<String?> read() async => 'test-only-token-00000000000000000000000000';
  @override
  Future<void> write(String token) async {}
}

class _Audit extends McpAudit {
  _Audit() : super(path: 'auditoria do teste');
  @override
  Future<void> write(Map<String, Object?> event) async {}
  @override
  Future<void> flush() async {}
}

void main() {
  testWidgets(
    'MCP settings default off, copy safe TOML, review apply and undo activity',
    (tester) async {
      final c = EditorController(
        mediaImportService: MediaImportService(ffmpegService: FfmpegService()),
        initialProject: commandFixture(),
      );
      final a = EditorAutomation(
        c,
        settingsStore: McpSettingsStore(path: 'unused-settings.json'),
        tokenStore: _Tokens(),
        audit: _Audit(),
      );
      addTearDown(() {
        a.dispose();
        c.dispose();
      });
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final plan = a.plans.previewCommands([
        EditorCommand('add_marker', {'at': 2, 'name': 'aprovado'}),
      ], baseRevision: 0);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => McpSettingsDialog(automation: a),
                ),
                child: const Text('Abrir MCP'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir MCP'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const ValueKey('mcp_enabled')))
            .value,
        isFalse,
      );
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const ValueKey('mcp_approval')))
            .value,
        isTrue,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('mcp_copy_codex')),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('mcp_settings_list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.byKey(const ValueKey('mcp_copy_codex')));
      await tester.pumpAndSettle();
      expect(
        copied,
        contains('bearer_token_env_var = "FRAME_STUDIO_MCP_TOKEN"'),
      );
      expect(copied, isNot(contains('test-only-token')));
      await tester.tap(find.text('Atividade da IA'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revisar plano'));
      await tester.pumpAndSettle();
      expect(c.project.markers, isEmpty);
      expect(plan.approved, isFalse);
      await tester.tap(find.byKey(const ValueKey('mcp_approve_apply')));
      await tester.pumpAndSettle();
      expect(c.project.markers.single.name, 'aprovado');
      await tester.tap(find.text('Desfazer'));
      await tester.pumpAndSettle();
      expect(c.project.markers, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await a.shutdown();
    },
  );
}
