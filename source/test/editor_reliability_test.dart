import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/domain/models/clip.dart' as domain;
import 'package:tgi_video_editor/domain/models/media_item.dart';
import 'package:tgi_video_editor/domain/models/project.dart';
import 'package:tgi_video_editor/domain/models/track.dart';
import 'package:tgi_video_editor/features/editor/application/editor_controller.dart';
import 'package:tgi_video_editor/features/editor/presentation/widgets/timeline_panel.dart';
import 'package:tgi_video_editor/services/ffmpeg_service.dart';
import 'package:tgi_video_editor/services/media_import_service.dart';

void main() {
  test('reverse playback advances the timeline and stops at its end', () {
    final controller = _controller(_reverseProject());
    addTearDown(controller.dispose);
    controller.setTimelinePlaybackActive(true);
    expect(controller.timelinePlaybackActive, isTrue);
    controller.advanceGapPlaybackForTesting(const Duration(seconds: 1));
    expect(controller.playheadPosition, const Duration(seconds: 1));
    expect(
      controller.previewSourcePosition,
      const Duration(milliseconds: 4999),
    );
    controller.setTimelinePlaybackActive(false);
    controller.advanceGapPlaybackForTesting(const Duration(seconds: 1));
    expect(controller.playheadPosition, const Duration(seconds: 1));
    controller.setTimelinePlaybackActive(true);
    controller.advanceGapPlaybackForTesting(const Duration(seconds: 8));
    expect(controller.playheadPosition, const Duration(seconds: 6));
    expect(controller.timelinePlaybackActive, isFalse);
  });

  test(
    'reverse playback hands off at the next forward clip without skipping it',
    () {
      var project = _reverseProject();
      final first = project.tracks.single.clips.single;
      project = project.copyWith(
        tracks: [
          project.tracks.single.copyWith(
            clips: [
              first,
              first.copyWith(
                id: 'forward',
                timelineGroupId: 'forward',
                reverseVideo: false,
                timelineStart: const Duration(seconds: 6),
              ),
            ],
          ),
        ],
      );
      final controller = _controller(project);
      addTearDown(controller.dispose);
      controller.setPlayheadPosition(const Duration(seconds: 5));
      controller.setTimelinePlaybackActive(true);
      controller.advanceGapPlaybackForTesting(const Duration(seconds: 2));
      expect(controller.playheadPosition, const Duration(seconds: 6));
      expect(controller.activeTimelineClip!.id, 'forward');
      expect(controller.timelinePlaybackActive, isTrue);
      controller.advanceGapPlaybackForTesting(const Duration(seconds: 1));
      expect(controller.playheadPosition, const Duration(seconds: 6));
      controller.updatePlayheadFromPreview(
        'source',
        const Duration(seconds: 1),
      );
      expect(controller.playheadPosition, const Duration(seconds: 7));
    },
  );

  test(
    'reversed trimmed clips preserve source offsets at non-default speed',
    () {
      final project = _reverseProject();
      final controller = _controller(
        project.copyWith(
          tracks: [
            project.tracks.single.copyWith(
              clips: [
                project.tracks.single.clips.single.copyWith(
                  sourceStart: const Duration(seconds: 2),
                  sourceDuration: const Duration(seconds: 4),
                  duration: const Duration(seconds: 2),
                  playbackSpeed: 2,
                ),
              ],
            ),
          ],
        ),
      );
      addTearDown(controller.dispose);
      controller.setTimelinePlaybackActive(true);
      controller.advanceGapPlaybackForTesting(
        const Duration(milliseconds: 500),
      );
      expect(controller.playheadPosition, const Duration(milliseconds: 500));
      expect(
        controller.previewSourcePosition,
        const Duration(milliseconds: 4999),
      );
    },
  );

  test(
    'reverse playback timer actually advances without native player events',
    () async {
      final controller = _controller(_reverseProject());
      addTearDown(controller.dispose);
      final advanced = Completer<void>();
      controller.addListener(() {
        if (controller.playheadPosition > Duration.zero &&
            !advanced.isCompleted) {
          advanced.complete();
        }
      });
      controller.setTimelinePlaybackActive(true);
      await advanced.future.timeout(const Duration(seconds: 3));
      expect(
        controller.previewSourcePosition,
        lessThan(const Duration(milliseconds: 5999)),
      );
      controller.setTimelinePlaybackActive(false);
    },
  );

  test(
    'disposing an exporting controller cancels work and ignores late notifications',
    () async {
      final service = _PendingExportService();
      final controller = _controller(_reverseProject(), service: service);
      var notifications = 0;
      controller.addListener(() => notifications++);
      final exporting = controller.exportTimeline('output.mp4');
      expect(controller.isExporting, isTrue);
      final beforeDispose = notifications;
      controller.dispose();
      expect(service.cancelled, isTrue);
      service.progress!(0.75);
      await exporting;
      expect(notifications, beforeDispose);
      expect(controller.errorMessage, isNull);
      await controller.exportTimeline('another.mp4');
      expect(service.exports, 1);
    },
  );

  testWidgets(
    'long timeline only builds nearby clips and keeps lane state on playback',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 360));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final project = TgiProject.empty(name: 'Long timeline').copyWith(
        tracks: [
          Track(
            id: 'captions',
            name: 'Captions',
            type: TrackType.text,
            clips: [
              for (var index = 0; index < 500; index++)
                domain.Clip(
                  id: 'clip_$index',
                  mediaItemId: '',
                  timelineGroupId: 'group_$index',
                  trackType: TrackType.text,
                  timelineStart: Duration(seconds: index * 2),
                  sourceStart: Duration.zero,
                  duration: const Duration(seconds: 1),
                  textContent: 'Caption $index',
                ),
            ],
          ),
        ],
      );
      var playhead = Duration.zero;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return TimelinePanel(
                  project: project,
                  playheadPosition: playhead,
                  selectedTimelineGroupId: 'group_499',
                  onMediaDropped:
                      (
                        _,
                        _, {
                        targetTrackId,
                        bool forceNewVideoTrack = false,
                        bool forceNewAudioTrack = false,
                      }) {},
                  onClipMoved: (_, _) {},
                  onPlayheadChanged: (_) {},
                );
              },
            ),
          ),
        ),
      );
      final first = find.byKey(const ValueKey('timeline-clip-body-clip_0'));
      final distant = find.byKey(const ValueKey('timeline-clip-body-clip_100'));
      final selected = find.byKey(
        const ValueKey('timeline-clip-body-clip_499'),
      );
      final clipBodies = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'timeline-clip-body-',
            ),
      );
      expect(first, findsOneWidget);
      expect(distant, findsNothing);
      expect(selected, findsOneWidget);
      expect(clipBodies.evaluate().length, lessThan(15));
      final firstElement = tester.element(first);
      update(() => playhead = const Duration(milliseconds: 100));
      await tester.pump();
      expect(tester.element(first), same(firstElement));
      final scroll = tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey('timeline-horizontal-scroll')),
      );
      scroll.controller!.jumpTo(200 * 76);
      await tester.pump();
      expect(first, findsNothing);
      expect(distant, findsOneWidget);
      expect(selected, findsOneWidget);
      expect(clipBodies.evaluate().length, lessThan(15));
      expect(tester.takeException(), isNull);
    },
  );
}

