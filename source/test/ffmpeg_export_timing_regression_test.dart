import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/domain/models/clip.dart';
import 'package:tgi_video_editor/domain/models/media_item.dart';
import 'package:tgi_video_editor/domain/models/project.dart';
import 'package:tgi_video_editor/domain/models/track.dart';
import 'package:tgi_video_editor/services/ffmpeg_service.dart';

const _settings = FfmpegExportSettings(
  resolution: FfmpegExportResolution(
    id: 'test',
    label: 'Test',
    width: 160,
    height: 90,
  ),
  framesPerSecond: 30,
  quality: FfmpegExportQuality.light,
);

void main() {
  group(
    'real export matches timeline timing',
    () {
      late Directory temporary;
      late FfmpegService service;
      late MediaItem music;
      late MediaItem video;

      setUp(() async {
        temporary = await Directory.systemTemp.createTemp('tgi_timing_');
        service = FfmpegService();
        music = _media(
          'music',
          '${temporary.path}/music.mp3',
          MediaType.audio,
          6,
        );
        video = _media(
          'video',
          '${temporary.path}/video.mp4',
          MediaType.video,
          4,
        );
        await _run(service, [
          '-y',
          '-v',
          'error',
          '-f',
          'lavfi',
          '-i',
          "aevalsrc='if(lt(t,3),0.2*sin(2*PI*220*t),0.2*sin(2*PI*880*t))':s=44100:d=6",
          '-c:a',
          'libmp3lame',
          music.filePath,
        ]);
        await _run(service, [
          '-y',
          '-v',
          'error',
          '-f',
          'lavfi',
          '-i',
          'color=black:s=160x90:r=30:d=4',
          '-f',
          'lavfi',
          '-i',
          'aevalsrc=0.08*sin(2*PI*330*t):s=44100:d=4',
          '-c:v',
          'libx264',
          '-preset',
          'ultrafast',
          '-c:a',
          'aac',
          '-shortest',
          video.filePath,
        ]);
      });

      tearDown(() => temporary.delete(recursive: true));

      for (final withVideo in [false, true]) {
        test(
          'trimmed music starts at its timeline position (video=$withVideo)',
          () async {
            final project = TgiProject.empty(name: 'Delayed music').copyWith(
              mediaPool: [music, video],
              tracks: [
                if (withVideo) ...[
                  Track(
                    id: 'v',
                    name: 'Video',
                    type: TrackType.video,
                    clips: [
                      _clip('v', video, TrackType.video, durationMs: 3000),
                    ],
                  ),
                  Track(
                    id: 'a',
                    name: 'Source audio',
                    type: TrackType.audio,
                    clips: [
                      _clip('a', video, TrackType.audio, durationMs: 3000),
                    ],
                  ),
                ],
                Track(
                  id: 'music',
                  name: 'Music',
                  type: TrackType.audio,
                  clips: [
                    _clip(
                      'music',
                      music,
                      TrackType.audio,
                      startMs: 2250,
                      sourceMs: 3250,
                      durationMs: 1500,
                    ),
                  ],
                ),
              ],
            );
            final output = '${temporary.path}/export.mp4';
            await service.exportProject(project, output, settings: _settings);
            final samples = await _audio(service, output);
            expect(
              _tone(samples, 880, 0.4, 0.5),
              lessThan(0.003),
              reason: 'The late music must not leak into the beginning.',
            );
            expect(
              _tone(samples, 880, 2.5, 0.4),
              greaterThan(0.16),
              reason:
                  'The selected source range must play at the requested gain.',
            );
            expect(
              _tone(samples, 220, 2.5, 0.4),
              lessThan(0.01),
              reason:
                  'The removed beginning of the music must not be restored.',
            );
            expect(
              _tone(samples, 880, 3.2, 0.4),
              greaterThan(0.16),
              reason: 'Music must continue after the last video frame.',
            );
            expect(samples.length / 8000, closeTo(3.75, 0.06));
            if (withVideo) {
              expect(
                _tone(samples, 330, 0.4, 0.5),
                closeTo(0.08, 0.008),
                reason:
                    'A silent delayed track must not halve the source gain.',
              );
            }
          },
        );

        test('image fades match preview opacity (video=$withVideo)', () async {
          final image = _media(
            'image',
            '${temporary.path}/white.ppm',
            MediaType.image,
            3,
          );
          await File(image.filePath).writeAsBytes([
            ...'P6\n2 2\n255\n'.codeUnits,
            ...List.filled(12, 255),
          ]);
          final project = TgiProject.empty(name: 'Image fades').copyWith(
            mediaPool: [image, video],
            tracks: [
              if (withVideo)
                Track(
                  id: 'v',
                  name: 'Video',
                  type: TrackType.video,
                  clips: [_clip('v', video, TrackType.video, durationMs: 4000)],
                ),
              Track(
                id: 'image',
                name: 'Image',
                type: TrackType.image,
                clips: [
                  _clip(
                    'image',
                    image,
                    TrackType.image,
                    startMs: 1000,
                    durationMs: 3000,
                  ).copyWith(
                    imageFit: ImageClipFit.cover,
                    opacity: 0.6,
                    fadeIn: const Duration(seconds: 1),
                    fadeOut: const Duration(seconds: 1),
                  ),
                ],
              ),
            ],
          );
          final output = '${temporary.path}/fades.mp4';
          await service.exportProject(project, output, settings: _settings);
          expect(await _brightness(service, output, 0.5), lessThan(0.02));
          expect(await _brightness(service, output, 1.25), closeTo(0.15, 0.04));
          expect(await _brightness(service, output, 2.5), closeTo(0.6, 0.04));
          expect(await _brightness(service, output, 3.5), closeTo(0.3, 0.04));
          expect(await _brightness(service, output, 3.9), lessThan(0.1));
        });
      }

      test(
        'audio timeline rendering preserves leading silence and gain',
        () async {
          final output = '${temporary.path}/timeline.wav';
          final command = service.buildAudioTimelineCommand(
            clips: [
              FfmpegAudioTimelineClip(
                inputPath: music.filePath,
                timelineStart: const Duration(milliseconds: 2250),
                duration: const Duration(milliseconds: 1500),
              ),
            ],
            outputPath: output,
          );
          await _run(service, command.arguments);
          final samples = await _audio(service, output);
          expect(_tone(samples, 220, 0.4, 0.5), lessThan(0.003));
          expect(_tone(samples, 220, 2.5, 0.5), greaterThan(0.16));
          expect(samples.length / 8000, closeTo(3.75, 0.02));
        },
      );
    },
    skip: !const bool.fromEnvironment('TGI_RUN_FFMPEG_INTEGRATION_TESTS'),
  );
}

