import 'dart:convert';
import 'dart:io';

import '../domain/models/project.dart';
import 'app_component_paths.dart';

class RecentProjectEntry {
  const RecentProjectEntry({
    required this.projectName,
    required this.filePath,
    required this.updatedAt,
  });

  final String projectName;
  final String filePath;
  final DateTime updatedAt;

  factory RecentProjectEntry.fromJson(Map<String, dynamic> json) {
    return RecentProjectEntry(
      projectName: json['projectName'] as String? ?? 'Projeto recente',
      filePath: json['filePath'] as String? ?? '',
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'projectName': projectName,
    'filePath': filePath,
    'updatedAt': updatedAt.toIso8601String(),
  };
}

class RecentProjectService {
  const RecentProjectService();

  Future<RecentProjectEntry?> loadLastProject() async {
    try {
      final file = File(_statePath());
      if (!await file.exists()) {
        return null;
      }
      final data = jsonDecode(await file.readAsString());
      if (data is! Map<String, dynamic>) {
        return null;
      }
      final entry = RecentProjectEntry.fromJson(data);
      if (entry.filePath.trim().isEmpty) {
        return null;
      }
      return entry;
    } catch (_) {
      return null;
    }
  }

  Future<void> recordProject({
    required TgiProject project,
    required String filePath,
  }) async {
    try {
      final cleanPath = filePath.trim();
      if (cleanPath.isEmpty) {
        return;
      }
      final file = File(_statePath());
      await file.parent.create(recursive: true);
      final entry = RecentProjectEntry(
        projectName: project.name,
        filePath: cleanPath,
        updatedAt: DateTime.now(),
      );
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(entry.toJson()),
      );
    } catch (_) {
      // Recent-project state is optional; saving a project must not depend on it.
    }
  }

  Future<void> clearLastProject() async {
    try {
      final file = File(_statePath());
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort cleanup only.
    }
  }

  String _statePath() {
    return [
      tgiAppLocalDataRoot(),
      'recent_project.json',
    ].join(Platform.pathSeparator);
  }
}
