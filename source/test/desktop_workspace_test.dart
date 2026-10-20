import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/app/theme/app_theme.dart';
import 'package:tgi_video_editor/domain/models/media_item.dart';
import 'package:tgi_video_editor/domain/models/project.dart';
import 'package:tgi_video_editor/domain/models/track.dart';
import 'package:tgi_video_editor/features/editor/presentation/editor_screen.dart';
import 'package:tgi_video_editor/features/editor/presentation/widgets/timeline_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/Lato-Bold.ttf'));
    await loader.load();
    for (final family in ['Arial', 'Ahem', 'Segoe UI']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/Lato-Bold.ttf'))).load();
    }
    final icons = File(
      '../aplicativo/data/flutter_assets/fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(
            icons.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
          ))
          .load();
    }
  });
  for (final size in [
    const Size(1440, 900),
    const Size(1280, 720),
    const Size(1024, 768),
    const Size(900, 600),
    const Size(640, 480),
  ]) {
    testWidgets('desktop keeps preview and timeline visible at $size', (
      tester,
    ) async {
      await _viewport(tester, size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(theme: TgiTheme.darkTheme, home: const EditorScreen()),
      );
      await tester.pumpAndSettle();
      final preview = tester.getRect(
        find.byKey(const ValueKey('desktop-preview-region')),
      );
      final timeline = tester.getRect(
        find.byKey(const ValueKey('desktop-timeline-region')),
      );
      expect(preview.height, greaterThan(120));
      expect(timeline.height, greaterThan(130));
      expect(timeline.top, greaterThanOrEqualTo(preview.bottom));
      expect(timeline.bottom, lessThanOrEqualTo(size.height));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'title library inserts real content; typing preserves editor shortcuts',
    (tester) async {
      await _viewport(tester, const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(theme: TgiTheme.darkTheme, home: const EditorScreen()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Títulos'));
      await tester.pump();
      await tester.tap(find.text('Seu título'));
      await tester.pumpAndSettle();
      TimelinePanel timeline() =>
          tester.widget<TimelinePanel>(find.byType(TimelinePanel));
      expect(timeline().project.tracks.single.kind, TrackKind.visual);
      expect(
        timeline().project.tracks.single.clips.single.textContent,
        'Seu título',
      );
      await tester.tap(
        find.byKey(
          ValueKey(
            'timeline-clip-body-${timeline().project.tracks.single.clips.single.id}',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final textField = find.byKey(
        ValueKey(
          'clip_text_${timeline().project.tracks.single.clips.single.id}',
        ),
      );
      await tester.enterText(textField, 'Texto em edição');
      await tester.pump();
      expect(
        timeline().project.tracks.single.clips.single.textContent,
        'Texto em edição',
      );
      final position = timeline().playheadPosition;
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(timeline().project.hasTimelineClips, isTrue);
      expect(timeline().playheadPosition, position);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(
        find.byKey(
          ValueKey(
            'timeline-clip-body-${timeline().project.tracks.single.clips.single.id}',
          ),
        ),
      );
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.context?.widget,
        isNot(isA<EditableText>()),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(timeline().project.hasTimelineClips, isFalse);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(timeline().project.hasTimelineClips, isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(timeline().project.hasTimelineClips, isFalse);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(timeline().playheadPosition, greaterThan(Duration.zero));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(timeline().playheadPosition, Duration.zero);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final mediaType in [MediaType.video, MediaType.audio]) {
    testWidgets(
      '${mediaType.name} drag moves between compatible lanes, creates one and respects locks',
      (tester) async {
        await _viewport(tester, const Size(1200, 450));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final video = MediaItem(
          id: 'video',
          filePath: 'not-read-by-timeline.mp4',
          name: 'Video',
          type: mediaType,
          duration: const Duration(seconds: 2),
          importedAt: DateTime(2026),
          hasAudio: false,
        );
        var project = TgiProject.empty(name: 'Drag')
            .addMediaItem(video)
            .addMediaItemToTimeline(video, timelineStart: Duration.zero)
            .addTimelineTrack(
              mediaType == MediaType.audio ? TrackType.audio : TrackType.text,
            );
        final clipId = project.tracks.expand((track) => track.clips).single.id;
        final targetId = mediaType == MediaType.audio
            ? project.tracks.last.id
            : project.tracks.first.id;
        late StateSetter update;
        await tester.pumpWidget(
          MaterialApp(
            theme: TgiTheme.darkTheme,
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return TimelinePanel(
                    project: project,
                    playheadPosition: Duration.zero,
                    onMediaDropped:
                        (
                          _,
                          _, {
                          targetTrackId,
                          bool forceNewVideoTrack = false,
                          bool forceNewAudioTrack = false,
                        }) {},
                    onClipMoved: (group, start) => update(
                      () => project = project.moveTimelineClipGroup(
                        group,
                        timelineStart: start,
                      ),
                    ),
                    onClipMovedToTrack: (clip, track, start) => update(
                      () => project = project.moveClipToTrack(
                        clip,
                        targetTrackId: track,
                        timelineStart: start,
                      ),
                    ),
                    onClipMovedToNewTrack: (clip, start) => update(
                      () => project = project.moveClipToNewTrack(
                        clip,
                        timelineStart: start,
                      ),
                    ),
                    onPlayheadChanged: (_) {},
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final body = find.byKey(ValueKey('timeline-clip-body-$clipId'));
        final source = tester.getCenter(body);
        final target = tester.getCenter(find.byKey(ValueKey(targetId)));
        await tester.dragFrom(source, Offset(0, target.dy - source.dy));
        await tester.pumpAndSettle();
        expect(project.trackForClip(clipId)?.id, targetId);
        final before = project.tracks.length;
        final movedSource = tester.getCenter(body);
        final newLayer = tester.getCenter(
          find.byKey(const ValueKey('timeline-new-track-drop-zone')),
        );
        await tester.dragFrom(
          movedSource,
          Offset(0, newLayer.dy - movedSource.dy),
        );
        await tester.pumpAndSettle();
        expect(project.tracks.length, before + 1);
        expect(
          project.trackForClip(clipId)?.id,
          mediaType == MediaType.audio
              ? project.tracks.last.id
              : project.tracks.first.id,
        );
        update(() => project = project.setTimelineTrackLocked(targetId, true));
        await tester.pumpAndSettle();
        final snapshot = project;
        final locked = tester.getCenter(find.byKey(ValueKey(targetId)));
        final from = tester.getCenter(body);
        await tester.dragFrom(from, Offset(0, locked.dy - from.dy));
        await tester.pumpAndSettle();
        expect(project, same(snapshot));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('render a review image from the actual editor widgets', (
    tester,
  ) async {
    await _viewport(tester, const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final boundary = GlobalKey();
    final project = TgiProject.empty(name: 'Meu filme · TGI Video Editor')
        .addTextClipToTimeline(
          text: 'TGI VIDEO EDITOR',
          timelineStart: Duration.zero,
          fontSize: 64,
          backgroundColor: 0,
          duration: const Duration(seconds: 8),
        );
    await tester.pumpWidget(
      MaterialApp(
        theme: TgiTheme.darkTheme,
        home: RepaintBoundary(
          key: boundary,
          child: EditorScreen(initialProject: project),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        ValueKey('timeline-clip-body-${project.tracks.single.clips.single.id}'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TimelinePanel>(find.byType(TimelinePanel))
          .selectedTimelineGroupId,
      project.tracks.single.clips.single.timelineGroupId,
    );
    final render =
        boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await render.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = File('../.work/editor-desktop-review.png');
      await output.parent.create(recursive: true);
      await output.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

Future<void> _viewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.binding.setSurfaceSize(size);
}
