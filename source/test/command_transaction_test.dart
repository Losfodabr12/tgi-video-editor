import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/core/commands/command_engine.dart';
import 'package:tgi_video_editor/features/editor/application/editor_controller.dart';
import 'package:tgi_video_editor/services/media_import_service.dart';
import 'package:tgi_video_editor/services/ffmpeg_service.dart';
import 'package:tgi_video_editor/services/project_io_service.dart';
import 'command_engine_test.dart' show commandFixture;

void main() {
  EditorController create() => EditorController(
    mediaImportService: MediaImportService(ffmpegService: FfmpegService()),
    initialProject: commandFixture(),
  );
  String snapshot(EditorController c) =>
      jsonEncode(ProjectIOService().serializeProject(c.project));
  test(
    'batch is one labeled transaction and undo restores byte-identical v14 JSON',
    () {
      final c = create();
      addTearDown(c.dispose);
      final original = snapshot(c);
      final clip = c.project.tracks.expand((t) => t.clips).first;
      c.executeCommands(
        [
          EditorCommand('set_volume', {'clip_id': clip.id, 'volume': 0.3}),
          EditorCommand('add_marker', {'at': 2, 'name': 'IA'}),
          EditorCommand('split_clip', {'clip_id': clip.id, 'at': 4}),
        ],
        baseRevision: 0,
        label: 'IA: corte e mixagem',
      );
      final edited = snapshot(c);
      expect(c.projectRevision, 1);
      expect(c.undoLabel, 'IA: corte e mixagem');
      c.undo();
      expect(snapshot(c), original);
      expect(c.canUndo, isFalse);
      expect(c.projectRevision, 2);
      c.redo();
      expect(snapshot(c), edited);
      expect(c.projectRevision, 3);
      expect(
        () => c.executeCommands([
          EditorCommand('add_marker', {'at': 0, 'name': 'old'}),
        ], baseRevision: 1),
        throwsA(isA<CommandError>()),
      );
    },
  );
  test('invalid second command rolls back all changes and history', () {
    final c = create();
    addTearDown(c.dispose);
    final before = snapshot(c);
    expect(
      () => c.executeCommands([
        EditorCommand('add_marker', {'at': 1, 'name': 'tentativa'}),
        EditorCommand('delete_clip', {'clip_id': 'bad'}),
      ], baseRevision: 0),
      throwsA(
        isA<CommandError>().having(
          (e) => e.details['command_index'],
          'index',
          1,
        ),
      ),
    );
    expect(snapshot(c), before);
    expect(c.projectRevision, 0);
    expect(c.canUndo, isFalse);
  });
  test(
    'UI mutation invalidates AI revision and active gesture rejects command',
    () {
      final c = create();
      addTearDown(c.dispose);
      c.addMarkerAtPlayhead();
      expect(
        () => c.executeCommands([EditorCommand('undo', {})], baseRevision: 0),
        throwsA(isA<CommandError>()),
      );
      c.beginInteractiveEdit();
      expect(
        () => c.executeCommands([
          EditorCommand('undo', {}),
        ], baseRevision: c.projectRevision),
        throwsA(
          isA<CommandError>().having((e) => e.code, 'code', 'editor_busy'),
        ),
      );
    },
  );
}
