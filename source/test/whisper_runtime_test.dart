import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/services/whisper_runtime.dart';

void main() {
  test('device presence does not claim GPU inference', () {
    expect(WhisperRuntime.vulkanEngine('ggml_vulkan: 0 = NVIDIA RTX'), isNull);
    expect(
      WhisperRuntime.vulkanEngine(
        'whisper_backend_init_gpu: using Vulkan1 backend\n'
        'whisper_model_load: Vulkan1 total size = 573.40 MB',
      ),
      'Vulkan1',
    );
    expect(WhisperRuntime.vulkanEngine('whisper_init: no GPU found'), isNull);
  });
  test(
    'missing Vulkan runtime returns CPU without failing transcription setup',
    () async {
      final selected = await WhisperRuntime.preferExecutable(
        'missing/bin/whisper-cli.exe',
      );
      expect(selected, 'missing/bin/whisper-cli.exe');
      expect(WhisperRuntime.backend.value, startsWith('CPU'));
      expect(WhisperRuntime.selectedDevice, isNull);
    },
  );
  test('tampered DLLs are rejected before loading a driver', () async {
    final temp = await Directory.systemTemp.createTemp('vulkan_integrity_');
    addTearDown(() => temp.delete(recursive: true));
    for (final name in WhisperRuntime.manifest.keys) {
      await File('${temp.path}/$name').writeAsString('corrupt');
    }
    await expectLater(
      WhisperRuntime.verifyVulkan(temp.path),
      throwsFormatException,
    );
  });
  test(
    'failed GPU initialization never claims Vulkan from a selection log',
    () {
      const selection = 'whisper_backend_init_gpu: using Vulkan0 backend';
      expect(WhisperRuntime.vulkanEngine(selection), isNull);
      expect(
        WhisperRuntime.vulkanEngine(
          '$selection\nfailed to initialize Vulkan0 backend',
        ),
        isNull,
      );
      expect(
        WhisperRuntime.vulkanEngine(
          '$selection\nwhisper_model_load: Vulkan1 total size = 10 MB',
        ),
        isNull,
      );
      expect(
        WhisperRuntime.vulkanEngine(
          '$selection\nwhisper_model_load: Vulkan0 total size = 0.00 MB',
        ),
        isNull,
      );
    },
  );
}
