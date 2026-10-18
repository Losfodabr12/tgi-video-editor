import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../domain/models/project.dart';
import 'app_component_paths.dart';
import 'ffmpeg_export_settings.dart';
import 'project_io_service.dart';

class ProjectHistoryEntry {
  const ProjectHistoryEntry({
    required this.path,
    required this.savedAt,
    required this.label,
    required this.projectName,
  });
  final String path;
  final DateTime savedAt;
  final String label;
  final String projectName;
}

class ProjectHistoryService {
  ProjectHistoryService({String? directoryPath, this.limit = 30})
    : directoryPath =
          directoryPath ??
          joinPlatformPath([tgiAppLocalDataRoot(), 'project_history']);
  final String directoryPath;
  final int limit;
  static final _pending = <String, Future<void>>{};
  final _io = ProjectIOService();

  Directory _directory(String projectId) => Directory(
    joinPlatformPath([
      directoryPath,
      sha256.convert(utf8.encode(projectId)).toString(),
    ]),
  );

  Future<void> record(
    TgiProject project, {
    FfmpegExportSettings? exportSettings,
    String label = 'Salvamento',
  }) {
    final dir = _directory(project.id);
    final key = dir.absolute.path;
    final result = (_pending[key] ?? Future<void>.value()).then((_) async {
      await dir.create(recursive: true);
      final now = DateTime.now();
      final data = _io.serializeProject(
        project,
        exportSettings: exportSettings,
      );
      data['_history'] = {'savedAt': now.toIso8601String(), 'label': label};
      final file = joinPlatformPath([
        dir.path,
        '${now.microsecondsSinceEpoch}.json',
      ]);
      await _io.saveSerializedToFile(data, file);
      final entries = await list(project.id);
      for (final entry in entries.skip(limit < 1 ? 1 : limit)) {
        await File(entry.path).delete();
      }
    });
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _pending[key] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_pending[key], tail)) _pending.remove(key);
      }),
    );
    return result;
  }

  Future<List<ProjectHistoryEntry>> list(String projectId) async {
    final dir = _directory(projectId);
    if (!await dir.exists()) return [];
    final entries = <ProjectHistoryEntry>[];
    await for (final file in dir.list(followLinks: false)) {
      if (file is! File || !RegExp(r'[\\/]\d+\.json$').hasMatch(file.path)) {
        continue;
      }
      try {
        final data = await _io.readFromFile(file.path);
        final metadata = data['_history'] as Map<String, dynamic>;
        entries.add(
          ProjectHistoryEntry(
            path: file.path,
            savedAt: DateTime.parse(metadata['savedAt'] as String),
            label: metadata['label'] as String? ?? 'Salvamento',
            projectName: data['projectName'] as String? ?? 'Projeto',
          ),
        );
      } catch (_) {
        // A damaged entry must not hide the other recoverable versions.
      }
    }
    entries.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return entries;
  }

  Future<ProjectLoadResult> restore(ProjectHistoryEntry entry) async =>
      _io.deserializeProject(await _io.readFromFile(entry.path));
}
