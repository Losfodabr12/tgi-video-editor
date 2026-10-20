import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/app/theme/app_theme.dart';
import 'package:tgi_video_editor/domain/models/project.dart';
import 'package:tgi_video_editor/domain/text_style_profile.dart';
import 'package:tgi_video_editor/features/editor/application/editor_controller.dart';
import 'package:tgi_video_editor/features/editor/presentation/editor_screen.dart';
import 'package:tgi_video_editor/features/editor/presentation/widgets/timeline_panel.dart';
import 'package:tgi_video_editor/services/ffmpeg_filtergraph_builder.dart';
import 'package:tgi_video_editor/services/ffmpeg_service.dart';
import 'package:tgi_video_editor/services/media_import_service.dart';
import 'package:tgi_video_editor/services/project_io_service.dart';

import 'support/render_fixture.dart';
import 'support/four_track_project.dart';

void main() {
  test(
    'new creation style round-trips in v14 and leaves saved styles intact',
    () {
      final legacy = TgiProject.empty(name: 'Existente').addTextClipToTimeline(
        text: 'Preservado',
        timelineStart: Duration.zero,
        fontFamily: 'Georgia',
        textColor: 0xFFFFD166,
        backgroundColor: 0x99000000,
      );
      final io = ProjectIOService();
      final original = io.serializeProject(legacy);
      final controller = EditorController(
        initialProject: io.deserializeProject(original).project,
        mediaImportService: MediaImportService(ffmpegService: FfmpegService()),
      );
      addTearDown(controller.dispose);
      controller.addTextToTimeline('Novo');
      final clips = controller.project.tracks.expand((t) => t.clips).toList();
      final old = clips.singleWhere((c) => c.textContent == 'Preservado');
      final fresh = clips.singleWhere((c) => c.textContent == 'Novo');
      expect(old.fontFamily, 'Georgia');
      expect(old.textColor, 0xFFFFD166);
      expect(old.backgroundColor, 0x99000000);
      expect(fresh.fontFamily, NewTextStyle.fontFamily);
      expect(fresh.textColor, 0xFFFFFFFF);
      expect(fresh.backgroundColor, 0);
      final saved = io.serializeProject(controller.project);
      expect(saved['version'], 14);
      final loaded = io
          .deserializeProject(jsonDecode(jsonEncode(saved)))
          .project;
      expect(
        loaded.tracks.expand((t) => t.clips).map((c) => c.fontFamily),
        clips.map((c) => c.fontFamily),
      );
      String graph(TgiProject project) => FfmpegFiltergraphBuilder(
        fontPath: (_) => 'font.ttf',
      ).buildExportCommand(project, 'out.mp4').arguments.join(' ');
      expect(graph(legacy), isNot(contains('borderw=2:bordercolor=')));
      expect(graph(loaded), contains('borderw=2:bordercolor='));
      controller.importSrt('1\n00:00:14,000 --> 00:00:15,000\nImportada');
      expect(
        controller.generatedCaptionClips.single.fontFamily,
        NewTextStyle.fontFamily,
      );
      expect(controller.generatedCaptionClips.single.backgroundColor, 0);
    },
  );

  test(
    'FFmpeg renders white text on dark and black outline on bright frames',
    () async {
      final fixture = RenderFixture();
      await fixture.open();
      addTearDown(fixture.close);
      for (final background in ['white', 'black']) {
        final video = await fixture.color(background);
        final project = fixture
            .project([video], [fixture.clip(video)])
            .addTextClipToTimeline(
              text: 'READABLE',
              timelineStart: Duration.zero,
              duration: const Duration(seconds: 1),
              fontFamily: NewTextStyle.fontFamily,
              fontSize: 120,
              backgroundColor: 0,
            );
        final output = await fixture.export(project, 'caption-$background');
        final frame = await fixture.run([
          '-v',
          'error',
          '-ss',
          '0.5',
          '-i',
          output,
          '-frames:v',
          '1',
          '-pix_fmt',
          'rgb24',
          '-f',
          'rawvideo',
          'pipe:1',
        ]);
        final pixels = frame.stdout as List<int>;
        expect(pixels.length, 160 * 90 * 3);
        var contrasting = 0;
        for (var i = 0; i < pixels.length; i += 3) {
          final value = (pixels[i] + pixels[i + 1] + pixels[i + 2]) / 3;
          if (background == 'white' ? value < 40 : value > 220) contrasting++;
        }
        expect(
          contrasting,
          greaterThan(60),
          reason: '$background caption pixels',
        );
      }
    },
  );

  Future<Directory> open(
    WidgetTester tester,
    Size size, {
    Map<String, dynamic>? layout,
  }) async {
    final directory = Directory.systemTemp.createTempSync(
      'frame_short_visual_',
    );
    final path = '${directory.path}/layout.json';
    if (layout != null) File(path).writeAsStringSync(jsonEncode(layout));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    await tester.binding.setSurfaceSize(size);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      await tester.binding.setSurfaceSize(null);
      await tester.runAsync(() => directory.delete(recursive: true));
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: TgiTheme.darkTheme,
        home: EditorScreen(
          initialProject: fourTrackProject(),
          workspaceLayoutPath: path,
        ),
      ),
    );
    for (var i = 0; i < 24; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      if (layout == null && i >= 2) break;
      if (layout != null) {
        // Async file reads/writes require several event-loop turns in the
        // widget harness. Wait for the persisted migration, not a fixed sleep.
        try {
          final saved = jsonDecode(File(path).readAsStringSync());
          if (saved['layoutVersion'] == 3 &&
              saved['previewPanelFraction'] == .55) {
            break;
          }
        } on FormatException {
          // A write can have opened/truncated the file before its flush.
        }
      }
    }
    return directory;
  }

  for (final size in [const Size(1440, 900), const Size(1280, 720)]) {
    testWidgets(
      'four tracks visible or scrollable, including full audio at $size',
      (tester) async {
        await open(tester, size);
        final bar = tester.widget<Scrollbar>(
          find.byKey(const ValueKey('timeline-vertical-scrollbar')),
        );
        expect(bar.thumbVisibility, isTrue);
        expect(bar.trackVisibility, isTrue);
        final preview = tester.getRect(
          find.byKey(const ValueKey('desktop-preview-region')),
        );
        expect(preview.left, 8 + 280 + 8);
        expect(size.width - preview.right, 8 + 280 + 8);
        final timeline = tester.getRect(
          find.byKey(const ValueKey('desktop-timeline-region')),
        );
        if (size.height >= 900) {
          expect(
            tester.getRect(find.byKey(const ValueKey('audio'))).bottom,
            lessThanOrEqualTo(timeline.bottom - 8),
          );
        } else {
          expect(bar.controller!.position.maxScrollExtent, greaterThan(0));
          bar.controller!.jumpTo(bar.controller!.position.maxScrollExtent);
          await tester.pumpAndSettle();
          final audio = tester.getRect(find.byKey(const ValueKey('audio')));
          expect(audio.height, 64);
          expect(audio.top, greaterThan(timeline.top + 44 + 34));
          expect(audio.bottom, lessThanOrEqualTo(timeline.bottom - 8));
          final label = tester.getRect(
            find.byKey(const ValueKey('track-header-audio')),
          );
          expect(label.top, closeTo(audio.top, .1));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final version in [2, 3]) {
    testWidgets(
      'saved layout $version with undersized timeline migrates to 45 percent',
      (tester) async {
        final directory = await open(
          tester,
          const Size(1440, 900),
          layout: {
            'layoutVersion': version,
            'leftPanelFraction': 280 / 1440,
            'propertiesPanelFraction': 280 / 1440,
            'previewPanelFraction': .68,
            'timelineFocusMode': false,
          },
        );
        final saved = jsonDecode(
          File('${directory.path}/layout.json').readAsStringSync(),
        );
        expect(saved['layoutVersion'], 3);
        expect(saved['previewPanelFraction'], .55);
        final preview = tester.getRect(
          find.byKey(const ValueKey('desktop-preview-region')),
        );
        final timeline = tester.getRect(
          find.byKey(const ValueKey('desktop-timeline-region')),
        );
        expect(
          timeline.height / (timeline.height + preview.height),
          closeTo(.45, .01),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'timeline groups and shortcut tooltips trigger actions, with text input guarded',
    (tester) async {
      await open(tester, const Size(1440, 900));
      for (final group in [
        'editing-snapping',
        'snapping-markers',
        'markers-navigation',
      ]) {
        expect(find.byKey(ValueKey('timeline-group-$group')), findsOneWidget);
      }
      expect(find.byTooltip('Encaixe magnético ligado · N'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Encaixe magnético desligado · N'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pumpAndSettle();
      TimelinePanel panel() =>
          tester.widget<TimelinePanel>(find.byType(TimelinePanel));
      expect(panel().project.markers, hasLength(1));
      await tester.tap(find.text('Texto').first);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pumpAndSettle();
      expect(panel().project.markers, hasLength(1));
      final menu = find.byKey(const ValueKey('preview-proxy-menu'));
      final label = tester.widget<Text>(
        find.descendant(of: menu, matching: find.text('Original')),
      );
      expect(label.style!.fontSize, 14);
      expect(tester.takeException(), isNull);
    },
  );
}
