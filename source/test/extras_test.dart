import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/domain/models/project.dart';
import 'package:tgi_video_editor/features/editor/application/editor_controller.dart';
import 'package:tgi_video_editor/features/editor/presentation/caption_style_dialog.dart';
import 'package:tgi_video_editor/features/editor/presentation/editor_keyboard.dart';
import 'package:tgi_video_editor/services/auto_caption_service.dart';
import 'package:tgi_video_editor/services/ffmpeg_service.dart';
import 'package:tgi_video_editor/services/media_import_service.dart';
import 'package:tgi_video_editor/services/project_io_service.dart';
import 'package:tgi_video_editor/services/subtitle_service.dart';

import 'support/render_fixture.dart';

class _NoGpu extends FfmpegService {
  _NoGpu({this.failAfterProbe = false});
  final bool failAfterProbe;
  @override
  Future<FfmpegCommandProcess> startCommand(
    List<String> arguments, {
    bool useFfprobe = false,
  }) {
    final codec = arguments.indexOf('-c:v');
    if (codec >= 0 && arguments[codec + 1] != 'libx264') {
      if (failAfterProbe && arguments.contains('null')) {
        final cpu = [...arguments];
        cpu[codec + 1] = 'libx264';
        return super.startCommand(cpu, useFfprobe: useFfprobe);
      }
      throw const FfmpegProcessException('Hardware failure injected by test');
    }
    return super.startCommand(arguments, useFfprobe: useFfprobe);
  }
}

