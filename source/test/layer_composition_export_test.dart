import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/domain/models/clip.dart';
import 'package:tgi_video_editor/domain/models/media_item.dart';
import 'package:tgi_video_editor/domain/models/project.dart';
import 'package:tgi_video_editor/domain/models/track.dart';
import 'package:tgi_video_editor/features/editor/application/editor_controller.dart';
import 'package:tgi_video_editor/services/ffmpeg_service.dart';
import 'package:tgi_video_editor/services/media_import_service.dart';

const settings = FfmpegExportSettings(
  resolution: FfmpegExportResolution(
    id: 'test',
    label: 'Test',
    width: 160,
    height: 90,
  ),
  framesPerSecond: 20,
  quality: FfmpegExportQuality.light,
);

MediaItem media(String id, String path, MediaType type) => MediaItem(
  id: id,
  filePath: path,
  name: id,
  type: type,
  duration: const Duration(seconds: 1),
  importedAt: DateTime(2026),
  hasAudio: false,
);

Clip clip(String id, MediaItem media, TrackType type) => Clip(
  id: id,
  mediaItemId: media.id,
  timelineGroupId: id,
  trackType: type,
  timelineStart: Duration.zero,
  sourceStart: Duration.zero,
  duration: const Duration(seconds: 1),
  imageFit: ImageClipFit.cover,
);

