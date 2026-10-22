import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../domain/models/media_item.dart';
import 'app_component_paths.dart';
import 'ffmpeg_service.dart';
import 'whisper_runtime.dart';
import 'package:crypto/crypto.dart';

const defaultLocalWhisperModelName = 'base';
const localWhisperModelNames = <String>[
  'tiny',
  'base',
  'small',
  'medium',
  'large-v3',
];

const _defaultCaptionChunkDuration = Duration(minutes: 5);
const _defaultWhisperTimeout = Duration(minutes: 30);
const _audioPreparationProgressShare = 0.25;
const _transcriptionProgressShare = 0.70;
const _defaultMediumWhisperThreads = 2;

typedef AutoCaptionProgressCallback =
    void Function(double progress, String message);

enum SubtitleExportFormat {
  srt('srt'),
  vtt('vtt');

  const SubtitleExportFormat(this.extension);

  final String extension;
}

class CaptionWord {
  const CaptionWord({
    required this.start,
    required this.end,
    required this.text,
  });
  final Duration start, end;
  final String text;
  Map<String, Object> toJson() => {
    'start': _durationSeconds(start),
    'end': _durationSeconds(end),
    'text': text,
  };
}

class CaptionCue {
  const CaptionCue({
    required this.start,
    required this.end,
    required this.text,
    this.words = const [],
  });

  final Duration start;
  final Duration end;
  final String text;
  final List<CaptionWord> words;

  Duration get duration => end - start;

  Map<String, Object> toJson() => {
    'start': _durationSeconds(start),
    'end': _durationSeconds(end),
    'text': text,
    if (words.isNotEmpty) 'words': words.map((w) => w.toJson()).toList(),
  };
}

class AutoCaptionException implements Exception {
  const AutoCaptionException(this.message, [this.details]);

  final String message;
  final String? details;

  @override
  String toString() {
    final trimmedDetails = details?.trim();
    if (trimmedDetails == null || trimmedDetails.isEmpty) {
      return message;
    }
    return '$message\n$trimmedDetails';
  }
}

abstract class AutoCaptionService {
  Future<List<CaptionCue>> generateCaptionsForMedia(
    MediaItem mediaItem, {
    String? languageCode,
    String modelName = '',
    String vocabulary = '',
    bool vad = true,
    int maxCharsPerCue = 44,
    AutoCaptionProgressCallback? onProgress,
  });
}

class LocalWhisperAutoCaptionService implements AutoCaptionService {
  LocalWhisperAutoCaptionService({
    required this.ffmpegService,
    this.whisperExecutablePath,
    this.modelPath,
    this.chunkDuration = _defaultCaptionChunkDuration,
    Duration? processTimeout,
  }) : processTimeout = processTimeout ?? _resolveTimeoutFromEnvironment(),
       assert(chunkDuration >= Duration.zero);

  final FfmpegService ffmpegService;
  final String? whisperExecutablePath;
  final String? modelPath;
  final Duration chunkDuration;
  final Duration processTimeout;

  Future<void> _lastJob = Future<void>.value();
  bool _cancelled = false;
  Process? _activeWhisper;
  void cancel() {
    _cancelled = true;
    _activeWhisper?.kill();
    ffmpegService.cancelActiveTranscriptionPreparation();
  }

  void _checkCancelled() {
    if (_cancelled) {
      throw const AutoCaptionException('Transcrição cancelada.');
    }
  }

  @override
  Future<List<CaptionCue>> generateCaptionsForMedia(
    MediaItem mediaItem, {
    String? languageCode,
    String modelName = '',
    String vocabulary = '',
    bool vad = true,
    int maxCharsPerCue = 44,
    AutoCaptionProgressCallback? onProgress,
  }) {
    onProgress?.call(0, 'Aguardando processamento local');
    return _enqueue(
      () => _generateCaptionsForMedia(
        mediaItem,
        languageCode: languageCode,
        modelName: modelName,
        vocabulary: vocabulary,
        vad: vad,
        maxCharsPerCue: maxCharsPerCue,
        onProgress: onProgress,
      ),
    );
  }

