import 'dart:async';
import 'dart:io';

class EditorDebugLog {
  const EditorDebugLog._();

  static const enabled = bool.fromEnvironment('TGI_EDITOR_DEBUG_LOG');

  static Future<void> _writeQueue = Future<void>.value();

  static Future<void> clear() async {
    if (!enabled) {
      return;
    }
    try {
      await _writeQueue;
      final file = File(path);
      if (await file.exists()) {
        await file.writeAsString('');
      }
    } catch (_) {
      // Logging must never affect editing.
    }
  }

  static void write(String area, String message) {
    if (!enabled) {
      return;
    }
    final line =
        '${DateTime.now().toIso8601String()} [$area] $message${Platform.lineTerminator}';
    _writeQueue = _writeQueue.then((_) => _append(line));
    unawaited(_writeQueue);
  }

  static String get path {
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.trim().isNotEmpty) {
      return _join(_join(appData, 'TGI Video Editor'), 'editor_debug.log');
    }
    return _join(Directory.current.path, 'editor_debug.log');
  }

  static Future<void> _append(String line) async {
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(line, mode: FileMode.append, flush: true);
    } catch (_) {
      // Logging must never affect editing.
    }
  }

  static String _join(String first, String second) {
    return first.endsWith(Platform.pathSeparator)
        ? '$first$second'
        : '$first${Platform.pathSeparator}$second';
  }
}