void main() {
  group(
    'actual multi-layer FFmpeg composition',
    () {
      late Directory temporary;
      late FfmpegService service;
      late MediaItem red, blue, green;
      setUp(() async {
        final root = Directory('../.work')..createSync(recursive: true);
        temporary = await root.createTemp('layer_export_');
        service = FfmpegService();
        red = media('red', '${temporary.path}/red.mp4', MediaType.video);
        blue = media('blue', '${temporary.path}/blue.mp4', MediaType.video);
        green = media('green', '${temporary.path}/green.ppm', MediaType.image);
        for (final item in [red, blue]) {
          await _run(service, [
            '-y',
            '-v',
            'error',
            '-f',
            'lavfi',
            '-i',
            'color=${item.id}:s=160x90:r=20:d=1',
            '-c:v',
            'libx264',
            '-preset',
            'ultrafast',
            item.filePath,
          ]);
        }
        await File(green.filePath).writeAsBytes([
          ...'P6\n2 2\n255\n'.codeUnits,
          for (var n = 0; n < 4; n++) ...[0, 255, 0],
        ]);
      });
      tearDown(() async {
        final safeRoot = await Directory('../.work').resolveSymbolicLinks();
        final target = await temporary.resolveSymbolicLinks();
        expect(target.startsWith('$safeRoot${Platform.pathSeparator}'), isTrue);
        await temporary.delete(recursive: true);
      });

      test(
        'overlay video and text fades reveal the lower visual layer',
        () async {
          final base = Track(
            id: 'base',
            name: 'Base',
            kind: TrackKind.visual,
            clips: [clip('base', red, TrackType.video)],
          );
          final overlay = clip('overlay', blue, TrackType.video).copyWith(
            overlayX: .5,
            overlayY: .5,
            overlayScale: 4,
            fadeIn: const Duration(milliseconds: 500),
            fadeOut: const Duration(milliseconds: 500),
          );
          final project = TgiProject.empty(name: 'Fades').copyWith(
            mediaPool: [red, blue],
            tracks: [
              Track(
                id: 'overlay',
                name: 'Overlay',
                kind: TrackKind.visual,
                clips: [overlay],
              ),
              base,
            ],
          );
          final output = '${temporary.path}/overlay_fades.mp4';
          await service.exportProject(project, output, settings: settings);
          final start = await _pixel(service, output, .1);
          final middle = await _pixel(service, output, .5);
          final end = await _pixel(service, output, .9);
          expect(start[0], greaterThan(start[2]));
          expect(middle[2], greaterThan(210));
          expect(end[0], greaterThan(end[2]));
          final text = overlay.copyWith(
            id: 'text',
            trackType: TrackType.text,
            textContent: 'TGI',
            fontSize: 140,
            overlayScale: 1,
          );
          final textProject = project.copyWith(
            tracks: [
              Track(
                id: 'text',
                name: 'Text',
                kind: TrackKind.visual,
                clips: [text],
              ),
              base,
            ],
          );
          final textOutput = '${temporary.path}/text_fades.mp4';
          await service.exportProject(
            textProject,
            textOutput,
            settings: settings,
          );
          expect(await _whitePixels(service, textOutput, time: .1), 0);
          expect(
            await _whitePixels(service, textOutput, time: .5),
            greaterThan(15),
          );
          expect(await _whitePixels(service, textOutput, time: .9), 0);
        },
      );

      test(
        'moving image below video changes exported pixels and preview order',
        () async {
          final project = TgiProject.empty(name: 'Order').copyWith(
            mediaPool: [red, green],
            tracks: [
              Track(
                id: 'top',
                name: 'Image',
                kind: TrackKind.visual,
                clips: [clip('image', green, TrackType.image)],
              ),
              Track(
                id: 'bottom',
                name: 'Video',
                kind: TrackKind.visual,
                clips: [clip('video', red, TrackType.video)],
              ),
            ],
          );
          final output = '${temporary.path}/image_top.mp4';
          await service.exportProject(project, output, settings: settings);
          final top = await _pixel(service, output, .5);
          expect(top[1], greaterThan(210));
          expect(top[0], lessThan(30));
          final moved = project.reorderTrack('top', 1);
          await service.exportProject(
            moved,
            '${temporary.path}/video_top.mp4',
            settings: settings,
          );
          final bottom = await _pixel(
            service,
            '${temporary.path}/video_top.mp4',
            .5,
          );
          expect(bottom[0], greaterThan(210));
          expect(bottom[1], lessThan(30));
          expect(project.visualClipsAt(Duration.zero).map((clip) => clip.id), [
            'video',
            'image',
          ]);
          expect(moved.visualClipsAt(Duration.zero).map((clip) => clip.id), [
            'image',
            'video',
          ]);
        },
      );

      test(
        'two video layers export and selection does not change their stacking',
        () async {
          final project = TgiProject.empty(name: 'Two videos').copyWith(
            mediaPool: [red, blue],
            tracks: [
              Track(
                id: 'top',
                name: 'Top',
                kind: TrackKind.visual,
                clips: [
                  clip(
                    'blue',
                    blue,
                    TrackType.video,
                  ).copyWith(overlayX: .5, overlayY: .5, overlayScale: 4),
                ],
              ),
              Track(
                id: 'bottom',
                name: 'Bottom',
                kind: TrackKind.visual,
                clips: [clip('red', red, TrackType.video)],
              ),
            ],
          );
          final controller = EditorController(
            initialProject: project,
            mediaImportService: MediaImportService(ffmpegService: service),
          );
          addTearDown(controller.dispose);
          final before = controller.allVideoOverlaysAtPlayhead
              .map((entry) => entry.clip.id)
              .toList();
          controller.selectTimelineClipGroup('red');
          expect(
            controller.allVideoOverlaysAtPlayhead.map((entry) => entry.clip.id),
            before,
          );
          final output = '${temporary.path}/two_videos.mp4';
          await service.exportProject(project, output, settings: settings);
          final pixel = await _pixel(service, output, .5);
          expect(pixel[2], greaterThan(200));
          expect(pixel[0], lessThan(40));
        },
      );

      test(
        'text below image stays hidden, text above it is rendered',
        () async {
          final title = clip('text', green, TrackType.text).copyWith(
            textContent: 'TGI',
            fontSize: 140,
            overlayX: .5,
            overlayY: .5,
            backgroundColor: 0,
          );
          final project = TgiProject.empty(name: 'Title order').copyWith(
            mediaPool: [green],
            tracks: [
              Track(
                id: 'image',
                name: 'Image',
                kind: TrackKind.visual,
                clips: [clip('image', green, TrackType.image)],
              ),
              Track(
                id: 'title',
                name: 'Title',
                kind: TrackKind.visual,
                clips: [title],
              ),
            ],
          );
          final hidden = '${temporary.path}/hidden.mp4';
          final visible = '${temporary.path}/visible.mp4';
          await service.exportProject(project, hidden, settings: settings);
          await service.exportProject(
            project.reorderTrack('title', 0),
            visible,
            settings: settings,
          );
          expect(await _whitePixels(service, hidden), 0);
          expect(await _whitePixels(service, visible), greaterThan(15));
        },
      );

      test('main video opacity keyframes reveal lower layers', () async {
        final project = TgiProject.empty(name: 'Alpha').copyWith(
          mediaPool: [red, green],
          tracks: [
            Track(
              id: 'video',
              name: 'Video',
              kind: TrackKind.visual,
              clips: [
                clip('red', red, TrackType.video).copyWith(
                  keyframes: const [
                    ClipKeyframe(
                      id: 'a',
                      property: ClipKeyframeProperty.opacity,
                      time: 0,
                      value: 0,
                    ),
                    ClipKeyframe(
                      id: 'b',
                      property: ClipKeyframeProperty.opacity,
                      time: 1,
                      value: 1,
                    ),
                  ],
                ),
              ],
            ),
            Track(
              id: 'image',
              name: 'Image',
              kind: TrackKind.visual,
              clips: [clip('green', green, TrackType.image)],
            ),
          ],
        );
        final output = '${temporary.path}/alpha.mp4';
        await service.exportProject(project, output, settings: settings);
        final early = await _pixel(service, output, .25);
        final late = await _pixel(service, output, .75);
        expect(early[1], greaterThan(early[0]));
        expect(late[0], greaterThan(late[1]));
        expect(early[0], inInclusiveRange(35, 100));
        expect(late[0], inInclusiveRange(155, 225));
      });

      test(
        'mixed visual lane exports its image, video and text in time',
        () async {
          final image = clip('image', green, TrackType.image);
          final video = clip(
            'video',
            red,
            TrackType.video,
          ).copyWith(timelineStart: const Duration(seconds: 1));
          final text = clip('text', green, TrackType.text).copyWith(
            textContent: 'TGI',
            fontSize: 140,
            overlayX: .5,
            overlayY: .5,
            timelineStart: const Duration(seconds: 2),
          );
          final project = TgiProject.empty(name: 'Mixed').copyWith(
            mediaPool: [green, red],
            tracks: [
              Track(
                id: 'mixed',
                name: 'Visual',
                kind: TrackKind.visual,
                clips: [image, video, text],
              ),
            ],
          );
          final output = '${temporary.path}/mixed.mp4';
          await service.exportProject(project, output, settings: settings);
          expect((await _pixel(service, output, .5))[1], greaterThan(210));
          expect((await _pixel(service, output, 1.5))[0], greaterThan(210));
          expect(
            await _whitePixels(service, output, time: 2.5),
            greaterThan(15),
          );
        },
      );
    },
    skip: !const bool.fromEnvironment('TGI_RUN_FFMPEG_INTEGRATION_TESTS'),
  );
}