  Future<List<CaptionCue>> _generateCaptionsForMedia(
    MediaItem mediaItem, {
    required String? languageCode,
    required String modelName,
    required String vocabulary,
    required bool vad,
    required int maxCharsPerCue,
    required AutoCaptionProgressCallback? onProgress,
  }) async {
    if (mediaItem.type != MediaType.video &&
        mediaItem.type != MediaType.audio) {
      throw const AutoCaptionException(
        'Selecione um video ou audio com fala para gerar legendas.',
      );
    }
    if (!mediaItem.hasAudio) {
      throw const AutoCaptionException(
        'O video selecionado nao tem trilha de audio.',
      );
    }

    _checkCancelled();
    final config = await _resolveConfig(modelName);
    _checkCancelled();
    final tempDir = await Directory.systemTemp.createTemp('tgi_auto_caption_');
    try {
      onProgress?.call(0, 'Preparando audio');
      final chunks = await ffmpegService.extractAudioChunksForTranscription(
        mediaItem.filePath,
        tempDir.path,
        chunkDuration: chunkDuration,
        onProgress: (progress) {
          onProgress?.call(
            progress * _audioPreparationProgressShare,
            'Extraindo audio',
          );
        },
      );
      if (chunks.isEmpty) {
        throw const AutoCaptionException(
          'Nenhum trecho de audio foi extraido do video.',
        );
      }

      final rawCues = <CaptionCue>[];
      for (var index = 0; index < chunks.length; index++) {
        _checkCancelled();
        final chunk = chunks[index];
        final baseProgress =
            _audioPreparationProgressShare +
            (index / chunks.length) * _transcriptionProgressShare;
        onProgress?.call(
          baseProgress,
          'Transcrevendo trecho ${index + 1}/${chunks.length}',
        );
        final chunkCues = await _transcribeChunk(
          chunk,
          config: config,
          languageCode: languageCode,
          vocabulary: vocabulary,
          vadModel: vad ? await _resolveVadModel() : null,
          outputDirectory: tempDir,
          chunkIndex: index,
          chunkCount: chunks.length,
          onProgress: onProgress,
        );
        rawCues.addAll(chunkCues);
        onProgress?.call(
          _audioPreparationProgressShare +
              ((index + 1) / chunks.length) * _transcriptionProgressShare,
          'Transcrevendo trecho ${index + 1}/${chunks.length}',
        );
      }

      final cues = segmentCaptionCues(rawCues, maxCharsPerCue: maxCharsPerCue);
      if (cues.isEmpty) {
        throw const AutoCaptionException(
          'Nenhuma fala foi detectada na transcricao.',
        );
      }
      onProgress?.call(1, 'Legendas geradas — ${WhisperRuntime.backend.value}');
      return cues;
    } finally {
      unawaited(
        tempDir.delete(recursive: true).then((_) {}).catchError((_) {}),
      );
    }
  }

  Future<List<CaptionCue>> _transcribeChunk(
    FfmpegAudioChunk chunk, {
    required _LocalWhisperConfig config,
    required String? languageCode,
    required String vocabulary,
    required String? vadModel,
    required Directory outputDirectory,
    required int chunkIndex,
    required int chunkCount,
    required AutoCaptionProgressCallback? onProgress,
  }) async {
    try {
      return await _runTranscribeChunk(
        chunk,
        config: config,
        languageCode: languageCode,
        vocabulary: vocabulary,
        vadModel: vadModel,
        outputDirectory: outputDirectory,
        chunkIndex: chunkIndex,
        chunkCount: chunkCount,
        onProgress: onProgress,
      );
    } catch (error) {
      _checkCancelled();
      if (config.executablePath == config.cpuExecutablePath) rethrow;
      WhisperRuntime.fallbackReason = error.toString();
      WhisperRuntime.backend.value = 'CPU (fallback CUDA)';
      final cpu = _LocalWhisperConfig(
        executablePath: config.cpuExecutablePath,
        cpuExecutablePath: config.cpuExecutablePath,
        modelPath: config.modelPath,
        modelName: config.modelName,
        threads: config.threads,
      );
      return _runTranscribeChunk(
        chunk,
        config: cpu,
        languageCode: languageCode,
        vocabulary: vocabulary,
        vadModel: vadModel,
        outputDirectory: outputDirectory,
        chunkIndex: chunkIndex,
        chunkCount: chunkCount,
        onProgress: onProgress,
      );
    }
  }

