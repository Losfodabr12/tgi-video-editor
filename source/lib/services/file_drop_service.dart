import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

bool canHandleFileDrop({required bool routeIsCurrent, bool active = true}) {
  return routeIsCurrent && active;
}

class DroppedFilesEvent {
  const DroppedFilesEvent({
    required this.files,
    required this.x,
    required this.y,
  });

  final List<String> files;
  final double x;
  final double y;
}

class FileDropService {
  FileDropService._();

  static const _channel = MethodChannel('tgi_app_suite/drop_files');
  static final _events = StreamController<DroppedFilesEvent>.broadcast();
  static bool _initialized = false;

  static Stream<DroppedFilesEvent> get events {
    _ensureInitialized();
    return _events.stream;
  }

  static void _ensureInitialized() {
    if (_initialized || !Platform.isWindows) {
      return;
    }
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'filesDropped') {
        return;
      }
      final args = call.arguments;
      if (args is! Map) {
        return;
      }
      final rawFiles = args['files'];
      final files = <String>[
        if (rawFiles is List)
          for (final file in rawFiles)
            if (file is String && file.trim().isNotEmpty) file,
      ];
      if (files.isEmpty) {
        return;
      }
      final x = args['x'];
      final y = args['y'];
      _events.add(
        DroppedFilesEvent(
          files: files,
          x: x is num ? x.toDouble() : 0,
          y: y is num ? y.toDouble() : 0,
        ),
      );
    });
  }
}