void main() {
  test('export presets include requested ratios, GPU selection and audio', () {
    final presets = {for (final p in FfmpegExportPreset.all) p.id: p.settings};
    expect(
      presets.keys,
      containsAll(['youtube', '4k', 'vertical', 'square', 'audio']),
    );
    expect(presets['4k']!.resolution.width, 3840);
    expect(
      presets['vertical']!.resolution.width /
          presets['vertical']!.resolution.height,
      9 / 16,
    );
    expect(
      presets['square']!.resolution.width,
      presets['square']!.resolution.height,
    );
    expect(presets['youtube']!.encoder, FfmpegVideoEncoder.automatic);
    expect(presets['audio']!.audioOnly, isTrue);
  });

  test(
    'SRT preserves multiline Unicode and timestamps through export/import',
    () {
      const source =
          '\ufeff1\r\n00:00:01,250 --> 00:00:02,750\r\nOlá\r\nsegunda linha\r\n\r\n2\r\n00:00:03,000 --> 00:00:04,000\r\nFim';
      final cues = SubtitleService.parseSrt(source);
      expect(cues.first.text, 'Olá\nsegunda linha');
      final roundTrip = SubtitleService.parseSrt(
        formatSubtitleCues(cues, SubtitleExportFormat.srt),
      );
      expect(roundTrip.map((c) => c.toJson()), cues.map((c) => c.toJson()));
      for (final bad in [
        '',
        '1\n00:61:00,000 --> 00:62:00,000\nInvalid',
        '1\n00:00:02,000 --> 00:00:01,000\nInvalid',
      ]) {
        expect(() => SubtitleService.parseSrt(bad), throwsFormatException);
      }
    },
  );

  test(
    'caption import and bulk style are undoable and preserve project v14',
    () {
      final controller = EditorController(
        mediaImportService: MediaImportService(ffmpegService: FfmpegService()),
      );
      addTearDown(controller.dispose);
      final empty = controller.project;
      controller.importSrt('1\n00:00:01,000 --> 00:00:02,000\nCaption');
      expect(controller.generatedCaptionClips.single.textContent, 'Caption');
      final imported = controller.project;
      controller.applyCaptionStyle(
        const CaptionStyle(
          fontFamily: 'Poppins',
          fontSize: 54,
          textColor: 0xFFFFFF00,
          y: .8,
        ),
      );
      expect(controller.generatedCaptionClips.single.fontSize, 54);
      final io = ProjectIOService();
      final saved = io.serializeProject(controller.project);
      expect(saved['version'], 14);
      final restored = io
          .deserializeProject(
            jsonDecode(jsonEncode(saved)) as Map<String, dynamic>,
          )
          .project;
      expect(restored.tracks.expand((t) => t.clips).single.fontSize, 54);
      controller.undo();
      expect(controller.project, same(imported));
      controller.undo();
      expect(controller.project, same(empty));
      controller.redo();
      expect(controller.project, same(imported));
      final track = controller.project.tracks.single;
      controller.setTimelineTrackLocked(track.id, true);
      final locked = controller.project;
      controller.applyCaptionStyle(const CaptionStyle(fontSize: 72));
      expect(controller.project, same(locked));
      controller.importSrt('broken');
      expect(controller.project, same(locked));
    },
  );

  testWidgets('caption style dialog applies a changed size', (tester) async {
    CaptionStyle? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<CaptionStyle>(
                  context: context,
                  builder: (_) => const CaptionStyleDialog(),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('caption_style_size')),
      const Offset(80, 0),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('caption_style_apply')),
    );
    await tester.tap(find.byKey(const ValueKey('caption_style_apply')));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.fontSize, greaterThan(36));
  });

  testWidgets('shortcut screen remaps undo through real keyboard events', (
    tester,
  ) async {
    Map<EditorShortcutAction, SingleActivator>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result =
                    await showDialog<
                      Map<EditorShortcutAction, SingleActivator>
                    >(
                      context: context,
                      builder: (_) => KeyboardShortcutsDialog(
                        initialBindings: defaultEditorShortcutBindings(),
                      ),
                    );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alterar').first);
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
    expect(
      result![EditorShortcutAction.undo]!.trigger,
      LogicalKeyboardKey.keyP,
    );
    expect(result![EditorShortcutAction.undo]!.control, isTrue);
  });

  group('real media exports', () {
    final fixture = RenderFixture();
    setUp(fixture.open);
    tearDown(fixture.close);
    test(
      'video presets render their actual output geometry including 4K',
      () async {
        final media = await fixture.color('red', seconds: .1);
        final project = fixture.project([media], [fixture.clip(media)]);
        for (final preset in FfmpegExportPreset.all.where(
          (p) => !p.settings.audioOnly,
        )) {
          final output = '${fixture.directory.path}/${preset.id}.mp4';
          await fixture.service.exportProject(
            project,
            output,
            settings: preset.settings.copyWith(
              encoder: FfmpegVideoEncoder.software,
            ),
          );
          final probe = await fixture.service.runCommand([
            '-v',
            'error',
            '-select_streams',
            'v:0',
            '-show_entries',
            'stream=width,height',
            '-of',
            'json',
            output,
          ], useFfprobe: true);
          final stream =
              (jsonDecode(probe.stdout as String) as Map)['streams'][0] as Map;
          expect(stream['width'], preset.settings.resolution.width);
          expect(stream['height'], preset.settings.resolution.height);
        }
      },
    );
    test(
      'audio-only writes PCM WAV with no video stream, without changing v14',
      () async {
        final media = await fixture.color('red', audio: '440');
        final project = TgiProject.empty(name: 'Audio')
            .copyWith(mediaPool: [media])
            .addMediaItemToTimeline(media, timelineStart: Duration.zero);
        const settings = FfmpegExportSettings(
          resolution: FfmpegExportResolution.p450,
          framesPerSecond: 30,
          quality: FfmpegExportQuality.light,
          audioOnly: true,
        );
        final output = '${fixture.directory.path}/audio.wav';
        await fixture.service.exportProject(
          project,
          output,
          settings: settings,
        );
        final probe = await fixture.service.runCommand([
          '-v',
          'error',
          '-show_streams',
          '-show_format',
          '-of',
          'json',
          output,
        ], useFfprobe: true);
        final data = jsonDecode(probe.stdout as String) as Map;
        expect((data['streams'] as List).map((s) => s['codec_type']), [
          'audio',
        ]);
        expect(data['streams'][0]['codec_name'], 'pcm_s16le');
        expect(
          double.parse(data['format']['duration'] as String),
          closeTo(1, .02),
        );
        expect(await File(output).length(), greaterThan(48000));
        // Only the execution mode is transient; the serialized project shape is unchanged.
        expect(settings.toJson().containsKey('audioOnly'), isFalse);
        expect(
          FfmpegExportSettings.fromJson(
            FfmpegExportSettings.uiDefault.toJson(),
          )!.audioOnly,
          isFalse,
        );
        final saved = ProjectIOService().serializeProject(
          project,
          exportSettings: settings,
        );
        expect(saved['version'], 14);
        expect(
          ProjectIOService()
              .deserializeProject(saved)
              .exportSettings!
              .audioOnly,
          isFalse,
        );
      },
    );
    test(
      'NVENC, QSV and AMF unavailability falls back to a real CPU export',
      () async {
        final media = await fixture.color('blue');
        final project = fixture.project([media], [fixture.clip(media)]);
        for (final encoder in [
          FfmpegVideoEncoder.nvidia,
          FfmpegVideoEncoder.intel,
          FfmpegVideoEncoder.amd,
        ]) {
          final service = _NoGpu();
          final output = '${fixture.directory.path}/${encoder.name}.mp4';
          await service.exportProject(
            project,
            output,
            settings: RenderFixture.settings.copyWith(encoder: encoder),
          );
          expect(service.lastExportEncoder, FfmpegVideoEncoder.software);
          expect(service.lastExportNotice, contains('CPU'));
          expect((await fixture.pixel(output, .5))[2], greaterThan(225));
        }
      },
    );
    test(
      'hardware render failure after a successful probe retries on CPU',
      () async {
        final media = await fixture.color('blue');
        final service = _NoGpu(failAfterProbe: true);
        final output = '${fixture.directory.path}/retry.mp4';
        await service.exportProject(
          fixture.project([media], [fixture.clip(media)]),
          output,
          settings: RenderFixture.settings.copyWith(
            encoder: FfmpegVideoEncoder.nvidia,
          ),
        );
        expect(service.lastExportEncoder, FfmpegVideoEncoder.software);
        expect(service.lastExportNotice, contains('não concluiu'));
        expect((await fixture.pixel(output, .5))[2], greaterThan(225));
      },
    );
  });
}