  Future<List<CaptionCue>> _runTranscribeChunk(
    FfmpegAudioChunk chunk, {
    required _LocalWhisperConfig config,
    required String? languageCode,
    required String vocabulary,
    required String? vadModel,
    required Directory outputDirectory,
    required int chunkIndex,
    required int chunkCount,
    required AutoCaptionProgressCallback? onProgress,
  }) async {
    final outputPrefix = _join(
      outputDirectory.path,
      'whisper_${chunkIndex.toString().padLeft(3, '0')}',
    );
    final arguments = <String>[
      '-m',
      config.modelPath,
      '-f',
      chunk.path,
      '-ojf',
      '-of',
      outputPrefix,
      '-pp',
      if (config.executablePath == config.cpuExecutablePath) '-ng',
    ];

    arguments.addAll(
      whisperSpeechArguments(vocabulary: vocabulary, vadModel: vadModel),
    );
    final normalizedLanguage = languageCode?.trim();
    if (normalizedLanguage != null && normalizedLanguage.isNotEmpty) {
      arguments.addAll(['-l', normalizedLanguage]);
    }
    if (config.threads != null) {
      arguments.addAll(['-t', config.threads.toString()]);
    }

    final output = StringBuffer();
    Process process;
    try {
      process = await Process.start(
        config.executablePath,
        arguments,
        runInShell: !_isAbsoluteWindowsPath(config.executablePath),
      );
    } on ProcessException catch (error) {
      throw AutoCaptionException(
        'Nao foi possivel iniciar o transcritor local.',
        '${error.message}\n${_localWhisperInstallHint(config.modelName)}',
      );
    }

    _activeWhisper = process;
    if (_cancelled) {
      process.kill();
    }

    void handleOutput(String chunkOutput) {
      output.write(chunkOutput);
      final normalizedLocalProgress = _parseWhisperProgressRatio(
        chunkOutput,
        chunk.duration,
      );
      if (normalizedLocalProgress == null) {
        return;
      }
      final overallProgress =
          _audioPreparationProgressShare +
          ((chunkIndex + normalizedLocalProgress) / chunkCount) *
              _transcriptionProgressShare;
      onProgress?.call(
        overallProgress.clamp(0.0, 0.98).toDouble(),
        'Transcrevendo trecho ${chunkIndex + 1}/$chunkCount',
      );
    }

    final stdoutDone = process.stdout
        .transform(systemEncoding.decoder)
        .listen(handleOutput)
        .asFuture<void>();
    final stderrDone = process.stderr
        .transform(systemEncoding.decoder)
        .listen(handleOutput)
        .asFuture<void>();

    final exitCode = await _waitForWhisperExitCode(process);
    _activeWhisper = null;
    _checkCancelled();
    await Future.wait([
      stdoutDone,
      stderrDone,
    ]).timeout(const Duration(seconds: 5), onTimeout: () => const []);

    if (exitCode != 0) {
      throw AutoCaptionException(
        'Falha ao transcrever com whisper.cpp local.',
        _lastOutputLines(output.toString()),
      );
    }

    final jsonFile = File('$outputPrefix.json');
    if (!await jsonFile.exists() || await jsonFile.length() == 0) {
      throw AutoCaptionException(
        'O transcritor local nao gerou a saida esperada.',
        _lastOutputLines(output.toString()),
      );
    }

    final gpuUsed = WhisperRuntime.usesCuda(output.toString());
    if (config.executablePath != config.cpuExecutablePath && !gpuUsed) {
      throw AutoCaptionException(
        'CUDA não foi ativado pelo engine.',
        _lastOutputLines(output.toString()),
      );
    }
    WhisperRuntime.backend.value = gpuUsed
        ? 'CUDA'
        : WhisperRuntime.fallbackReason == null
        ? 'CPU'
        : 'CPU (fallback CUDA)';
    final body = await jsonFile.readAsString();
    return _captionCuesFromWhisperJson(body, chunk);
  }

  Future<int> _waitForWhisperExitCode(Process process) async {
    try {
      return await process.exitCode.timeout(processTimeout);
    } on TimeoutException {
      process.kill();
      throw AutoCaptionException(
        'A transcricao local demorou demais e foi interrompida.',
        'Ajuste TGI_WHISPER_TIMEOUT_MINUTES ou use um modelo menor.',
      );
    }
  }

  Future<_LocalWhisperConfig> _resolveConfig(String requestedModelName) async {
    final modelName = _normalizeModelName(
      requestedModelName,
      Platform.environment['TGI_WHISPER_MODEL'],
    );
    final executable = await _resolveWhisperExecutable();
    await WhisperRuntime.verify(executable);
    final selected = await WhisperRuntime.preferExecutable(executable);
    final model = await _resolveWhisperModel(modelName);
    return _LocalWhisperConfig(
      executablePath: selected,
      cpuExecutablePath: executable,
      modelPath: model,
      modelName: modelName,
      threads: _resolveThreadCount(modelName),
    );
  }

  Future<String> _resolveWhisperExecutable() async {
    final explicitPath = _firstNonBlank(
      whisperExecutablePath,
      Platform.environment['TGI_WHISPER_CPP_PATH'],
      Platform.environment['TGI_WHISPER_CLI_PATH'],
    );
    if (explicitPath != null) {
      final resolved = await _resolveExecutableFromPath(explicitPath);
      if (resolved != null) {
        return resolved;
      }
      throw AutoCaptionException(
        'whisper.cpp local nao foi encontrado.',
        '$explicitPath\n${_localWhisperInstallHint(defaultLocalWhisperModelName)}',
      );
    }

    for (final candidate in _whisperExecutableCandidates()) {
      if (await File(candidate).exists()) {
        return candidate;
      }
    }

    throw AutoCaptionException(
      'whisper.cpp local nao foi encontrado.',
      _localWhisperInstallHint(defaultLocalWhisperModelName),
    );
  }

