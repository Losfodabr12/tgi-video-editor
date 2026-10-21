import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/core/commands/command_engine.dart';
import 'package:tgi_video_editor/domain/models/clip.dart';
import 'package:tgi_video_editor/domain/models/project.dart';
import 'package:tgi_video_editor/domain/models/track.dart';
import 'command_engine_test.dart' show commandFixture;

void main() {
  const engine = CommandEngine();
  late TgiProject project;
  setUp(() {
    const first = Clip(
      id: 'first',
      mediaItemId: 'media',
      timelineGroupId: 'g1',
      trackType: TrackType.video,
      timelineStart: Duration.zero,
      sourceStart: Duration.zero,
      duration: Duration(seconds: 4),
    );
    project = commandFixture().copyWith(
      tracks: [
        Track(
          id: 'visual',
          name: 'Visual',
          clips: [
            first,
            first.copyWith(
              id: 'second',
              timelineGroupId: 'g2',
              timelineStart: const Duration(seconds: 6),
            ),
          ],
        ),
        Track(id: 'audio', name: 'Audio', type: TrackType.audio),
      ],
    );
  });
  CommandError failure(EditorCommand command, [TgiProject? input]) {
    try {
      engine.apply(input ?? project, command);
      fail('Expected a placement failure');
    } on CommandError catch (error) {
      expect(error.details['clip_ids'], isNotEmpty);
      expect(error.details['track_ids'], isNotEmpty);
      expect(error.details['interval'], containsPair('start', isA<num>()));
      expect(error.details['suggestion'], isNotEmpty);
      return error;
    }
  }

  test('overlap reports both clips, exact lane and intersecting interval', () {
    final error = failure(
      EditorCommand('move_clip', {'clip_id': 'first', 'timeline_start': 4}),
    );
    expect(error.details['cause'], 'overlap');
    expect(error.details['clip_ids'], ['first', 'second']);
    expect(error.details['track_ids'], ['visual']);
    expect(error.details['interval'], {'start': 6.0, 'end': 8.0});
  });
  test('incompatible destination reports required lane kind', () {
    final error = failure(
      EditorCommand('move_clip', {
        'clip_id': 'first',
        'track_id': 'audio',
        'timeline_start': 0,
      }),
    );
    expect(error.details['cause'], 'incompatible_track');
    expect(error.details['track_ids'], ['audio']);
  });
  test(
    'locked lane exposes the affected linked clips without changing the legacy error code',
    () {
      final locked = project.copyWith(
        tracks: [
          project.tracks.first.copyWith(isLocked: true),
          project.tracks.last,
        ],
      );
      final error = failure(
        EditorCommand('delete_clip', {'clip_id': 'first'}),
        locked,
      );
      expect(error.code, 'track_locked');
      expect(error.details['cause'], 'locked_track');
      expect(error.details['clip_ids'], ['first']);
    },
  );
  test(
    'linked group outside available destination lanes has a distinct cause',
    () {
      final first = project.clipById('first')!;
      final linked = project.copyWith(
        tracks: [
          project.tracks.first.copyWith(clips: [first]),
          Track(
            id: 'upper',
            name: 'Upper',
            clips: [first.copyWith(id: 'linked', trackType: TrackType.text)],
          ),
        ],
      );
      final error = failure(
        EditorCommand('move_clip', {
          'clip_id': 'first',
          'track_id': 'upper',
          'timeline_start': 0,
        }),
        linked,
      );
      expect(error.details['cause'], 'linked_group');
      expect(error.details['clip_ids'], containsAll(['first', 'linked']));
    },
  );
  test(
    'trim retains the precise conflict from the model validation boundary',
    () {
      final error = failure(
        EditorCommand('trim_clip', {
          'clip_id': 'first',
          'source_start': 0,
          'source_duration': 8,
        }),
      );
      expect(error.details['cause'], 'overlap');
      expect(error.details['clip_ids'], ['first', 'second']);
    },
  );
}
