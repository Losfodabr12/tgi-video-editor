import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/app/theme/app_theme.dart';
import 'package:tgi_video_editor/app/theme/design_tokens.dart';
import 'package:tgi_video_editor/domain/models/audio_waveform.dart';
import 'package:tgi_video_editor/domain/models/clip.dart';
import 'package:tgi_video_editor/domain/models/media_item.dart';
import 'package:tgi_video_editor/domain/models/project.dart';
import 'package:tgi_video_editor/domain/models/track.dart';
import 'package:tgi_video_editor/domain/models/timeline_transition.dart';
import 'package:tgi_video_editor/features/editor/presentation/editor_screen.dart';
import 'package:tgi_video_editor/features/editor/presentation/editor_keyboard.dart';
import 'package:tgi_video_editor/features/editor/presentation/widgets/timeline_panel.dart';
import 'package:tgi_video_editor/services/app_preferences_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  setUpAll(() async {
    // Load bundled bytes, never fonts from the developer's installed app/OS.
    for (final family in ['Arial', 'Roboto']) {
      await (FontLoader(family)
            ..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'))
            ..addFont(rootBundle.load('assets/fonts/Lato-Bold.ttf')))
          .load();
    }
    final config =
        jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
            as Map<String, dynamic>;
    final flutter = (config['packages'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((p) => p['name'] == 'flutter');
    final sdk = Directory.fromUri(
      Uri.parse(flutter['rootUri'] as String),
    ).parent.parent;
    final icons = File(
      '${sdk.path}/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    );
    await (FontLoader(
          'MaterialIcons',
        )..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync()))))
        .load();
    temporary = Directory.systemTemp.createTempSync('frame_visual_');
  });
  tearDownAll(() => temporary.deleteSync(recursive: true));

  test('all saved appearance choices use compact tokens and one accent', () {
    for (final style in AppVisualStyle.values) {
      final theme = TgiTheme.forStyle(style);
      expect(theme.visualDensity, VisualDensity.compact);
      expect(theme.colorScheme.primary, TgiColors.primary);
      expect(theme.cardTheme.elevation, 0);
      expect(theme.dialogTheme.elevation, 0);
      expect(theme.shadowColor, Colors.transparent);
    }
    expect(
      {
        TgiColors.background,
        TgiColors.surfacePanel,
        TgiColors.surfaceRaised,
      }.length,
      3,
    );
    for (final spacing in [
      TgiSpacing.xxs,
      TgiSpacing.xs,
      TgiSpacing.sm,
      TgiSpacing.md,
      TgiSpacing.lg,
      TgiSpacing.xl,
      TgiSpacing.xxl,
    ]) {
      expect(spacing % 4, 0);
    }
  });

  Future<void> drainIo(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump();
    }
  }

  Future<void> viewport(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await drainIo(tester);
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      await tester.binding.setSurfaceSize(null);
    });
  }

  Future<void> workspace(WidgetTester tester, {TgiProject? project}) async {
    await viewport(tester);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('golden'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: TgiTheme.darkTheme,
          home: EditorScreen(
            initialProject: project,
            workspaceLayoutPath: '${temporary.path}/golden-layout.json',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('empty editor golden', (tester) async {
    await workspace(tester);
    await expectLater(
      find.byKey(const ValueKey('golden')),
      matchesGoldenFile('goldens/editor_empty.png'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected title and properties golden', (tester) async {
    final project = TgiProject.empty(name: 'Meu filme · TGI Video Editor')
        .addTextClipToTimeline(
          text: 'TGI VIDEO EDITOR',
          fontSize: 64,
          backgroundColor: 0,
          timelineStart: Duration.zero,
          duration: const Duration(seconds: 8),
        );
    await workspace(tester, project: project);
    await tester.tap(
      find.byKey(
        ValueKey('timeline-clip-body-${project.tracks.single.clips.single.id}'),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('golden')),
      matchesGoldenFile('goldens/editor_properties.png'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('export settings golden', (tester) async {
    await workspace(
      tester,
      project: TgiProject.empty(name: 'Meu filme').addTextClipToTimeline(
        text: 'Frame Studio',
        timelineStart: Duration.zero,
      ),
    );
    await tester.tap(find.text('Exportar').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('export_encoder')), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('golden')),
      matchesGoldenFile('goldens/export_settings.png'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard settings golden', (tester) async {
    await viewport(tester);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('golden'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: TgiTheme.darkTheme,
          home: Scaffold(
            body: KeyboardShortcutsDialog(
              initialBindings: defaultEditorShortcutBindings(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('golden')),
      matchesGoldenFile('goldens/keyboard_settings.png'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('timeline types thumbnails waveform and snapping golden', (
    tester,
  ) async {
    await viewport(tester);
    final thumbnail = File('assets/branding/editor_icon.png').absolute.path;
    final types = TrackType.values;
    final project = TgiProject(
      id: 'visual',
      name: 'Linha do tempo',
      transitions: const [
        TimelineTransition(
          id: 'fx',
          name: 'Dissolve',
          timelinePosition: Duration(seconds: 10),
          duration: Duration(milliseconds: 900),
          preset: TimelineTransitionPreset.dissolve,
        ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      mediaPool: [
        for (final type in types)
          MediaItem(
            id: type.name,
            filePath: thumbnail,
            thumbnailPath: thumbnail,
            name: '${type.name}.demo',
            type: MediaType.values[type.index],
            hasAudio: false,
            duration: const Duration(seconds: 10),
            importedAt: DateTime(2026),
          ),
      ],
      tracks: [
        for (final type in types)
          Track(
            id: type.name,
            name: type.name.toUpperCase(),
            type: type,
            height: 80,
            clips: [
              Clip(
                id: type.name,
                mediaItemId: type.name,
                timelineGroupId: type.name,
                trackType: type,
                textContent: type == TrackType.text
                    ? 'Uma história em camadas'
                    : '',
                timelineStart: Duration(seconds: type.index),
                sourceStart: Duration.zero,
                duration: const Duration(seconds: 8),
              ),
            ],
          ),
      ],
    );
    Duration? moved;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: TgiTheme.darkTheme,
        home: Scaffold(
          body: RepaintBoundary(
            key: const ValueKey('golden'),
            child: TimelinePanel(
              project: project,
              playheadPosition: const Duration(seconds: 4),
              audioWaveforms: {
                'audio': AudioWaveform(
                  samples: List.generate(
                    100,
                    (i) => (math.sin(i * .7).abs() * .8) + .1,
                  ),
                  sampleInterval: const Duration(milliseconds: 100),
                ),
              },
              onMediaDropped:
                  (
                    _,
                    _, {
                    targetTrackId,
                    bool forceNewVideoTrack = false,
                    bool forceNewAudioTrack = false,
                  }) {},
              onClipMoved: (_, start) => moved = start,
              onPlayheadChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await drainIo(tester);
    expect(
      tester
          .widgetList<RawImage>(find.byType(RawImage))
          .where((image) => image.image != null),
      isNotEmpty,
    );
    // At 76 px/s, drag the video almost to the 4s playhead. The actual
    // snapping code, not a flag in the test, must reveal the guide.
    final gesture = await tester.startGesture(
      tester.getTopLeft(
            find.byKey(const ValueKey('timeline-clip-body-video')),
          ) +
          const Offset(80, 32),
    );
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('snap-guide-video')), findsOneWidget);
    expect(find.byKey(const ValueKey('audio-waveform-audio')), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('golden')),
      matchesGoldenFile('goldens/timeline_snapping.png'),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(moved, const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('zoomed ruler and real 04:53 duration golden', (tester) async {
    await workspace(
      tester,
      project: TgiProject.empty(name: '04:53 · Revisão visual')
          .addTextClipToTimeline(
            text: 'Uma história em camadas',
            timelineStart: Duration.zero,
            duration: const Duration(seconds: 293),
          ),
    );
    final slider = find.byKey(const ValueKey('timeline-zoom-slider'));
    await tester.tapAt(
      tester.getRect(slider).centerRight - const Offset(16, 0),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('golden')),
      matchesGoldenFile('goldens/editor_zoomed.png'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('all three splitters restore their saved sizes', (tester) async {
    await viewport(tester);
    final path = '${temporary.path}/resized-layout.json';
    Future<void> open() async {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: TgiTheme.darkTheme,
          home: EditorScreen(workspaceLayoutPath: path),
        ),
      );
      await drainIo(tester);
      await tester.pumpAndSettle();
    }

    Rect preview() =>
        tester.getRect(find.byKey(const ValueKey('desktop-preview-region')));
    await open();
    final before = preview();
    await tester.drag(
      find.byKey(const ValueKey('resize-library')),
      const Offset(-64, 0),
    );
    await tester.drag(
      find.byKey(const ValueKey('resize-properties')),
      const Offset(-48, 0),
    );
    await tester.drag(
      find.byKey(const ValueKey('resize-timeline')),
      const Offset(0, -64),
    );
    await tester.pumpAndSettle();
    final resized = preview();
    expect(resized.left, lessThan(before.left));
    expect(resized.right, lessThan(before.right));
    expect(resized.height, lessThan(before.height));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
    await drainIo(tester);
    final saved =
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    expect(
      saved['layoutVersion'],
      3,
    ); // UI preferences, separate from project v14.
    await open();
    expect(preview().left, closeTo(resized.left, .1));
    expect(preview().right, closeTo(resized.right, .1));
    expect(preview().height, closeTo(resized.height, .1));
    expect(tester.takeException(), isNull);
  });
}