  Future<String> _resolveVadModel() async {
    for (final directory in _whisperModelDirectories()) {
      final path = _join(directory, 'ggml-silero-v5.1.2.bin');
      if (await File(path).exists()) {
        final hash = await TranscriptVadHash.sha(path);
        if (hash != TranscriptVadHash.expected) {
          throw const AutoCaptionException(
            'Modelo VAD falhou no SHA-256. Execute setup_tools.',
          );
        }
        return path;
      }
    }
    throw const AutoCaptionException(
      'Modelo VAD ausente. Execute setup_tools ou desligue VAD.',
    );
  }

  Future<String> _resolveWhisperModel(String modelName) async {
    final explicitPath = _firstNonBlank(
      modelPath,
      Platform.environment['TGI_WHISPER_MODEL_PATH'],
    );
    if (explicitPath != null) {
      if (await File(explicitPath).exists()) {
        return explicitPath;
      }
      throw AutoCaptionException(
        'Modelo Whisper local nao foi encontrado.',
        '$explicitPath\n${_localWhisperInstallHint(modelName)}',
      );
    }

    for (final candidate in _whisperModelCandidates(modelName)) {
      if (await File(candidate).exists()) {
        return candidate;
      }
    }

    final availableModels = await availableLocalWhisperModelNames();
    throw AutoCaptionException(
      'Modelo Whisper local nao foi encontrado.',
      _localWhisperInstallHint(modelName, availableModels: availableModels),
    );
  }

  Future<String?> _resolveExecutableFromPath(String path) async {
    final file = File(path);
    if (await file.exists()) {
      return file.path;
    }
    final directory = Directory(path);
    if (!await directory.exists()) {
      return null;
    }
    for (final name in _whisperExecutableNames) {
      final candidate = _join(directory.path, name);
      if (await File(candidate).exists()) {
        return candidate;
      }
    }
    final binDirectory = Directory(_join(directory.path, 'bin'));
    if (await binDirectory.exists()) {
      for (final name in _whisperExecutableNames) {
        final candidate = _join(binDirectory.path, name);
        if (await File(candidate).exists()) {
          return candidate;
        }
      }
    }
    return null;
  }

  Future<T> _enqueue<T>(Future<T> Function() job) {
    final previousJob = _lastJob.catchError((_) {});
    final completer = Completer<void>();
    _lastJob = completer.future;
    return previousJob.then((_) async {
      try {
        return await job();
      } finally {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    });
  }
}

Future<List<String>> availableLocalWhisperModelNames() async {
  final found = <String>{};
  final explicitModelPath = Platform.environment['TGI_WHISPER_MODEL_PATH']
      ?.trim();
  if (explicitModelPath != null &&
      explicitModelPath.isNotEmpty &&
      await File(explicitModelPath).exists()) {
    found.add(
      _modelNameFromPath(explicitModelPath) ??
          _normalizeModelName('', Platform.environment['TGI_WHISPER_MODEL']),
    );
  }

  for (final directoryPath in _whisperModelDirectories()) {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) {
      continue;
    }
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! File) {
        continue;
      }
      final modelName = _modelNameFromPath(entry.path);
      if (modelName != null) {
        found.add(modelName);
      }
    }
  }

  return _orderWhisperModelNames(found);
}

class _LocalWhisperConfig {
  const _LocalWhisperConfig({
    required this.executablePath,
    required this.cpuExecutablePath,
    required this.modelPath,
    required this.modelName,
    required this.threads,
  });

  final String executablePath;
  final String cpuExecutablePath;
  final String modelPath;
  final String modelName;
  final int? threads;
}

List<CaptionCue> segmentCaptionCues(
  List<CaptionCue> segments, {
  int maxCharsPerCue = 44,
}) {
  final words = segments.expand((c) => c.words).toList();
  if (words.isNotEmpty) {
    if (segments.any((c) => c.words.isEmpty)) {
      throw const AutoCaptionException(
        'Tempos incompletos em uma fala. Revise a transcrição antes de segmentar.',
      );
    }
    return timedCaptionCues(words, maxCharsPerCue: maxCharsPerCue);
  }
  return segments; // Legacy envelopes: never invent word timestamps.
}

