import 'dart:async';
import 'dart:io';

import 'github_visual_media_catalog.dart';

class PublicVisualMediaItem {
  const PublicVisualMediaItem({
    required this.id,
    required this.name,
    required this.fileName,
    required this.category,
    required this.downloadUrl,
    required this.library,
    required this.type,
    required this.license,
    required this.sourceName,
    required this.sourceUrl,
  });

  final String id;
  final String name;
  final String fileName;
  final String category;
  final String downloadUrl;
  final String library;
  final String type;
  final String license;
  final String sourceName;
  final String sourceUrl;

  bool get isImage => type == PublicVisualMediaService.imageType;
  bool get isVideo => type == PublicVisualMediaService.memeType;

  String get cacheFileName {
    final dotIndex = fileName.lastIndexOf('.');
    final extension = dotIndex >= 0 ? fileName.substring(dotIndex) : '';
    final safeId = id.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
    return '$safeId$extension';
  }
}

class PublicVisualMediaService {
  factory PublicVisualMediaService({
    HttpClient? httpClient,
    Directory? cacheDirectory,
  }) {
    return PublicVisualMediaService._(
      httpClient ?? HttpClient(),
      httpClient == null,
      cacheDirectory,
    );
  }

  PublicVisualMediaService._(
    this._httpClient,
    this._ownsHttpClient,
    this._cacheDirectory,
  );

  static const memesSourceUrl = 'https://github.com/Losfodabr12/tgi-memes';
  static const imagesSourceUrl = 'https://github.com/Losfodabr12/tgi-imagens';
  static const memeType = 'Memes';
  static const imageType = 'Imagens e icones';
  static const _memesRawBaseUrl =
      'https://raw.githubusercontent.com/Losfodabr12/tgi-memes/main';
  static const _imagesRawBaseUrl =
      'https://raw.githubusercontent.com/Losfodabr12/tgi-imagens/main';
  static const _downloadTimeout = Duration(seconds: 30);
  static const _maxDownloadBytes = 250 * 1024 * 1024;

  static final List<PublicVisualMediaItem> catalog = List.unmodifiable([
    ...tgiMemeEntries.map(_memeFromEntry),
    ...tgiImageEntries.map(_imageFromEntry),
  ]);

  final HttpClient _httpClient;
  final bool _ownsHttpClient;
  final Directory? _cacheDirectory;

  Future<String> downloadToCache(PublicVisualMediaItem item) async {
    final directory = await _resolveCacheDirectory();
    final target = File(
      '${directory.path}${Platform.pathSeparator}${item.cacheFileName}',
    );
    if (await target.exists() && await target.length() > 0) {
      return target.path;
    }

    final temp = File('${target.path}.download');
    if (await temp.exists()) {
      await temp.delete();
    }

    final request = await _httpClient
        .getUrl(Uri.parse(item.downloadUrl))
        .timeout(_downloadTimeout);
    request.headers.set(HttpHeaders.userAgentHeader, 'TGIAPP');
    final response = await request.close().timeout(_downloadTimeout);
    if (response.statusCode != HttpStatus.ok) {
      throw Exception(
        'Nao foi possivel baixar ${item.name} (${response.statusCode}).',
      );
    }

    await _writeDownload(response, temp, item.name);
    if (await target.exists()) {
      await target.delete();
    }
    await temp.rename(target.path);
    return target.path;
  }

  void dispose() {
    if (_ownsHttpClient) {
      _httpClient.close(force: true);
    }
  }

  Future<Directory> _resolveCacheDirectory() async {
    final directory = _cacheDirectory ?? Directory(_defaultCachePath());
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<void> _writeDownload(
    HttpClientResponse response,
    File temp,
    String name,
  ) async {
    if (response.contentLength > _maxDownloadBytes) {
      throw Exception('Download muito grande para $name.');
    }

    final sink = temp.openWrite();
    var downloadedBytes = 0;
    try {
      await for (final chunk in response.timeout(_downloadTimeout)) {
        downloadedBytes += chunk.length;
        if (downloadedBytes > _maxDownloadBytes) {
          throw Exception('Download muito grande para $name.');
        }
        sink.add(chunk);
      }
      await sink.close();
    } catch (_) {
      await sink.close();
      if (await temp.exists()) {
        await temp.delete();
      }
      rethrow;
    }
  }

  String _defaultCachePath() {
    final base =
        Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    return [base, 'TGI_VIDEO_EDITOR', 'visual_media_cache'].join(Platform.pathSeparator);
  }

  static PublicVisualMediaItem _memeFromEntry(
    TgiGithubVisualMediaCatalogEntry entry,
  ) {
    return PublicVisualMediaItem(
      id: entry.id,
      name: entry.name,
      fileName: entry.fileName,
      category: entry.category,
      downloadUrl: _rawUrl(_memesRawBaseUrl, entry.path),
      library: 'Memes TGI',
      type: memeType,
      license: 'Repositorio GitHub',
      sourceName: 'TGI Memes',
      sourceUrl: memesSourceUrl,
    );
  }

  static PublicVisualMediaItem _imageFromEntry(
    TgiGithubVisualMediaCatalogEntry entry,
  ) {
    return PublicVisualMediaItem(
      id: entry.id,
      name: entry.name,
      fileName: entry.fileName,
      category: entry.category,
      downloadUrl: _rawUrl(_imagesRawBaseUrl, entry.path),
      library: 'Imagens TGI',
      type: imageType,
      license: 'Repositorio GitHub',
      sourceName: 'TGI Imagens',
      sourceUrl: imagesSourceUrl,
    );
  }

  static String _rawUrl(String baseUrl, String path) {
    final encodedPath = path.split('/').map(Uri.encodeComponent).join('/');
    return '$baseUrl/$encodedPath';
  }
}
