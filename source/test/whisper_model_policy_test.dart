import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/services/whisper_model_policy.dart';
import 'package:tgi_video_editor/services/whisper_runtime.dart';
import 'package:tgi_video_editor/services/transcript_store.dart';
import 'package:tgi_video_editor/domain/models/project.dart';

WhisperGpuDevice gpu({
  int free = WhisperModelPolicy.turboFreeBytes,
  int total = WhisperModelPolicy.turboTotalBytes,
}) => WhisperGpuDevice(
  index: 0,
  id: 'rtx',
  name: 'RTX',
  engine: 'Vulkan0',
  discrete: true,
  freeBytes: free,
  totalBytes: total,
);
void main() {
  test('new work uses turbo only with both VRAM limits met', () {
    expect(WhisperModelPolicy.choose(gpu: gpu()).model, 'large-v3-turbo-q5_0');
    for (final device in [
      null,
      gpu(free: WhisperModelPolicy.turboFreeBytes - 1),
      gpu(total: WhisperModelPolicy.turboTotalBytes - 1),
    ]) {
      final decision = WhisperModelPolicy.choose(gpu: device);
      expect(decision.model, 'small');
      expect(decision.forceCpu, isTrue);
    }
  });
  test('every manual model wins independently of hardware', () {
    for (final model in ['base', 'small', 'medium', 'large-v3-turbo-q5_0']) {
      expect(WhisperModelPolicy.choose(requested: model).model, model);
      expect(
        WhisperModelPolicy.choose(requested: model, gpu: gpu()).model,
        model,
      );
      expect(WhisperModelPolicy.choose(requested: model).forceCpu, isFalse);
    }
  });
  test(
    'existing v14 projects keep Base while new unsaved work is adaptive',
    () async {
      final dir = await Directory.systemTemp.createTemp('model_policy_');
      addTearDown(() => dir.delete(recursive: true));
      final project = TgiProject.empty(name: 'Synthetic');
      final store = TranscriptStore(directoryOverride: dir.path);
      await store.open(project, path: '${dir.path}/legacy.json');
      expect(store.modelName, 'base');
      expect(
        WhisperModelPolicy.choose(
          requested: store.modelName!,
          gpu: gpu(),
        ).model,
        'base',
      );
      await store.open(project, isNewProject: true);
      expect(store.modelName, isNull);
      store.modelName = 'medium';
      await store.save(project);
      await store.open(project);
      expect(store.modelName, 'medium');
    },
  );
  test(
    'automatic successful model is frozen on reopening the saved companion',
    () async {
      final dir = await Directory.systemTemp.createTemp('model_companion_');
      addTearDown(() => dir.delete(recursive: true));
      final project = TgiProject.empty(name: 'Synthetic');
      final store = TranscriptStore(directoryOverride: dir.path);
      await store.open(project, isNewProject: true);
      store.lastModelName = 'large-v3-turbo-q5_0';
      await store.save(project);
      final reopened = TranscriptStore(directoryOverride: dir.path);
      await reopened.open(project);
      expect(reopened.modelName, 'large-v3-turbo-q5_0');
      expect(
        WhisperModelPolicy.choose(requested: reopened.modelName!).model,
        'large-v3-turbo-q5_0',
      );
    },
  );
}
