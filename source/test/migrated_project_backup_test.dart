import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/domain/models/clip.dart';
import 'package:tgi_video_editor/domain/models/project.dart';
import 'package:tgi_video_editor/domain/models/track.dart';
import 'package:tgi_video_editor/services/project_io_service.dart';

void main() {
  late Directory root;
  late String path;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('frame_migration_backup_');
    path = '${root.path}/project.json';
  });
  tearDown(() => root.delete(recursive: true));

  for (final version in [13, 14]) {
    test(
      'format $version migration keeps original bytes through subsequent saves',
      () async {
        final io = ProjectIOService();
        final old = TgiProject.empty(name: 'Antes').copyWith(
          tracks: [
            Track(
              id: 'video',
              name: 'Original',
              clips: [
                for (var i = 0; i < 2; i++)
                  Clip(
                    id: 'c$i',
                    mediaItemId: 'm$i',
                    timelineGroupId: 'g$i',
                    trackType: TrackType.video,
                    timelineStart: Duration(seconds: i),
                    sourceStart: Duration.zero,
                    duration: const Duration(seconds: 3),
                  ),
              ],
            ),
          ],
        );
        final data = io.serializeProject(old)..['version'] = version;
        final bytes = utf8.encode(
          '${const JsonEncoder.withIndent('  ').convert(data)}\r\n',
        );
        await File(path).writeAsBytes(bytes);
        final migrated = io
            .deserializeProject(await io.readFromFile(path))
            .project;
        expect(migrated.tracks.length, 2);
        expect(
          await File('$path.bak').exists(),
          isFalse,
        ); // Loading never writes.
        await io.saveToFile(migrated, path);
        expect(await File('$path.bak').readAsBytes(), bytes);
        expect((await io.readFromFile(path))['version'], 14);
        // A different service and concurrent saves must retain the pre-migration copy.
        await Future.wait([
          for (var i = 0; i < 5; i++)
            ProjectIOService().saveToFile(
              migrated.copyWith(name: 'Edit $i'),
              path,
            ),
        ]);
        expect(await File('$path.bak').readAsBytes(), bytes);
        expect((await io.readFromFile(path))['projectName'], 'Edit 4');
        expect(root.listSync().whereType<Directory>(), isEmpty);
      },
    );
  }

  test(
    'legacy project without overlaps is backed up by serialized save too',
    () async {
      final io = ProjectIOService();
      final data = io.serializeProject(TgiProject.empty(name: 'Legacy'))
        ..['version'] = 12;
      final original = jsonEncode(data);
      await File(path).writeAsString(original);
      final migrated = io.serializeProject(io.deserializeProject(data).project);
      await io.saveSerializedToFile(migrated, path);
      expect(await File('$path.bak').readAsString(), original);
      expect((await io.readFromFile(path))['version'], 14);
    },
  );

  test(
    'Save As leaves the source untouched and creates no unnecessary backup',
    () async {
      final io = ProjectIOService();
      final data = io.serializeProject(TgiProject.empty(name: 'Teste'))..['version'] = 13;
      await File(path).writeAsString(jsonEncode(data));
      final original = await File(path).readAsBytes();
      final migrated = io
          .deserializeProject(await io.readFromFile(path))
          .project;
      await io.saveToFile(migrated, '$path.new');
      expect(await File(path).readAsBytes(), original);
      expect(await File('$path.bak').exists(), isFalse);
      expect(await File('$path.new.bak').exists(), isFalse);
      expect((await io.readFromFile('$path.new'))['version'], 14);
    },
  );

  test(
    'an existing migration backup is never replaced by corrupt input',
    () async {
      final io = ProjectIOService();
      await File(path).writeAsString('{broken');
      await io.saveToFile(TgiProject.empty(name: 'Teste'), path);
      expect(await File('$path.bak').readAsString(), '{broken');
      await File(path).writeAsString('{also broken');
      await io.saveToFile(TgiProject.empty(name: 'Teste'), path);
      expect(await File('$path.bak').readAsString(), '{broken');
    },
  );
}
