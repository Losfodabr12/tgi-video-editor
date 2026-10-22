import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'whisper_vulkan_manifest.dart';
import 'app_preferences_service.dart';

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

class WhisperExecution {
  const WhisperExecution({
    required this.backend,
    required this.device,
    required this.deviceId,
    required this.model,
    required this.fallback,
  });
  final String backend, device, deviceId, model;
  final bool fallback;
  Map<String, Object> toJson() => {
    'backend': backend,
    'device': device,
    'device_id': deviceId,
    'model': model,
    'fallback': fallback,
  };
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
  static final devices = ValueNotifier<List<WhisperGpuDevice>>(const []);
  static String activeDevice = 'CPU';
  static String get description => '${backend.value} — $activeDevice';
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
    activeDevice = 'CPU';
    fallbackReason = reason;
    backend.value = reason == null ? 'CPU' : 'CPU (fallback Vulkan)';
  }

  static Future<String> preferExecutable(
    String cpu, {
    String? preference,
  }) async {
    useCpu();
    if (!Platform.isWindows ||
        Platform.environment['TGI_WHISPER_BACKEND'] == 'cpu') {
      return cpu;
    }
    try {
      final choice =
          preference ??
          (await AppPreferencesService.instance.load()).whisperDevice;
      if (choice == 'cpu') return cpu;
      final detected = await probeDevices(cpu);
      devices.value = detected;
      if (detected.isEmpty) {
        throw const FormatException('Nenhuma GPU Vulkan compatível detectada.');
      }
      selectedDevice = selectDevice(detected, choice);
      if (selectedDevice == null) {
        throw const FormatException('A GPU escolhida não está disponível.');
      }
      activeDevice = selectedDevice!.name;
      backend.value = 'Vulkan disponível; verificando inferência';
      return '${File(cpu).parent.parent.path}/vulkan/bin/whisper-cli.exe';
    } catch (error) {
      useCpu(reason: 'Vulkan indisponível: $error');
      return cpu;
    }
  }

  static WhisperGpuDevice? selectDevice(
    List<WhisperGpuDevice> available,
    String choice,
  ) {
    if (choice == 'cpu' || available.isEmpty) return null;
    if (choice != 'auto') {
      for (final device in available) {
        if (device.id == choice) return device;
      }
      return null;
    }
    final ranked = [...available]
      ..sort((a, b) {
        if (a.discrete != b.discrete) return a.discrete ? -1 : 1;
        final aRtx = a.name.toUpperCase().contains('RTX');
        final bRtx = b.name.toUpperCase().contains('RTX');
        if (aRtx != bRtx) return aRtx ? -1 : 1;
        return b.freeBytes.compareTo(a.freeBytes);
      });
    return ranked.first;
  }

  static String? findCpuExecutable() {
    final explicit =
        Platform.environment['TGI_WHISPER_CPP_PATH'] ??
        Platform.environment['TGI_WHISPER_CLI_PATH'];
    if (explicit != null && File(explicit).existsSync()) return explicit;
    for (final initial in [
      Directory.current,
      File(Platform.resolvedExecutable).parent,
    ]) {
      var root = initial;
      for (var i = 0; i < 8; i++) {
        for (final relative in [
          'whisper/bin/whisper-cli.exe',
          'tools/whisper/bin/whisper-cli.exe',
          'source/tools/whisper/bin/whisper-cli.exe',
        ]) {
          final file = File('${root.path}/$relative');
          if (file.existsSync()) return file.absolute.path;
        }
        if (root.parent.path == root.path) break;
        root = root.parent;
      }
    }
    return null;
  }

  static Future<List<WhisperGpuDevice>> refreshDevices() async {
    try {
      final cpu = findCpuExecutable();
      devices.value = cpu == null ? const [] : await probeDevices(cpu);
    } catch (_) {
      devices.value = const [];
    }
    return devices.value;
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
