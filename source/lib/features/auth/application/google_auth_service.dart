import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class GoogleUserProfile {
  const GoogleUserProfile({
    required this.id,
    required this.email,
    required this.name,
    this.pictureUrl,
    this.planCode,
  });

  final String id;
  final String email;
  final String name;
  final String? pictureUrl;
  final String? planCode;

  bool get hasPaidPlan =>
      planCode == 'studio_lifetime' || planCode == 'reward_day';

  String get planLabel => switch (planCode) {
    'studio_lifetime' => 'TGI Permanente',
    'reward_day' => 'Premium por anuncio - 24 horas',
    _ => 'Plano gratuito',
  };

  String get firstName {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return email.split('@').first;
    }
    return trimmed.split(RegExp(r'\s+')).first;
  }

  String get initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return email.isEmpty ? '?' : email.substring(0, 1).toUpperCase();
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'email': email,
    'name': name,
    'pictureUrl': pictureUrl,
    'planCode': planCode,
  };

  factory GoogleUserProfile.fromJson(Map<String, Object?> json) {
    return GoogleUserProfile(
      id: json['id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      name: json['name'] as String? ?? '',
      pictureUrl: json['pictureUrl'] as String?,
      planCode: switch (json['planCode']) {
        'studio_lifetime' => 'studio_lifetime',
        'reward_day' => 'reward_day',
        _ => null,
      },
    );
  }
}

abstract interface class TgiAuthService {
  bool get isConfigured;

  Future<GoogleUserProfile?> restoreSession();

  Future<GoogleUserProfile> signIn();

  Future<void> signOut();
}

class TgiAuthConfig {
  const TgiAuthConfig({required this.baseUri});

  static final _productionBaseUri = Uri.parse('https://tgiapp.pages.dev');

  final Uri baseUri;

  bool get isConfigured {
    if (baseUri.scheme == 'https' && baseUri.host.isNotEmpty) {
      return true;
    }
    return baseUri.scheme == 'http' &&
        (baseUri.host == '127.0.0.1' || baseUri.host == 'localhost');
  }

  factory TgiAuthConfig.fromEnvironment() {
    const compiledBaseUrl = String.fromEnvironment('TGI_AUTH_BASE_URL');
    final runtimeBaseUrl = Platform.environment['TGI_AUTH_BASE_URL'];
    return TgiAuthConfig(
      baseUri: resolveEnvironmentBaseUri(
        releaseMode: kReleaseMode,
        runtimeBaseUrl: runtimeBaseUrl,
        compiledBaseUrl: compiledBaseUrl,
      ),
    );
  }

  @visibleForTesting
  static Uri resolveEnvironmentBaseUri({
    required bool releaseMode,
    String? runtimeBaseUrl,
    String? compiledBaseUrl,
  }) {
    if (releaseMode) {
      return _productionBaseUri;
    }
    return _developmentLoopbackUri(runtimeBaseUrl) ??
        _developmentLoopbackUri(compiledBaseUrl) ??
        _productionBaseUri;
  }

  static Uri? _developmentLoopbackUri(String? rawValue) {
    final value = rawValue?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'http' ||
        (uri.host != '127.0.0.1' && uri.host != 'localhost') ||
        !uri.hasPort ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      return null;
    }
    return uri;
  }
}