/// Every partition boundary is a real word boundary, including the final cue.
List<CaptionCue> timedCaptionCues(
  List<CaptionWord> input, {
  int maxCharsPerCue = 44,
  Duration minimumDuration = Duration.zero,
}) {
  final seen = <String>{};
  final words =
      input
          .where(
            (w) =>
                w.end >= w.start &&
                seen.add(
                  '${w.start.inMicroseconds}|${w.end.inMicroseconds}|${w.text}',
                ),
          )
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));
  final limit = maxCharsPerCue.clamp(24, 60);
  final cost = List<double>.filled(words.length + 1, double.infinity);
  final next = List<int>.filled(words.length, -1);
  cost[words.length] = 0;
  for (var i = words.length - 1; i >= 0; i--) {
    var length = 0;
    for (var j = i; j < words.length; j++) {
      length += words[j].text.trim().length + (j == i ? 0 : 1);
      if (length > limit) break;
      if (words[j].end - words[i].start < minimumDuration) continue;
      final pause = j + 1 < words.length
          ? words[j + 1].start - words[j].end
          : Duration.zero;
      final boundary =
          RegExp(r'[.!?]$').hasMatch(words[j].text) ||
          pause > const Duration(milliseconds: 500);
      final score =
          cost[j + 1] + 1000 + (limit - length) * 0.01 - (boundary ? 2 : 0);
      if (score < cost[i]) {
        cost[i] = score;
        next[i] = j + 1;
      }
    }
  }
  final result = <CaptionCue>[];
  for (var i = 0; i < words.length;) {
    final end = next[i];
    if (end < 0) {
      throw const AutoCaptionException(
        'Não é possível alinhar a legenda com os limites de texto e duração. Revise este trecho.',
      );
    }
    final group = words.sublist(i, end);
    result.add(
      CaptionCue(
        start: group.first.start,
        end: group.last.end,
        text: _wrapCaptionText(
          group.map((w) => w.text.trim()).join(' '),
          limit.toInt(),
        ),
        words: group,
      ),
    );
    i = end;
  }
  return result;
}

/// Repartition timed words; legacy final short envelopes merge backward.
List<CaptionCue> minimumCaptionCues(List<CaptionCue> input) {
  final words = input.expand((c) => c.words).toList();
  if (words.isNotEmpty) {
    return timedCaptionCues(words, minimumDuration: const Duration(seconds: 1));
  }
  final result = <CaptionCue>[];
  for (var i = 0; i < input.length; i++) {
    var cue = input[i];
    while (cue.duration < const Duration(seconds: 1) && i + 1 < input.length) {
      final other = input[++i];
      cue = CaptionCue(
        start: cue.start,
        end: other.end,
        text: '${cue.text} ${other.text}',
      );
    }
    if (cue.duration < const Duration(seconds: 1) && result.isNotEmpty) {
      final previous = result.removeLast();
      cue = CaptionCue(
        start: previous.start,
        end: cue.end,
        text: '${previous.text} ${cue.text}',
      );
    }
    if (cue.duration < const Duration(seconds: 1)) {
      throw const AutoCaptionException(
        'Fala isolada abaixo de 1s: revise o agrupamento.',
      );
    }
    result.add(cue);
  }
  return result;
}

String formatSubtitleCues(List<CaptionCue> cues, SubtitleExportFormat format) {
  final normalized =
      cues
          .where((cue) => cue.end > cue.start && cue.text.trim().isNotEmpty)
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));

  switch (format) {
    case SubtitleExportFormat.srt:
      final buffer = StringBuffer();
      for (var index = 0; index < normalized.length; index++) {
        final cue = normalized[index];
        buffer
          ..writeln(index + 1)
          ..writeln(
            '${_formatSrtTime(cue.start)} --> ${_formatSrtTime(cue.end)}',
          )
          ..writeln(cue.text.trim())
          ..writeln();
      }
      return buffer.toString();
    case SubtitleExportFormat.vtt:
      final buffer = StringBuffer('WEBVTT\n\n');
      for (final cue in normalized) {
        buffer
          ..writeln(
            '${_formatVttTime(cue.start)} --> ${_formatVttTime(cue.end)}',
          )
          ..writeln(cue.text.trim().replaceAll('-->', '->'))
          ..writeln();
      }
      return buffer.toString();
  }
}

String _wrapCaptionText(String text, int maxCharsPerCue) {
  final maxLineChars = (maxCharsPerCue / 2).ceil();
  if (text.length <= maxLineChars) {
    return text;
  }
  final words = text.split(' ');
  final lines = <String>[];
  final current = <String>[];
  var currentLength = 0;

  for (final word in words) {
    final projectedLength = current.isEmpty
        ? word.length
        : currentLength + 1 + word.length;
    if (current.isNotEmpty && projectedLength > maxLineChars) {
      lines.add(current.join(' '));
      current
        ..clear()
        ..add(word);
      currentLength = word.length;
    } else {
      current.add(word);
      currentLength = projectedLength;
    }
  }
  if (current.isNotEmpty) {
    lines.add(current.join(' '));
  }
  if (lines.length <= 2) {
    return lines.join('\n');
  }
  return '${lines.first}\n${lines.sublist(1).join(' ')}';
}

List<CaptionCue> _captionCuesFromWhisperJson(
  String body,
  FfmpegAudioChunk chunk,
) {
  return parseWhisperCaptionCues(body, offset: chunk.offset);
}

