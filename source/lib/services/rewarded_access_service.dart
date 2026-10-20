import '../app/app_identity.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../features/auth/application/google_auth_service.dart';

enum RewardedAccessState {
  granted,
  pending,
  unavailable,
  signInRequired,
  failed,
}

class RewardedAccessResult {
  const RewardedAccessResult({
    required this.state,
    required this.message,
    this.validUntil,
  });

  final RewardedAccessState state;
  final String message;
  final DateTime? validUntil;

  bool get granted => state == RewardedAccessState.granted;
}

abstract interface class RewardedAccessManager {
  Future<bool> isAvailable();

  Future<RewardedAccessResult> watchRewardAd();

  void close();
}

class RewardedAccessService implements RewardedAccessManager {
  RewardedAccessService({
    TgiAuthConfig? config,
    AuthSessionStore? store,
    http.Client? client,
    Future<bool> Function(Uri uri)? openBrowser,
    this.pollInterval = const Duration(seconds: 2),
    this.maxPollAttempts = 90,
  }) : _config = config ?? TgiAuthConfig.fromEnvironment(),
       _store = store ?? const SecureAuthSessionStore(),
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _openBrowser = openBrowser ?? _launchExternalBrowser;

  final TgiAuthConfig _config;
  final AuthSessionStore _store;
  final http.Client _client;
  final bool _ownsClient;
  final Future<bool> Function(Uri uri) _openBrowser;
  final Duration pollInterval;
  final int maxPollAttempts;

  @override
  Future<bool> isAvailable() async {
    if (kStandalone) return false;
    if (!_config.isConfigured) return false;
    try {
      final response = await _client
          .get(
            _endpoint('/api/rewards/config'),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != HttpStatus.ok) return false;
      return _decodeObject(response.body)['enabled'] == true;
    } on Object {
      return false;
    }
  }

  @override
  Future<RewardedAccessResult> watchRewardAd() async {
    requireOnlineIntegrations();
    final sessionToken = await _store.read(
      TgiAccountAuthService.sessionTokenStorageKey,
    );
    if (sessionToken == null || sessionToken.isEmpty) {
      return const RewardedAccessResult(
        state: RewardedAccessState.signInRequired,
        message: 'Entre na sua conta TGI para liberar o acesso por anuncio.',
      );
    }

    try {
      final startResponse = await _client
          .post(
            _endpoint('/api/rewards/start'),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $sessionToken',
            },
          )
          .timeout(const Duration(seconds: 15));
      final start = _decodeObject(startResponse.body);
      if (startResponse.statusCode == HttpStatus.unauthorized) {
        return const RewardedAccessResult(
          state: RewardedAccessState.signInRequired,
          message: 'Sua sessao expirou. Entre novamente na conta TGI.',
        );
      }
      if (startResponse.statusCode == HttpStatus.serviceUnavailable) {
        return RewardedAccessResult(
          state: RewardedAccessState.unavailable,
          message:
              start['error'] as String? ??
              'Os anuncios ainda aguardam ativacao.',
        );
      }
      if (startResponse.statusCode < 200 || startResponse.statusCode >= 300) {
        return RewardedAccessResult(
          state: RewardedAccessState.failed,
          message:
              start['error'] as String? ??
              'Nao foi possivel preparar o anuncio.',
        );
      }
      if (start['alreadyActive'] == true) {
        return RewardedAccessResult(
          state: RewardedAccessState.granted,
          message: 'Seu acesso Premium ja esta ativo.',
          validUntil: _dateTimeFromUnix(start['validUntil']),
        );
      }

      final rewardSession = start['rewardSession'] as String?;
      final adUrl = Uri.tryParse(start['adUrl'] as String? ?? '');
      if (!_validRewardSession(rewardSession) || !_allowedAdUrl(adUrl)) {
        return const RewardedAccessResult(
          state: RewardedAccessState.failed,
          message: 'O servidor retornou uma sessao de anuncio invalida.',
        );
      }
      if (!await _openBrowser(adUrl!)) {
        return const RewardedAccessResult(
          state: RewardedAccessState.failed,
          message: 'Nao foi possivel abrir o anuncio no navegador.',
        );
      }

      for (var attempt = 0; attempt < maxPollAttempts; attempt++) {
        await Future<void>.delayed(pollInterval);
        final statusResponse = await _client
            .get(
              _endpoint(
                '/api/rewards/status',
              ).replace(queryParameters: {'session': rewardSession}),
              headers: {
                'Accept': 'application/json',
                'Authorization': 'Bearer $sessionToken',
              },
            )
            .timeout(const Duration(seconds: 10));
        if (statusResponse.statusCode != HttpStatus.ok) continue;
        final status = _decodeObject(statusResponse.body);
        if (status['granted'] == true) {
          return RewardedAccessResult(
            state: RewardedAccessState.granted,
            message: 'Premium liberado por 24 horas.',
            validUntil: _dateTimeFromUnix(status['validUntil']),
          );
        }
        if (status['status'] == 'expired') {
          return const RewardedAccessResult(
            state: RewardedAccessState.failed,
            message: 'O tempo para concluir o anuncio acabou.',
          );
        }
      }
      return const RewardedAccessResult(
        state: RewardedAccessState.pending,
        message:
            'O anuncio foi aberto, mas a confirmacao ainda esta pendente. Tente atualizar o acesso em alguns minutos.',
      );
    } on TimeoutException {
      return const RewardedAccessResult(
        state: RewardedAccessState.pending,
        message:
            'A confirmacao esta demorando. Verifique novamente em instantes.',
      );
    } on SocketException {
      return const RewardedAccessResult(
        state: RewardedAccessState.failed,
        message: 'Sem conexao com o servidor de recompensas.',
      );
    } on http.ClientException {
      return const RewardedAccessResult(
        state: RewardedAccessState.failed,
        message: 'Nao foi possivel consultar o servidor de recompensas.',
      );
    } on FormatException {
      return const RewardedAccessResult(
        state: RewardedAccessState.failed,
        message: 'O servidor de recompensas retornou uma resposta invalida.',
      );
    }
  }

  @override
  void close() {
    if (_ownsClient) _client.close();
  }

  Uri _endpoint(String path) => _config.baseUri.resolve(path);

  bool _allowedAdUrl(Uri? uri) {
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;
    return uri.scheme == _config.baseUri.scheme &&
        uri.host == _config.baseUri.host &&
        uri.port == _config.baseUri.port &&
        uri.path == '/reward';
  }
}

Map<String, Object?> _decodeObject(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) throw const FormatException();
  return decoded.cast<String, Object?>();
}

bool _validRewardSession(String? value) {
  return value != null && RegExp(r'^[A-Za-z0-9_-]{20,256}$').hasMatch(value);
}

DateTime? _dateTimeFromUnix(Object? value) {
  if (value is! num || !value.isFinite || value <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(
    value.round() * 1000,
    isUtc: true,
  ).toLocal();
}

Future<bool> _launchExternalBrowser(Uri uri) {
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