class TgiAuthException implements Exception {
  const TgiAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class AuthSessionStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class SecureAuthSessionStore implements AuthSessionStore {
  const SecureAuthSessionStore();

  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class TgiAccountAuthService implements TgiAuthService {
  TgiAccountAuthService({
    TgiAuthConfig? config,
    AuthSessionStore? store,
    http.Client? client,
    Future<bool> Function(Uri uri)? openBrowser,
  }) : _config = config ?? TgiAuthConfig.fromEnvironment(),
       _store = store ?? const SecureAuthSessionStore(),
       _client = client ?? http.Client(),
       _openBrowser = openBrowser ?? _launchExternalBrowser;

  static const sessionTokenStorageKey = 'tgiapp.account.session_token';
  static const _profileKey = 'tgiapp.account.profile';
  static const _legacyRefreshTokenKey = 'tgiapp.google.refresh_token';
  static const _legacyProfileKey = 'tgiapp.google.profile';

  final TgiAuthConfig _config;
  final AuthSessionStore _store;
  final http.Client _client;
  final Future<bool> Function(Uri uri) _openBrowser;

  @override
  bool get isConfigured => _config.isConfigured;

  @override
  Future<GoogleUserProfile?> restoreSession() async {
    if (!isConfigured) {
      return null;
    }
    final sessionToken = await _store.read(sessionTokenStorageKey);
    if (sessionToken == null || sessionToken.isEmpty) {
      await _clearLegacyGoogleSession();
      return null;
    }
    final cachedProfile = await _readCachedProfile();
    try {
      final response = await _client
          .get(
            _endpoint('/api/auth/session'),
            headers: {'Authorization': 'Bearer $sessionToken'},
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 401 || response.statusCode == 403) {
        await _clearSession();
        return null;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return cachedProfile;
      }
      final profile = _profileFromResponse(response.body);
      await _store.write(_profileKey, jsonEncode(profile.toJson()));
      return profile;
    } on SocketException {
      return cachedProfile;
    } on TimeoutException {
      return cachedProfile;
    } on http.ClientException {
      return cachedProfile;
    }
  }

  @override
  Future<GoogleUserProfile> signIn() async {
    if (!isConfigured) {
      throw const TgiAuthException(
        'O serviço de conta TGI ainda não foi configurado.',
      );
    }

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = Uri.parse('http://127.0.0.1:${server.port}/callback');
    final state = _randomToken(32);
    final authorizationUri = _endpoint('/api/auth/login').replace(
      queryParameters: {
        'mode': 'desktop',
        'redirect_uri': redirectUri.toString(),
        'client_state': state,
      },
    );
    HttpRequest? browserRequest;

    try {
      if (!await _openBrowser(authorizationUri)) {
        throw const TgiAuthException(
          'Não foi possível abrir o navegador para entrar com Google.',
        );
      }

      browserRequest = await server.first.timeout(const Duration(minutes: 3));
      final callback = browserRequest.uri;
      if (callback.queryParameters['state'] != state) {
        throw const TgiAuthException(
          'A resposta de login não corresponde a esta tentativa.',
        );
      }
      final oauthError = callback.queryParameters['error'];
      if (oauthError != null) {
        if (oauthError == 'access_denied') {
          throw const TgiAuthException('O login foi cancelado.');
        }
        throw const TgiAuthException(
          'O serviço de conta não conseguiu concluir o login.',
        );
      }
      final code = callback.queryParameters['code'];
      if (code == null || code.isEmpty) {
        throw const TgiAuthException(
          'O serviço de conta não retornou o código temporário.',
        );
      }

      final response = await _client
          .post(
            _endpoint('/api/auth/desktop/exchange'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'code': code}),
          )
          .timeout(const Duration(seconds: 20));
      final payload = _decodeJsonObject(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw TgiAuthException(
          payload['error'] as String? ??
              'O serviço de conta não conseguiu concluir o login.',
        );
      }
      final sessionToken = payload['session_token'] as String?;
      final rawUser = payload['user'];
      if (sessionToken == null || sessionToken.isEmpty || rawUser is! Map) {
        throw const TgiAuthException(
          'O serviço de conta retornou uma sessão inválida.',
        );
      }
      final profile = GoogleUserProfile.fromJson(
        rawUser.cast<String, Object?>(),
      );
      await _saveSession(sessionToken: sessionToken, profile: profile);
      await _respondToBrowser(browserRequest, success: true);
      return profile;
    } on TimeoutException {
      if (browserRequest != null) {
        await _respondToBrowser(browserRequest, success: false);
      }
      throw const TgiAuthException('O tempo para concluir o login acabou.');
    } on Object {
      if (browserRequest != null) {
        await _respondToBrowser(browserRequest, success: false);
      }
      rethrow;
    } finally {
      await server.close(force: true);
    }
  }

  @override
  Future<void> signOut() async {
    final sessionToken = await _store.read(sessionTokenStorageKey);
    if (sessionToken != null && sessionToken.isNotEmpty) {
      try {
        await _client
            .post(
              _endpoint('/api/auth/logout'),
              headers: {'Authorization': 'Bearer $sessionToken'},
            )
            .timeout(const Duration(seconds: 10));
      } on Object {
        // The local session must still be cleared when the server is offline.
      }
    }
    await _clearSession();
  }

  Uri _endpoint(String path) => _config.baseUri.resolve(path);

  GoogleUserProfile _profileFromResponse(String raw) {
    final payload = _decodeJsonObject(raw);
    final user = payload['user'];
    if (user is! Map) {
      throw const TgiAuthException(
        'O serviço de conta retornou um perfil inválido.',
      );
    }
    return GoogleUserProfile.fromJson(user.cast<String, Object?>());
  }

  Future<GoogleUserProfile?> _readCachedProfile() async {
    final raw = await _store.read(_profileKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      return GoogleUserProfile.fromJson(_decodeJsonObject(raw));
    } on Object {
      return null;
    }
  }

  Future<void> _saveSession({
    required String sessionToken,
    required GoogleUserProfile profile,
  }) async {
    await _clearLegacyGoogleSession();
    await _store.write(sessionTokenStorageKey, sessionToken);
    await _store.write(_profileKey, jsonEncode(profile.toJson()));
  }

  Future<void> _clearSession() async {
    await _store.delete(sessionTokenStorageKey);
    await _store.delete(_profileKey);
    await _clearLegacyGoogleSession();
  }

  Future<void> _clearLegacyGoogleSession() async {
    await _store.delete(_legacyRefreshTokenKey);
    await _store.delete(_legacyProfileKey);
  }

  Future<void> _respondToBrowser(
    HttpRequest request, {
    required bool success,
  }) async {
    request.response.statusCode = success
        ? HttpStatus.ok
        : HttpStatus.badRequest;
    request.response.headers.contentType = ContentType.html;
    request.response.write('''
<!doctype html>
<html lang="pt-BR">
  <head><meta charset="utf-8"><title>TGI APP</title></head>
  <body style="background:#0a0a0a;color:#f0f0f0;font-family:Arial,sans-serif;display:grid;place-items:center;height:100vh;margin:0">
    <main style="text-align:center">
      <h1 style="color:#f5c400">TGI APP</h1>
      <p>${success ? 'Login concluído. O site e o aplicativo estão conectados.' : 'Não foi possível concluir o login. Volte ao aplicativo.'}</p>
    </main>
  </body>
</html>
''');
    await request.response.close();
  }
}

Map<String, Object?> _decodeJsonObject(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) {
    throw const TgiAuthException(
      'O serviço de conta retornou uma resposta inválida.',
    );
  }
  return decoded.cast<String, Object?>();
}

String _randomToken(int byteCount) {
  final random = Random.secure();
  final bytes = List<int>.generate(byteCount, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

Future<bool> _launchExternalBrowser(Uri uri) {
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
