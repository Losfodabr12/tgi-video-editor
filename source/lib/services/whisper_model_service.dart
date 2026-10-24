import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'app_component_paths.dart';
import 'whisper_runtime.dart';

const whisperModelCatalog = <WhisperModelInfo>[
  WhisperModelInfo(
    name: 'tiny',
    label: 'tiny',
    quality: 'Não medida',
    speed: 'Medir nesta máquina',
    sizeBytes: 77691713,
    sha256: 'BE07E048E1E599AD46341C8D2A135645097A538221678B7ACDD1B1919C6E1B21',
  ),
  WhisperModelInfo(
    name: 'base',
    label: 'base',
    quality: 'Não medida',
    speed: 'Medir nesta máquina',
    sizeBytes: 147951465,
    sha256: '60ED5BC3DD14EEA856493D334349B405782DDCAF0028D4B5DF4088345FBA2EFE',
  ),
  WhisperModelInfo(
    name: 'small',
    label: 'small',
    quality: 'Não medida',
    speed: 'Medir nesta máquina',
    sizeBytes: 487601967,
    sha256: '1BE3A9B2063867B937E64E2EC7483364A79917E157FA98C5D94B5C1FFFEA987B',
  ),
  WhisperModelInfo(
    name: 'medium',
    label: 'medium',
    quality: 'Não medida',
    speed: 'Medir nesta máquina',
    sizeBytes: 1533763059,
    sha256: '6C14D5ADEE5F86394037B4E4E8B59F1673B6CEE10E3CF0B11BBDBEE79C156208',
  ),
  WhisperModelInfo(
    name: 'large-v3-turbo-q5_0',
    label: 'Preciso (turbo)',
    quality: 'Não medida',
    speed: 'Medir nesta máquina',
    sizeBytes: 574041195,
    sha256: '394221709CD5AD1F40C46E6031CA61BCE88931E6E088C188294C6D5A55FFA7E2',
  ),
  WhisperModelInfo(
    name: 'large-v3-q5_0',
    label: 'large-v3-q5_0',
    quality: 'Não medida',
    speed: 'Medir nesta máquina',
    sizeBytes: 1081140203,
    sha256: 'D75795ECFF3F83B5FAA89D1900604AD8C780ABD5739FAE406DE19F23ECD98AD1',
  ),
  WhisperModelInfo(
    name: 'large-v3',
    label: 'Máxima (large-v3)',
    quality: 'Não medida',
    speed: 'Medir nesta máquina',
    sizeBytes: 3095033483,
    sha256: '64D182B440B98D5203C4F9BD541544D84C605196C4F7B845DFA11FB23594D1E2',
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
    'https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/$fileName',
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

  bool get hasExpectedSize => sizeBytes == info.sizeBytes;
}

typedef WhisperModelDownloadProgress = void Function(double progress);

class WhisperModelDownloadCancellationToken {
  bool _isCancelled = false;
  void Function()? _abort;

  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
    _abort?.call();
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
    this.downloadUriOverride,
  });

  final String? modelsDirectoryOverride;
  final Uri? downloadUriOverride;
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
    bool userInitiated = false,
    WhisperModelDownloadProgress? onProgress,
    WhisperModelDownloadCancellationToken? cancellationToken,
  }) async {
    if (!userInitiated) {
      throw StateError('Download somente por ação explícita no gerenciador.');
    }
    final expectedHash = info.sha256;
    if (expectedHash == null) {
      throw const FormatException('Modelo sem SHA-256 fixado.');
    }
    final output = File(await pathForModel(info));
    await output.parent.create(recursive: true);
    final temp = File('${output.path}.download');
    var start = await temp.exists() ? await temp.length() : 0;
    if (start > info.sizeBytes) {
      await temp.delete();
      start = 0;
    }
    if (start == info.sizeBytes) {
      if ((await sha256ForFile(temp.path)).toUpperCase() ==
          expectedHash.toUpperCase()) {
        if (await output.exists()) await output.delete();
        onProgress?.call(1);
        return temp.rename(output.path);
      }
      await temp.delete();
      start = 0;
    }
    final free = await freeSpaceForModelsDirectory();
    if (free == null || free < info.sizeBytes - start + 64 * 1024 * 1024) {
      throw FileSystemException(
        'Espaço livre insuficiente ou não verificável para o modelo.',
        output.parent.path,
      );
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    cancellationToken?._abort = () => client.close(force: true);
    try {
      _throwIfCancelled(info, cancellationToken);
      final request = await client.getUrl(
        downloadUriOverride ?? info.downloadUri,
      );
      if (start > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-');
      }
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode == 206) {
        final range = response.headers.value(HttpHeaders.contentRangeHeader);
        if (range == null ||
            !range.startsWith('bytes $start-') ||
            !range.endsWith('/${info.sizeBytes}')) {
          throw const HttpException(
            'Content-Range inválido; parcial preservado.',
          );
        }
      } else if (response.statusCode == 200) {
        start =
            0; // Server ignored Range: replace the partial, never append a full body.
      } else {
        throw HttpException('Download retornou HTTP ${response.statusCode}');
      }
      var downloaded = start;
      final sink = temp.openWrite(
        mode: start == 0 ? FileMode.write : FileMode.append,
      );
      try {
        await for (final chunk in response) {
          _throwIfCancelled(info, cancellationToken);
          downloaded += chunk.length;
          if (downloaded > info.sizeBytes) {
            throw const FormatException('Modelo excede tamanho fixado.');
          }
          sink.add(chunk);
          onProgress?.call(downloaded / info.sizeBytes);
        }
        _throwIfCancelled(info, cancellationToken);
      } finally {
        await sink.close();
      }
      if (await temp.length() != info.sizeBytes) {
        throw const HttpException(
          'Download incompleto; parcial preservado para retomar.',
        );
      }
      if ((await sha256ForFile(temp.path)).toUpperCase() !=
          expectedHash.toUpperCase()) {
        await temp.delete();
        throw const FormatException(
          'O modelo baixado falhou na validação SHA-256.',
        );
      }
      if (await output.exists()) await output.delete();
      await temp.rename(output.path);
      onProgress?.call(1);
      return output;
    } finally {
      cancellationToken?._abort = null;
      client.close(
        force: true,
      ); // Cancellation/network errors retain the resumable partial.
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
    int? gpuMemory;
    if (WhisperRuntime.backend.value == 'CUDA') {
      try {
        final result = await Process.run('nvidia-smi', [
          '--query-gpu=memory.total',
          '--format=csv,noheader,nounits',
        ]).timeout(const Duration(seconds: 4));
        gpuMemory = int.tryParse(
          result.stdout.toString().trim().split('\n').first,
        );
        if (gpuMemory != null) gpuMemory *= 1024 * 1024;
      } catch (_) {}
    }
    final recommendation = recommendationForMemory(
      await physicalMemoryBytes(),
      gpuMemoryBytes: gpuMemory,
    );
    return WhisperMachineRecommendation(
      info: recommendation.info,
      memoryBytes: recommendation.memoryBytes,
      reason:
          '${recommendation.reason} GPU Whisper: ${gpuMemory == null ? 'não verificada/indisponível' : '${gpuMemory ~/ (1024 * 1024)} MiB'}.',
    );
  }

  static WhisperMachineRecommendation recommendationForMemory(
    int? memoryBytes, {
    int? gpuMemoryBytes,
  }) {
    if (memoryBytes == null) {
      return WhisperMachineRecommendation(
        info: infoForModel('base') ?? whisperModelCatalog[1],
        reason: 'RAM não detectada. Comece pelo Base e meça o custo.',
      );
    }
    final gib = memoryBytes / (1024 * 1024 * 1024);
    if (gib < 8) {
      return WhisperMachineRecommendation(
        info: infoForModel('tiny') ?? whisperModelCatalog.first,
        memoryBytes: memoryBytes,
        reason:
            'Menos de 8 GiB de RAM. Tiny ocupa menos disco; meça antes de usar.',
      );
    }
    if (gib < 16) {
      return WhisperMachineRecommendation(
        info: infoForModel('base') ?? whisperModelCatalog[1],
        memoryBytes: memoryBytes,
        reason:
            'Entre 8 e 16 GiB de RAM. Base é uma sugestão de capacidade, sem WER medido.',
      );
    }
    if (gib >= 24 && (gpuMemoryBytes ?? 0) >= 8 * 1024 * 1024 * 1024) {
      return WhisperMachineRecommendation(
        info: infoForModel('large-v3-turbo-q5_0')!,
        memoryBytes: memoryBytes,
        reason:
            'RAM ≥24 GiB e GPU ativa ≥8 GiB: turbo q5 cabe na heurística; valide tempo e WER.',
      );
    }
    return WhisperMachineRecommendation(
      info: infoForModel('small') ?? whisperModelCatalog[2],
      memoryBytes: memoryBytes,
      reason:
          'RAM ≥16 GiB: Small é candidato para medição. O padrão depende da GPU; sua escolha manual prevalece.',
    );
  }

  Future<void> removeModel(String modelName) async {
    final info = infoForModel(modelName);
    if (info == null) {
      return;
    }
    final file = File(await pathForModel(info));
    if (await file.exists()) await file.delete();
    final partial = File('${file.path}.download');
    if (await partial.exists()) await partial.delete();
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
