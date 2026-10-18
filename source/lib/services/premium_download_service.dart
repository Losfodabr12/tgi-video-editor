import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import 'app_component_paths.dart';
import 'whisper_model_service.dart';

enum PremiumComponentId { realEsrgan, biRefNet, whisperSmall }

class PremiumComponentInfo {
  const PremiumComponentInfo({
    required this.id,
    required this.title,
    required this.description,
    required this.downloadSizeBytes,
  });

  final PremiumComponentId id;
  final String title;
  final String description;
  final int downloadSizeBytes;
}

const premiumComponentCatalog = <PremiumComponentInfo>[
  PremiumComponentInfo(
    id: PremiumComponentId.realEsrgan,
    title: 'Melhoria de imagem IA 2x e 4x',
    description: 'Aumenta a resolucao preservando detalhes com Real-ESRGAN.',
    downloadSizeBytes: 33106994,
  ),
  PremiumComponentInfo(
    id: PremiumComponentId.biRefNet,
    title: 'Remover fundo por IA',
    description: 'Recorta pessoas e objetos localmente com BiRefNet.',
    downloadSizeBytes: 97055877,
  ),
  PremiumComponentInfo(
    id: PremiumComponentId.whisperSmall,
    title: 'Legendas automaticas - alta qualidade',
    description: 'Instala o Whisper Small para transcricoes mais precisas.',
    downloadSizeBytes: 487601967,
  ),
];

typedef PremiumDownloadProgress = void Function(double progress);

class PremiumDownloadCancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

class PremiumDownloadException implements Exception {
  const PremiumDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class PremiumDownloadManager {
  Future<bool> isInstalled(PremiumComponentId id);

  Future<void> install(
    PremiumComponentId id, {
    PremiumDownloadProgress? onProgress,
    PremiumDownloadCancellationToken? cancellationToken,
  });

  Future<void> remove(PremiumComponentId id);
}

class PremiumDownloadService implements PremiumDownloadManager {
  PremiumDownloadService({
    required this.hasPaidPlan,
    String? componentsRootOverride,
  }) : _componentsRoot = componentsRootOverride ?? tgiAppComponentsRoot();

  final bool hasPaidPlan;
  final String _componentsRoot;

  late final WhisperModelService _whisperService = WhisperModelService(
    modelsDirectoryOverride: joinPlatformPath([
      _componentsRoot,
      'whisper',
      'models',
    ]),
  );

  @override
  Future<bool> isInstalled(PremiumComponentId id) async {
    if (id == PremiumComponentId.whisperSmall) {
      final info = WhisperModelService.infoForModel('small');
      if (info == null) return false;
      final file = File(await _whisperService.pathForModel(info));
      return file.exists();
    }
    final spec = _archiveSpec(id);
    final root = Directory(_componentDirectory(id));
    if (!await root.exists()) return false;
    for (final relativePath in spec.allowedPaths) {
      if (!await File(
        joinPlatformPath([root.path, ...relativePath.split('/')]),
      ).exists()) {
        return false;
      }
    }
    return true;
  }

  @override
  Future<void> install(
    PremiumComponentId id, {
    PremiumDownloadProgress? onProgress,
    PremiumDownloadCancellationToken? cancellationToken,
  }) async {
    if (!hasPaidPlan) {
      throw const PremiumDownloadException(
        'Este download requer o TGI Permanente ou acesso temporario ativo.',
      );
    }
    if (id == PremiumComponentId.whisperSmall) {
      await _installWhisper(onProgress, cancellationToken);
      return;
    }
    await _installArchive(id, onProgress, cancellationToken);
  }

  Future<void> _installWhisper(
    PremiumDownloadProgress? onProgress,
    PremiumDownloadCancellationToken? cancellationToken,
  ) async {
    final info = WhisperModelService.infoForModel('small');
    if (info == null) {
      throw const PremiumDownloadException('Modelo Whisper Small ausente.');
    }
    final whisperToken = WhisperModelDownloadCancellationToken();
    Timer? cancellationPoll;
    if (cancellationToken != null) {
      cancellationPoll = Timer.periodic(const Duration(milliseconds: 150), (_) {
        if (cancellationToken.isCancelled) whisperToken.cancel();
      });
    }
    try {
      await _whisperService.installModel(
        info,
        onProgress: onProgress,
        cancellationToken: whisperToken,
      );
    } on WhisperModelDownloadCancelledException {
      throw const PremiumDownloadException('Download cancelado.');
    } finally {
      cancellationPoll?.cancel();
    }
  }

