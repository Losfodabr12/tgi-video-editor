import 'dart:io';

import '../domain/models/project.dart';
import 'app_component_paths.dart';
import 'ffmpeg_export_settings.dart';
import 'project_io_service.dart';
import 'project_file_storage.dart';

class ProjectRecoveryEntry {
  const ProjectRecoveryEntry({
    required this.project,
    required this.missingMediaItems,
    required this.savedAt,
    required this.originalProjectPath,
    required this.editorStartPreset,
    required this.exportSettings,
  });

  final TgiProject project;
  final List<Map<String, dynamic>> missingMediaItems;
  final DateTime savedAt;
  final String? originalProjectPath;
  final String? editorStartPreset;
  final FfmpegExportSettings? exportSettings;
}

class ProjectRecoveryService {
  ProjectRecoveryService({
    ProjectIOService? projectIOService,
    this.recoveryFilePath,
  }) : _projectIOService = projectIOService ?? ProjectIOService(),
       assert(recoveryFilePath == null || recoveryFilePath != '');

  static const _recoveryKey = 'tgiRecovery';
  static const _savedAtKey = 'savedAt';
  static const _originalProjectPathKey = 'originalProjectPath';
  static const _editorStartPresetKey = 'editorStartPreset';

  final ProjectIOService _projectIOService;
  final String? recoveryFilePath;

  Future<void> saveDraft({
    required TgiProject project,
    String? originalProjectPath,
    String? editorStartPreset,
    FfmpegExportSettings? exportSettings,
    DateTime? savedAt,
  }) async {
    final data = _projectIOService.serializeProject(
      project,
      exportSettings: exportSettings,
    );
    data[_recoveryKey] = <String, dynamic>{
      _savedAtKey: (savedAt ?? DateTime.now()).toIso8601String(),
      _originalProjectPathKey: originalProjectPath,
      _editorStartPresetKey: editorStartPreset,
    };
    await _projectIOService.saveSerializedToFile(data, _statePath());
  }

  Future<ProjectRecoveryEntry?> loadDraft() async {
    try {
      final decoded = await _projectIOService.readFromFile(_statePath());
      final recovery = decoded[_recoveryKey];
      if (recovery is! Map<String, dynamic>) {
        return null;
      }
      final savedAt = DateTime.tryParse(recovery[_savedAtKey] as String? ?? '');
      if (savedAt == null) {
        return null;
      }
      final result = _projectIOService.deserializeProject(decoded);
      final originalPath = (recovery[_originalProjectPathKey] as String?)
          ?.trim();
      final startPreset = (recovery[_editorStartPresetKey] as String?)?.trim();
      return ProjectRecoveryEntry(
        project: result.project,
        missingMediaItems: result.missingMediaItems,
        savedAt: savedAt,
        originalProjectPath: originalPath == null || originalPath.isEmpty
            ? null
            : originalPath,
        editorStartPreset: startPreset == null || startPreset.isEmpty
            ? null
            : startPreset,
        exportSettings: result.exportSettings,
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> clearDraft() async {
    try {
      await ProjectFileStorage.delete(_statePath());
      return true;
    } catch (_) {
      // Recovery is best effort and must never block the editor.
      return false;
    }
  }

  String _statePath() {
    return recoveryFilePath ??
        [
          tgiAppLocalDataRoot(),
          'project_recovery.json',
        ].join(Platform.pathSeparator);
  }
}
