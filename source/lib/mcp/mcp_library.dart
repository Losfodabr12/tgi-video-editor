import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../core/commands/editor_command.dart';
import '../core/commands/prepared_library_insert.dart';
import '../domain/models/media_item.dart';
import '../services/app_component_paths.dart';
import '../services/editor_library_presets.dart';
import '../services/ffmpeg_service.dart';
import '../services/sound_effects_service.dart';
import '../services/visual_media_service.dart';
import 'mcp_import_paths.dart';
import 'mcp_media_import.dart';

class McpLibraryAsset {
  const McpLibraryAsset({
    required this.id,
    required this.name,
    required this.kind,
    required this.category,
    required this.library,
    this.fileName,
    this.downloadUrl,
    this.license = 'Incluído no editor',
    this.sourceUrl,
    this.duration,
    this.nativeTool,
    this.defaults = const {},
  });
  final String id, name, kind, category, library, license;
  final String? fileName, downloadUrl, sourceUrl, nativeTool;
  final double? duration;
  final Map<String, Object?> defaults;
  bool get isMedia => nativeTool == null;
  String get cacheFileName =>
      '${id.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_')}.${fileName!.split('.').last.toLowerCase()}';
  Map<String, Object?> get credit => {
    'asset_id': id,
    'name': name,
    'kind': kind,
    'license': license,
    if (sourceUrl != null) 'source_url': sourceUrl,
  };
}

final editorMcpLibrary = List<McpLibraryAsset>.unmodifiable([
  for (final a in PublicSoundEffectsService.catalog)
    McpLibraryAsset(
      id: a.id,
      name: a.name,
      kind: 'audio',
      category: a.category,
      library: a.library,
      fileName: a.fileName,
      downloadUrl: a.downloadUrl,
      license: a.license,
      sourceUrl: a.sourceUrl,
      duration: a.duration.inMicroseconds / 1e6,
    ),
  for (final a in PublicVisualMediaService.catalog)
    McpLibraryAsset(
      id: a.id,
      name: a.name,
      kind: a.isImage ? 'image' : 'video',
      category: a.category,
      library: a.library,
      fileName: a.fileName,
      downloadUrl: a.downloadUrl,
      license: a.license,
      sourceUrl: a.sourceUrl,
    ),
  for (final a in editorTitlePresets)
    McpLibraryAsset(
      id: a.id,
      name: a.name,
      kind: 'title',
      category: 'Títulos',
      library: 'Editor',
      duration: 5,
      nativeTool: 'add_text',
      defaults: {
        'text': a.text,
        'font_family': a.fontFamily,
        'font_size': a.fontSize,
        'animation': a.animation.name,
        'is_caption': a.caption,
      },
    ),
  for (final a in editorTransitionPresets)
    McpLibraryAsset(
      id: a.id,
      name: a.name,
      kind: 'transition',
      category: 'Transições',
      library: 'Editor',
      duration: a.duration.inMicroseconds / 1e6,
      nativeTool: 'add_transition',
      defaults: {
        'preset': a.preset!.name,
        'name': a.name,
        'direction': a.direction.name,
        'color': a.color,
        'intensity': a.intensity,
      },
    ),
]);

class McpLibrary {
  McpLibrary(
    this.ffmpeg, {
    List<McpLibraryAsset>? catalog,
    this.cacheDirectoryOverride,
    this.downloadOverride,
  }) : catalog = List.unmodifiable(catalog ?? editorMcpLibrary);
  final FfmpegService ffmpeg;
  final List<McpLibraryAsset> catalog;
  final String? cacheDirectoryOverride;
  // Test host injection; never accepted over MCP.
  final Future<void> Function(McpLibraryAsset asset, File destination)?
  downloadOverride;
  static const maxDownloadBytes = 20 * 1024 * 1024;

  String _root(McpLibraryAsset asset) =>
      cacheDirectoryOverride ??
      joinPlatformPath([
        tgiAppLocalDataRoot(),
        asset.kind == 'audio' ? 'sound_effects_cache' : 'visual_media_cache',
      ]);
  String _path(McpLibraryAsset asset) =>
      joinPlatformPath([_root(asset), asset.cacheFileName]);

  Future<bool> _cached(McpLibraryAsset asset) async {
    if (!asset.isMedia) return true;
    if (await FileSystemEntity.type(_path(asset), followLinks: false) !=
        FileSystemEntityType.file) {
      return false;
    }
    try {
      await McpImportPaths(directories: [_root(asset)]).file(_path(asset));
      return await File(_path(asset)).length() > 0;
    } on CommandError {
      return false;
    }
  }

  Future<Map<String, Object?>> list({
    String query = '',
    String? kind,
    int offset = 0,
    int limit = 50,
  }) async {
    final q = query.trim().toLowerCase();
    final matching = catalog
        .where(
          (a) =>
              (kind == null || a.kind == kind) &&
              '${a.name} ${a.category} ${a.library}'.toLowerCase().contains(q),
        )
        .toList();
    final items = <Map<String, Object?>>[];
    for (final a in matching.skip(offset).take(limit)) {
      final cached = await _cached(a);
      items.add({
        ...a.credit,
        'category': a.category,
        'library': a.library,
        if (a.duration != null) 'duration': a.duration,
        'cached': cached,
        'download_required': a.isMedia && !cached,
      });
    }
    return {
      'total': matching.length,
      'items': items,
      'next_offset': offset + items.length < matching.length
          ? offset + items.length
          : null,
      'insertion_tool': 'add_library_asset',
      'download_hint':
          'download=true baixa somente o ID fixo do catálogo; não aceita URL externa.',
    };
  }

