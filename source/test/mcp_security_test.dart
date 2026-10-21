import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/core/commands/editor_command.dart';
import 'package:tgi_video_editor/features/editor/application/editor_controller.dart';
import 'package:tgi_video_editor/mcp/editor_automation.dart';
import 'package:tgi_video_editor/mcp/mcp_audit.dart';
import 'package:tgi_video_editor/mcp/mcp_path_policy.dart';
import 'package:tgi_video_editor/mcp/mcp_settings.dart';
import 'package:tgi_video_editor/services/media_import_service.dart';
import 'package:tgi_video_editor/services/ffmpeg_service.dart';
import 'support/mcp_test_client.dart';
import 'command_engine_test.dart' show commandFixture;

class _Tokens implements McpTokenStore {
  String? token;
  @override
  Future<String?> read() async => token;
  @override
  Future<void> write(String value) async {
    token = value;
  }
}

class _DelayedTokens extends _Tokens {
  _DelayedTokens() {
    token = 'existing-test-token-00000000000000000000000';
  }
  final started = Completer<void>(), release = Completer<void>();
  @override
  Future<void> write(String value) async {
    started.complete();
    await release.future;
    await super.write(value);
  }
}

void main() {
  late Directory temp;
  setUp(() async {
    HttpOverrides.global = null;
    temp = await Directory.systemTemp.createTemp('editor_mcp_security_');
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });
  test(
    'emergency stop during token rotation prevents an automatic restart',
    () async {
      final tokens = _DelayedTokens();
      final c = EditorController(
        mediaImportService: MediaImportService(ffmpegService: FfmpegService()),
        initialProject: commandFixture(),
      );
      final a = EditorAutomation(
        c,
        settingsStore: McpSettingsStore(path: '${temp.path}/settings.json'),
        tokenStore: tokens,
        audit: McpAudit(path: '${temp.path}/audit.jsonl'),
      );
      addTearDown(() async {
        await a.shutdown();
        a.dispose();
        c.dispose();
      });
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      await a.configure(McpSettings(port: port));
      await a.start();
      expect(a.running, isTrue);
      final rotation = a.rotateToken();
      await tokens.started.future;
      await a.stop();
      tokens.release.complete();
      await rotation;
      expect(
        a.running,
        isFalse,
        reason:
            'A rotação pendente não pode reativar o servidor após uma parada de emergência.',
      );
    },
  );
  test(
    'paths reject traversal, outside files, existing exports and network input',
    () async {
      final root = await Directory('${temp.path}/project').create(),
          exports = await Directory('${temp.path}/exports').create();
      final inside = await File(
        '${root.path}/video.mp4',
      ).writeAsString('fixture');
      final outside = await File(
        '${temp.path}/private.txt',
      ).writeAsString('private');
      final policy = McpPathPolicy(
        projectDirectory: root.path,
        exportDirectory: exports.path,
      );
      expect(
        await policy.authorizeFile(inside.path),
        await inside.resolveSymbolicLinks(),
      );
      for (final path in [
        outside.path,
        'https://attacker.invalid/a.mp4',
        '../private.txt',
        r'\\server\share\file.mp4',
      ]) {
        await expectLater(
          policy.authorizeFile(path),
          throwsA(isA<CommandError>()),
        );
      }
      for (final filename in [
        '../outside.mp4',
        r'..\outside.mp4',
        'C:\\outside.mp4',
        'CON.mp4',
        'x:stream.mp4',
        'x.mov',
      ]) {
        await expectLater(
          policy.resolveExport(filename),
          throwsA(isA<CommandError>()),
        );
      }
      final output = await policy.resolveExport('safe.mp4');
      expect(File(output).parent.path, await exports.resolveSymbolicLinks());
      await File(output).writeAsString('keep');
      await expectLater(
        policy.resolveExport('safe.mp4'),
        throwsA(
          isA<CommandError>().having((e) => e.code, 'code', 'file_exists'),
        ),
      );
      await expectLater(
        policy.authorizeExport('${root.path}/outside.mp4'),
        throwsA(isA<CommandError>()),
      );
      expect(await File(output).readAsString(), 'keep');
    },
  );
  test(
    'persistent token rotates, old sessions fail, audit contains no credentials, startup is off',
    () async {
      final settings = McpSettingsStore(path: '${temp.path}/settings.json'),
          tokens = _Tokens(),
          audit = McpAudit(path: '${temp.path}/audit.jsonl');
      final c = EditorController(
        mediaImportService: MediaImportService(ffmpegService: FfmpegService()),
        initialProject: commandFixture(),
      );
      final automation = EditorAutomation(
        c,
        settingsStore: settings,
        tokenStore: tokens,
        audit: audit,
      );
      addTearDown(() async {
        await automation.shutdown();
        automation.dispose();
        c.dispose();
      });
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      await automation.configure(
        McpSettings(
          port: port,
          requireApproval: false,
          exportDirectory: temp.path,
        ),
      );
      await automation.load();
      expect(automation.running, isFalse);
      final token = await automation.tokenForClipboard();
      expect(token.length, greaterThanOrEqualTo(32));
      expect(await automation.tokenForClipboard(), token);
      await automation.start();
      expect(automation.running, isTrue, reason: automation.lastError);
      final client = McpTestClient(port, token);
      await client.initialize();
      expect((await client.call('get_project', {}))['isError'], isFalse);
      await automation.rotateToken();
      expect(tokens.token, isNot(token));
      expect((await client.request('tools/list', {})).$1, 401);
      client.close();
      final fresh = McpTestClient(port, tokens.token!);
      await fresh.initialize();
      expect(
        (await fresh.call('export', {
          'filename': '../escape.mp4',
          'base_revision': 0,
        }))['structuredContent']['error']['code'],
        'path_not_allowed',
      );
      await automation.stop();
      expect(automation.running, isFalse);
      fresh.close();
      await audit.flush();
      final log = await File(audit.path).readAsString();
      expect(log, isNot(contains(token)));
      expect(log, isNot(contains(tokens.token!)));
      expect(log, contains('token_rotated'));
      expect(log, contains('tool_call'));
      final saved = jsonDecode(await File(settings.path).readAsString()) as Map;
      expect(saved.containsKey('token'), isFalse);
      expect(saved.containsKey('enabled'), isFalse);
      await automation.shutdown();
    },
  );
}
