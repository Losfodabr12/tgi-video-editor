import 'app/app_identity.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'services/app_component_paths.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.setTitle(AppIdentity.name);
    await windowManager.setMinimumSize(const Size(720, 520));
  }
  await initializeAppComponentPaths();
  runApp(const VideoEditorApp());
}