/// Preserves actual word/token timestamps; never estimates word times from text.
List<CaptionCue> parseWhisperCaptionCues(
  String body, {
  Duration offset = Duration.zero,
}) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw const AutoCaptionException(
      'Resposta inesperada do transcritor local.',
    );
  }

  final entries = _whisperSegmentEntries(decoded);
  if (entries.isNotEmpty) {
    final cues = <CaptionCue>[];
    for (final entry in entries) {
      final start = _whisperSegmentStart(entry);
      final end = _whisperSegmentEnd(entry);
      final text = _normalizeCaptionText(entry['text']);
      if (start == null ||
          end == null ||
          end <= start ||
          text == null ||
          text.isEmpty) {
        continue;
      }
      cues.add(
        CaptionCue(
          start: offset + start,
          end: offset + end,
          text: text,
          words: _whisperWords(entry, offset),
        ),
      );
    }
    return cues;
  }

  final text = _normalizeCaptionText(decoded['text']);
  if (text == null || text.isEmpty) {
    return const [];
  }
  throw const AutoCaptionException(
    'O transcritor local nao retornou timestamps de fala.',
    'Gere novamente as legendas; se persistir, atualize o whisper.cpp local.',
  );
}

List<CaptionWord> _whisperWords(Map<String, dynamic> entry, Duration offset) {
  final rawWords = entry['words'];
  if (rawWords is List) {
    return List.unmodifiable([
      for (final raw in rawWords.whereType<Map<String, dynamic>>())
        if (_whisperSegmentStart(raw) case final Duration start)
          if (_whisperSegmentEnd(raw) case final Duration end)
            if (end > start && (raw['word'] ?? raw['text']) is String)
              CaptionWord(
                start: offset + start,
                end: offset + end,
                text: (raw['word'] ?? raw['text']) as String,
              ),
    ]);
  }
  final tokens = entry['tokens'];
  if (tokens is! List) return const [];
  final words = <CaptionWord>[];
  Duration? start, end;
  var text = '';
  void flush() {
    if (start != null &&
        end != null &&
        end! >= start! &&
        text.trim().isNotEmpty) {
      words.add(
        CaptionWord(
          start: offset + start!,
          end: offset + end!,
          text: text.trim(),
        ),
      );
    }
    text = '';
    start = null;
    end = null;
  }

  for (final raw in tokens.whereType<Map<String, dynamic>>()) {
    final part = raw['text'];
    if (part is! String || part.startsWith('[_') || part.startsWith('<|')) {
      continue;
    }
    final a = _whisperSegmentStart(raw), b = _whisperSegmentEnd(raw);
    // Incomplete timing must fall back to the cue envelope, not false word precision.
    if (a == null || b == null || b < a) return const [];
    if (part.startsWith(RegExp(r'\s')) && text.isNotEmpty) flush();
    start ??= a;
    end = b;
    text += part;
  }
  flush();
  return List.unmodifiable(words);
}

List<Map<String, dynamic>> _whisperSegmentEntries(Map<String, dynamic> json) {
  final transcription = json['transcription'];
  if (transcription is List) {
    return [
      for (final item in transcription)
        if (item is Map<String, dynamic>) item,
    ];
  }

  final segments = json['segments'];
  if (segments is List) {
    return [
      for (final item in segments)
        if (item is Map<String, dynamic>) item,
    ];
  }
  return const [];
}

Duration? _whisperSegmentStart(Map<String, dynamic> segment) {
  return _durationFromTimestampMap(segment['timestamps'], 'from') ??
      _durationFromOffsetMap(segment['offsets'], 'from') ??
      _durationFromWhisperValue(segment['start']) ??
      _durationFromWhisperValue(segment['start_time']);
}

Duration? _whisperSegmentEnd(Map<String, dynamic> segment) {
  return _durationFromTimestampMap(segment['timestamps'], 'to') ??
      _durationFromOffsetMap(segment['offsets'], 'to') ??
      _durationFromWhisperValue(segment['end']) ??
      _durationFromWhisperValue(segment['end_time']);
}

Duration? _durationFromTimestampMap(Object? value, String key) {
  if (value is! Map<String, dynamic>) {
    return null;
  }
  return _durationFromTimestamp(value[key]);
}

Duration? _durationFromOffsetMap(Object? value, String key) {
  if (value is! Map<String, dynamic>) {
    return null;
  }
  return _durationFromMilliseconds(value[key]);
}

Duration? _durationFromWhisperValue(Object? value) {
  return _durationFromTimestamp(value) ?? _durationFromSeconds(value);
}

Duration? _durationFromTimestamp(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final seconds = double.tryParse(trimmed.replaceAll(',', '.'));
  if (seconds != null) {
    return _durationFromSeconds(seconds);
  }

  final match = RegExp(
    r'^(?:(\d+):)?(\d{1,2}):(\d{1,2})(?:[\.,](\d{1,3}))?$',
  ).firstMatch(trimmed);
  if (match == null) {
    return null;
  }

  final hours = int.tryParse(match.group(1) ?? '0');
  final minutes = int.tryParse(match.group(2) ?? '');
  final parsedSeconds = int.tryParse(match.group(3) ?? '');
  final milliseconds = int.tryParse((match.group(4) ?? '0').padRight(3, '0'));
  if (hours == null ||
      minutes == null ||
      parsedSeconds == null ||
      milliseconds == null) {
    return null;
  }
  return Duration(
    hours: hours,
    minutes: minutes,
    seconds: parsedSeconds,
    milliseconds: milliseconds,
  );
}