MediaItem _media(String id, String path, MediaType type, int seconds) =>
    MediaItem(
      id: id,
      filePath: path,
      name: id,
      type: type,
      duration: Duration(seconds: seconds),
      importedAt: DateTime(2026),
    );

Clip _clip(
  String id,
  MediaItem media,
  TrackType type, {
  int startMs = 0,
  int sourceMs = 0,
  required int durationMs,
}) => Clip(
  id: id,
  mediaItemId: media.id,
  timelineGroupId: media.id,
  trackType: type,
  timelineStart: Duration(milliseconds: startMs),
  sourceStart: Duration(milliseconds: sourceMs),
  duration: Duration(milliseconds: durationMs),
);

Future<void> _run(FfmpegService service, List<String> args) async {
  final result = await service.runCommand(args);
  expect(result.exitCode, 0, reason: '${result.stderr}');
}

Future<Uint8List> _bytes(FfmpegService service, List<String> args) async {
  final process = await service.startCommand(args);
  final bytes = process.stdout.fold<BytesBuilder>(
    BytesBuilder(copy: false),
    (builder, chunk) => builder..add(chunk),
  );
  final errors = process.stderr.fold<String>(
    '',
    (text, chunk) => text + String.fromCharCodes(chunk),
  );
  final code = await process.exitCode;
  expect(code, 0, reason: await errors);
  return (await bytes).takeBytes();
}

Future<Float32List> _audio(FfmpegService service, String path) async {
  final bytes = await _bytes(service, [
    '-v',
    'error',
    '-i',
    path,
    '-vn',
    '-ac',
    '1',
    '-ar',
    '8000',
    '-f',
    'f32le',
    'pipe:1',
  ]);
  return Float32List.view(bytes.buffer, bytes.offsetInBytes, bytes.length ~/ 4);
}

double _tone(
  Float32List samples,
  int frequency,
  double start,
  double duration,
) {
  final begin = (start * 8000).round();
  final count = (duration * 8000).round();
  expect(samples.length, greaterThanOrEqualTo(begin + count));
  var sine = 0.0;
  var cosine = 0.0;
  for (var i = 0; i < count; i++) {
    final phase = 2 * math.pi * frequency * i / 8000;
    sine += samples[begin + i] * math.sin(phase);
    cosine += samples[begin + i] * math.cos(phase);
  }
  return 2 * math.sqrt(sine * sine + cosine * cosine) / count;
}

Future<double> _brightness(
  FfmpegService service,
  String path,
  double time,
) async {
  final bytes = await _bytes(service, [
    '-v',
    'error',
    '-ss',
    '$time',
    '-i',
    path,
    '-frames:v',
    '1',
    '-vf',
    'scale=16:16',
    '-pix_fmt',
    'gray',
    '-f',
    'rawvideo',
    'pipe:1',
  ]);
  expect(bytes, hasLength(256));
  return bytes.reduce((a, b) => a + b) / bytes.length / 255;
}
