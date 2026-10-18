import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/domain/models/clip.dart';
import 'package:tgi_video_editor/domain/models/media_item.dart';
import 'package:tgi_video_editor/domain/models/project.dart';
import 'package:tgi_video_editor/domain/models/track.dart';
import 'package:tgi_video_editor/services/audio_level_service.dart';
import 'package:tgi_video_editor/services/editor_font_service.dart';
import 'package:tgi_video_editor/services/ffmpeg_service.dart';

const _settings = FfmpegExportSettings(
  resolution: FfmpegExportResolution(
    id: 'test',
    label: 'Test',
    width: 320,
    height: 180,
  ),
  framesPerSecond: 30,
  quality: FfmpegExportQuality.light,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group(
    'editor upgrade real FFmpeg',
    () {
      late Directory directory;
      late FfmpegService service;
      setUp(() async {
        directory = await Directory.systemTemp.createTemp('tgi_editor_render_');
        service = FfmpegService();
      });
      tearDown(() => directory.delete(recursive: true));

      test(
        'range preserves audio and title timing on CPU and automatic GPU',
        () async {
          final input = '${directory.path}/voice.wav';
          final source = await service.runCommand([
            '-y',
            '-v',
            'error',
            '-f',
            'lavfi',
            '-i',
            'aevalsrc=if(lt(t\\,2)\\,0.2*sin(2*PI*220*t)\\,0.2*sin(2*PI*880*t)):s=48000:d=4',
            input,
          ]);
          expect(source.exitCode, 0, reason: '${source.stderr}');
          final media = MediaItem(
            id: 'voice',
            filePath: input,
            name: 'Voice',
            type: MediaType.audio,
            duration: const Duration(seconds: 4),
            importedAt: DateTime(2026),
          );
          final project = TgiProject.empty(name: 'Range').copyWith(
            mediaPool: [media],
            tracks: [
              Track(
                id: 'audio',
                name: 'Audio',
                type: TrackType.audio,
                clips: [
                  Clip(
                    id: 'audio',
                    mediaItemId: media.id,
                    timelineGroupId: 'audio',
                    trackType: TrackType.audio,
                    timelineStart: Duration.zero,
                    sourceStart: Duration.zero,
                    duration: const Duration(seconds: 4),
                  ),
                ],
              ),
              Track(
                id: 'text',
                name: 'Text',
                type: TrackType.text,
                clips: [
                  _title(
                    'range',
                    'Bebas Neue',
                    const Duration(seconds: 2),
                    const Duration(seconds: 1),
                  ),
                ],
              ),
            ],
          );
          for (final encoder in [
            FfmpegVideoEncoder.software,
            FfmpegVideoEncoder.automatic,
          ]) {
            final output = '${directory.path}/${encoder.name}.mp4';
            final clock = Stopwatch()..start();
            await service.exportProject(
              project,
              output,
              settings: _settings.copyWith(
                rangeStart: const Duration(milliseconds: 1500),
                rangeEnd: const Duration(milliseconds: 3500),
                encoder: encoder,
              ),
            );
            // Logged for the local validation report; speed varies by hardware.
            // ignore: avoid_print
            print(
              'Range render: ${service.lastExportEncoder.name}, ${clock.elapsedMilliseconds} ms',
            );
            final probe = await service.runCommand([
              '-v',
              'error',
              '-show_entries',
              'format=duration',
              '-of',
              'csv=p=0',
              output,
            ], useFfprobe: true);
            expect(probe.exitCode, 0, reason: '${probe.stderr}');
            expect(
              double.parse(probe.stdout.toString().trim()),
              closeTo(2, 0.08),
            );
            final audioBytes = await _bytes(service, [
              '-v',
              'error',
              '-i',
              output,
              '-vn',
              '-ac',
              '1',
              '-ar',
              '8000',
              '-f',
              'f32le',
              'pipe:1',
            ]);
            final samples = ByteData.sublistView(
              Uint8List.fromList(audioBytes),
            );
            expect(_tone(samples, 220, 0.1, 0.2), greaterThan(0.17));
            expect(_tone(samples, 880, 0.9, 0.2), greaterThan(0.17));
            expect(await _brightest(service, output, 0.2), lessThan(25));
            expect(await _brightest(service, output, 0.8), greaterThan(150));
            expect(await _brightest(service, output, 1.8), lessThan(25));
          }
          final meter = AudioLevelService(service);
          addTearDown(meter.dispose);
          final levels = await meter.analyze(input);
          expect(levels.frames, hasLength(40));
          expect(
            levels.measure(Duration.zero, const Duration(seconds: 4)).peak,
            // FFmpeg's mono-to-stereo mapping applies -3 dB per channel.
            closeTo(0.2 / math.sqrt(2), 0.001),
          );
          expect(
            levels.at(const Duration(seconds: 1)).rms,
            closeTo(0.1, 0.001),
          );
        },
      );

      test('all 13 bundled fonts render visible accented text', () async {
        final families = EditorFontService.bundled.keys.toList();
        final project = TgiProject.empty(name: 'Fonts').copyWith(
          tracks: [
            Track(
              id: 'text',
              name: 'Fonts',
              type: TrackType.text,
              clips: [
                for (var i = 0; i < families.length; i++)
                  _title(
                    'font$i',
                    families[i],
                    Duration(milliseconds: i * 400),
                    const Duration(milliseconds: 400),
                  ),
              ],
            ),
          ],
        );
        final output = '${directory.path}/fonts.mp4';
        await service.exportProject(project, output, settings: _settings);
        for (var i = 0; i < families.length; i++) {
          expect(
            File(EditorFontService.filePath(families[i])).lengthSync(),
            greaterThan(1000),
          );
          expect(
            await _brightest(service, output, i * 0.4 + 0.2),
            greaterThan(150),
            reason: families[i],
          );
        }
      });
    },
    skip: !const bool.fromEnvironment('TGI_RUN_FFMPEG_INTEGRATION_TESTS'),
  );
}

Clip _title(String id, String font, Duration start, Duration duration) => Clip(
  id: id,
  mediaItemId: '',
  timelineGroupId: id,
  trackType: TrackType.text,
  timelineStart: start,
  sourceStart: Duration.zero,
  duration: duration,
  textContent: 'Olá! Ação',
  fontFamily: font,
  fontSize: 32,
);

Future<List<int>> _bytes(FfmpegService service, List<String> args) async {
  final process = await service.startCommand(args);
  final output = process.stdout.expand((chunk) => chunk).toList();
  final errors = process.stderr.transform(utf8.decoder).join();
  expect(await process.exitCode, 0, reason: await errors);
  return output;
}

Future<int> _brightest(FfmpegService service, String path, double time) async {
  final bytes = await _bytes(service, [
    '-v',
    'error',
    '-ss',
    time.toStringAsFixed(3),
    '-i',
    path,
    '-frames:v',
    '1',
    '-pix_fmt',
    'gray',
    '-f',
    'rawvideo',
    'pipe:1',
  ]);
  expect(bytes, hasLength(320 * 180));
  return bytes.reduce(math.max);
}

double _tone(
  ByteData samples,
  double frequency,
  double start,
  double duration,
) {
  var real = 0.0, imaginary = 0.0;
  final offset = (start * 8000).round();
  final count = (duration * 8000).round();
  for (var i = 0; i < count; i++) {
    final sample = samples.getFloat32((offset + i) * 4, Endian.little);
    final phase = 2 * math.pi * frequency * i / 8000;
    real += sample * math.cos(phase);
    imaginary += sample * math.sin(phase);
  }
  return 2 * math.sqrt(real * real + imaginary * imaginary) / count;
}
