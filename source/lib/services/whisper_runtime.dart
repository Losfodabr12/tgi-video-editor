import 'dart:io';
import 'package:crypto/crypto.dart';

abstract final class WhisperRuntime {
  static const version = '1.9.5';
  static const release = 'b5454';
  static const cpuCliSha256 =
      '331dba46d6427105d2b802cdbc7eae916ea1c5abf9b0d3b5cfe460d8db8e4366';
  static Future<void> verify(String executable) async {
    final digest = (await sha256.bind(File(executable).openRead()).first)
        .toString();
    if (digest != cpuCliSha256) {
      throw const FormatException(
        'Runtime Whisper diferente do pacote fixado. Execute tool/setup_tools.ps1.',
      );
    }
  }
}
