import '../app/app_identity.dart';
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'app_component_paths.dart';

const whisperModelCatalog = <WhisperModelInfo>[
  WhisperModelInfo(
    name: 'tiny',
    label: 'Leve',
    quality: 'Basica',
    speed: 'Muito rapida',
    sizeBytes: 77 * 1024 * 1024,
  ),
  WhisperModelInfo(
    name: 'base',
    label: 'Equilibrado',
    quality: 'Boa',
    speed: 'Rapida',
    sizeBytes: 148 * 1024 * 1024,
  ),
  WhisperModelInfo(
    name: 'small',
    label: 'Melhor qualidade',
    quality: 'Alta',
    speed: 'Media',
    sizeBytes: 488 * 1024 * 1024,
    sha256: '1BE3A9B2063867B937E64E2EC7483364A79917E157FA98C5D94B5C1FFFEA987B',
  ),
  WhisperModelInfo(
    name: 'medium',
    label: 'Alta precisao',
    quality: 'Muito alta',
    speed: 'Lenta',
    sizeBytes: 1530 * 1024 * 1024,
  ),
];

class WhisperModelInfo {
  const WhisperModelInfo({
    required this.name,
    required this.label,
    required this.quality,
    required this.speed,
    required this.sizeBytes,
    this.sha256,
  });

  final String name;
  final String label;
  final String quality;
  final String speed;
  final int sizeBytes;
  final String? sha256;

  String get fileName => 'ggml-$name.bin';
  Uri get downloadUri => Uri.parse(
    'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$fileName',
  );
}

class InstalledWhisperModel {
  const InstalledWhisperModel({
    required this.info,
    required this.path,
    required this.sizeBytes,
  });

  final WhisperModelInfo info;
  final String path;
  final int sizeBytes;

  bool get hasExpectedSize => sizeBytes >= (info.sizeBytes * 0.75);
}

typedef WhisperModelDownloadProgress = void Function(double progress);

class WhisperModelDownloadCancellationToken {
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }
}

class WhisperModelDownloadCancelledException implements Exception {
  const WhisperModelDownloadCancelledException(this.modelName);

  final String modelName;

  @override
  String toString() => 'Download do modelo $modelName cancelado.';
}

class WhisperMachineRecommendation {
  const WhisperMachineRecommendation({
    required this.info,
    required this.reason,
    this.memoryBytes,
  });

  final WhisperModelInfo info;
  final String reason;
  final int? memoryBytes;
}

class WhisperModelService {
  const WhisperModelService({
    this.modelsDirectoryOverride,
    this.freeSpaceBytesOverride,
    this.physicalMemoryBytesOverride,
  });

  final String? modelsDirectoryOverride;
  final int? freeSpaceBytesOverride;
  final int? physicalMemoryBytesOverride;

  Future<String> modelsDirectoryPath() async {
    final explicit = modelsDirectoryOverride;
    if (explicit != null && explicit.trim().isNotEmpty) {
      return explicit;
    }
    final environmentPath = Platform.environment['TGI_WHISPER_MODELS_PATH'];
    if (environmentPath != null && environmentPath.trim().isNotEmpty) {
      return environmentPath;
    }
    return joinPlatformPath([tgiAppComponentsRoot(), 'whisper', 'models']);
  }

  Future<List<InstalledWhisperModel>> listInstalledModels() async {
    final directories = <Directory>[
      Directory(await modelsDirectoryPath()),
      if (modelsDirectoryOverride == null) ...[
        Directory(
          joinPlatformPath([
            File(Platform.resolvedExecutable).parent.path,
            'whisper',
            'models',
          ]),
        ),
        Directory(
          joinPlatformPath([
            Directory.current.path,
            'tools',
            'whisper',
            'models',
          ]),
        ),
      ],
    ];
    final installed = <InstalledWhisperModel>[];
    final seen = <String>{};
    for (final directory in directories) {
      if (!await directory.exists()) continue;
      await for (final entry in directory.list(followLinks: false)) {
        if (entry is! File) continue;
        final name = _modelNameFromPath(entry.path);
        final info = infoForModel(name);
        if (info == null || !seen.add(info.name)) continue;
        installed.add(
          InstalledWhisperModel(
            info: info,
            path: entry.path,
            sizeBytes: await entry.length(),
          ),
        );
      }
    }
    installed.sort((a, b) => a.info.name.compareTo(b.info.name));
    return installed;
  }

  Future<bool> isInstalled(String modelName) async {
    final info = infoForModel(modelName);
    if (info == null) {
      return false;
    }
    final models = await listInstalledModels();
    return models.any((model) => model.info.name == info.name);
  }

  Future<String> pathForModel(WhisperModelInfo info) async {
    return _joinParts([await modelsDirectoryPath(), info.fileName]);
  }

