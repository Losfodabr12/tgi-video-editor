import 'dart:io';

import '../domain/models/media_item.dart';

class PreviewProxyCacheService {
  PreviewProxyCacheService({String? cacheDirectoryPath})
    : cacheDirectoryPath =
          cacheDirectoryPath ??
          _join(Directory.systemTemp.path, 'tgi_video_editor_preview_proxies');

  static final PreviewProxyCacheService instance = PreviewProxyCacheService();

  final String cacheDirectoryPath;

  Future<String> proxyPathFor(MediaItem item) async {
    final source = File(item.filePath);
    final stat = await source.stat();
    final fingerprint = _stableHash(
      '${source.absolute.path.toLowerCase()}|'
      '${stat.size}|${stat.modified.microsecondsSinceEpoch}|v1',
    );
    final stem = _sanitizeFileName(_fileStem(item.filePath));
    return _join(cacheDirectoryPath, '${fingerprint}_$stem.mp4');
  }

  Future<bool> isReusable(String proxyPath, FileStat sourceStat) async {
    final proxy = File(proxyPath);
    if (!await proxy.exists()) {
      return false;
    }
    final stat = await proxy.stat();
    return stat.size > 0 && !stat.modified.isBefore(sourceStat.modified);
  }

  Future<int> sizeInBytes() async {
    final directory = Directory(cacheDirectoryPath);
    if (!await directory.exists()) {
      return 0;
    }
    var total = 0;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } on FileSystemException {
          // A file may disappear while its size is being calculated.
        }
      }
    }
    return total;
  }

  Future<int> clear() async {
    final directory = Directory(cacheDirectoryPath);
    if (!await directory.exists()) {
      return 0;
    }
    var removed = 0;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      try {
        await entity.delete();
        removed++;
      } on FileSystemException {
        // Keep clearing the remaining cache if one file is currently in use.
      }
    }
    return removed;
  }

  static String _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final byte in value.codeUnits) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static String _sanitizeFileName(String value) {
    final sanitized = value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
    return sanitized.isEmpty ? 'video' : sanitized;
  }

  static String _fileStem(String value) {
    final name = value.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? name : name.substring(0, dot);
  }

  static String _join(String first, String second) =>
      [first, second].join(Platform.pathSeparator);
}
