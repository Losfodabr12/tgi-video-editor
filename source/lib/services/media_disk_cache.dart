import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'app_component_paths.dart';

class MediaDiskCache {
  MediaDiskCache({String? directoryPath})
    : directoryPath =
          directoryPath ?? joinPlatformPath([tgiAppLocalDataRoot(), 'cache']);
  final String directoryPath;

  static Future<String> fingerprint(String path, String variant) async {
    final file = File(path).absolute;
    final stat = await file.stat();
    final normalized = Platform.isWindows ? file.path.toLowerCase() : file.path;
    return sha256
        .convert(
          utf8.encode(
            '$normalized|${stat.size}|${stat.modified.microsecondsSinceEpoch}|$variant',
          ),
        )
        .toString();
  }

  Future<File> entry(String path, String variant, String extension) async {
    final key = await fingerprint(path, variant);
    final directory = Directory(directoryPath);
    await directory.create(recursive: true);
    return File(joinPlatformPath([directory.path, '$key.$extension']));
  }

  static Future<void> publish(File temporary, File target) async {
    try {
      await temporary.rename(target.path);
    } on FileSystemException {
      // Another instance may have completed this cache entry first.
      if (!await target.exists() || await target.length() == 0) rethrow;
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
