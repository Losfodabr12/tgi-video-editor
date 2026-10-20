import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/app/theme/app_theme.dart';
import 'package:tgi_video_editor/app/theme/design_tokens.dart';
import 'package:tgi_video_editor/domain/models/clip.dart';
import 'package:tgi_video_editor/domain/models/project.dart';
import 'package:tgi_video_editor/domain/models/track.dart';
import 'package:tgi_video_editor/features/editor/presentation/editor_screen.dart';
import 'package:tgi_video_editor/features/editor/presentation/timeline_ruler_scale.dart';
import 'package:tgi_video_editor/features/editor/presentation/widgets/video_preview_panel.dart';
import 'package:tgi_video_editor/services/ffmpeg_export_settings.dart';

void main() {
  test('neutral toggles and zoom do not consume the action accent', () {
    final theme = TgiTheme.darkTheme;
    expect(theme.colorScheme.primary, const Color(0xFF34C38F));
    const selected = {WidgetState.selected};
    expect(
      theme.switchTheme.trackColor!.resolve(selected),
      TgiColors.surfaceHover,
    );
    expect(
      theme.checkboxTheme.fillColor!.resolve(selected),
      TgiColors.surfaceHover,
    );
    expect(
      theme.segmentedButtonTheme.style!.backgroundColor!.resolve(selected),
      TgiColors.surfaceHover,
    );
    expect(theme.sliderTheme.activeTrackColor, TgiColors.textSecondary);
  });

  test(
    'ruler uses readable major spacing at every zoom, even for a long project',
    () {
      const duration = Duration(hours: 6);
      for (final pixelsPerSecond in [.38, 4.75, 76.0, 608.0, 2432.0]) {
        final scale = TimelineRulerScale(
          duration: duration,
          contentWidth: duration.inSeconds * pixelsPerSecond,
        );
        final ticks = scale.visibleTicks(
          scrollOffset: 1200,
          viewportWidth: 1280,
        );
        expect(ticks.length, lessThan(120));
        final major = ticks.where((t) => t.major).toList();
        expect(major.length, greaterThan(3));
        for (var i = 1; i < major.length; i++) {
          final distance =
              (major[i].position - major[i - 1].position).inMilliseconds /
              1000 *
              pixelsPerSecond;
          expect(distance, greaterThanOrEqualTo(96));
        }
      }
      final detail = TimelineRulerScale(
        duration: const Duration(minutes: 5),
        contentWidth: 300 * 2432,
      );
      expect(detail.label(const Duration(milliseconds: 1250)), '00:01.250');
      final overview = TimelineRulerScale(
        duration: duration,
        contentWidth: 1280,
      );
      expect(overview.label(const Duration(hours: 2)), '2:00:00');
    },
  );

  Future<void> open(WidgetTester tester, TgiProject project, Size size) async {
    final directory = Directory.systemTemp.createTempSync(
      'frame_visual_refinement_',
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    await tester.binding.setSurfaceSize(size);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      await tester.binding.setSurfaceSize(null);
      await directory.delete(recursive: true);
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: TgiTheme.darkTheme,
        home: EditorScreen(
          initialProject: project,
          workspaceLayoutPath: '${directory.path}/layout.json',
          initialExportSettings: const FfmpegExportSettings(
            quality: FfmpegExportQuality.standard,
            resolution: FfmpegExportResolution.square1080,
            framesPerSecond: 24,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('04:53 is the same in preview, project properties and timeline', (
    tester,
  ) async {
    final project = TgiProject.empty(name: '293 segundos')
        .addTextClipToTimeline(
          text: 'Frame Studio',
          timelineStart: Duration.zero,
          duration: const Duration(seconds: 293),
        );
    await open(tester, project, const Size(1440, 900));
    expect(
      tester
          .widget<VideoPreviewPanel>(find.byType(VideoPreviewPanel))
          .timelineDuration,
      const Duration(seconds: 293),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('timeline-timecode')),
        matching: find.text('00:00 / 04:53'),
      ),
      findsOneWidget,
    );
    expect(find.text('00:00 / 04:58'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('project-properties')),
        matching: find.text('04:53'),
      ),
      findsOneWidget,
    );
    expect(find.text('1080 × 1080'), findsOneWidget);
    expect(find.text('24 fps'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(1440, 900), const Size(1280, 720)]) {
    testWidgets(
      'default layout shows three entire rows including the main at $size',
      (tester) async {
        final project = TgiProject.empty(name: 'Três trilhas').copyWith(
          tracks: [
            Track(id: 'titles', name: 'Títulos', type: TrackType.text),
            Track(
              id: 'main',
              name: 'Principal',
              clips: [
                const Clip(
                  id: 'main-title',
                  mediaItemId: 'title',
                  timelineGroupId: 'main-title',
                  trackType: TrackType.text,
                  timelineStart: Duration.zero,
                  sourceStart: Duration.zero,
                  duration: Duration(seconds: 10),
                  textContent: 'Frame Studio',
                ),
              ],
            ),
            Track(id: 'audio', name: 'Áudio', kind: TrackKind.audio),
          ],
        );
        await open(tester, project, size);
        final preview = tester.getRect(
          find.byKey(const ValueKey('desktop-preview-region')),
        );
        final timeline = tester.getRect(
          find.byKey(const ValueKey('desktop-timeline-region')),
        );
        final fraction = timeline.height / (timeline.height + preview.height);
        expect(fraction, inInclusiveRange(.44, .49));
        for (final id in ['titles', 'main', 'audio']) {
          final row = tester.getRect(find.byKey(ValueKey(id)));
          expect(row.height, 64);
          expect(row.top, greaterThanOrEqualTo(timeline.top));
          expect(row.bottom, lessThanOrEqualTo(timeline.bottom - 8));
        }
        final playback = tester.getRect(
          find.byKey(const ValueKey('preview-playback-controls')),
        );
        expect(playback.center.dx, closeTo(preview.center.dx, .1));
        final tools = tester.getRect(
          find.byKey(const ValueKey('preview-edit-tools')),
        );
        expect(tools.right, lessThanOrEqualTo(playback.left));
        final body = find.byKey(
          const ValueKey('timeline-clip-body-main-title'),
        );
        await tester.tap(body);
        await tester.pumpAndSettle();
        final selected = tester
            .widgetList<AnimatedContainer>(
              find.descendant(
                of: body,
                matching: find.byType(AnimatedContainer),
              ),
            )
            .map((widget) => widget.decoration)
            .whereType<BoxDecoration>()
            .firstWhere((decoration) => decoration.color == TgiColors.clipText);
        final outline = selected.border! as Border;
        expect(outline.top.color, TgiColors.primary);
        expect(outline.top.width, 2);
        final previewOutlines = tester
            .widgetList<DecoratedBox>(
              find.descendant(
                of: find.byType(VideoPreviewPanel),
                matching: find.byType(DecoratedBox),
              ),
            )
            .map((widget) => widget.decoration)
            .whereType<BoxDecoration>()
            .map((decoration) => decoration.border)
            .whereType<Border>();
        expect(
          previewOutlines.any(
            (border) =>
                border.top.color == TgiColors.primary && border.top.width == 2,
          ),
          isTrue,
        );
        expect(find.text('I · Marcar início'), findsNothing);
        expect(find.text('O · Marcar fim'), findsNothing);
        expect(
          find.byKey(const ValueKey('timeline-zoom-slider')),
          findsOneWidget,
        );
        final slider = find.byKey(const ValueKey('timeline-zoom-slider'));
        final ruler = find.byKey(const ValueKey('timeline-ruler'));
        final initialLabels = tester
            .widgetList<Text>(
              find.descendant(of: ruler, matching: find.byType(Text)),
            )
            .map((t) => t.data)
            .toList();
        await tester.tapAt(
          tester.getRect(slider).centerRight - const Offset(16, 0),
        );
        await tester.pumpAndSettle();
        final zoomLabels = tester
            .widgetList<Text>(
              find.descendant(of: ruler, matching: find.byType(Text)),
            )
            .map((t) => t.data)
            .toList();
        expect(zoomLabels, isNot(equals(initialLabels)));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
