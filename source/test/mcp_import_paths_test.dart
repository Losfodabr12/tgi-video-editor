import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/core/commands/editor_command.dart';
import 'package:tgi_video_editor/mcp/mcp_import_paths.dart';
import 'package:tgi_video_editor/mcp/mcp_settings.dart';

void main() {
  late Directory temp, assets;
  late File inside, outside;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mcp_import_grants_');
    assets = await Directory('${temp.path}/assets').create();
    inside = await File('${assets.path}/image.png').writeAsString('fixture');
    final sibling = await Directory('${temp.path}/assets-private').create();
    outside = await File('${sibling.path}/secret.png').writeAsString('private');
  });
  tearDown(() => temp.delete(recursive: true));

  test(
    'imports are denied by default; grants persist separately from v14',
    () async {
      expect(const McpSettings().importDirectories, isEmpty);
      final legacy = McpSettings.fromJson({
        'port': 47321,
        'require_approval': true,
        'export_directory': null,
      });
      expect(legacy.importDirectories, isEmpty);
      await expectLater(
        McpImportPaths().file(inside.path),
        throwsA(isA<CommandError>()),
      );
      final store = McpSettingsStore(path: '${temp.path}/settings.json');
      await store.save(McpSettings(importDirectories: [assets.path]));
      expect((await store.load()).importDirectories, [assets.path]);
      final policy = McpImportPaths(
        directories: (await store.load()).importDirectories,
      );
      expect(
        await policy.file(inside.path),
        await inside.resolveSymbolicLinks(),
      );
      policy.directories = [];
      await expectLater(policy.file(inside.path), throwsA(isA<CommandError>()));
    },
  );

  test(
    'outside paths, sibling prefixes, traversal, network and ADS are rejected',
    () async {
      final policy = McpImportPaths(directories: [assets.path]);
      for (final path in [
        outside.path,
        '${assets.path}/../assets/image.png',
        '${assets.path}/./image.png',
        '../image.png',
        r'\\server\share\image.png',
        'https://example.invalid/image.png',
        '${inside.path}\u0000',
        if (Platform.isWindows) '${inside.path}:secret',
      ]) {
        await expectLater(
          policy.file(path),
          throwsA(isA<CommandError>()),
          reason: path,
        );
      }
    },
  );

  test(
    'symlink files, ancestor directories and granted roots are rejected',
    () async {
      final fileLink = Link('${assets.path}/linked.png');
      await fileLink.create(outside.path);
      final directoryLink = Link('${assets.path}/linked-directory');
      await directoryLink.create(outside.parent.path);
      final rootLink = Link('${temp.path}/linked-root');
      await rootLink.create(assets.path);
      final policy = McpImportPaths(directories: [assets.path]);
      for (final path in [fileLink.path, '${directoryLink.path}/secret.png']) {
        await expectLater(policy.file(path), throwsA(isA<CommandError>()));
      }
      await expectLater(
        McpImportPaths(
          directories: [rootLink.path],
        ).file('${rootLink.path}/image.png'),
        throwsA(isA<CommandError>()),
      );
    },
  );
}
