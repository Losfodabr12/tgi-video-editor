import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../core/commands/editor_command.dart';
import '../core/commands/prepared_media_import.dart';
import '../domain/models/media_item.dart';
import '../services/ffmpeg_service.dart';
import 'mcp_import_paths.dart';

class McpMediaImport {
  McpMediaImport(this.paths, this.ffmpeg, {this.extraAudioFormats = const {}});
  final McpImportPaths paths;
  final FfmpegService ffmpeg;
  final Map<String, String> extraAudioFormats;
  static const maxFileBytes = 512 * 1024 * 1024;
  static const maxBatchBytes = 2 * 1024 * 1024 * 1024;
  static const formats = {
    'png': 'png_pipe',
    'jpg': 'jpeg_pipe',
    'webp': 'webp_pipe',
    'mp4': 'mov',
    'mov': 'mov',
    'webm': 'matroska',
    'mp3': 'mp3',
    'wav': 'wav',
  };

  Future<Map<String, Object?>> browse({
    String? directory,
    int offset = 0,
    int limit = 50,
  }) async {
    if (directory == null) {
      return {
        'roots': List<String>.of(paths.directories),
        'entries': <Object>[],
        'total': 0,
        'next_offset': null,
      };
    }
    final root = await paths.folder(directory);
    final entries = <Map<String, Object?>>[];
    var visited = 0;
    await for (final entry in Directory(root).list(followLinks: false)) {
      if (++visited > 10000) {
        throw const CommandError(
          'browse_limit',
          'Pasta muito grande; escolha uma subpasta.',
        );
      }
      if (entry is Link) continue;
      final name = entry.path.split(RegExp(r'[\\/]')).last;
      if (entry is Directory) {
        entries.add({
          'name': name,
          'path': await paths.folder(entry.path),
          'type': 'directory',
        });
      } else if (entry is File) {
        final extension = name.split('.').last.toLowerCase();
        if (!formats.containsKey(extension)) continue;
        final file = await paths.file(entry.path);
        final size = (await File(file).stat()).size;
        entries.add({
          'name': name,
          'path': file,
          'type': ['png', 'jpg', 'webp'].contains(extension)
              ? 'image'
              : ['mp3', 'wav'].contains(extension)
              ? 'audio'
              : 'video',
          'size_bytes': size,
          'importable': size > 0 && size <= maxFileBytes,
        });
      }
    }
    await paths.folder(directory);
    entries.sort((a, b) {
      final folders = (a['type'] == 'directory' ? 0 : 1).compareTo(
        b['type'] == 'directory' ? 0 : 1,
      );
      return folders != 0
          ? folders
          : (a['name'] as String).toLowerCase().compareTo(
              (b['name'] as String).toLowerCase(),
            );
    });
    final page = entries.skip(offset).take(limit).toList();
    return {
      'roots': List<String>.of(paths.directories),
      'directory': root,
      'entries': page,
      'total': entries.length,
      'next_offset': offset + page.length < entries.length
          ? offset + page.length
          : null,
    };
  }

