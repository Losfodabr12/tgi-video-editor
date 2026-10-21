import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/commands/editor_command.dart';
import '../services/app_component_paths.dart';

class McpSettings {
  const McpSettings({
    this.port = 47321,
    this.requireApproval = true,
    this.exportDirectory,
  });
  final int port;
  final bool requireApproval;
  final String? exportDirectory;
  Map<String, Object?> toJson() => {
    'port': port,
    'require_approval': requireApproval,
    'export_directory': exportDirectory,
  };
  factory McpSettings.fromJson(Map<String, dynamic> value) {
    final port = value['port'];
    if (port is! int ||
        port < 1024 ||
        port > 65535 ||
        value['require_approval'] is! bool ||
        (value['export_directory'] != null &&
            value['export_directory'] is! String)) {
      throw const CommandError(
        'invalid_settings',
        'Porta deve ser 1024–65535 e aprovação deve ser booleano.',
      );
    }
    return McpSettings(
      port: port,
      requireApproval: value['require_approval'] as bool,
      exportDirectory: value['export_directory'] as String?,
    );
  }
}

abstract class McpTokenStore {
  Future<String?> read();
  Future<void> write(String token);
}

class SecureMcpTokenStore implements McpTokenStore {
  const SecureMcpTokenStore();
  static const _storage = FlutterSecureStorage();
  static const _key = 'frame_studio_mcp_bearer_v1';
  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);
}

class McpSettingsStore {
  McpSettingsStore({String? path})
    : path =
          path ??
          joinPlatformPath([tgiAppLocalDataRoot(), 'mcp_settings.json']);
  final String path;
  Future<McpSettings> load() async {
    final file = File(path);
    if (!await file.exists()) {
      return const McpSettings();
    }
    return McpSettings.fromJson(
      jsonDecode(await file.readAsString()) as Map<String, dynamic>,
    );
  }

  Future<void> save(McpSettings settings) async {
    McpSettings.fromJson(Map<String, dynamic>.from(settings.toJson()));
    final file = File(path);
    await file.parent.create(recursive: true);
    final temporary = File('$path.tmp');
    await temporary.writeAsString(jsonEncode(settings.toJson()), flush: true);
    await temporary.rename(path);
  }
}