  Future<File> installModel(
    WhisperModelInfo info, {
    WhisperModelDownloadProgress? onProgress,
    WhisperModelDownloadCancellationToken? cancellationToken,
  }) async {
    requireOnlineIntegrations();
    final output = File(await pathForModel(info));
    await output.parent.create(recursive: true);
    final temp = File('${output.path}.download');
    if (await temp.exists()) {
      await temp.delete();
    }

    final client = HttpClient();
    try {
      _throwIfCancelled(info, cancellationToken);
      final request = await client.getUrl(info.downloadUri);
      _throwIfCancelled(info, cancellationToken);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Download retornou HTTP ${response.statusCode}',
          uri: info.downloadUri,
        );
      }
      final contentLength = response.contentLength;
      var downloaded = 0;
      final sink = temp.openWrite();
      try {
        await for (final chunk in response) {
          _throwIfCancelled(info, cancellationToken);
          downloaded += chunk.length;
          sink.add(chunk);
          if (contentLength > 0) {
            onProgress?.call(downloaded / contentLength);
          }
        }
        _throwIfCancelled(info, cancellationToken);
      } finally {
        await sink.close();
      }
      final expectedHash = info.sha256;
      if (expectedHash != null) {
        final actualHash = await sha256ForFile(temp.path);
        if (actualHash != expectedHash) {
          throw const FormatException(
            'O modelo baixado falhou na validacao SHA-256.',
          );
        }
      }
      if (await output.exists()) {
        await output.delete();
      }
      await temp.rename(output.path);
      onProgress?.call(1);
      return output;
    } finally {
      client.close(force: true);
      if (await temp.exists()) {
        try {
          await temp.delete();
        } catch (_) {}
      }
    }
  }

  Future<String> sha256ForFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('Nao foi possivel calcular SHA-256', path);
    }
    try {
      final digest = await sha256.bind(file.openRead()).first;
      return digest.toString().toUpperCase();
    } on Object {
      throw FileSystemException('Nao foi possivel calcular SHA-256', path);
    }
  }

  Future<Map<String, String>> hashInstalledModels() async {
    final models = await listInstalledModels();
    final hashes = <String, String>{};
    for (final model in models) {
      hashes[model.info.name] = await sha256ForFile(model.path);
    }
    return hashes;
  }

  Future<int?> freeSpaceForModelsDirectory() async {
    final override = freeSpaceBytesOverride;
    if (override != null) {
      return override;
    }
    final directory = Directory(await modelsDirectoryPath());
    await directory.create(recursive: true);
    if (Platform.isWindows) {
      final driveMatch = RegExp(r'^([A-Za-z]):').firstMatch(directory.path);
      final drive = driveMatch?.group(1);
      if (drive == null) {
        return null;
      }
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        "(Get-PSDrive -Name '$drive').Free",
      ], runInShell: true);
      if (result.exitCode != 0) {
        return null;
      }
      return int.tryParse('${result.stdout}'.trim());
    }

    final result = await Process.run('df', ['-k', directory.path]);
    if (result.exitCode != 0) {
      return null;
    }
    final lines = '${result.stdout}'
        .split(RegExp(r'[\r\n]+'))
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.length < 2) {
      return null;
    }
    final columns = lines.last.trim().split(RegExp(r'\s+'));
    if (columns.length < 4) {
      return null;
    }
    final availableKb = int.tryParse(columns[3]);
    return availableKb == null ? null : availableKb * 1024;
  }

  Future<int?> physicalMemoryBytes() async {
    final override = physicalMemoryBytesOverride;
    if (override != null) {
      return override;
    }
    if (!Platform.isWindows) {
      return null;
    }
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      r'(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory',
    ], runInShell: true);
    if (result.exitCode != 0) {
      return null;
    }
    return int.tryParse('${result.stdout}'.trim());
  }

  Future<WhisperMachineRecommendation> machineRecommendation() async {
    return recommendationForMemory(await physicalMemoryBytes());
  }

  static WhisperMachineRecommendation recommendationForMemory(
    int? memoryBytes,
  ) {
    if (memoryBytes == null) {
      return WhisperMachineRecommendation(
        info: infoForModel('base') ?? whisperModelCatalog[1],
        reason: 'RAM nao detectada. Base e o ponto de partida equilibrado.',
      );
    }
    final gib = memoryBytes / (1024 * 1024 * 1024);
    if (gib < 8) {
      return WhisperMachineRecommendation(
        info: infoForModel('tiny') ?? whisperModelCatalog.first,
        memoryBytes: memoryBytes,
        reason: 'Menos de 8 GB de RAM. Tiny reduz travamentos e demora.',
      );
    }
    if (gib < 16) {
      return WhisperMachineRecommendation(
        info: infoForModel('base') ?? whisperModelCatalog[1],
        memoryBytes: memoryBytes,
        reason: 'Entre 8 e 16 GB de RAM. Base equilibra tempo e qualidade.',
      );
    }
    return WhisperMachineRecommendation(
      info: infoForModel('small') ?? whisperModelCatalog[2],
      memoryBytes: memoryBytes,
      reason: '16 GB de RAM ou mais. Small melhora qualidade sem exagerar.',
    );
  }

  Future<void> removeModel(String modelName) async {
    final info = infoForModel(modelName);
    if (info == null) {
      return;
    }
    final file = File(await pathForModel(info));
    if (await file.exists()) {
      await file.delete();
    }
  }

  static WhisperModelInfo? infoForModel(String? modelName) {
    if (modelName == null) {
      return null;
    }
    final normalized = modelName.trim().toLowerCase();
    for (final info in whisperModelCatalog) {
      if (info.name == normalized) {
        return info;
      }
    }
    return null;
  }
}

void _throwIfCancelled(
  WhisperModelInfo info,
  WhisperModelDownloadCancellationToken? cancellationToken,
) {
  if (cancellationToken?.isCancelled ?? false) {
    throw WhisperModelDownloadCancelledException(info.name);
  }
}

String? _modelNameFromPath(String path) {
  final name = path.split(RegExp(r'[\\/]')).last;
  final match = RegExp(
    r'^ggml-(.+)\.bin$',
    caseSensitive: false,
  ).firstMatch(name);
  return match?.group(1)?.toLowerCase();
}

String _joinParts(List<String> parts) {
  return joinPlatformPath(parts);
}
