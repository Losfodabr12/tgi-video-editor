import '../app/app_identity.dart';
import 'dart:async';
import 'dart:io';

import 'github_audio_catalog.dart';

class PublicSoundEffect {
  const PublicSoundEffect({
    required this.id,
    required this.name,
    required this.fileName,
    required this.category,
    required this.downloadUrl,
    required this.library,
    required this.type,
    required this.duration,
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
  final Duration duration;
  final String license;
  final String sourceName;
  final String sourceUrl;

  String get cacheFileName {
    final dotIndex = fileName.lastIndexOf('.');
    final extension = dotIndex >= 0 ? fileName.substring(dotIndex) : '';
    final safeId = id.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
    return '$safeId$extension';
  }
}

class PublicSoundEffectsService {
  factory PublicSoundEffectsService({
    HttpClient? httpClient,
    Directory? cacheDirectory,
  }) {
    return PublicSoundEffectsService._(
      httpClient ?? HttpClient(),
      httpClient == null,
      cacheDirectory,
    );
  }

  PublicSoundEffectsService._(
    this._httpClient,
    this._ownsHttpClient,
    this._cacheDirectory,
  );

  static const kenneySourceUrl = 'https://github.com/Calinou/kenney-ui-audio';
  static const tgiEffectsSourceUrl =
      'https://github.com/Losfodabr12/tgi-app-suite';
  static const tgiSoundtracksSourceUrl =
      'https://github.com/Losfodabr12/tgi-trilhas-sonoras';
  static const soundEffectType = 'Efeitos Sonoros';
  static const soundtrackType = 'Trilhas Sonoras';
  static const _kenneyRawBaseUrl =
      'https://raw.githubusercontent.com/Calinou/kenney-ui-audio/master/addons/kenney_ui_audio';
  static const _tgiEffectsRawBaseUrl =
      'https://raw.githubusercontent.com/Losfodabr12/tgi-app-suite/main';
  static const _tgiSoundtracksRawBaseUrl =
      'https://raw.githubusercontent.com/Losfodabr12/tgi-trilhas-sonoras/main';
  static const _downloadTimeout = Duration(seconds: 30);
  static const _maxDownloadBytes = 200 * 1024 * 1024;

  static final List<PublicSoundEffect> catalog = List.unmodifiable([
    ...kenneyAudioEntries.map(_kenneyEffectFromEntry),
    ...tgiGithubEffectEntries.map(_tgiEffectFromEntry),
    ...tgiGithubSoundtrackEntries.map(_tgiSoundtrackFromEntry),
  ]);

  final HttpClient _httpClient;
  final bool _ownsHttpClient;
  final Directory? _cacheDirectory;

  Future<String> downloadToCache(PublicSoundEffect effect) async {
    final directory = await _resolveCacheDirectory();
    final target = File(
      '${directory.path}${Platform.pathSeparator}${effect.cacheFileName}',
    );
    if (await target.exists() && await target.length() > 0) {
      return target.path;
    }

    requireOnlineIntegrations();
    final temp = File('${target.path}.download');
    if (await temp.exists()) {
      await temp.delete();
    }

    final request = await _httpClient
        .getUrl(Uri.parse(effect.downloadUrl))
        .timeout(_downloadTimeout);
    request.headers.set(HttpHeaders.userAgentHeader, 'TGIAPP');
    final response = await request.close().timeout(_downloadTimeout);
    if (response.statusCode != HttpStatus.ok) {
      throw Exception(
        'Nao foi possivel baixar ${effect.name} (${response.statusCode}).',
      );
    }

    await _writeDownload(response, temp, effect.name);
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
    return [base, 'TGI_VIDEO_EDITOR', 'sound_effects_cache'].join(Platform.pathSeparator);
  }

  static PublicSoundEffect _kenneyEffectFromEntry(
    TgiGithubAudioCatalogEntry entry,
  ) {
    return PublicSoundEffect(
      id: entry.id,
      name: entry.name,
      fileName: entry.fileName,
      category: entry.category,
      downloadUrl: '$_kenneyRawBaseUrl/${entry.encodedPath}',
      library: 'Kenney',
      type: soundEffectType,
      duration: _durationFromMilliseconds(entry.durationMilliseconds),
      license: 'CC0 1.0',
      sourceName: 'Kenney UI Audio',
      sourceUrl: kenneySourceUrl,
    );
  }

  static PublicSoundEffect _tgiEffectFromEntry(
    TgiGithubAudioCatalogEntry entry,
  ) {
    return PublicSoundEffect(
      id: entry.id,
      name: entry.name,
      fileName: entry.fileName,
      category: entry.category,
      downloadUrl: '$_tgiEffectsRawBaseUrl/${entry.encodedPath}',
      library: 'Efeitos TGI',
      type: soundEffectType,
      duration: _durationFromMilliseconds(entry.durationMilliseconds),
      license: 'Repositorio GitHub',
      sourceName: 'TGI Efeitos Sonoros',
      sourceUrl: tgiEffectsSourceUrl,
    );
  }

  static PublicSoundEffect _tgiSoundtrackFromEntry(
    TgiGithubAudioCatalogEntry entry,
  ) {
    return PublicSoundEffect(
      id: entry.id,
      name: entry.name,
      fileName: entry.fileName,
      category: entry.category,
      downloadUrl: '$_tgiSoundtracksRawBaseUrl/${entry.encodedPath}',
      library: 'Trilhas TGI',
      type: soundtrackType,
      duration: _durationFromMilliseconds(entry.durationMilliseconds),
      license: 'Repositorio GitHub',
      sourceName: 'TGI Trilhas Sonoras',
      sourceUrl: tgiSoundtracksSourceUrl,
    );
  }

  static Duration _durationFromMilliseconds(int? milliseconds) {
    return Duration(milliseconds: milliseconds ?? 0);
  }
}
