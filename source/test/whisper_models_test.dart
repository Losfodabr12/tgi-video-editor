import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/services/whisper_model_service.dart';

class _LocalHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'DIRECT';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides? previous;
  setUp(() {
    previous = HttpOverrides.current;
    HttpOverrides.global = _LocalHttp();
  });
  tearDown(() {
    HttpOverrides.global = previous;
  });

  for (final rangeSupported in [true, false]) {
    test(
      'model resume handles HTTP ${rangeSupported ? 206 : 200} and verifies SHA',
      () async {
        final dir = await Directory.systemTemp.createTemp('models-');
        final data = List.generate(1024, (i) => i % 256);
        final info = WhisperModelInfo(
          name: 'small',
          label: 'test',
          quality: '',
          speed: '',
          sizeBytes: data.length,
          sha256: sha256.convert(data).toString(),
        );
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() async {
          await server.close(force: true);
          await dir.delete(recursive: true);
        });
        var requests = 0;
        server.listen((r) async {
          requests++;
          expect(r.headers.value('range'), 'bytes=300-');
          if (rangeSupported) {
            r.response.statusCode = 206;
            r.response.headers.set('content-range', 'bytes 300-1023/1024');
          }
          r.response.add(rangeSupported ? data.sublist(300) : data);
          await r.response.close();
        });
        final service = WhisperModelService(
          modelsDirectoryOverride: dir.path,
          freeSpaceBytesOverride: 1000000000,
          downloadUriOverride: Uri.parse(
            'http://127.0.0.1:${server.port}/model',
          ),
        );
        final partial = File('${await service.pathForModel(info)}.download');
        await partial.writeAsBytes(data.sublist(0, 300));
        final progress = <double>[];
        final installed = await service.installModel(
          info,
          userInitiated: true,
          onProgress: progress.add,
        );
        expect(await installed.readAsBytes(), data);
        expect(progress.last, 1);
        expect(requests, 1);
        expect(await partial.exists(), false);
        await service.removeModel('small');
        expect(await installed.exists(), false);
      },
    );
  }
  test('bad SHA never installs; insufficient space makes no request', () async {
    final dir = await Directory.systemTemp.createTemp('models-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    var requests = 0;
    server.listen((r) async {
      requests++;
      r.response.add([1, 2]);
      await r.response.close();
    });
    const info = WhisperModelInfo(
      name: 'small',
      label: '',
      quality: '',
      speed: '',
      sizeBytes: 2,
      sha256: 'bad',
    );
    WhisperModelService service(int free) => WhisperModelService(
      modelsDirectoryOverride: dir.path,
      freeSpaceBytesOverride: free,
      downloadUriOverride: Uri.parse('http://127.0.0.1:${server.port}/model'),
    );
    await expectLater(
      service(0).installModel(info, userInitiated: true),
      throwsA(isA<FileSystemException>()),
    );
    expect(requests, 0);
    await expectLater(
      service(1000000000).installModel(info, userInitiated: true),
      throwsFormatException,
    );
    expect(await File('${dir.path}/${info.fileName}').exists(), false);
    expect(await File('${dir.path}/${info.fileName}.download').exists(), false);
  });
  test(
    'cancellation preserves partial; no explicit action means no download',
    () async {
      final dir = await Directory.systemTemp.createTemp('models-');
      addTearDown(() => dir.delete(recursive: true));
      final service = WhisperModelService(
        modelsDirectoryOverride: dir.path,
        freeSpaceBytesOverride: 1000000000,
      );
      final info = whisperModelCatalog.first;
      final partial = File('${await service.pathForModel(info)}.download');
      await partial.writeAsBytes([1, 2]);
      await expectLater(service.installModel(info), throwsStateError);
      final token = WhisperModelDownloadCancellationToken()..cancel();
      await expectLater(
        service.installModel(
          info,
          userInitiated: true,
          cancellationToken: token,
        ),
        throwsA(isA<WhisperModelDownloadCancelledException>()),
      );
      expect(await partial.readAsBytes(), [1, 2]);
    },
  );
  test(
    'catalog pins official size, revision and SHA; recommendations use RAM/GPU',
    () {
      for (final info in whisperModelCatalog) {
        expect(info.sha256, matches(RegExp(r'^[A-F0-9]{64}$')));
        expect(
          info.downloadUri.path,
          contains('/5359861c739e955e79d9a303bcbc70fb988958b1/'),
        );
      }
      final turbo = whisperModelCatalog.singleWhere(
        (info) => info.name == 'large-v3-turbo-q5_0',
      );
      expect(turbo.label, 'Preciso (turbo)');
      expect(turbo.fileName, 'ggml-large-v3-turbo-q5_0.bin');
      expect(turbo.sizeBytes, 574041195);
      expect(turbo.sha256, isNotNull);
      expect(
        WhisperModelService.recommendationForMemory(
          32 * 1024 * 1024 * 1024,
          gpuMemoryBytes: 8 * 1024 * 1024 * 1024,
        ).info.name,
        'large-v3-turbo-q5_0',
      );
      expect(
        WhisperModelService.recommendationForMemory(
          16 * 1024 * 1024 * 1024,
        ).info.name,
        'small',
      );
    },
  );
}
