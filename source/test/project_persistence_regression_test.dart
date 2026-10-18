import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/domain/models/project.dart';
import 'package:tgi_video_editor/services/project_file_storage.dart';
import 'package:tgi_video_editor/services/project_io_service.dart';
import 'package:tgi_video_editor/services/project_recovery_service.dart';

void main() {
  late Directory root;
  late String path;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tgi_persistence_test_');
    path = '${root.path}${Platform.pathSeparator}project.json';
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'concurrent saves across services keep the last requested project',
    () async {
      await Future.wait([
        for (var i = 0; i < 30; i++)
          ProjectIOService().saveToFile(
            TgiProject.empty(name: 'Version $i'),
            path,
          ),
      ]);
      expect(
        (await ProjectIOService().readFromFile(path))['projectName'],
        'Version 29',
      );
      expect(root.listSync().map((entry) => entry.path), [path]);
    },
  );

  test(
    'serialization cannot reorder saves and reads see the requested revision',
    () async {
      final pending = Completer<String>();
      final started = Completer<void>();
      final first = ProjectFileStorage.write(path, () {
        started.complete();
        return pending.future;
      });
      await started.future;
      final readingFirst = ProjectFileStorage.read(path);
      final second = ProjectFileStorage.write(path, () => 'second');
      pending.complete('first');
      await Future.wait([first, second]);
      expect(await readingFirst, 'first');
      expect(await ProjectFileStorage.read(path), 'second');
    },
  );

  test('recovery writes, reads and cleanup share the same queue', () async {
    final services = [
      ProjectRecoveryService(recoveryFilePath: path),
      ProjectRecoveryService(recoveryFilePath: path),
    ];
    for (var i = 0; i < 10; i++) {
      final first = services.first.saveDraft(
        project: TgiProject.empty(name: 'old $i'),
      );
      final read = services.last.loadDraft();
      final clear = services.last.clearDraft();
      final latest = services.first.saveDraft(
        project: TgiProject.empty(name: 'new $i'),
      );
      await Future.wait<Object?>([first, clear, latest]);
      expect((await read)!.project.name, 'old $i');
      expect((await services.last.loadDraft())!.project.name, 'new $i');
    }
    final writing = services.first.saveDraft(
      project: TgiProject.empty(name: 'discard'),
    );
    final clearing = services.last.clearDraft();
    await writing;
    expect(await clearing, isTrue);
    expect(await services.first.loadDraft(), isNull);
    expect(root.listSync(), isEmpty);
  });

  test(
    'failed replacement preserves the original and releases the queue',
    () async {
      final service = ProjectIOService();
      await service.saveToFile(TgiProject.empty(name: 'Keep this'), path);
      final original = await File(path).readAsBytes();
      final blockedBackup = await Directory('$path.bak').create();
      await expectLater(
        service.saveToFile(TgiProject.empty(name: 'Must fail'), path),
        throwsA(isA<FileSystemException>()),
      );
      expect(await File(path).readAsBytes(), original);
      expect(
        root.listSync().whereType<Directory>().map((entry) => entry.path),
        [blockedBackup.path],
      );
      await blockedBackup.delete();
      await service.saveToFile(TgiProject.empty(name: 'Retry succeeds'), path);
      expect(
        (await service.readFromFile(path))['projectName'],
        'Retry succeeds',
      );
      expect(root.listSync().map((entry) => entry.path), [path]);
    },
  );

  test('serialization failure does not block later recovery writes', () async {
    final broken = ProjectFileStorage.write(
      path,
      () => throw const FormatException('invalid'),
    );
    final next = ProjectRecoveryService(
      recoveryFilePath: path,
    ).saveDraft(project: TgiProject.empty(name: 'Recovered'));
    await expectLater(broken, throwsA(isA<FormatException>()));
    await next;
    expect(
      (await ProjectRecoveryService(
        recoveryFilePath: path,
      ).loadDraft())!.project.name,
      'Recovered',
    );
  });

  test('an unrelated project is not blocked by a slow save', () async {
    final hold = Completer<String>();
    final first = ProjectFileStorage.write(path, () => hold.future);
    try {
      await ProjectFileStorage.write(
        '$path.other',
        () => 'independent',
      ).timeout(const Duration(seconds: 3));
      expect(await File('$path.other').readAsString(), 'independent');
    } finally {
      hold.complete('finished');
      await first;
    }
  });

  test(
    'recovery loads a backup and cleanup also removes legacy temporary files',
    () async {
      final recovery = ProjectRecoveryService(recoveryFilePath: path);
      await recovery.saveDraft(project: TgiProject.empty(name: 'Backup'));
      await File(path).rename('$path.bak');
      await File('$path.tmp').writeAsString('legacy partial write');
      expect((await recovery.loadDraft())!.project.name, 'Backup');
      expect(await recovery.clearDraft(), isTrue);
      expect(root.listSync(), isEmpty);
    },
  );

  test('malformed recovery remains a non-fatal read error', () async {
    await File(path).writeAsString(jsonEncode({'tgiRecovery': 'invalid'}));
    expect(
      await ProjectRecoveryService(recoveryFilePath: path).loadDraft(),
      isNull,
    );
  });
}