  Future<PreparedMediaImport> prepare(List<String> requested) async {
    if (requested.isEmpty || requested.length > 32) {
      throw const CommandError('import_limit', 'Use de 1 a 32 arquivos.');
    }
    final files = <String, (String, FileStat)>{};
    var bytes = 0;
    for (final requestedPath in requested) {
      final path = await paths.file(requestedPath);
      final extension = path
          .split(RegExp(r'[\\/]'))
          .last
          .split('.')
          .last
          .toLowerCase();
      if (!formats.containsKey(extension) &&
          !extraAudioFormats.containsKey(extension)) {
        throw const CommandError(
          'unsupported_media_type',
          'Use png, jpg, webp, mp4, mov, webm, mp3 ou wav.',
        );
      }
      final stat = await File(path).stat();
      if (stat.size <= 0 || stat.size > maxFileBytes) {
        throw const CommandError(
          'media_size_limit',
          'Arquivo vazio ou maior que 512 MiB.',
        );
      }
      if (files.containsKey(path)) continue;
      files[path] = (extension, stat);
      bytes += stat.size;
      if (bytes > maxBatchBytes) {
        throw const CommandError('import_limit', 'O lote excede 2 GiB.');
      }
    }
    final media = <MediaItem>[];
    final hashes = <String, String>{};
    for (final entry in files.entries) {
      final path = entry.key,
          extension = entry.value.$1,
          before = entry.value.$2;
      await paths.file(path);
      final metadata = await _probe(
        path,
        formats[extension] ?? extraAudioFormats[extension]!,
      );
      final streams = (metadata['streams'] as List? ?? const []).cast<Map>();
      final image = ['png', 'jpg', 'webp'].contains(extension);
      final audio =
          ['mp3', 'wav'].contains(extension) ||
          extraAudioFormats.containsKey(extension);
      final expected = audio ? 'audio' : 'video';
      final stream = streams
          .where((s) => s['codec_type'] == expected)
          .firstOrNull;
      final width = (stream?['width'] as num?)?.toInt();
      final height = (stream?['height'] as num?)?.toInt();
      if (stream == null ||
          streams.length > 64 ||
          (!audio &&
              (width == null ||
                  height == null ||
                  width <= 0 ||
                  height <= 0 ||
                  width > 16384 ||
                  height > 16384 ||
                  width * height > 67108864)) ||
          (image &&
              stream['codec_name'] !=
                  {'png': 'png', 'jpg': 'mjpeg', 'webp': 'webp'}[extension])) {
        throw const CommandError(
          'invalid_media',
          'Tipo ou dimensões incompatíveis com a extensão.',
        );
      }
      final format = metadata['format'] as Map? ?? const {};
      final duration = image
          ? 5.0
          : double.tryParse('${format['duration'] ?? stream['duration']}');
      if (duration == null ||
          !duration.isFinite ||
          duration <= 0 ||
          duration > 2592000) {
        throw const CommandError('invalid_media', 'Duração de mídia inválida.');
      }
      final hash = await _hash(path);
      await paths.file(path);
      if (!_same(before, await File(path).stat())) {
        throw const CommandError(
          'media_changed',
          'O arquivo mudou durante a validação.',
        );
      }
      hashes[path] = hash;
      final id = sha256
          .convert(utf8.encode('$path\n$hash'))
          .toString()
          .substring(0, 24);
      media.add(
        MediaItem(
          id: 'media_ai_$id',
          filePath: path,
          name: path.split(RegExp(r'[\\/]')).last,
          type: image
              ? MediaType.image
              : audio
              ? MediaType.audio
              : MediaType.video,
          duration: Duration(microseconds: (duration * 1e6).round()),
          importedAt: DateTime.now(),
          hasAudio: streams.any((s) => s['codec_type'] == 'audio'),
          width: width,
          height: height,
          thumbnailPath: image ? path : null,
        ),
      );
    }
    return PreparedMediaImport(
      files.keys.toList(),
      media,
      verify: () async {
        for (final entry in files.entries) {
          final path = await paths.file(entry.key);
          if (!_same(entry.value.$2, await File(path).stat()) ||
              await _hash(path) != hashes[path]) {
            throw const CommandError(
              'media_changed',
              'O arquivo mudou após a prévia. Gere outro plano.',
            );
          }
          await paths.file(path);
        }
      },
    );
  }

  static bool _same(FileStat a, FileStat b) =>
      a.size == b.size &&
      a.modified == b.modified &&
      a.changed == b.changed &&
      a.type == b.type;
  static Future<String> _hash(String path) async =>
      (await sha256.bind(File(path).openRead()).first).toString();

  Future<Map<String, dynamic>> _probe(String path, String format) async {
    final process = await ffmpeg.startCommand([
      '-v',
      'error',
      '-protocol_whitelist',
      'file',
      '-f',
      format,
      '-probesize',
      '8388608',
      '-analyzeduration',
      '10000000',
      '-show_entries',
      'format=duration:stream=codec_type,codec_name,width,height,duration',
      '-of',
      'json',
      '-i',
      path,
    ], useFfprobe: true);
    Future<List<int>> bounded(Stream<List<int>> stream, int limit) async {
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in stream) {
        if (bytes.length + chunk.length > limit) {
          await process.cancel();
          throw const CommandError(
            'invalid_media',
            'Metadados excedem o limite.',
          );
        }
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    }

    try {
      final values = await Future.wait<Object>([
        bounded(process.stdout, 65536),
        bounded(process.stderr, 32768),
        process.exitCode,
      ], eagerError: true).timeout(const Duration(seconds: 15));
      if (values[2] != 0) {
        throw const CommandError(
          'invalid_media',
          'ffprobe rejeitou o arquivo.',
        );
      }
      return jsonDecode(utf8.decode(values[0] as List<int>))
          as Map<String, dynamic>;
    } on TimeoutException {
      await process.cancel();
      throw const CommandError('probe_timeout', 'ffprobe excedeu 15 segundos.');
    } on CommandError {
      rethrow;
    } catch (_) {
      await process.cancel();
      throw const CommandError(
        'invalid_media',
        'Metadados de mídia inválidos.',
      );
    }
  }
}
