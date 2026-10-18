import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/domain/models/clip.dart';
import 'package:tgi_video_editor/domain/models/media_item.dart';
import 'package:tgi_video_editor/domain/models/project.dart';
import 'package:tgi_video_editor/domain/models/track.dart';
import 'package:tgi_video_editor/features/editor/presentation/widgets/advanced_speed_panel.dart';
import 'package:tgi_video_editor/features/editor/presentation/widgets/preview_entries.dart';
import 'package:tgi_video_editor/features/editor/presentation/widgets/professional_color_panel.dart';
import 'package:tgi_video_editor/features/editor/presentation/widgets/timeline_panel.dart';

void main() {
  Clip videoClip() => const Clip(
    id: 'video-professional',
    mediaItemId: 'media-1',
    timelineGroupId: 'group-1',
    trackType: TrackType.video,
    timelineStart: Duration.zero,
    sourceStart: Duration.zero,
    duration: Duration(seconds: 8),
  );

  testWidgets('professional color exposes histogram curves and white balance', (
    tester,
  ) async {
    bool? picker;
    bool? compare;
    double? brightness;
    var interactionStarts = 0;
    var interactionEnds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 850,
            child: ProfessionalColorPanel(
              clip: videoClip(),
              mediaName: 'cor.mp4',
              analysis: const VideoColorAnalysis(
                luma: [0.1, 0.8, 0.2],
                red: [0.2, 0.6, 0.1],
                green: [0.1, 0.5, 0.2],
                blue: [0.3, 0.4, 0.1],
                averageColor: 0xFF808080,
              ),
              analysisLoading: false,
              compareOriginal: false,
              whiteBalancePickerActive: false,
              onRefreshAnalysis: () {},
              onCompareOriginalChanged: (value) => compare = value,
              onWhiteBalancePickerChanged: (value) => picker = value,
              onBrightnessChanged: (value) => brightness = value,
              onContrastChanged: (_) {},
              onSaturationChanged: (_) {},
              onExposureChanged: (_) {},
              onHueChanged: (_) {},
              onTemperatureChanged: (_) {},
              onTintChanged: (_) {},
              onShadowsChanged: (_) {},
              onHighlightsChanged: (_) {},
              onCurvesChanged: (_, _, _) {},
              onInteractionStart: () => interactionStarts++,
              onInteractionEnd: () => interactionEnds++,
              onReset: () {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('professional_color_histogram')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('color_before_after_switch')));
    expect(compare, isTrue);
    await tester.tap(find.byKey(const ValueKey('white_balance_picker_button')));
    expect(picker, isTrue);
    final brightnessControl = find.byKey(
      const ValueKey('color_brightness_video-professional'),
    );
    await tester.scrollUntilVisible(
      brightnessControl,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final brightnessSlider = find.descendant(
      of: brightnessControl,
      matching: find.byType(Slider),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(brightnessSlider),
    );
    await gesture.moveBy(const Offset(50, 0));
    await tester.pump();

    expect(brightness, isNotNull);
    expect(interactionStarts, greaterThan(0));

    await gesture.up();
    await tester.pump();
    expect(interactionEnds, greaterThan(0));
    await tester.scrollUntilVisible(
      find.text('Curva de luminância'),
      420,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Curva de luminância'), findsOneWidget);
  });

  testWidgets(
    'advanced speed exposes real ramps slow motion freeze and reverse',
    (tester) async {
      List<double>? ramp;
      var slowMotion = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 850,
              child: AdvancedSpeedPanel(
                clip: videoClip(),
                mediaName: 'velocidade.mp4',
                onConstantSpeedChanged: (_) {},
                onRampSelected: (values, _) => ramp = values,
                onSlowMotion: () => slowMotion = true,
                onFreezeFrame: () {},
                onReverseChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Rampas de velocidade'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('speed_ramp_accelerate')));
      expect(ramp, hasLength(5));
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('advanced_slow_motion_button')),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(
        find.byKey(const ValueKey('advanced_slow_motion_button')),
      );
      expect(slowMotion, isTrue);
      expect(
        find.byKey(const ValueKey('advanced_freeze_frame_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('advanced_reverse_switch')),
        findsOneWidget,
      );
    },
  );

  testWidgets('short speed ramp segments do not overlap in the timeline', (
    tester,
  ) async {
    final item = MediaItem(
      id: 'short_ramp_media',
      filePath: r'C:\videos\short-ramp.mp4',
      name: 'short-ramp.mp4',
      type: MediaType.video,
      duration: const Duration(seconds: 3),
      importedAt: DateTime(2026),
    );
    var project = TgiProject.empty(name: 'Rampa cortada')
        .addMediaItem(item)
        .addMediaItemToTimeline(item, timelineStart: Duration.zero);
    var videoClips = project.tracks
        .firstWhere((track) => track.type == TrackType.video)
        .clips;
    project = project.splitTimelineClipGroupAt(
      videoClips.single.id,
      timelinePosition: const Duration(seconds: 1),
    );
    videoClips = project.tracks
        .firstWhere((track) => track.type == TrackType.video)
        .clips;
    final right = videoClips.last;
    project = project.splitTimelineClipGroupAt(
      right.id,
      timelinePosition: const Duration(seconds: 2),
    );
    videoClips = project.tracks
        .firstWhere((track) => track.type == TrackType.video)
        .clips;
    final middle = videoClips.firstWhere(
      (clip) => clip.timelineStart == const Duration(seconds: 1),
    );
    project = project.applyClipGroupSpeedRamp(
      middle.timelineGroupId,
      speedMultipliers: const [0.65, 0.8, 1, 1.5, 3],
    );
    final rampClips =
        project.tracks
            .firstWhere((track) => track.type == TrackType.video)
            .clips
            .where(
              (clip) =>
                  clip.sourceStart >= const Duration(seconds: 1) &&
                  clip.sourceEnd <= const Duration(seconds: 2),
            )
            .toList()
          ..sort((a, b) => a.timelineStart.compareTo(b.timelineStart));
    expect(rampClips, hasLength(5));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 280,
            child: TimelinePanel(
              project: project,
              playheadPosition: Duration.zero,
              onMediaDropped:
                  (
                    item,
                    timelineStart, {
                    targetTrackId,
                    bool forceNewVideoTrack = false,
                    bool forceNewAudioTrack = false,
                  }) {},
              onClipMoved: (_, _) {},
              onPlayheadChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (var index = 1; index < rampClips.length; index++) {
      final previous = tester.getRect(
        find.byKey(ValueKey('timeline-clip-body-${rampClips[index - 1].id}')),
      );
      final current = tester.getRect(
        find.byKey(ValueKey('timeline-clip-body-${rampClips[index].id}')),
      );
      expect(previous.right, lessThanOrEqualTo(current.left + 1.5));
    }
  });
}
