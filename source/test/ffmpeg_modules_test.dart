import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/domain/models/clip.dart';
import 'package:tgi_video_editor/domain/models/project.dart';
import 'package:tgi_video_editor/domain/models/track.dart';
import 'package:tgi_video_editor/services/ffmpeg_filtergraph_builder.dart';
import 'package:tgi_video_editor/services/ffmpeg_progress_parser.dart';
import 'package:tgi_video_editor/features/editor/application/editor_history.dart';

void main() {
  test('pure builder returns text inputs without writing them', () {
    final directory =
        '${Directory.systemTemp.path}/not_created_${DateTime.now().microsecondsSinceEpoch}';
    final project = TgiProject.empty(name: 'Pure').copyWith(
      tracks: [
        Track(
          id: 'text',
          name: 'Text',
          kind: TrackKind.visual,
          clips: [
            const Clip(
              id: 'text',
              mediaItemId: '',
              timelineGroupId: 'text',
              trackType: TrackType.text,
              timelineStart: Duration.zero,
              sourceStart: Duration.zero,
              duration: Duration(seconds: 1),
              textContent: 'Olá: teste',
            ),
          ],
        ),
      ],
    );
    final builder = FfmpegFiltergraphBuilder(fontPath: (_) => 'font.ttf');
    final first = builder.buildExportCommand(
      project,
      'output.mp4',
      drawTextDirectoryPath: directory,
    );
    final second = builder.buildExportCommand(
      project,
      'output.mp4',
      drawTextDirectoryPath: directory,
    );
    expect(first.arguments, second.arguments);
    expect(first.textFiles.values, contains('Olá: teste'));
    expect(Directory(directory).existsSync(), isFalse);
  });

  test('progress parser selects the last complete timestamp', () {
    const parser = FfmpegProgressParser();
    expect(
      parser.parse('time=00:00:01.25\ntime=01:02:03.456'),
      const Duration(hours: 1, minutes: 2, milliseconds: 3456),
    );
    expect(parser.parse('time=N/A'), isNull);
  });

  test('history trims snapshots and clears redo on a new mutation', () {
    final history = EditorHistory(limit: 2);
    final project = TgiProject.empty(name: 'A');
    history.record(project);
    history.record(project.copyWith(name: 'B'));
    history.redoStack.add(project);
    history.record(project.copyWith(name: 'C'));
    expect(history.undoStack.map((p) => p.name), ['B', 'C']);
    expect(history.redoStack, isEmpty);
  });
}
