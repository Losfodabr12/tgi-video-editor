import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

abstract final class WhisperRuntime {
  static const version = '1.9.5';
  static const release = 'b5454';
  static const cpuCliSha256 =
      '331dba46d6427105d2b802cdbc7eae916ea1c5abf9b0d3b5cfe460d8db8e4366';
  static const cudaCliSha256 =
      '80fe839a13f5fd70d7511e6f714498de12522e59da2a5333c6efea40fe05ee51';
  static final backend = ValueNotifier<String>('Aguardando transcrição');
  static String? fallbackReason;
  static bool usesCuda(String output) => RegExp(
    r'using (?:device CUDA|CUDA(?:\d+)? backend)',
    caseSensitive: false,
  ).hasMatch(output);
  static Future<String> preferExecutable(String cpu) async {
    fallbackReason = null;
    if (!Platform.isWindows ||
        Platform.environment['TGI_WHISPER_BACKEND'] == 'cpu') {
      backend.value = 'CPU';
      return cpu;
    }
    final cuda = File(
      '${File(cpu).parent.parent.path}/cuda/bin/whisper-cli.exe',
    );
    if (!await cuda.exists()) {
      backend.value = 'CPU';
      fallbackReason = 'Pacote CUDA não instalado';
      return cpu;
    }
    final search = [
      cuda.parent.path,
      '${Platform.environment['WINDIR'] ?? r'C:\Windows'}/System32',
      ...?Platform.environment['PATH']?.split(';'),
    ];
    if (!search.any((p) => File('$p/cublas64_11.dll').existsSync())) {
      fallbackReason =
          'CUDA indisponível: cublas64_11.dll ausente (dependência do ggml-cuda.dll; Windows erro 126).';
      backend.value = 'CPU (fallback CUDA)';
      return cpu;
    }
    try {
      await verify(cuda.path);
      final gpu = await Process.run('nvidia-smi', [
        '--query-gpu=name',
        '--format=csv,noheader',
      ], runInShell: false).timeout(const Duration(seconds: 4));
      if (gpu.exitCode == 0 && gpu.stdout.toString().trim().isNotEmpty) {
        backend.value = 'CUDA disponível; verificando inferência';
        return cuda.path;
      }
      fallbackReason = 'nvidia-smi retornou ${gpu.exitCode}: ${gpu.stderr}'
          .trim();
    } catch (e) {
      fallbackReason = e.toString();
    }
    backend.value = 'CPU (fallback)';
    return cpu;
  }

  static Future<void> verify(String executable) async {
    final digest = (await sha256.bind(File(executable).openRead()).first)
        .toString();
    if (digest != cpuCliSha256 && digest != cudaCliSha256) {
      throw const FormatException(
        'Runtime Whisper diferente do pacote fixado. Execute tool/setup_tools.ps1.',
      );
    }
  }
}
