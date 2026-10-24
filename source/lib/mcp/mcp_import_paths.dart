import 'dart:io';
import '../core/commands/editor_command.dart';

/// User grants for new imports, independent of already imported project media.
class McpImportPaths {
  McpImportPaths({List<String> directories = const []})
    : directories = List.unmodifiable(directories);

  List<String> directories;

  static String _normal(String value) {
    var path = Platform.isWindows
        ? value.replaceAll('/', '\\').toLowerCase()
        : value;
    final minimum = Platform.isWindows ? 3 : 1;
    while (path.length > minimum &&
        (path.endsWith('/') || path.endsWith('\\'))) {
      path = path.substring(0, path.length - 1);
    }
    return path;
  }

  static bool _inside(String path, String root) {
    final p = _normal(path), r = _normal(root);
    return p == r || p.startsWith('$r${Platform.pathSeparator}');
  }

  static void _shape(String path) {
    if (path.length > 4096 ||
        path.contains(RegExp(r'[\x00-\x1f]')) ||
        path.startsWith('\\\\') ||
        path.startsWith('//') ||
        path.split(RegExp(r'[\\/]')).any((p) => p == '..' || p == '.') ||
        (Platform.isWindows
            ? !RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path) ||
                  path.substring(2).contains(':')
            : !path.startsWith('/'))) {
      throw const CommandError(
        'path_not_allowed',
        'Use um caminho local absoluto, sem .., links, rede ou streams.',
      );
    }
  }

  static Future<String> directory(String path) async {
    _shape(path);
    await _rejectLinks(path);
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const CommandError('path_not_allowed', 'Pasta local inexistente.');
    }
    return Directory(path).resolveSymbolicLinks();
  }

  Future<String> file(String path) async {
    _shape(path);
    for (final chosen in List<String>.of(directories)) {
      _shape(chosen);
      final root = await directory(chosen);
      // Windows may spell the same directory with an 8.3 name. Revalidation
      // must also accept the canonical path returned by the first check.
      if (!_inside(path, chosen) && !_inside(path, root)) continue;
      await _rejectLinks(path);
      if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const CommandError('media_missing', 'Arquivo local inexistente.');
      }
      final resolved = await File(path).resolveSymbolicLinks();
      if (_inside(resolved, root)) return resolved;
    }
    throw const CommandError(
      'path_not_allowed',
      'Autorize a pasta de importação nas configurações de IA do app.',
    );
  }

  static Future<void> _rejectLinks(String path) async {
    var current = path;
    while (true) {
      final kind = await FileSystemEntity.type(current, followLinks: false);
      if (kind == FileSystemEntityType.link) {
        throw const CommandError(
          'path_not_allowed',
          'Links simbólicos e junctions não são aceitos na importação.',
        );
      }
      // Inspect every ancestor without following links. Comparing spellings
      // after resolution would also reject harmless Windows short names.
      final parent = File(current).parent.path;
      if (_normal(parent) == _normal(current)) break;
      current = parent;
    }
  }
}
