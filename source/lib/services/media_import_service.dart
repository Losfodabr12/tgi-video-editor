import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../domain/models/media_item.dart';
import 'ffmpeg_service.dart';

const _defaultImageDuration = Duration(seconds: 5);
const _videoExtensions = {'mp4', 'mov', 'mkv', 'avi', 'webm', 'm4v'};
const _audioExtensions = {
  'mp3',
  'wav',
  'aac',
  'm4a',
  'flac',
  'ogg',
  'opus',
  'wma',
};
const _imageExtensions = {'png', 'jpg', 'jpeg'};
const _supportedMediaExtensions = [
  'mp4',
  'mov',
  'mkv',
  'avi',
  'webm',
  'm4v',
  'png',
  'jpg',
  'jpeg',
  'mp3',
  'wav',
  'aac',
  'm4a',
  'flac',
  'ogg',
  'opus',
  'wma',
];

int _nextImportedMediaId = 0;

class MediaImportService {
  const MediaImportService({required this.ffmpegService});

  final FfmpegService ffmpegService;

  Future<MediaItem?> importVideo() async {
    final items = await _pickAndImportFiles(
      allowMultiple: false,
      dialogTitle: 'Importar arquivo de midia',
    );
    return items.isEmpty ? null : items.first;
  }

  Future<List<MediaItem>> importMediaFiles() {
    return _pickAndImportFiles(
      allowMultiple: true,
      dialogTitle: 'Importar arquivos de midia',
    );
  }

  Future<List<MediaItem>> _pickAndImportFiles({
    required bool allowMultiple,
    required String dialogTitle,
  }) async {
    final result = await FilePicker.pickFiles(
      allowMultiple: allowMultiple,
      type: FileType.custom,
      allowedExtensions: _supportedMediaExtensions,
      dialogTitle: dialogTitle,
    );

    if (result == null || result.files.isEmpty) {
      return const [];
    }

    final items = <MediaItem>[];
    for (final file in result.files) {
      final path = file.path;
      if (path == null || path.isEmpty) {
        continue;
      }
      items.add(await importFile(path));
    }

    return items;
  }

  Future<MediaItem> importFile(String path) async {
    final file = File(path);
    final extension = _extension(file.path);
    if (_imageExtensions.contains(extension)) {
      return _imageMediaItem(file);
    }
    if (_videoExtensions.contains(extension)) {
      return _videoMediaItem(file);
    }
    if (_audioExtensions.contains(extension)) {
      return _audioMediaItem(file);
    }

    throw const FfmpegProcessException('Formato de arquivo nao suportado.');
  }

  Future<MediaItem> _videoMediaItem(File file) async {
    final metadata = await ffmpegService.inspectVideo(file);
    final now = DateTime.now();

    return MediaItem(
      id: _mediaId(now),
      filePath: file.path,
      name: _fileName(file.path),
      type: MediaType.video,
      duration: metadata.duration,
      importedAt: now,
      hasAudio: metadata.hasAudio,
      thumbnailPath: metadata.thumbnailPath,
      width: metadata.width,
      height: metadata.height,
    );
  }

  Future<MediaItem> _audioMediaItem(File file) async {
    final duration = await ffmpegService.inspectDuration(file);
    final now = DateTime.now();

    return MediaItem(
      id: _mediaId(now),
      filePath: file.path,
      name: _fileName(file.path),
      type: MediaType.audio,
      duration: duration,
      importedAt: now,
      hasAudio: true,
    );
  }

  MediaItem _imageMediaItem(File file) {
    final now = DateTime.now();
    return MediaItem(
      id: _mediaId(now),
      filePath: file.path,
      name: _fileName(file.path),
      type: MediaType.image,
      duration: _defaultImageDuration,
      importedAt: now,
      hasAudio: false,
      thumbnailPath: file.path,
    );
  }

  String _mediaId(DateTime now) {
    return 'media_${now.microsecondsSinceEpoch}_${++_nextImportedMediaId}';
  }

  String _extension(String path) {
    final name = _fileName(path);
    final dot = name.lastIndexOf('.');
    if (dot == -1 || dot == name.length - 1) {
      return '';
    }
    return name.substring(dot + 1).toLowerCase();
  }

  String _fileName(String path) {
    return path.split(RegExp(r'[\\/]')).last;
  }
}