Future<ProcessResult> _run(FfmpegService service, List<String> args) async {
  final result = await Process.run(
    (await service.resolveToolchain()).ffmpegPath,
    args,
    stdoutEncoding: null,
    stderrEncoding: null,
  );
  expect(
    result.exitCode,
    0,
    reason: String.fromCharCodes(result.stderr as List<int>),
  );
  return result;
}

Future<Uint8List> _pixels(
  FfmpegService service,
  String path,
  double time,
  String filter,
) async => Uint8List.fromList(
  (await _run(service, [
        '-v',
        'error',
        '-ss',
        '$time',
        '-i',
        path,
        '-vf',
        filter,
        '-frames:v',
        '1',
        '-pix_fmt',
        'rgb24',
        '-f',
        'rawvideo',
        'pipe:1',
      ])).stdout
      as List<int>,
);

Future<Uint8List> _pixel(FfmpegService service, String path, double time) =>
    _pixels(service, path, time, 'crop=2:2:80:44,scale=1:1');

Future<int> _whitePixels(
  FfmpegService service,
  String path, {
  double time = .5,
}) async {
  final pixels = await _pixels(service, path, time, 'scale=160:90');
  var count = 0;
  for (var index = 0; index < pixels.length; index += 3) {
    if (pixels[index] > 180 &&
        pixels[index + 1] > 180 &&
        pixels[index + 2] > 180) {
      count++;
    }
  }
  return count;
}
