import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:tgi_video_editor/core/commands/command_engine.dart';
import 'package:tgi_video_editor/domain/models/project.dart';
import 'package:tgi_video_editor/features/editor/application/editor_controller.dart';
import 'package:tgi_video_editor/mcp/editor_plans.dart';
import 'package:tgi_video_editor/mcp/editor_read_service.dart';
import 'package:tgi_video_editor/mcp/mcp_import_paths.dart';
import 'package:tgi_video_editor/mcp/mcp_media_import.dart';
import 'package:tgi_video_editor/mcp/mcp_tool_router.dart';
import 'package:tgi_video_editor/services/media_import_service.dart';
import 'package:tgi_video_editor/services/project_io_service.dart';
import 'support/render_fixture.dart';

void main() {
  late RenderFixture fixture;
  late EditorController c;
  late EditorReadService reads;
  late EditorPlans plans;
  late McpImportPaths paths;
  late McpToolRouter router;
  late File png;
  setUp(() async {
    fixture = RenderFixture();
    await fixture.open();
    png = await File('${fixture.directory.path}/alpha.png').writeAsBytes(
      image.encodePng(image.Image(width: 32, height: 24, numChannels: 4)),
    );
    c = EditorController(
      initialProject: TgiProject.empty(name: 'Import contracts'),
      mediaImportService: MediaImportService(ffmpegService: fixture.service),
    );
    reads = EditorReadService(c, ffmpeg: fixture.service);
    plans = EditorPlans(c, reads);
    paths = McpImportPaths(directories: [fixture.directory.path]);
    router = McpToolRouter(
      reads,
      plans,
      imports: McpMediaImport(paths, fixture.service),
    );
  });
  tearDown(() async {
    await reads.dispose();
    c.dispose();
    await fixture.close();
  });
  Map<String, dynamic> data(Map<String, Object?> value) =>
      Map<String, dynamic>.from(value['structuredContent'] as Map);
  String snapshot() =>
      jsonEncode(ProjectIOService().serializeProject(c.project));
  Future<Map<String, dynamic>> preview(List<String> files) async => data(
    await router.call('import_media', {
      'paths': files,
      'base_revision': c.projectRevision,
    }),
  );

  test(
    'ffprobe-backed imports preview, require approval, apply once and undo media pool in v14',
    () async {
      final before = snapshot();
      final result = await preview([png.path]);
      expect(result, isNot(contains('error')));
      expect(snapshot(), before);
      final id = result['plan_id'] as String;
      final imported = (result['imported_media'] as List).single as Map;
      expect(imported['type'], 'image');
      expect(imported['duration'], 5);
      expect(imported['media_id'], startsWith('media_ai_'));
      expect(
        data(
          await router.call('apply_plan', {'plan_id': id, 'base_revision': 0}),
        )['error'],
        isNotNull,
      );
      plans.approve(id);
      expect(
        () => plans.apply(id, baseRevision: 0),
        throwsA(isA<CommandError>()),
      );
      final applied = data(
        await router.call('apply_plan', {'plan_id': id, 'base_revision': 0}),
      );
      expect(applied, isNot(contains('error')));
      expect(c.project.mediaPool.single.id, imported['media_id']);
      expect(c.project.mediaPool.single.width, 32);
      expect(c.project.mediaPool.single.height, 24);
      expect(ProjectIOService().serializeProject(c.project)['version'], 14);
      expect(c.undoLabel, startsWith('IA:'));
      c.undo();
      expect(snapshot(), before);
    },
  );

  test(
    'revoked grants, changed files and stale revisions cannot apply a prepared import',
    () async {
      final first = await preview([png.path]);
      final id = first['plan_id'] as String;
      plans.approve(id);
      paths.directories = [];
      expect(
        data(
          await router.call('apply_plan', {'plan_id': id, 'base_revision': 0}),
        )['error'],
        isNotNull,
      );
      expect(c.project.mediaPool, isEmpty);
      paths.directories = [fixture.directory.path];
      final second = await preview([png.path]);
      final secondId = second['plan_id'] as String;
      plans.approve(secondId);
      await png.writeAsString('changed');
      final changed = data(
        await router.call('apply_plan', {
          'plan_id': secondId,
          'base_revision': 0,
        }),
      );
      expect((changed['error'] as Map)['code'], 'media_changed');
      expect(c.project.mediaPool, isEmpty);
      final stale = data(
        await router.call('import_media', {
          'paths': [png.path],
          'base_revision': 99,
        }),
      );
      expect((stale['error'] as Map)['code'], 'revision_conflict');
    },
  );

  test(
    'unsupported, disguised, oversized and mixed invalid batches leave no imported media',
    () async {
      final executable = await File(
        '${fixture.directory.path}/payload.exe',
      ).writeAsString('not executed');
      final disguised = await File(
        '${fixture.directory.path}/payload.mp4',
      ).writeAsString('#EXTM3U\nhttps://example.invalid/private');
      final oversized = await File(
        '${fixture.directory.path}/large.png',
      ).open(mode: FileMode.write);
      await oversized.truncate(McpMediaImport.maxFileBytes + 1);
      await oversized.close();
      for (final batch in [
        [executable.path],
        [disguised.path],
        ['${fixture.directory.path}/large.png'],
        [png.path, disguised.path],
      ]) {
        expect((await preview(batch))['error'], isNotNull);
        expect(c.project.mediaPool, isEmpty);
        expect(c.canUndo, isFalse);
      }
      final spoof = data(
        await router.call('preview_plan', {
          'base_revision': 0,
          'commands': [
            {
              'tool': 'import_media',
              'arguments': {
                'paths': [png.path],
                'media': [],
              },
            },
          ],
        }),
      );
      expect(spoof['error'], isNotNull);
      expect(
        () => const CommandEngine().apply(
          c.project,
          EditorCommand('import_media', {
            'paths': [png.path],
          }),
        ),
        throwsA(isA<CommandError>()),
      );
    },
  );

  test(
    'replaced symlinks cannot apply and disguised scripts are never executed',
    () async {
      final result = await preview([png.path]);
      final id = result['plan_id'] as String;
      plans.approve(id);
      final other = await File(
        '${fixture.directory.path}/other.png',
      ).writeAsBytes(await png.readAsBytes());
      await png.delete();
      await Link(png.path).create(other.path);
      final failed = data(
        await router.call('apply_plan', {'plan_id': id, 'base_revision': 0}),
      );
      expect((failed['error'] as Map)['code'], 'path_not_allowed');
      expect(c.project.mediaPool, isEmpty);
      final marker = '${fixture.directory.path}/should-not-exist.txt';
      final script = await File(
        '${fixture.directory.path}/script.png',
      ).writeAsString('@echo off\r\necho executed > "$marker"\r\n');
      expect((await preview([script.path]))['error'], isNotNull);
      expect(File(marker).existsSync(), isFalse);
    },
  );

  test('all eight supported formats are checked by real ffprobe', () async {
    final jpg = await File(
      '${fixture.directory.path}/photo.jpg',
    ).writeAsBytes(image.encodeJpg(image.Image(width: 24, height: 16)));
    final webp = '${fixture.directory.path}/image.webp';
    await fixture.run([
      '-y',
      '-v',
      'error',
      '-i',
      png.path,
      '-frames:v',
      '1',
      webp,
    ]);
    final video = await fixture.color('blue', seconds: 1);
    final mov = '${fixture.directory.path}/clip.mov',
        webm = '${fixture.directory.path}/clip.webm';
    await fixture.run([
      '-y',
      '-v',
      'error',
      '-i',
      video.filePath,
      '-c',
      'copy',
      mov,
    ]);
    await fixture.run([
      '-y',
      '-v',
      'error',
      '-i',
      video.filePath,
      '-c:v',
      'libvpx-vp9',
      webm,
    ]);
    final audio = <String>[];
    for (final extension in ['mp3', 'wav']) {
      final file = '${fixture.directory.path}/sound.$extension';
      await fixture.run([
        '-y',
        '-v',
        'error',
        '-f',
        'lavfi',
        '-i',
        'sine=frequency=440:duration=1',
        file,
      ]);
      audio.add(file);
    }
    final result = await preview([
      png.path,
      jpg.path,
      webp,
      video.filePath,
      mov,
      webm,
      ...audio,
    ]);
    expect(result, isNot(contains('error')));
    expect((result['imported_media'] as List).length, 8);
    expect(c.project.mediaPool, isEmpty);
  });
}
