import 'dart:io';
import '../core/commands/editor_command.dart';
import '../domain/models/media_item.dart';
import '../domain/models/project.dart';
import '../services/export_destination_service.dart';

class McpPathPolicy {
  McpPathPolicy({this.projectDirectory, this.exportDirectory});
  String? projectDirectory, exportDirectory;
  final Map<String, String> _trustedFiles = {};
  String? _projectId;
  static String _normal(String path) =>
      Platform.isWindows ? path.replaceAll('/', '\\').toLowerCase() : path;
  static bool _localAbsolute(String path) =>
      !path.startsWith('\\\\') &&
      !path.startsWith('//') &&
      (Platform.isWindows
          ? RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path)
          : path.startsWith('/'));
  static bool _inside(String path, String root) =>
      _normal(path) == _normal(root) ||
      _normal(path).startsWith('${_normal(root)}${Platform.pathSeparator}');
  Future<String> _file(String path) async {
    if (!_localAbsolute(path) ||
        path.contains('\u0000') ||
        (Platform.isWindows && path.substring(2).contains(':'))) {
      throw const CommandError(
        'path_not_allowed',
        'Use somente arquivos locais importados no projeto. Caminhos relativos, rede e streams não são aceitos.',
      );
    }
    if (!await File(path).exists()) {
      throw const CommandError(
        'media_missing',
        'Arquivo indisponível. Reconecte a mídia pela interface.',
      );
    }
    return File(path).resolveSymbolicLinks();
  }

  /// Called only from the app's trusted project/import flow, never from a tool.
  /// Existing grants are pinned to canonical targets, preventing link retargeting.
  Future<void> trustProject(TgiProject project) async {
    if (_projectId != project.id) {
      _trustedFiles.clear();
      _projectId = project.id;
    }
    final paths = {
      for (final m in project.mediaPool)
        if (m.type != MediaType.text) m.filePath,
      for (final t in project.transitions)
        if (t.filePath.isNotEmpty) t.filePath,
      if (project.watermark.imagePath.isNotEmpty) project.watermark.imagePath,
    };
    _trustedFiles.removeWhere((path, _) => !paths.contains(path));
    for (final path in paths) {
      if (_trustedFiles.containsKey(path)) {
        continue;
      }
      try {
        _trustedFiles[path] = await _file(path);
      } on CommandError {
        /* Missing media stays ungranted. */
      }
    }
  }

  Future<String> authorizeMedia(MediaItem media) =>
      authorizeFile(media.filePath);
  Future<String> authorizeFile(String path) async {
    final canonical = await _file(path), trusted = _trustedFiles[path];
    if (trusted != null && _normal(canonical) == _normal(trusted)) {
      return canonical;
    }
    final directory = projectDirectory;
    if (trusted == null &&
        directory != null &&
        await Directory(directory).exists()) {
      final root = await Directory(directory).resolveSymbolicLinks();
      if (_inside(canonical, root)) {
        return canonical;
      }
    }
    throw const CommandError(
      'path_not_allowed',
      'Arquivo fora do projeto ou das mídias importadas. Importe-o pela interface do app.',
    );
  }

  Future<void> authorizeProject(TgiProject project) async {
    for (final m in project.mediaPool.where((m) => m.type != MediaType.text)) {
      await authorizeMedia(m);
    }
    for (final t in project.transitions.where((t) => t.filePath.isNotEmpty)) {
      await authorizeFile(t.filePath);
    }
    if (project.watermark.enabled && project.watermark.imagePath.isNotEmpty) {
      await authorizeFile(project.watermark.imagePath);
    }
  }

  Future<String> resolveExport(String filename) async {
    if (filename != ExportDestinationService.sanitizeFileName(filename) ||
        filename == '.' ||
        filename == '..' ||
        !RegExp(r'\.(mp4|wav)$', caseSensitive: false).hasMatch(filename)) {
      throw const CommandError(
        'path_not_allowed',
        'Use somente um nome de arquivo .mp4/.wav, sem caminho, .., separadores ou caracteres reservados.',
      );
    }
    final chosen = exportDirectory;
    if (chosen == null ||
        !_localAbsolute(chosen) ||
        !await Directory(chosen).exists()) {
      throw const CommandError(
        'export_directory_required',
        'Escolha uma pasta local existente nas configurações MCP do app.',
      );
    }
    final root = await Directory(chosen).resolveSymbolicLinks();
    final path = ExportDestinationService.join(root, filename);
    await authorizeExport(path);
    return path;
  }

  Future<void> authorizeExport(String path) async {
    final chosen = exportDirectory;
    if (chosen == null || !_localAbsolute(path) || !_localAbsolute(chosen)) {
      throw const CommandError(
        'path_not_allowed',
        'Pasta de exportação não autorizada.',
      );
    }
    final root = await Directory(chosen).resolveSymbolicLinks();
    final parent = await File(path).parent.resolveSymbolicLinks();
    if (_normal(root) != _normal(parent) ||
        !RegExp(r'\.(mp4|wav)$', caseSensitive: false).hasMatch(path)) {
      throw const CommandError(
        'path_not_allowed',
        'Exportação permitida somente na pasta escolhida pelo usuário.',
      );
    }
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const CommandError(
        'file_exists',
        'Arquivo já existe. Escolha outro nome; MCP não sobrescreve arquivos.',
      );
    }
  }
}
