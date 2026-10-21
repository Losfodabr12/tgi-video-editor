import 'dart:convert';
import 'dart:io';
import '../services/app_component_paths.dart';

/// Records metadata, never credentials, transcript content or thumbnail bytes.
class McpAudit {
  McpAudit({String? path})
    : path =
          path ?? joinPlatformPath([tgiAppLocalDataRoot(), 'mcp_audit.jsonl']);
  final String path;
  String? lastError;
  Future<void> _tail = Future.value();
  Future<void> write(Map<String, Object?> event) {
    _tail = _tail
        .then((_) async {
          final file = File(path);
          await file.parent.create(recursive: true);
          if (await file.exists() && await file.length() > 5 * 1024 * 1024) {
            final old = File('$path.1');
            if (await old.exists()) {
              await old.delete();
            }
            await file.rename(old.path);
          }
          await file.writeAsString(
            '${jsonEncode({'time': DateTime.now().toUtc().toIso8601String(), ...event})}\n',
            mode: FileMode.append,
            flush: true,
          );
          lastError = null;
        })
        .catchError((Object e) {
          lastError = 'Não foi possível gravar auditoria: $e';
        });
    return _tail;
  }

  Future<void> flush() => _tail;
}
