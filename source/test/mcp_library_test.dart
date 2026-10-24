import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:tgi_video_editor/core/commands/command_engine.dart';
import 'package:tgi_video_editor/domain/models/track.dart';
import 'package:tgi_video_editor/features/editor/application/editor_controller.dart';
import 'package:tgi_video_editor/mcp/editor_plans.dart';
import 'package:tgi_video_editor/mcp/editor_mcp_server.dart';
import 'package:tgi_video_editor/mcp/editor_read_service.dart';
import 'package:tgi_video_editor/mcp/mcp_import_paths.dart';
import 'package:tgi_video_editor/mcp/mcp_library.dart';
import 'package:tgi_video_editor/mcp/mcp_media_import.dart';
import 'package:tgi_video_editor/mcp/mcp_tool_router.dart';
import 'package:tgi_video_editor/services/editor_library_presets.dart';
import 'package:tgi_video_editor/services/media_import_service.dart';
import 'package:tgi_video_editor/services/project_io_service.dart';
import 'support/render_fixture.dart';
import 'support/silence_project.dart';
import 'support/mcp_test_client.dart';

void main() {
  late RenderFixture fixture;
  late EditorController controller;
  late EditorReadService reads;
  late EditorPlans plans;
  late McpLibrary library;
  late McpToolRouter router;
  late EditorMcpServer server;
  late McpTestClient client;
  HttpOverrides? originalHttp;
  late File tone;
  var downloads = 0;
  const audio = McpLibraryAsset(
    id: 'fixture_audio',
    name: 'Music fixture',
    kind: 'audio',
    category: 'Music',
    library: 'Fixture',
    fileName: 'tone.wav',
    license: 'CC0 1.0',
    sourceUrl: 'https://example.invalid/source',
  );
  const png = McpLibraryAsset(
    id: 'fixture_png',
    name: 'Alpha fixture',
    kind: 'image',
    category: 'Images',
    library: 'Fixture',
    fileName: 'alpha.png',
  );
  const m4a = McpLibraryAsset(
    id: 'fixture_m4a',
    name: 'M4A fixture',
    kind: 'audio',
    category: 'Music',
    library: 'Fixture',
    fileName: 'tone.m4a',
  );
  setUp(() async {
    originalHttp = HttpOverrides.current;
    HttpOverrides.global = null;
    fixture = RenderFixture();
    await fixture.open();
    tone = File('${fixture.directory.path}/source.wav');
    final result = await fixture.service.runCommand([
      '-v',
      'error',
      '-y',
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=440:duration=4',
      '-c:a',
      'pcm_s16le',
      tone.path,
    ]);
    expect(result.exitCode, 0);
    downloads = 0;
    controller = EditorController(
      initialProject: silenceProject(),
      mediaImportService: MediaImportService(ffmpegService: fixture.service),
    );
    reads = EditorReadService(controller, ffmpeg: fixture.service);
    plans = EditorPlans(controller, reads);
    library = McpLibrary(
      fixture.service,
      catalog: [audio, png, m4a, ...editorMcpLibrary.where((a) => !a.isMedia)],
      cacheDirectoryOverride: fixture.directory.path,
      downloadOverride: (asset, file) async {
        downloads++;
        await tone.copy(file.path);
      },
    );
    router = McpToolRouter(
      reads,
      plans,
      library: library,
      imports: McpMediaImport(
        McpImportPaths(directories: [fixture.directory.path]),
        fixture.service,
      ),
    );
    server = EditorMcpServer(router, token: randomMcpToken(), port: 0);
    await server.start();
    client = McpTestClient(server.boundPort, server.token);
    await client.initialize();
  });
  tearDown(() async {
    client.close();
    await server.stop();
    await reads.dispose();
    controller.dispose();
    await fixture.close();
    HttpOverrides.global = originalHttp;
  });
  Map data(Map r) => r['structuredContent'] as Map;
  String snapshot() =>
      jsonEncode(ProjectIOService().serializeProject(controller.project));
  Future<Map> call(String name, Map<String, Object?> args) async =>
      data(await client.call(name, args));
  Future<Map> apply(Map preview) async {
    expect(preview['error'], isNull, reason: preview.toString());
    plans.approve(preview['plan_id'] as String);
    return call('apply_plan', {
      'plan_id': preview['plan_id'],
      'base_revision': controller.projectRevision,
    });
  }

  test(
    'library listing shares UI catalogs, filters and paginates without downloading',
    () async {
      expect(
        editorMcpLibrary.map((a) => a.id).toSet().length,
        editorMcpLibrary.length,
      );
      expect(
        editorMcpLibrary.where((a) => a.kind == 'title').length,
        editorTitlePresets.length,
      );
      expect(
        editorMcpLibrary.where((a) => a.kind == 'transition').length,
        editorTransitionPresets.length,
      );
      final page = await call('list_library', {
        'kind': 'audio',
        'query': 'fixture',
        'limit': 1,
      });
      expect(page['total'], 2);
      expect(page['next_offset'], 1);
      expect((page['items'] as List).single['cached'], false);
      expect((page['items'] as List).single['license'], 'CC0 1.0');
      expect(downloads, 0);
      final capabilities = await call('get_project', {});
      expect(capabilities['mcp']['tools'], contains('add_library_asset'));
      expect(capabilities['mcp']['tool_count'], 42);
    },
  );

  test(
    'explicit library download imports and inserts music in a new audio lane with one undo',
    () async {
      final before = snapshot();
      final required = await call('add_library_asset', {
        'asset_id': audio.id,
        'at': 1,
        'base_revision': 0,
      });
      expect(required['error']['code'], 'library_download_required');
      expect(downloads, 0);
      final preview = await call('add_library_asset', {
        'asset_id': audio.id,
        'at': 1,
        'in': .5,
        'duration': 2,
        'volume': .2,
        'fade_in_ms': 100,
        'fade_out_ms': 100,
        'download': true,
        'base_revision': 0,
      });
      expect(snapshot(), before);
      expect(downloads, 1);
      final applied = await apply(preview);
      expect(applied['error'], isNull, reason: applied.toString());
      expect(controller.projectRevision, 1);
      expect(
        controller.project.tracks.where((t) => t.type == TrackType.audio),
        hasLength(2),
      );
      final inserted = controller.project.tracks
          .expand((t) => t.clips)
          .singleWhere(
            (c) =>
                c.mediaItemId ==
                (applied['imported_media'] as List).single['media_id'],
          );
      expect(inserted.timelineStart, const Duration(seconds: 1));
      expect(inserted.sourceStart, const Duration(milliseconds: 500));
      expect(inserted.duration, const Duration(seconds: 2));
      expect(inserted.volume, .2);
      expect(inserted.fadeIn, const Duration(milliseconds: 100));
      final serialized = ProjectIOService().serializeProject(
        controller.project,
      );
      expect(serialized['version'], 14);
      expect(
        jsonEncode(
          ProjectIOService().serializeProject(
            ProjectIOService().deserializeProject(serialized).project,
          ),
        ),
        jsonEncode(serialized),
      );
      controller.undo();
      expect(snapshot(), before);
    },
  );

  test(
    'cached image overlays preserve the PNG and place a visual above the base',
    () async {
      final bytes = image.encodePng(
        image.Image(width: 16, height: 16, numChannels: 4),
      );
      final file = await File(
        '${fixture.directory.path}/${png.cacheFileName}',
      ).writeAsBytes(bytes);
      final preview = await call('add_library_asset', {
        'asset_id': png.id,
        'at': 2,
        'duration': 3,
        'overlay': true,
        'position': {'x': 1, 'y': 1},
        'scale': .18,
        'fade_in_ms': 200,
        'fade_out_ms': 200,
        'base_revision': 0,
      });
      final result = await apply(preview);
      expect(result['error'], isNull);
      expect(controller.project.tracks.first.type, TrackType.image);
      expect(
        controller.project.tracks.first.clips.single.overlayScale,
        closeTo(.72, .0001),
      );
      expect(await file.readAsBytes(), bytes);
      expect(downloads, 0);
    },
  );

  test(
    'native titles and transitions need no network or media import and share one undo',
    () async {
      final before = snapshot();
      final preview = await call('preview_plan', {
        'base_revision': 0,
        'label': 'IA: biblioteca',
        'commands': [
          {
            'tool': 'add_library_asset',
            'arguments': {
              'asset_id': 'title_simple',
              'at': 0,
              'duration': 2,
              'text': 'Meu título',
            },
          },
          {
            'tool': 'add_library_asset',
            'arguments': {
              'asset_id': 'preset_dissolve',
              'at': 5,
              'duration': .3,
            },
          },
        ],
      });
      expect((await apply(preview))['error'], isNull);
      expect(
        controller.project.tracks
            .expand((t) => t.clips)
            .where((c) => c.textContent == 'Meu título'),
        hasLength(1),
      );
      expect(
        controller.project.transitions.single.duration,
        const Duration(milliseconds: 300),
      );
      expect(controller.project.mediaPool, hasLength(1));
      expect(downloads, 0);
      controller.undo();
      expect(snapshot(), before);
    },
  );

  test(
    'stale/changed library files, cache symlinks, arbitrary URLs and forged metadata cannot apply',
    () async {
      final before = snapshot();
      final preview = await call('add_library_asset', {
        'asset_id': audio.id,
        'at': 1,
        'download': true,
        'base_revision': 0,
      });
      await File(
        '${fixture.directory.path}/${audio.cacheFileName}',
      ).writeAsBytes([1, 2, 3]);
      expect((await apply(preview))['error']['code'], 'media_changed');
      expect(snapshot(), before);
      await Link(
        '${fixture.directory.path}/${png.cacheFileName}',
      ).create(tone.path);
      final linked = await call('add_library_asset', {
        'asset_id': png.id,
        'at': 0,
        'download': true,
        'base_revision': 0,
      });
      expect(linked['error']['code'], 'path_not_allowed');
      final url = await call('add_library_asset', {
        'asset_id': audio.id,
        'at': 0,
        'url': 'https://example.invalid/file.wav',
        'base_revision': 0,
      });
      expect(url['error']['code'], 'invalid_argument');
      final unknown = await call('add_library_asset', {
        'asset_id': '../outside',
        'at': 0,
        'base_revision': 0,
      });
      expect(unknown['error']['code'], 'library_asset_not_found');
      expect(
        () => const CommandEngine().apply(
          controller.project,
          EditorCommand('add_library_asset', {'asset_id': audio.id, 'at': 0}),
        ),
        throwsA(isA<CommandError>()),
      );
      expect(snapshot(), before);
    },
  );

  test(
    'catalog M4A is probed as audio while arbitrary PC imports retain their eight-format limit',
    () async {
      final file = File('${fixture.directory.path}/${m4a.cacheFileName}');
      expect(
        (await fixture.service.runCommand([
          '-v',
          'error',
          '-y',
          '-i',
          tone.path,
          '-c:a',
          'aac',
          file.path,
        ])).exitCode,
        0,
      );
      final pc = await call('import_media', {
        'paths': [file.path],
        'base_revision': 0,
      });
      expect(pc['error']['code'], 'unsupported_media_type');
      final preview = await call('add_library_asset', {
        'asset_id': m4a.id,
        'at': 0,
        'duration': 2,
        'base_revision': 0,
      });
      expect((await apply(preview))['error'], isNull);
      expect(controller.project.mediaPool.last.type.name, 'audio');
    },
  );
}