TgiProject _reverseProject() {
  final media = MediaItem(
    id: 'source',
    filePath: 'source.mp4',
    name: 'source.mp4',
    type: MediaType.video,
    duration: const Duration(seconds: 6),
    importedAt: DateTime(2026),
    hasAudio: false,
  );
  return TgiProject.empty(name: 'Reverse').copyWith(
    mediaPool: [media],
    tracks: [
      Track(
        id: 'video',
        name: 'Video',
        type: TrackType.video,
        clips: [
          const domain.Clip(
            id: 'reverse',
            mediaItemId: 'source',
            timelineGroupId: 'reverse',
            trackType: TrackType.video,
            timelineStart: Duration.zero,
            sourceStart: Duration.zero,
            duration: Duration(seconds: 6),
            reverseVideo: true,
          ),
        ],
      ),
    ],
  );
}

EditorController _controller(TgiProject project, {FfmpegService? service}) =>
    EditorController(
      mediaImportService: MediaImportService(
        ffmpegService: service ?? FfmpegService(),
      ),
      initialProject: project,
    );

class _PendingExportService extends FfmpegService {
  final completion = Completer<void>();
  FfmpegExportProgressCallback? progress;
  bool cancelled = false;
  int exports = 0;
  @override
  Future<void> exportProject(
    TgiProject project,
    String outputPath, {
    FfmpegExportSettings settings = FfmpegExportSettings.defaultSettings,
    FfmpegExportProgressCallback? onProgress,
  }) {
    exports++;
    progress = onProgress;
    return completion.future;
  }

  @override
  bool cancelActiveExport() {
    cancelled = true;
    completion.completeError(const FfmpegExportCancelledException());
    return true;
  }
}
