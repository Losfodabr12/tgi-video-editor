import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/services/auto_caption_service.dart';
import 'package:tgi_video_editor/services/transcript_store.dart';
import 'package:tgi_video_editor/services/whisper_runtime.dart';
import 'package:tgi_video_editor/services/project_io_service.dart';
import 'package:tgi_video_editor/services/ffmpeg_service.dart';
import 'package:tgi_video_editor/services/media_import_service.dart';
import 'package:tgi_video_editor/domain/models/media_item.dart';
import 'package:tgi_video_editor/features/editor/application/editor_controller.dart';
import 'package:tgi_video_editor/mcp/editor_read_service.dart';
import 'support/silence_project.dart';

class RecordingCaptions implements AutoCaptionService {
  String? used;
  String? prompt;
  bool? usedVad;
  @override
  Future<List<CaptionCue>> generateCaptionsForMedia(
    MediaItem media, {
    String? languageCode,
    String modelName = '',
    String vocabulary = '',
    bool vad = true,
    int maxCharsPerCue = 44,
    AutoCaptionProgressCallback? onProgress,
  }) async {
    used = languageCode;
    prompt = vocabulary;
    usedVad = vad;
    return const [
      CaptionCue(
        start: Duration(seconds: 1),
        end: Duration(seconds: 3),
        text: 'Olá mundo',
        words: [
          CaptionWord(
            start: Duration(seconds: 1),
            end: Duration(milliseconds: 1700),
            text: 'Olá',
          ),
          CaptionWord(
            start: Duration(seconds: 2),
            end: Duration(seconds: 3),
            text: 'mundo',
          ),
        ],
      ),
    ];
  }
}

void main() {
  test(
    'VAD and vocabulary map exactly to CLI flags; off adds no VAD flags',
    () {
      expect(
        whisperSpeechArguments(vocabulary: '  Arsenal  ', vadModel: 'vad.bin'),
        ['--prompt', 'Arsenal', '--vad', '-vm', 'vad.bin'],
      );
      expect(whisperSpeechArguments(), isEmpty);
      expect(
        () => whisperSpeechArguments(vocabulary: 'a' * 2001),
        throwsA(isA<AutoCaptionException>()),
      );
    },
  );

  test(
    'timed boundaries stay within one 30fps frame, including 0.60s tail',
    () {
      final words = [
        for (var i = 0; i < 18; i++)
          CaptionWord(
            start: Duration(milliseconds: 100 + i * 600),
            end: Duration(milliseconds: 700 + i * 600),
            text: i == 17 ? 'tchau!' : 'palavra',
          ),
      ];
      final cues = minimumCaptionCues(
        segmentCaptionCues([
          CaptionCue(
            start: Duration.zero,
            end: const Duration(seconds: 30),
            text: words.map((w) => w.text).join(' '),
            words: words,
          ),
        ]),
      );
      expect(cues.last.end, words.last.end);
      expect(
        cues.every((c) => c.duration >= const Duration(seconds: 1)),
        isTrue,
      );
      for (final cue in cues) {
        expect(
          (cue.start - cue.words.first.start).inMicroseconds.abs(),
          lessThanOrEqualTo(33333),
        );
        expect(
          (cue.end - cue.words.last.end).inMicroseconds.abs(),
          lessThanOrEqualTo(33333),
        );
        expect(cue.text.replaceAll('\n', ' ').length, lessThanOrEqualTo(44));
        expect(cue.text.split('\n').length, lessThanOrEqualTo(2));
      }
      expect(cues.expand((c) => c.words).length, words.length);
    },
  );
  test(
    'sidecar survives fresh controller and MCP; media hash invalidates it; v14 unchanged',
    () async {
      final dir = await Directory.systemTemp.createTemp('words-roundtrip-');
      addTearDown(() => dir.delete(recursive: true));
      final mediaFile = File('${dir.path}/speech.wav');
      await mediaFile.writeAsBytes([1, 2, 3, 4]);
      final base = silenceProject();
      final project = base.copyWith(
        mediaPool: [base.mediaPool.first.copyWith(filePath: mediaFile.path)],
      );
      final projectPath = '${dir.path}/project.json';
      final store = TranscriptStore(directoryOverride: dir.path);
      await store.open(project, path: projectPath);
      final c = EditorController(
        mediaImportService: MediaImportService(ffmpegService: FfmpegService()),
        initialProject: project,
        transcriptStore: store,
      );
      addTearDown(c.dispose);
      final fake = RecordingCaptions();
      final reads = EditorReadService(c, captions: fake);
      addTearDown(reads.dispose);
      var job = reads.transcribe('speech');
      while (!job.finished) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(job.status, 'completed', reason: job.error.toString());
      expect(fake.used, 'pt');
      expect((job.result as Map)['language'], 'pt');
      expect(fake.usedVad, isTrue);
      store.language = 'es';
      store.vocabulary = 'Roblox, Arsenal';
      store.vad = false;
      job = reads.transcribe('speech');
      while (!job.finished) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(fake.used, 'es');
      expect(fake.prompt, 'Roblox, Arsenal');
      expect(fake.usedVad, isFalse);
      expect((job.result as Map)['language'], 'es');
      final io = ProjectIOService();
      await io.saveToFile(project, projectPath);
      final data = await io.readFromFile(projectPath);
      expect(data['version'], 14);
      expect(data.containsKey('words'), isFalse);
      final reopened = io.deserializeProject(data).project;
      final restored = TranscriptStore(directoryOverride: dir.path);
      await restored.open(reopened, path: projectPath);
      final c2 = EditorController(
        mediaImportService: MediaImportService(ffmpegService: FfmpegService()),
        initialProject: reopened,
        transcriptStore: restored,
      );
      addTearDown(c2.dispose);
      final reads2 = EditorReadService(c2);
      addTearDown(reads2.dispose);
      final result = reads2.getTranscript(mediaId: 'speech');
      expect(result['language'], 'es');
      expect(restored.vocabulary, 'Roblox, Arsenal');
      expect(restored.vad, isFalse);
      expect(((result['cues'] as List).single as Map)['words'], hasLength(2));
      await mediaFile.writeAsBytes([5, 6, 7, 8]);
      await restored.open(reopened, path: projectPath);
      expect(restored.cues(reopened.id, 'speech'), isEmpty);
    },
  );
  test('tests use the same pinned CLI SHA accepted by ZIP packager', () async {
    if (!Platform.isWindows) return;
    final cli = File('tools/whisper/bin/whisper-cli.exe');
    expect(await cli.exists(), isTrue, reason: 'Run tool/setup_tools.ps1.');
    await WhisperRuntime.verify(cli.path);
    final cuda = File('tools/whisper/cuda/bin/whisper-cli.exe');
    if (await cuda.exists()) await WhisperRuntime.verify(cuda.path);
    await WhisperRuntime.verifyVulkan('tools/whisper/vulkan/bin');
    expect(
      WhisperRuntime.usesCuda('whisper_backend_init_gpu: using CUDA backend'),
      isTrue,
    );
    expect(
      WhisperRuntime.usesCuda(
        'whisper_init_with_params_no_state: no GPU found',
      ),
      isFalse,
    );
    final version = await Process.run(cli.path, ['--version']);
    expect(version.exitCode, 0);
    expect(version.stdout.toString(), contains(WhisperRuntime.version));
  });
}