Duration? _durationFromSeconds(Object? value) {
  if (value is! num) {
    return null;
  }
  final seconds = value.toDouble();
  if (seconds.isNaN || seconds.isInfinite || seconds < 0) {
    return null;
  }
  return Duration(milliseconds: (seconds * 1000).round());
}

Duration? _durationFromMilliseconds(Object? value) {
  if (value is! num) {
    return null;
  }
  final milliseconds = value.toDouble();
  if (milliseconds.isNaN || milliseconds.isInfinite || milliseconds < 0) {
    return null;
  }
  return Duration(milliseconds: milliseconds.round());
}

double? _parseWhisperProgressRatio(String value, Duration chunkDuration) {
  final percentageMatches = RegExp(
    r'progress\s*=\s*(\d{1,3})\s*%',
    caseSensitive: false,
  ).allMatches(value);
  final lastPercentage = percentageMatches.isEmpty
      ? null
      : percentageMatches.last;
  if (lastPercentage != null) {
    final percentage = int.tryParse(lastPercentage.group(1) ?? '');
    if (percentage != null) {
      return (percentage / 100).clamp(0.0, 1.0).toDouble();
    }
  }

  if (chunkDuration <= Duration.zero) {
    return null;
  }
  final matches = RegExp(
    r'\[\s*(\d{1,2}:\d{2}:\d{2}[\.,]\d{1,3})\s+-->\s+'
    r'(\d{1,2}:\d{2}:\d{2}[\.,]\d{1,3})\s*\]',
  ).allMatches(value);
  final last = matches.isEmpty ? null : matches.last;
  if (last == null) {
    return null;
  }
  final progress = _durationFromTimestamp(last.group(2));
  if (progress == null) {
    return null;
  }
  return (progress.inMicroseconds / chunkDuration.inMicroseconds)
      .clamp(0.0, 1.0)
      .toDouble();
}

String? _normalizeCaptionText(Object? value) {
  if (value is! String) {
    return null;
  }
  final text = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  return text.isEmpty ? null : text;
}

String _formatSrtTime(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  final milliseconds = duration.inMilliseconds.remainder(1000);
  return '${_two(hours)}:${_two(minutes)}:${_two(seconds)},${_three(milliseconds)}';
}

String _formatVttTime(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  final milliseconds = duration.inMilliseconds.remainder(1000);
  return '${_two(hours)}:${_two(minutes)}:${_two(seconds)}.${_three(milliseconds)}';
}

String _two(int value) => value.toString().padLeft(2, '0');

String _three(int value) => value.toString().padLeft(3, '0');

double _durationSeconds(Duration duration) {
  return duration.inMicroseconds / Duration.microsecondsPerSecond;
}

String _normalizeModelName(String requested, String? environmentValue) {
  final trimmedRequested = requested.trim();
  if (trimmedRequested.isNotEmpty) {
    return trimmedRequested;
  }
  final trimmedEnvironment = environmentValue?.trim();
  if (trimmedEnvironment != null && trimmedEnvironment.isNotEmpty) {
    return trimmedEnvironment;
  }
  return defaultLocalWhisperModelName;
}

int? _resolveThreadCount(String modelName) {
  final rawValue = Platform.environment['TGI_WHISPER_THREADS']?.trim();
  if (rawValue == null || rawValue.isEmpty) {
    return modelName == 'medium' ? _defaultMediumWhisperThreads : null;
  }
  final value = int.tryParse(rawValue);
  if (value == null || value <= 0) {
    return null;
  }
  return value;
}

Duration _resolveTimeoutFromEnvironment() {
  final rawValue = Platform.environment['TGI_WHISPER_TIMEOUT_MINUTES']?.trim();
  if (rawValue == null || rawValue.isEmpty) {
    return _defaultWhisperTimeout;
  }
  final minutes = int.tryParse(rawValue);
  if (minutes == null || minutes <= 0) {
    return _defaultWhisperTimeout;
  }
  return Duration(minutes: minutes);
}

