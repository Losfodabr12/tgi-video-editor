import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/core/commands/timeline_time_map.dart';
import 'package:tgi_video_editor/domain/models/track.dart';
import 'support/render_fixture.dart';
import 'support/silence_project.dart';

void main() {
  test(
    'join fades use existing audio fields, preserve outer fades and do not fade video',
    () {
      final p = silenceProject();
      final map = TimelineTimeMap([(2000000, 4000000)], end: 10000000);
      final after = const TimelineRemapper()
          .apply(p, p.clipById('video')!, map, joinFadeMs: 8)
          .project;
      final audio = after.trackById('audio')!.clips;
      expect(audio.first.fadeIn, Duration.zero);
      expect(audio.first.fadeOut, const Duration(milliseconds: 8));
      expect(audio.last.fadeIn, const Duration(milliseconds: 8));
      expect(audio.last.fadeOut, Duration.zero);
      expect(
        after
            .trackById('main')!
            .clips
            .every(
              (c) => c.fadeIn == Duration.zero && c.fadeOut == Duration.zero,
            ),
        true,
      );
      final disabled = const TimelineRemapper()
          .apply(p, p.clipById('video')!, map)
          .project;
      expect(
        disabled
            .trackById('audio')!
            .clips
            .every(
              (c) => c.fadeIn == Duration.zero && c.fadeOut == Duration.zero,
            ),
        true,
      );
      final existing = p.copyWith(
        tracks: [
          p.tracks.first,
          p.tracks.last.copyWith(
            clips: [
              p.tracks.last.clips.single.copyWith(
                fadeIn: const Duration(milliseconds: 90),
                fadeOut: const Duration(milliseconds: 60),
              ),
            ],
          ),
        ],
      );
      final preserved = const TimelineRemapper()
          .apply(existing, existing.clipById('video')!, map, joinFadeMs: 8)
          .project
          .trackById('audio')!
          .clips;
      expect(preserved.first.fadeIn.inMilliseconds, 90);
      expect(preserved.last.fadeOut.inMilliseconds, 60);
    },
  );

  test(
    'native continuous tone: exported afade reduces adjacent-sample jump around join',
    () async {
      final f = RenderFixture();
      await f.open();
      addTearDown(f.close);
      final source = '${f.directory.path}/tone.wav';
      await f.run([
        '-y',
        '-v',
        'error',
        '-f',
        'lavfi',
        '-i',
        'aevalsrc=0.7*sin(2*PI*437*t):s=48000:d=3',
        '-c:a',
        'pcm_s16le',
        source,
      ]);
      final base = silenceProject(duration: 3);
      final p = base.copyWith(
        mediaPool: [base.mediaPool.single.copyWith(filePath: source)],
        tracks: [base.trackById('audio')!],
      );
      final map = TimelineTimeMap([(503000, 1231000)], end: 3000000);
      final jumps = <String, double>{};
      for (final fade in [0, 8]) {
        final remapped = const TimelineRemapper()
            .apply(p, p.tracks.single.clips.single, map, joinFadeMs: fade)
            .project;
        expect(
          remapped.tracks.single.clips.every(
            (c) => c.trackType == TrackType.audio,
          ),
          true,
        );
        final output = '${f.directory.path}/fade_$fade.wav';
        await f.service.exportProject(
          remapped,
          output,
          settings: RenderFixture.settings.copyWith(audioOnly: true),
        );
        final raw =
            (await f.run([
                  '-v',
                  'error',
                  '-i',
                  output,
                  '-ac',
                  '1',
                  '-ar',
                  '48000',
                  '-f',
                  'f32le',
                  'pipe:1',
                ])).stdout
                as List<int>;
        final bytes = ByteData.sublistView(Uint8List.fromList(raw));
        double sample(int n) => bytes.getFloat32(n * 4, Endian.little);
        final join = (.503 * 48000).round();
        var jump = 0.0;
        for (var n = join - 240; n <= join + 240; n++) {
          jump = math.max(jump, (sample(n) - sample(n - 1)).abs());
        }
        jumps['${fade}ms'] = jump;
      }
      expect(jumps['8ms']!, lessThan(jumps['0ms']! * .25), reason: '$jumps');
      // Only numeric measurements, no media paths or credentials in the artifact.
      final report = Platform.environment['CUT_FADE_REPORT'];
      if (report != null) {
        await File(report).writeAsString(
          '${const JsonEncoder.withIndent('  ').convert({'sample_rate': 48000, 'window_ms_each_side': 5, 'maximum_adjacent_sample_jump': jumps, 'ratio': jumps['8ms']! / jumps['0ms']!})}\n',
        );
      }
    },
    skip: !const bool.fromEnvironment('TGI_RUN_FFMPEG_INTEGRATION_TESTS'),
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