  Future<PreparedLibraryInsert> prepare(Map<String, Object?> args) async {
    final id = args['asset_id'] as String;
    final asset = catalog.where((a) => a.id == id).firstOrNull;
    if (asset == null) {
      throw const CommandError(
        'library_asset_not_found',
        'Use asset_id retornado por list_library.',
      );
    }
    if (!asset.isMedia) {
      final allowed = {
        'asset_id',
        'at',
        'duration',
        if (asset.kind == 'title') 'text',
      };
      if (args.keys.any((k) => !allowed.contains(k))) {
        throw const CommandError(
          'invalid_library_arguments',
          'Este preset aceita at, duration e text para títulos.',
        );
      }
      final native = EditorCommand(asset.nativeTool!, {
        ...asset.defaults,
        if (asset.kind == 'title')
          'timeline_start': args['at']
        else
          'at': args['at'],
        'duration': args['duration'] ?? asset.duration,
        if (args.containsKey('text')) 'text': args['text'],
      });
      return PreparedLibraryInsert(args, preset: native, credit: asset.credit);
    }
    final directory = Directory(_root(asset));
    var ancestor = directory;
    while (!await ancestor.exists()) {
      ancestor = ancestor.parent;
    }
    await McpImportPaths.directory(ancestor.path);
    await directory.create(recursive: true);
    await McpImportPaths.directory(directory.path);
    final policy = McpImportPaths(directories: [directory.path]);
    final file = File(_path(asset));
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.link ||
        type == FileSystemEntityType.directory) {
      throw const CommandError(
        'path_not_allowed',
        'Cache da biblioteca não aceita links ou diretórios como arquivo.',
      );
    }
    if (!await _cached(asset)) {
      if (args['download'] != true) {
        throw const CommandError(
          'library_download_required',
          'Item não está no cache. Repita com download=true para baixar este ID do catálogo.',
        );
      }
      final temp = File(
        joinPlatformPath([
          directory.path,
          '.download-${Random.secure().nextInt(1 << 32)}.${asset.fileName!.split('.').last}',
        ]),
      );
      try {
        if (downloadOverride != null) {
          await downloadOverride!(asset, temp);
        } else {
          await _download(asset, temp);
        }
        final staged = await McpMediaImport(
          policy,
          ffmpeg,
          extraAudioFormats: const {'m4a': 'mov'},
        ).prepare([temp.path]);
        // The partial file must keep the format suffix for forced demuxing.
        await staged.verify();
        await policy.folder(directory.path);
        await temp.rename(file.path);
      } finally {
        if (await temp.exists()) await temp.delete();
      }
    }
    final imported = await McpMediaImport(
      policy,
      ffmpeg,
      extraAudioFormats: const {'m4a': 'mov'},
    ).prepare([file.path]);
    final expected = switch (asset.kind) {
      'audio' => MediaType.audio,
      'image' => MediaType.image,
      _ => MediaType.video,
    };
    if (imported.media.single.type != expected) {
      throw const CommandError(
        'invalid_media',
        'O conteúdo não corresponde ao tipo do item da biblioteca.',
      );
    }
    return PreparedLibraryInsert(
      args,
      imported: imported,
      credit: asset.credit,
    );
  }

  Future<void> _download(McpLibraryAsset asset, File temp) async {
    final uri = Uri.parse(asset.downloadUrl!);
    if (uri.scheme != 'https' ||
        uri.host != 'raw.githubusercontent.com' ||
        uri.userInfo.isNotEmpty) {
      throw const CommandError(
        'library_source_not_allowed',
        'A biblioteca só baixa dos repositórios fixos do catálogo.',
      );
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    var timedOut = false;
    final watchdog = Timer(const Duration(seconds: 30), () {
      timedOut = true;
      client.close(force: true);
    });
    IOSink? sink;
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      final response = await request.close();
      if (response.statusCode != 200) {
        throw CommandError(
          'library_download_failed',
          'Download da biblioteca retornou HTTP ${response.statusCode}.',
        );
      }
      if (response.contentLength > maxDownloadBytes) {
        throw const CommandError('library_size_limit', 'Item excede 20 MiB.');
      }
      sink = temp.openWrite();
      var bytes = 0;
      await for (final chunk in response) {
        bytes += chunk.length;
        if (bytes > maxDownloadBytes) {
          throw const CommandError('library_size_limit', 'Item excede 20 MiB.');
        }
        sink.add(chunk);
      }
    } catch (e) {
      if (e is CommandError) rethrow;
      throw CommandError(
        timedOut ? 'library_download_timeout' : 'library_download_failed',
        timedOut
            ? 'Download excedeu 30 s.'
            : 'Falha ao baixar item da biblioteca.',
      );
    } finally {
      watchdog.cancel();
      client.close(force: true);
      await sink?.close();
    }
  }
}
