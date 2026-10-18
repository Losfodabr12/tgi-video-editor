import 'package:flutter/material.dart';

import '../features/editor/presentation/editor_screen.dart';
import '../services/app_preferences_service.dart';
import '../services/project_recovery_service.dart';
import 'theme/app_theme.dart';

class VideoEditorApp extends StatefulWidget {
  const VideoEditorApp({super.key});

  @override
  State<VideoEditorApp> createState() => _VideoEditorAppState();
}

class _VideoEditorAppState extends State<VideoEditorApp> {
  final _preferences = AppPreferencesService.instance;
  late final _startup = _loadStartup();

  Future<ProjectRecoveryEntry?> _loadStartup() async {
    await _preferences.load();
    return ProjectRecoveryService().loadDraft();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppVisualStyle>(
      valueListenable: _preferences.visualStyleListenable,
      builder: (context, style, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Editor de Video',
        theme: TgiTheme.forStyle(style),
        home: FutureBuilder<ProjectRecoveryEntry?>(
          future: _startup,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            final recovery = snapshot.data;
            return EditorScreen(
              startPreset: recovery == null
                  ? EditorStartPreset.standard
                  : editorStartPresetForProject(
                      recovery.project,
                      exportSettings: recovery.exportSettings,
                    ),
              initialProject: recovery?.project,
              initialProjectPath: recovery?.originalProjectPath,
              initialExportSettings: recovery?.exportSettings,
              initialMissingMediaItems: recovery?.missingMediaItems ?? const [],
              isRecoveredDraft: recovery != null,
            );
          },
        ),
      ),
    );
  }
}
