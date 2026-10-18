import 'dart:io';

import 'package:file_picker/file_picker.dart';

final class ExportDestinationService {
  const ExportDestinationService._();

  static Future<String?> pickPath({
    required String dialogTitle,
    required String fileName,
    required List<String> allowedExtensions,
    String? initialDirectory,
    bool lockParentWindow = false,
  }) async {
    final safeFileName = sanitizeFileName(fileName);
    if (Platform.isAndroid || Platform.isIOS) {
      final directory = await FilePicker.getDirectoryPath(
        dialogTitle: '$dialogTitle - escolha a pasta',
      );
      if (directory == null || directory.trim().isEmpty) {
        return null;
      }
      return join(directory, safeFileName);
    }

    return FilePicker.saveFile(
      dialogTitle: dialogTitle,
      initialDirectory: initialDirectory,
      fileName: safeFileName,
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      lockParentWindow: lockParentWindow,
    );
  }

  static String join(String directory, String fileName) {
    final separator = Platform.pathSeparator;
    return directory.endsWith(separator)
        ? '$directory$fileName'
        : '$directory$separator$fileName';
  }

  static String sanitizeFileName(String value) {
    final trimmed = value.trim();
    final sanitized = trimmed
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'[. ]+$'), '')
        .trim();
    if (sanitized.isEmpty) {
      return 'arquivo';
    }

    final dot = sanitized.indexOf('.');
    final stem = (dot < 0 ? sanitized : sanitized.substring(0, dot)).trim();
    final reserved = RegExp(
      r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])$',
      caseSensitive: false,
    );
    return reserved.hasMatch(stem) ? '_$sanitized' : sanitized;
  }
}
