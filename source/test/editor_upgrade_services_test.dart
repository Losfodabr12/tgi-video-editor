import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/domain/models/clip.dart';
import 'package:tgi_video_editor/domain/models/media_item.dart';
import 'package:tgi_video_editor/domain/models/project.dart';
import 'package:tgi_video_editor/domain/models/track.dart';
import 'package:tgi_video_editor/features/editor/application/editor_controller.dart';
import 'package:tgi_video_editor/services/audio_ducking.dart';
import 'package:tgi_video_editor/services/audio_level_service.dart';
import 'package:tgi_video_editor/services/editor_preset_service.dart';
import 'package:tgi_video_editor/services/ffmpeg_service.dart';
import 'package:tgi_video_editor/services/media_import_service.dart';
import 'package:tgi_video_editor/services/project_collection_service.dart';
import 'package:tgi_video_editor/services/project_history_service.dart';
import 'package:tgi_video_editor/services/project_io_service.dart';

void main() {
  late Directory temporary;
  setUp(
    () async => temporary = await Directory.systemTemp.createTemp(
      'tgi_editor_upgrade_',
    ),
  );
  tearDown(() async => temporary.delete(recursive: true));

  test('captions survive serialization, reopening, copy and undo', () {
    final controller = EditorController(
      mediaImportService: MediaImportService(ffmpegService: FfmpegService()),
    );
    addTearDown(controller.dispose);
    controller.addTextToTimeline('Título comum');
    controller.addTextToTimeline('Primeira fala', registerAsCaption: true);
    controller.addTextToTimeline('Segunda fala', registerAsCaption: true);
    expect(controller.generatedCaptionCues, hasLength(2));
    controller.undo();
    expect(controller.generatedCaptionCues, hasLength(1));
    controller.redo();
    final io = ProjectIOService();
    controller.loadProjectFromData(
      io.deserializeProject(io.serializeProject(controller.project)),
    );
    expect(controller.canExportGeneratedCaptions, isTrue);
    expect(controller.generatedCaptionCues.map((c) => c.text), [
      'Primeira fala',
      'Segunda fala',
    ]);
    final caption = controller.generatedCaptionClips.first;
    expect(
      caption.copyWith(duration: const Duration(seconds: 2)).isCaption,
      isTrue,
    );
  });

  test(
    'older selected text can be explicitly included in SRT without changing other titles',
    () {
      final controller = EditorController(
        mediaImportService: MediaImportService(ffmpegService: FfmpegService()),
      );
      addTearDown(controller.dispose);
      controller.addTextToTimeline('Título');
      controller.addTextToTimeline('Legenda antiga');
      controller.registerSelectedTextClipsAsCaptions();
      expect(controller.generatedCaptionCues.single.text, 'Legenda antiga');
      controller.undo();
      expect(controller.canExportGeneratedCaptions, isFalse);
    },
  );

  test(
    'history retains newest versions and restores project plus export range',
    () async {
      final service = ProjectHistoryService(
        directoryPath: '${temporary.path}/history',
        limit: 3,
      );
      final project = TgiProject.empty(name: 'Edição');
      final settings = FfmpegExportSettings.uiDefault.copyWith(
        rangeStart: const Duration(seconds: 1),
        rangeEnd: const Duration(seconds: 3),
        encoder: FfmpegVideoEncoder.automatic,
      );
      await Future.wait([
        for (var i = 0; i < 5; i++)
          service.record(
            project.copyWith(name: 'Versão $i'),
            exportSettings: settings,
            label: 'Ponto $i',
          ),
      ]);
      final entries = await service.list(project.id);
      expect(entries, hasLength(3));
      expect(entries.map((e) => e.projectName), [
        'Versão 4',
        'Versão 3',
        'Versão 2',
      ]);
      final restored = await service.restore(entries.last);
      expect(restored.project.name, 'Versão 2');
      expect(restored.exportSettings, settings);
      expect(await service.list('outro projeto'), isEmpty);
    },
  );

  test(
    'portable project remains valid after moving, including duplicate names and watermark',
    () async {
      final first = File('${temporary.path}/a/clip.mp4');
      final second = File('${temporary.path}/b/clip.mp4');
      await first.parent.create();
      await second.parent.create();
      await first.writeAsString('original A');
      await second.writeAsString('original B');
      final mediaA = media('a', first.path), mediaB = media('b', second.path);
      final project = TgiProject.empty(name: 'Portátil').copyWith(
        mediaPool: [mediaA, mediaB],
        watermark: ProjectWatermark(enabled: true, imagePath: first.path),
        tracks: [
          Track(
            id: 'v',
            name: 'Vídeo',
            type: TrackType.video,
            clips: [clip('a'), clip('b')],
          ),
        ],
      );
      final path = await ProjectCollectionService().collect(
        project,
        '${temporary.path}/exports',
        exportSettings: FfmpegExportSettings.uiDefault,
      );
      final originalData = jsonDecode(await File(path).readAsString()) as Map;
      expect(originalData['portable'], isTrue);
      expect(
        (originalData['mediaPool'] as List).every(
          (m) => (m['filePath'] as String).startsWith('media/'),
        ),
        isTrue,
      );
      final moved = await File(path).parent.rename('${temporary.path}/moved');
      final io = ProjectIOService();
      final restored = io.deserializeProject(
        await io.readFromFile('${moved.path}/projeto.json'),
      );
      expect(restored.missingMediaItems, isEmpty);
      expect(
        await File(restored.project.mediaPool[0].filePath).readAsString(),
        'original A',
      );
      expect(
        await File(restored.project.mediaPool[1].filePath).readAsString(),
        'original B',
      );
      expect(File(restored.project.watermark.imagePath).existsSync(), isTrue);
      expect(await first.readAsString(), 'original A');
      expect(await second.readAsString(), 'original B');
      expect(await Directory('${moved.path}/media').list().length, 2);
    },
  );

  test(
    'collection refuses missing media without leaving a partial folder',
    () async {
      final parent = Directory('${temporary.path}/output');
      await parent.create();
      final project = TgiProject.empty(name: 'Ausente').copyWith(
        mediaPool: [media('a', '${temporary.path}/missing.mp4')],
        tracks: [
          Track(
            id: 'v',
            name: 'Vídeo',
            type: TrackType.video,
            clips: [clip('a')],
          ),
        ],
      );
      await expectLater(
        ProjectCollectionService().collect(project, parent.path),
        throwsA(isA<FileSystemException>()),
      );
      expect(await parent.list().toList(), isEmpty);
    },
  );

  test('portable project cannot escape its own folder', () async {
    final file = File('${temporary.path}/project.json');
    await file.writeAsString(
      jsonEncode({
        'portable': true,
        'mediaPool': [
          {'filePath': '../elsewhere.mp4'},
        ],
      }),
    );
    await expectLater(
      ProjectIOService().readFromFile(file.path),
      throwsFormatException,
    );
  });

  test(
    'personal text preset persists and preserves clip identity, words and caption membership',
    () async {
      final service = EditorPresetService(
        filePath: '${temporary.path}/presets.json',
      );
      final source = clip('template', type: TrackType.text).copyWith(
        fontFamily: 'Bebas Neue',
        fontSize: 80,
        textColor: 0xFFFFFF00,
        textContent: 'não copiar estas palavras',
      );
      final first = EditorPresetService.capture(
        'Meu texto',
        EditorPresetKind.text,
        source,
      );
      final second = EditorPresetService.capture(
        'Minha animação',
        EditorPresetKind.animation,
        source,
      );
      await Future.wait([service.save(first), service.save(second)]);
      final loaded = await EditorPresetService(
        filePath: service.filePath,
      ).list();
      expect(loaded, hasLength(2));
      final target = clip('target', type: TrackType.text).copyWith(
        textContent: 'Minha fala',
        isCaption: true,
        timelineStart: const Duration(seconds: 7),
        duration: const Duration(seconds: 2),
      );
      final result = EditorPresetService.apply(loaded.first, target);
      expect(result.fontFamily, 'Bebas Neue');
      expect(result.fontSize, 80);
      expect(result.textContent, 'Minha fala');
      expect(result.id, target.id);
      expect(result.timelineStart, target.timelineStart);
      expect(result.duration, target.duration);
      expect(result.isCaption, isTrue);
      await service.remove(first.id);
      expect((await service.list()).single.id, second.id);
    },
  );

  test(
    'PCM meter keeps actual peak and RMS across fragmented stream chunks',
    () async {
      final bytes = ByteData(9600 * 4);
      for (var i = 0; i < 9600; i++) {
        bytes.setFloat32(i * 4, i.isEven ? 0.25 : -0.25, Endian.little);
      }
      final raw = bytes.buffer.asUint8List();
      final levels = await AudioLevelService.decodePcm(
        Stream.fromIterable([
          raw.sublist(0, 3),
          raw.sublist(3, 167),
          raw.sublist(167),
        ]),
      );
      expect(levels.frames, hasLength(1));
      expect(levels.frames.single.peak, closeTo(0.25, 0.00001));
      expect(levels.frames.single.rms, closeTo(0.25, 0.00001));
      expect(levels.at(const Duration(seconds: 1)).peak, 0);
    },
  );

  test(
    'ducking lowers only speech regions and preserves unrelated automation',
    () {
      final music = clip('music', type: TrackType.audio).copyWith(
        duration: const Duration(seconds: 10),
        keyframes: [
          const ClipKeyframe(
            id: 'other',
            property: ClipKeyframeProperty.opacity,
            time: 0,
            value: 0.7,
          ),
        ],
      );
      final changed = music.copyWith(
        keyframes: buildDuckingKeyframes(music, [
          const SpeechInterval(Duration(seconds: 3), Duration(seconds: 5)),
        ], reductionDb: 12),
      );
      expect(changed.keyframedValue(ClipKeyframeProperty.volume, 0.1), 1);
      expect(
        changed.keyframedValue(ClipKeyframeProperty.volume, 0.4),
        closeTo(0.25119, 0.0001),
      );
      expect(changed.keyframedValue(ClipKeyframeProperty.volume, 0.8), 1);
      expect(changed.keyframedValue(ClipKeyframeProperty.opacity, 0.4), 0.7);
      expect(
        changed.keyframedValue(ClipKeyframeProperty.volume, 0.2925),
        closeTo(0.62559, 0.001),
      );
    },
  );

  test(
    'range settings round trip and reject reversed or out-of-bounds ranges',
    () {
      final settings = FfmpegExportSettings.uiDefault.copyWith(
        rangeStart: const Duration(seconds: 2),
        rangeEnd: const Duration(seconds: 4),
        encoder: FfmpegVideoEncoder.nvidia,
      );
      expect(FfmpegExportSettings.fromJson(settings.toJson()), settings);
      expect(
        settings.exportDuration(const Duration(seconds: 6)),
        const Duration(seconds: 2),
      );
      expect(
        () => settings.exportDuration(const Duration(seconds: 3)),
        throwsFormatException,
      );
      expect(
        () => settings
            .copyWith(rangeStart: const Duration(seconds: 5))
            .exportDuration(const Duration(seconds: 6)),
        throwsFormatException,
      );
      expect(settings.copyWith(clearRange: true).hasRange, isFalse);
    },
  );
}

MediaItem media(String id, String path) => MediaItem(
  id: id,
  filePath: path,
  name: id,
  type: MediaType.video,
  duration: const Duration(seconds: 5),
  importedAt: DateTime(2026),
);
Clip clip(String id, {TrackType type = TrackType.video}) => Clip(
  id: 'clip_$id',
  mediaItemId: id,
  timelineGroupId: 'group_$id',
  trackType: type,
  timelineStart: Duration.zero,
  sourceStart: Duration.zero,
  duration: const Duration(seconds: 5),
);