String? _firstNonBlank(String? first, String? second, [String? third]) {
  for (final value in [first, second, third]) {
    final trimmed = value?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return null;
}

Iterable<String> _whisperExecutableCandidates() sync* {
  for (final root in _candidateRootDirectories()) {
    for (final relative in _whisperExecutableRelativePaths) {
      yield _joinParts([root, ...relative]);
    }
  }
}

Iterable<String> _whisperModelCandidates(String modelName) sync* {
  yield joinPlatformPath([
    tgiAppComponentsRoot(),
    'whisper',
    'models',
    'ggml-$modelName.bin',
  ]);
  for (final root in _candidateRootDirectories()) {
    for (final relative in _whisperModelRelativeDirectories) {
      yield _joinParts([root, ...relative, 'ggml-$modelName.bin']);
    }
  }
}

Iterable<String> _whisperModelDirectories() sync* {
  yield joinPlatformPath([tgiAppComponentsRoot(), 'whisper', 'models']);
  for (final root in _candidateRootDirectories()) {
    for (final relative in _whisperModelRelativeDirectories) {
      yield _joinParts([root, ...relative]);
    }
  }
}

List<String> _candidateRootDirectories() {
  final roots = <String>[];
  void add(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty || roots.contains(trimmed)) {
      return;
    }
    roots.add(trimmed);
  }

  void addWithAncestors(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return;
    }
    var directory = Directory(trimmed);
    for (var depth = 0; depth < 8; depth++) {
      add(directory.path);
      final parentPath = directory.parent.path;
      if (parentPath == directory.path) {
        break;
      }
      directory = Directory(parentPath);
    }
  }

  addWithAncestors(File(Platform.resolvedExecutable).parent.path);
  addWithAncestors(Directory.current.path);
  final scriptPath = Platform.script.toFilePath(windows: Platform.isWindows);
  if (scriptPath.isNotEmpty) {
    addWithAncestors(File(scriptPath).parent.path);
  }
  return roots;
}

const _whisperExecutableNames = <String>[
  'whisper-cli.exe',
  'whisper.exe',
  'main.exe',
  'whisper-cli',
  'whisper',
  'main',
];

const _whisperExecutableRelativePaths = <List<String>>[
  ['whisper', 'bin', 'whisper-cli.exe'],
  ['whisper', 'whisper-cli.exe'],
  ['tools', 'whisper', 'bin', 'whisper-cli.exe'],
  ['tools', 'whisper', 'whisper-cli.exe'],
  ['whisper.cpp', 'build', 'bin', 'Release', 'whisper-cli.exe'],
  ['whisper.cpp', 'build', 'bin', 'whisper-cli.exe'],
  ['whisper', 'bin', 'main.exe'],
  ['tools', 'whisper', 'bin', 'main.exe'],
];

const _whisperModelRelativeDirectories = <List<String>>[
  ['whisper', 'models'],
  ['tools', 'whisper', 'models'],
  ['whisper.cpp', 'models'],
];

String _localWhisperInstallHint(
  String modelName, {
  List<String> availableModels = const [],
}) {
  final availableText = availableModels.isEmpty
      ? ''
      : ' Modelos encontrados: ${availableModels.join(', ')}.';
  return 'Coloque whisper-cli.exe em whisper\\bin e ggml-$modelName.bin em '
      'whisper\\models, ou configure TGI_WHISPER_CPP_PATH e '
      'TGI_WHISPER_MODEL_PATH.$availableText';
}

List<String> _orderWhisperModelNames(Iterable<String> names) {
  final remaining = names.toSet();
  final ordered = <String>[
    for (final name in localWhisperModelNames)
      if (remaining.remove(name)) name,
  ];
  ordered.addAll(remaining.toList()..sort());
  return ordered;
}

String? _modelNameFromPath(String path) {
  final match = RegExp(
    r'^ggml-(.+)\.bin$',
    caseSensitive: false,
  ).firstMatch(_fileName(path));
  return match?.group(1);
}

String _fileName(String path) {
  final normalized = path.replaceAll(r'\', '/');
  final index = normalized.lastIndexOf('/');
  return index == -1 ? normalized : normalized.substring(index + 1);
}

String _join(String first, String second) {
  return '$first${Platform.pathSeparator}$second';
}

String _joinParts(List<String> parts) {
  return parts.where((part) => part.isNotEmpty).join(Platform.pathSeparator);
}

bool _isAbsoluteWindowsPath(String value) {
  if (!Platform.isWindows) {
    return value.startsWith('/');
  }
  return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value) || value.startsWith(r'\\');
}

String _lastOutputLines(String value, {int maxLines = 18}) {
  final lines = LineSplitter.split(value.trim()).where((line) {
    return line.trim().isNotEmpty;
  }).toList();
  if (lines.isEmpty) {
    return '';
  }
  return lines.skip(math.max(0, lines.length - maxLines)).join('\n');
}

class TranscriptVadHash {
  static const expected =
      '29940d98d42b91fbd05ce489f3ecf7c72f0a42f027e4875919a28fb4c04ea2cf';
  static Future<String> sha(String path) async =>
      (await sha256.bind(File(path).openRead()).first).toString();
}

List<String> whisperSpeechArguments({
  String vocabulary = '',
  String? vadModel,
}) {
  if (vocabulary.length > 2000) {
    throw const AutoCaptionException('Vocabulário: máximo de 2000 caracteres.');
  }
  return [
    if (vocabulary.trim().isNotEmpty) ...['--prompt', vocabulary.trim()],
    if (vadModel != null) ...['--vad', '-vm', vadModel],
  ];
}
