import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/core/commands/command_engine.dart';
import 'package:tgi_video_editor/domain/models/project.dart';
import 'package:tgi_video_editor/domain/models/media_item.dart';
import 'package:tgi_video_editor/domain/models/track.dart';

TgiProject commandFixture() {
  final media = MediaItem(
    id: 'media',
    name: 'sample.mp4',
    filePath: 'sample.mp4',
    importedAt: DateTime.utc(2026),
    type: MediaType.video,
    duration: Duration(seconds: 10),
    width: 1920,
    height: 1080,
    hasAudio: true,
  );
  return TgiProject.empty(name: 'MCP')
      .addMediaItem(media)
      .addMediaItemToTimeline(media, timelineStart: Duration.zero);
}

void main() {
  const engine = CommandEngine();
  test(
    'split preserves reversed trimmed source spans for linked video and audio',
    () {
      var p = commandFixture();
      final id = p.tracks
          .expand((t) => t.clips)
          .firstWhere((c) => c.trackType == TrackType.video)
          .id;
      p = engine.apply(
        p,
        EditorCommand('trim_clip', {
          'clip_id': id,
          'source_start': 1,
          'source_duration': 8,
        }),
      );
      p = engine.apply(
        p,
        EditorCommand('apply_effect', {'clip_id': id, 'reverse': true}),
      );
      p = engine.apply(
        p,
        EditorCommand('split_clip', {'clip_id': id, 'at': 3}),
      );
      for (final track in p.tracks.where((t) => t.clips.isNotEmpty)) {
        final clips = [...track.clips]
          ..sort((a, b) => a.timelineStart.compareTo(b.timelineStart));
        expect(clips.first.sourceStart, const Duration(seconds: 6));
        expect(clips.first.sourceEnd, const Duration(seconds: 9));
        expect(clips.last.sourceStart, const Duration(seconds: 1));
        expect(clips.last.sourceEnd, const Duration(seconds: 6));
      }
    },
  );
  test(
    'commands round-trip through JSON and reject invalid revision and IDs',
    () {
      final project = commandFixture();
      final clip = project.tracks.expand((t) => t.clips).first;
      final cmd = EditorCommand('split_clip', {
        'clip_id': clip.id,
        'at': 5,
      }, baseRevision: 0);
      final decoded = EditorCommand.fromJson(
        jsonDecode(jsonEncode(cmd.toJson())) as Map<String, dynamic>,
      );
      expect(decoded.toJson(), cmd.toJson());
      expect(
        engine
            .apply(project, decoded, revision: 0)
            .tracks
            .expand((t) => t.clips)
            .length,
        4,
      );
      expect(
        () => engine.apply(project, decoded, revision: 1),
        throwsA(
          isA<CommandError>().having(
            (e) => e.details['current_revision'],
            'current_revision',
            1,
          ),
        ),
      );
      expect(
        () => engine.apply(
          project,
          EditorCommand('delete_clip', {'clip_id': 'missing'}),
        ),
        throwsA(
          isA<CommandError>().having(
            (e) => e.details['valid_clip_ids'],
            'valid IDs',
            contains(clip.id),
          ),
        ),
      );
    },
  );
  test('all edit families transform pure project models', () {
    var p = commandFixture();
    final video = p.tracks
        .expand((t) => t.clips)
        .firstWhere((c) => c.trackType == TrackType.video);
    p = engine.apply(
      p,
      EditorCommand('trim_clip', {
        'clip_id': video.id,
        'source_start': 1,
        'source_duration': 8,
      }),
    );
    p = engine.apply(
      p,
      EditorCommand('move_clip', {'clip_id': video.id, 'timeline_start': 2}),
    );
    p = engine.apply(
      p,
      EditorCommand('set_clip_speed', {'clip_id': video.id, 'speed': 2}),
    );
    p = engine.apply(
      p,
      EditorCommand('apply_effect', {
        'clip_id': video.id,
        'brightness': 0.2,
        'filter': 'sepia',
      }),
    );
    p = engine.apply(
      p,
      EditorCommand('set_keyframe', {
        'clip_id': video.id,
        'property': 'opacity',
        'time': 0.5,
        'value': 0.7,
      }),
    );
    p = engine.apply(
      p,
      EditorCommand('set_volume', {'clip_id': video.id, 'volume': 0.4}),
    );
    p = engine.apply(
      p,
      EditorCommand('add_transition', {
        'at': 2,
        'duration': 0.5,
        'preset': 'dissolve',
      }),
    );
    p = engine.apply(p, EditorCommand('add_marker', {'at': 3, 'name': 'fala'}));
    p = engine.apply(
      p,
      EditorCommand('add_text', {
        'timeline_start': 2,
        'duration': 2,
        'text': 'Legenda',
        'is_caption': true,
      }),
    );
    final text = p.tracks
        .expand((t) => t.clips)
        .firstWhere((c) => c.trackType == TrackType.text);
    p = engine.apply(
      p,
      EditorCommand('set_caption_style', {'clip_id': text.id, 'font_size': 64}),
    );
    expect(p.clipById(video.id)!.brightness, 0.2);
    expect(p.clipById(video.id)!.keyframes.single.value, 0.7);
    expect(p.clipById(text.id)!.fontSize, 64);
    expect(p.markers.single.name, 'fala');
    p = engine.apply(
      p,
      EditorCommand('delete_clip', {'clip_id': video.id, 'ripple': true}),
    );
    expect(p.clipById(video.id), isNull);
  });
  test(
    'validation rejects bounds, unknown fields, locks and invalid split',
    () {
      final p = commandFixture();
      final c = p.tracks.expand((t) => t.clips).first;
      for (final cmd in [
        EditorCommand('set_volume', {'clip_id': c.id, 'volume': 3}),
        EditorCommand('split_clip', {'clip_id': c.id, 'at': 10}),
        EditorCommand('trim_clip', {
          'clip_id': c.id,
          'source_start': 8,
          'source_duration': 5,
        }),
        EditorCommand('set_keyframe', {
          'clip_id': c.id,
          'property': 'opacity',
          'time': 0.2,
          'value': 3,
        }),
        EditorCommand('move_clip', {
          'clip_id': c.id,
          'timeline_start': 2,
          'path': 'x',
        }),
      ]) {
        expect(() => engine.apply(p, cmd), throwsA(isA<CommandError>()));
      }
      final locked = p.setTimelineTrackLocked(p.clipTrackById(c.id)!.id, true);
      expect(
        () => engine.apply(
          locked,
          EditorCommand('delete_clip', {'clip_id': c.id}),
        ),
        throwsA(
          isA<CommandError>().having((e) => e.code, 'code', 'track_locked'),
        ),
      );
    },
  );
}
