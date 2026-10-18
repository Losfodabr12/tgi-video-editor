import 'dart:io';

import '../domain/models/project.dart';
import 'app_component_paths.dart';
import 'ffmpeg_export_settings.dart';
import 'project_io_service.dart';

/// Collects a new independent folder. Source files and project are untouched.
class ProjectCollectionService {
  Future<String> collect(
    TgiProject project,
    String parentDirectory, {
    FfmpegExportSettings? exportSettings,
    void Function(int done, int total)? onProgress,
  }) async {
    final io = ProjectIOService();
    final data = io.serializeProject(project, exportSettings: exportSettings);
    final media = (data['mediaPool'] as List)
        .cast<Map<String, dynamic>>()
        .toList();
    data['mediaPool'] = media;
    final references = <({Map<String, dynamic> owner, String key})>[
      for (final item in media) (owner: item, key: 'filePath'),
      for (final transition
          in (data['transitions'] as List).cast<Map<String, dynamic>>())
        if ((transition['filePath'] as String? ?? '').isNotEmpty)
          (owner: transition, key: 'filePath'),
      if (project.watermark.enabled && project.watermark.imagePath.isNotEmpty)
        (owner: data['watermark'] as Map<String, dynamic>, key: 'imagePath'),
    ];
    // Check all inputs before creating the destination.
    for (final reference in references) {
      final path = reference.owner[reference.key] as String? ?? '';
      if (path.isEmpty || !await File(path).exists()) {
        throw FileSystemException(
          'Mídia ausente. Religue o arquivo antes de reunir o projeto.',
          path,
        );
      }
    }
    final parent = Directory(parentDirectory);
    await parent.create(recursive: true);
    final name = project.name.replaceAll(RegExp(r'[^\w\- ]'), '_').trim();
    final folder = await parent.createTemp(
      'TGI_${name.isEmpty ? 'Projeto' : name}_',
    );
    final mediaDir = Directory(joinPlatformPath([folder.path, 'media']));
    try {
      await mediaDir.create();
      final copied = <String, String>{};
      var done = 0;
      for (final reference in references) {
        final source = File(reference.owner[reference.key] as String).absolute;
        final key = Platform.isWindows
            ? source.path.toLowerCase()
            : source.path;
        var relative = copied[key];
        if (relative == null) {
          final filename = source.uri.pathSegments.last.replaceAll(
            RegExp(r'[^\w.\- ]'),
            '_',
          );
          relative =
              'media/${copied.length.toString().padLeft(4, '0')}_$filename';
          await source.copy(
            joinPlatformPath([
              folder.path,
              relative.replaceAll('/', Platform.pathSeparator),
            ]),
          );
          copied[key] = relative;
        }
        reference.owner[reference.key] = relative;
        onProgress?.call(++done, references.length);
      }
      for (final item in media) {
        item.remove('previewProxyPath');
        item.remove('thumbnailPath');
      }
      if (!project.watermark.enabled) {
        (data['watermark'] as Map<String, dynamic>)['imagePath'] = '';
      }
      data['portable'] = true;
      final projectPath = joinPlatformPath([folder.path, 'projeto.json']);
      await io.saveSerializedToFile(data, projectPath);
      await File(joinPlatformPath([folder.path, 'LEIA-ME.txt'])).writeAsString(
        'Abra projeto.json no TGI APP. Mantenha a pasta media junto ao projeto.\n'
        'Copie esta pasta inteira para transportar ou arquivar a edição.\n',
      );
      return projectPath;
    } catch (_) {
      // Only the newly-created, unique destination belongs to this operation.
      await folder.delete(recursive: true);
      rethrow;
    }
  }
}
