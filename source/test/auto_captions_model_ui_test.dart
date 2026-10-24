import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/app/theme/app_theme.dart';
import 'package:tgi_video_editor/domain/models/media_item.dart';
import 'package:tgi_video_editor/features/editor/application/editor_controller.dart';
import 'package:tgi_video_editor/features/editor/presentation/editor_screen.dart';
import 'package:tgi_video_editor/services/auto_caption_service.dart';
import 'package:tgi_video_editor/services/ffmpeg_service.dart';
import 'package:tgi_video_editor/services/media_import_service.dart';
import 'package:tgi_video_editor/services/transcript_store.dart';

import 'support/silence_project.dart';

class _RequestedCaptions implements AutoCaptionService {
  String? model, language;

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
    model = modelName;
    language = languageCode;
    return const [];
  }
}

void main() {
  for (final chooseMaximum in [false, true]) {
    testWidgets(
      chooseMaximum
          ? 'maximum shortcut submits full large-v3 and Portuguese explicitly'
          : 'opening automatic captions preserves the existing project model',
      (tester) async {
        final directory = Directory.systemTemp.createTempSync('caption_model_');
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1440, 900);
        await tester.binding.setSurfaceSize(const Size(1440, 900));
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
          await tester.binding.setSurfaceSize(null);
          await tester.runAsync(() => directory.delete(recursive: true));
        });
        final project = silenceProject();
        final service = _RequestedCaptions();
        final controller = EditorController(
          initialProject: project,
          mediaImportService: MediaImportService(
            ffmpegService: FfmpegService(),
          ),
          autoCaptionService: service,
          transcriptStore: TranscriptStore(directoryOverride: directory.path),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: TgiTheme.darkTheme,
            home: EditorScreen(
              controller: controller,
              initialProject: project,
              workspaceLayoutPath: '${directory.path}/layout.json',
            ),
          ),
        );
        await tester.runAsync(() => controller.transcripts.ready);
        await tester.pump(const Duration(milliseconds: 300));
        expect(controller.transcripts.modelName, 'base');
        await tester.tap(find.text('Legendas').first);
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('captions_generate_button')),
        );
        await tester.pump();
        expect(find.text('Usar Máxima (large-v3)'), findsOneWidget);
        if (chooseMaximum) {
          // Choose before asynchronous model discovery finishes: it must not
          // replace this explicit request with the automatic small/turbo policy.
          await tester.tap(
            find.byKey(const ValueKey('caption_use_maximum_model')),
          );
          await tester.pump();
          expect(find.text('Máxima (large-v3) selecionada'), findsOneWidget);
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.ensureVisible(find.text('Gerar legendas'));
        await tester.tap(find.text('Gerar legendas'));
        await tester.runAsync(() async {
          final deadline = DateTime.now().add(const Duration(seconds: 10));
          while (service.model == null && DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        await tester.pump(const Duration(milliseconds: 300));
        expect(service.model, chooseMaximum ? 'large-v3' : 'base');
        expect(controller.transcripts.modelName, service.model);
        expect(service.language, 'pt');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
