import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/domain/models/cross_dissolve.dart';
import 'package:tgi_video_editor/domain/models/project.dart';
import 'package:tgi_video_editor/domain/models/timeline_transition.dart';
import 'package:tgi_video_editor/domain/models/track.dart';

import 'support/render_fixture.dart';

void main() {
  final fixture = RenderFixture();
  setUp(fixture.open);
  tearDown(fixture.close);

  test(
    'real xfade mixes A/B pixels and acrossfade mixes both tones without shortening',
    () async {
      final red = await fixture.color('red', audio: '220');
      final blue = await fixture.color('blue', audio: '880');
      final left = fixture.clip(red).copyWith(overlayScale: 1);
      final right = fixture
          .clip(blue, start: const Duration(seconds: 1))
          .copyWith(overlayScale: 1);
      final project = TgiProject.empty(name: 'Dissolve').copyWith(
        mediaPool: [red, blue],
        tracks: [
          Track(
            id: 'video',
            name: 'Video',
            kind: TrackKind.visual,
            clips: [left, right],
          ),
          Track(
            id: 'audio',
            name: 'Audio',
            kind: TrackKind.audio,
            clips: [
              left.copyWith(id: 'a', trackType: TrackType.audio),
              right.copyWith(id: 'b', trackType: TrackType.audio),
            ],
          ),
        ],
        transitions: const [
          TimelineTransition(
            id: 'd',
            name: 'Dissolve',
            timelinePosition: Duration(seconds: 1),
            duration: Duration(milliseconds: 400),
            preset: TimelineTransitionPreset.dissolve,
          ),
        ],
      );
      final plan = CrossDissolve.forProject(project).single;
      expect(plan.progressAt(const Duration(seconds: 1)), .5);
      final command = fixture.service.buildExportCommand(
        project,
        'unused.mp4',
        settings: RenderFixture.settings,
      );
      expect(command.arguments.join(' '), contains('xfade=transition=fade'));
      expect(command.arguments.join(' '), contains('acrossfade='));
      final output = await fixture.export(project, 'dissolve');
      expect((await fixture.pixel(output, .5))[0], greaterThan(225));
      final middle = await fixture.pixel(output, 1);
      expect(middle[0], closeTo(127, 25));
      expect(middle[2], closeTo(127, 25));
      expect((await fixture.pixel(output, 1.5))[2], greaterThan(225));
      final probe = await fixture.service.runCommand([
        '-v',
        'error',
        '-show_entries',
        'format=duration',
        '-of',
        'json',
        output,
      ], useFfprobe: true);
      final duration = double.parse(
        (jsonDecode(probe.stdout as String) as Map)['format']['duration']
            as String,
      );
      expect(duration, closeTo(2, .06));
      final pcm =
          (await fixture.run([
                '-v',
                'error',
                '-ss',
                '0.95',
                '-i',
                output,
                '-t',
                '0.1',
                '-vn',
                '-ac',
                '1',
                '-ar',
                '8000',
                '-f',
                'f32le',
                'pipe:1',
              ])).stdout
              as List<int>;
      final data = ByteData.sublistView(Uint8List.fromList(pcm));
      final samples = List.generate(
        data.lengthInBytes ~/ 4,
        (i) => data.getFloat32(i * 4, Endian.little),
      );
      double amplitude(int frequency) {
        var real = 0.0, imaginary = 0.0;
        for (var i = 0; i < samples.length; i++) {
          final phase = 2 * math.pi * frequency * i / 8000;
          real += samples[i] * math.cos(phase);
          imaginary += samples[i] * math.sin(phase);
        }
        return math.sqrt(real * real + imaginary * imaginary) / samples.length;
      }

      expect(amplitude(220), greaterThan(.01));
      expect(amplitude(880), greaterThan(.01));
    },
  );

  test(
    'dissolve only binds adjacent clips and clamps to available durations',
    () async {
      final red = await fixture.color('red');
      final left = fixture.clip(red);
      final right = left.copyWith(
        id: 'right',
        timelineStart: const Duration(seconds: 1),
      );
      final project = fixture
          .project([red], [left])
          .copyWith(
            tracks: [
              Track(id: 'v', name: 'v', clips: [left, right]),
            ],
            transitions: const [
              TimelineTransition(
                id: 'd',
                name: 'd',
                timelinePosition: Duration(seconds: 1),
                duration: Duration(seconds: 4),
                preset: TimelineTransitionPreset.dissolve,
              ),
            ],
          );
      expect(
        CrossDissolve.forProject(project).single.duration,
        const Duration(seconds: 1),
      );
      expect(
        CrossDissolve.forProject(
          project.copyWith(
            tracks: [
              Track(
                id: 'v',
                name: 'v',
                clips: [
                  left,
                  right.copyWith(timelineStart: const Duration(seconds: 2)),
                ],
              ),
            ],
          ),
        ),
        isEmpty,
      );
    },
  );
}
