import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'whisper_vulkan_manifest.dart';

class WhisperGpuDevice {
  const WhisperGpuDevice({
    required this.index,
    required this.id,
    required this.name,
    required this.engine,
    required this.discrete,
    required this.freeBytes,
    required this.totalBytes,
  });
  final int index, freeBytes, totalBytes;
  final String id, name, engine;
  final bool discrete;
  factory WhisperGpuDevice.fromJson(Map<String, dynamic> json) =>
      WhisperGpuDevice(
        index: json['index'] as int,
        id: json['id'] as String,
        name: json['name'] as String,
        engine: json['engine'] as String,
        discrete: json['discrete'] as bool,
        freeBytes: json['free'] as int,
        totalBytes: json['total'] as int,
      );
}

abstract final class WhisperRuntime {
  static const version = '1.9.5';
  static const release = 'b5454';
  static const cpuCliSha256 =
      '331dba46d6427105d2b802cdbc7eae916ea1c5abf9b0d3b5cfe460d8db8e4366';
  static const cudaCliSha256 =
      '80fe839a13f5fd70d7511e6f714498de12522e59da2a5333c6efea40fe05ee51';

  static final backend = ValueNotifier<String>('Aguardando transcrição');
  static String? fallbackReason;
  static WhisperGpuDevice? selectedDevice;
  static bool usesCuda(String output) => RegExp(
    r'using (?:device CUDA|CUDA(?:\d+)? backend)',
    caseSensitive: false,
  ).hasMatch(output);
  static String? vulkanEngine(String output) => RegExp(
    r'whisper_backend_init_gpu: using (Vulkan\d+) backend',
  ).firstMatch(output)?.group(1);

  static Map<String, String> get manifest {
    const encoded = String.fromEnvironment('TGI_VULKAN_MANIFEST');
    return encoded.isEmpty
        ? bundledVulkanManifest
        : Map<String, String>.from(
            jsonDecode(utf8.decode(base64Decode(encoded))) as Map,
          );
  }

  static Future<void> verifyVulkan(String directory) async {
    final hashes = manifest;
    const required = {
      'whisper-cli.exe',
      'whisper.dll',
      'ggml.dll',
      'ggml-base.dll',
      'ggml-cpu.dll',
      'ggml-vulkan.dll',
      'vulkan-probe.exe',
    };
    if (!hashes.keys.toSet().containsAll(required) ||
        hashes.length != required.length) {
      throw const FormatException('Manifesto Vulkan incompleto.');
    }
    for (final entry in hashes.entries) {
      final digest =
          (await sha256.bind(File('$directory/${entry.key}').openRead()).first)
              .toString();
      if (digest != entry.value) {
        throw FormatException('SHA-256 Vulkan inválido: ${entry.key}');
      }
    }
  }

  static Future<List<WhisperGpuDevice>> probeDevices(
    String cpu, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final directory = '${File(cpu).parent.parent.path}/vulkan/bin';
    await verifyVulkan(directory);
    final process = await Process.start(
      '$directory/vulkan-probe.exe',
      const [],
    );
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.drain<void>();
    try {
      final code = await process.exitCode.timeout(timeout);
      await errors.timeout(const Duration(seconds: 2));
      final body = await output.timeout(const Duration(seconds: 2));
      if (code != 0) {
        throw ProcessException(
          'vulkan-probe',
          [],
          'Driver Vulkan indisponível',
          code,
        );
      }
      return parseDevices(body);
    } on TimeoutException {
      process.kill();
      throw const FormatException(
        'Detecção Vulkan excedeu o limite; CPU será usada.',
      );
    } finally {
      process.kill();
    }
  }

  static List<WhisperGpuDevice> parseDevices(String output) => [
    for (final row in jsonDecode(output) as List)
      WhisperGpuDevice.fromJson(Map<String, dynamic>.from(row as Map)),
  ];

  static void useCpu({String? reason}) {
    selectedDevice = null;
    fallbackReason = reason;
    backend.value = reason == null ? 'CPU' : 'CPU (fallback Vulkan)';
  }

  static Future<String> preferExecutable(String cpu) async {
    useCpu();
    if (!Platform.isWindows ||
        Platform.environment['TGI_WHISPER_BACKEND'] == 'cpu') {
      return cpu;
    }
    try {
      final devices = await probeDevices(cpu);
      if (devices.isEmpty) {
        throw const FormatException('Nenhuma GPU Vulkan compatível detectada.');
      }
      selectedDevice = devices.first;
      backend.value = 'Vulkan disponível; verificando inferência';
      return '${File(cpu).parent.parent.path}/vulkan/bin/whisper-cli.exe';
    } catch (error) {
      useCpu(reason: 'Vulkan indisponível: $error');
      return cpu;
    }
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
