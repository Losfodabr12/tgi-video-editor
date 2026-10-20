import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:tgi_video_editor/app/app_identity.dart';
import 'package:tgi_video_editor/features/auth/application/google_auth_service.dart';
import 'package:tgi_video_editor/services/ffmpeg_export_settings.dart';
import 'package:tgi_video_editor/services/sound_effects_service.dart';
import 'package:tgi_video_editor/services/whisper_model_service.dart';

class _NoNetworkClient implements HttpClient {
  int requests = 0;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requests++;
    throw StateError('Unexpected network request');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('standalone unlocks every export resolution without an account', () {
    expect(kStandalone, isTrue);
    for (final resolution in FfmpegExportResolution.all) {
      expect(canExportResolution(resolution, hasPaidPlan: false), isTrue);
      expect(resolution.requiresPaidPlan, isFalse);
    }
  });

  test('standalone authentication never contacts production', () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      throw StateError('Network');
    });
    addTearDown(client.close);
    final auth = TgiAccountAuthService(client: client);
    expect(auth.isConfigured, isFalse);
    expect(await auth.restoreSession(), isNull);
    await expectLater(auth.signIn(), throwsA(isA<TgiAuthException>()));
    expect(requests, 0);
  });

  test(
    'uncached online assets and model installation fail before a request',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'offline_policy_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final client = _NoNetworkClient();
      final service = PublicSoundEffectsService(
        httpClient: client,
        cacheDirectory: directory,
      );
      await expectLater(
        service.downloadToCache(PublicSoundEffectsService.catalog.first),
        throwsStateError,
      );
      expect(client.requests, 0);
      await expectLater(
        const WhisperModelService().installModel(whisperModelCatalog.first),
        throwsStateError,
      );
    },
  );
}