  Future<void> _installArchive(
    PremiumComponentId id,
    PremiumDownloadProgress? onProgress,
    PremiumDownloadCancellationToken? cancellationToken,
  ) async {
    final spec = _archiveSpec(id);
    final components = Directory(_componentsRoot);
    await components.create(recursive: true);
    final download = File(
      joinPlatformPath([components.path, '.${spec.directoryName}.download']),
    );
    final staging = Directory(
      joinPlatformPath([components.path, '.${spec.directoryName}.installing']),
    );
    try {
      await _deleteFileIfPresent(download);
      await _deleteDirectoryIfPresent(staging);
      await _download(spec.uri, download, onProgress, cancellationToken);
      _throwIfCancelled(cancellationToken);
      final actualHash = (await sha256.bind(download.openRead()).first)
          .toString()
          .toUpperCase();
      if (actualHash != spec.sha256) {
        throw const PremiumDownloadException(
          'O pacote falhou na validacao de seguranca SHA-256.',
        );
      }

      final archive = ZipDecoder().decodeBytes(
        await download.readAsBytes(),
        verify: true,
      );
      final archivePaths = archive.files
          .where((entry) => entry.isFile)
          .map((entry) => _safeArchivePath(entry.name))
          .toSet();
      if (archivePaths.length != spec.allowedPaths.length ||
          !archivePaths.containsAll(spec.allowedPaths)) {
        throw const PremiumDownloadException(
          'O pacote possui uma lista de arquivos inesperada.',
        );
      }
      await staging.create(recursive: true);
      for (final entry in archive.files.where((entry) => entry.isFile)) {
        final relativePath = _safeArchivePath(entry.name);
        final output = File(
          joinPlatformPath([staging.path, ...relativePath.split('/')]),
        );
        await output.parent.create(recursive: true);
        await output.writeAsBytes(entry.content, flush: true);
      }
      _throwIfCancelled(cancellationToken);

      final destination = Directory(_componentDirectory(id));
      await _deleteDirectoryIfPresent(destination);
      await staging.rename(destination.path);
      onProgress?.call(1);
    } on PremiumDownloadException {
      rethrow;
    } on Object catch (error) {
      throw PremiumDownloadException('Falha ao instalar o componente: $error');
    } finally {
      await _deleteFileIfPresent(download);
      await _deleteDirectoryIfPresent(staging);
    }
  }

  Future<void> _download(
    Uri uri,
    File output,
    PremiumDownloadProgress? onProgress,
    PremiumDownloadCancellationToken? cancellationToken,
  ) async {
    final client = HttpClient();
    try {
      _throwIfCancelled(cancellationToken);
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'TGIAPP/1.4');
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw PremiumDownloadException(
          'O servidor retornou HTTP ${response.statusCode}.',
        );
      }
      var received = 0;
      final sink = output.openWrite();
      try {
        await for (final chunk in response) {
          _throwIfCancelled(cancellationToken);
          sink.add(chunk);
          received += chunk.length;
          if (response.contentLength > 0) {
            onProgress?.call(received / response.contentLength);
          }
        }
      } finally {
        await sink.close();
      }
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> remove(PremiumComponentId id) async {
    if (id == PremiumComponentId.whisperSmall) {
      await _whisperService.removeModel('small');
      return;
    }
    await _deleteDirectoryIfPresent(Directory(_componentDirectory(id)));
  }

  String _componentDirectory(PremiumComponentId id) =>
      joinPlatformPath([_componentsRoot, _archiveSpec(id).directoryName]);
}

class _ArchiveComponentSpec {
  const _ArchiveComponentSpec({
    required this.directoryName,
    required this.uri,
    required this.sha256,
    required this.allowedPaths,
  });

  final String directoryName;
  final Uri uri;
  final String sha256;
  final Set<String> allowedPaths;
}

_ArchiveComponentSpec _archiveSpec(PremiumComponentId id) {
  switch (id) {
    case PremiumComponentId.realEsrgan:
      return _ArchiveComponentSpec(
        directoryName: 'realesrgan',
        uri: Uri.parse(
          'https://github.com/Losfodabr12/tgiapp-downloads/releases/download/components-v1/tgiapp-realesrgan-windows-x64-v1.zip',
        ),
        sha256:
            '9F1CA6180650B96AB253A38C38972A2C312C004A0217AB8E294010A4712F6D41',
        allowedPaths: const {
          'LICENSE-NCNN.txt',
          'LICENSE-Real-ESRGAN-ncnn-vulkan.txt',
          'LICENSE-Real-ESRGAN.txt',
          'README_windows.md',
          'realesrgan-ncnn-vulkan.exe',
          'vcomp140.dll',
          'models/realesrgan-x4plus.bin',
          'models/realesrgan-x4plus.param',
        },
      );
    case PremiumComponentId.biRefNet:
      return _ArchiveComponentSpec(
        directoryName: 'birefnet',
        uri: Uri.parse(
          'https://github.com/Losfodabr12/tgiapp-downloads/releases/download/components-v1/tgiapp-birefnet-windows-x64-v1.zip',
        ),
        sha256:
            'D5D0162DEBCF2801D040E23FB83AD20629ACD6B6A82441DCD2BAB412710C9D47',
        allowedPaths: const {
          'BiRefNet-lite-F16.gguf',
          'LICENSE',
          'MODEL_LICENSE.txt',
          'README.md',
          'bin/ggml-base.dll',
          'bin/ggml-cpu.dll',
          'bin/ggml-vulkan.dll',
          'bin/ggml.dll',
          'bin/vision-cli.exe',
          'bin/visioncpp.dll',
        },
      );
    case PremiumComponentId.whisperSmall:
      throw ArgumentError('Whisper nao usa pacote ZIP.');
  }
}

String _safeArchivePath(String rawPath) {
  final normalized = rawPath.replaceAll('\\', '/');
  final parts = normalized.split('/');
  if (normalized.startsWith('/') ||
      RegExp(r'^[A-Za-z]:').hasMatch(normalized) ||
      parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
    throw const PremiumDownloadException('Caminho inseguro no pacote.');
  }
  return parts.join('/');
}

void _throwIfCancelled(PremiumDownloadCancellationToken? token) {
  if (token?.isCancelled ?? false) {
    throw const PremiumDownloadException('Download cancelado.');
  }
}

Future<void> _deleteFileIfPresent(File file) async {
  if (await file.exists()) await file.delete();
}

Future<void> _deleteDirectoryIfPresent(Directory directory) async {
  if (await directory.exists()) await directory.delete(recursive: true);
}
