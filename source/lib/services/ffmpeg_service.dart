import 'package:image/image.dart' as image;
import 'media_disk_cache.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart';

import '../domain/models/clip.dart';
import '../domain/models/media_item.dart';
import '../domain/models/project.dart';
import '../domain/models/track.dart';
import 'ffmpeg_export_settings.dart';
import 'editor_font_service.dart';
import 'preview_proxy_cache_service.dart';

export 'ffmpeg_export_settings.dart';
export 'ffmpeg_service_models.dart';
import 'ffmpeg_service_models.dart';
import 'ffmpeg_filtergraph_builder.dart';
import 'ffmpeg_executor.dart';
import 'ffmpeg_progress_parser.dart';
part 'ffmpeg_editor_export.dart';

class FfmpegService {
  FfmpegService({
    PreviewProxyCacheService? previewProxyCacheService,
    MediaDiskCache? thumbnailCache,
  }) : previewProxyCacheService =
           previewProxyCacheService ?? PreviewProxyCacheService.instance,
       thumbnailCache = thumbnailCache ?? MediaDiskCache();

  final MediaDiskCache thumbnailCache;
  int thumbnailCacheHits = 0;
  final PreviewProxyCacheService previewProxyCacheService;
  final _executor = const FfmpegExecutor();
  final _progressParser = const FfmpegProgressParser();
  bool get _usesEmbeddedMobileFfmpeg => _executor.usesEmbeddedMobileFfmpeg;
  Future<MediaProcessHandle> _startMediaProcess(
    String executable,
    List<String> arguments,
  ) => _executor.start(executable, arguments);
  Future<ProcessResult> _runTool(String executable, List<String> arguments) =>
      _executor.run(executable, arguments);
  Duration? _parseFfmpegProgressTime(String output) =>
      _progressParser.parse(output);

  FfmpegExportCommand buildExportCommand(
    TgiProject project,
    String outputPath, {
    FfmpegExportSettings settings = FfmpegExportSettings.defaultSettings,
    String? drawTextDirectoryPath,
  }) {
    final command =
        FfmpegFiltergraphBuilder(
          fontPath: EditorFontService.filePath,
          pathSeparator: Platform.pathSeparator,
        ).buildExportCommand(
          project,
          outputPath,
          settings: settings,
          drawTextDirectoryPath: drawTextDirectoryPath,
        );
    _executor.writeTextInputs(command.textFiles);
    return command;
  }

  FfmpegToolchain? _cachedToolchain;
  FfmpegCommandProcess? _activeExportProcess;
  bool _exportInProgress = false;
  String? lastExportNotice;
  FfmpegVideoEncoder lastExportEncoder = FfmpegVideoEncoder.software;
  final Map<FfmpegVideoEncoder, bool> _encoderAvailability = {};
  MediaProcessHandle? _activePreviewProxyProcess;
  bool _exportCancellationRequested = false;
  bool _previewProxyCancellationRequested = false;

  MediaProcessHandle? _transcriptionPreparation;
  bool _transcriptionPreparationCancelled = false;
  void cancelActiveTranscriptionPreparation() {
    _transcriptionPreparationCancelled = true;
    final active = _transcriptionPreparation;
    if (active != null) {
      unawaited(active.cancel());
    }
  }

  Future<ProcessResult> _runTranscriptionPreparation(
    String executable,
    List<String> arguments,
  ) async {
    if (_transcriptionPreparationCancelled) {
      throw const FfmpegProcessException('Transcrição cancelada.');
    }
    final process = await _startMediaProcess(executable, arguments);
    _transcriptionPreparation = process;
    if (_transcriptionPreparationCancelled) {
      await process.cancel();
    }
    try {
      final stdout = process.stdout.transform(systemEncoding.decoder).join();
      final stderr = process.stderr.transform(systemEncoding.decoder).join();
      final code = await process.exitCode;
      return ProcessResult(process.pid, code, await stdout, await stderr);
    } finally {
      _transcriptionPreparation = null;
    }
  }

  bool cancelActiveExport() {
    _exportCancellationRequested = true;
    final process = _activeExportProcess;
    if (process == null) return false;
    unawaited(process.cancel());
    return true;
  }

  bool cancelActivePreviewProxy() {
    _previewProxyCancellationRequested = true;
    final process = _activePreviewProxyProcess;
    if (process == null) return false;
    unawaited(process.cancel());
    return true;
  }

  Future<FfmpegCommandProcess> startCommand(
    List<String> arguments, {
    bool useFfprobe = false,
  }) async {
    final toolchain = await resolveToolchain();
    final executable = useFfprobe
        ? toolchain.ffprobePath
        : toolchain.ffmpegPath;
    return FfmpegCommandProcess(
      await _startMediaProcess(executable, arguments),
    );
  }

  Future<ProcessResult> runCommand(
    List<String> arguments, {
    bool useFfprobe = false,
  }) async {
    final toolchain = await resolveToolchain();
    return _runTool(
      useFfprobe ? toolchain.ffprobePath : toolchain.ffmpegPath,
      arguments,
    );
  }

  FfmpegPreviewProxyCommand buildPreviewProxyCommand(
    MediaItem item,
    String outputPath,
  ) {
    if (item.type != MediaType.video) {
      throw const FfmpegProcessException(
        'Proxy de preview so pode ser criado para videos.',
      );
    }

    return FfmpegPreviewProxyCommand(
      arguments: [
        '-y',
        '-hide_banner',
        '-nostdin',
        '-threads',
        '2',
        '-i',
        item.filePath,
        '-map',
        '0:v:0',
        '-map',
        '0:a?',
        '-vf',
        'scale=960:540:force_original_aspect_ratio=decrease:force_divisible_by=2,'
            'fps=30,setsar=1',
        '-c:v',
        'libx264',
        '-pix_fmt',
        'yuv420p',
        '-preset',
        'ultrafast',
        '-crf',
        '30',
        '-threads',
        '2',
        '-c:a',
        'aac',
        '-b:a',
        '96k',
        '-ac',
        '2',
        '-movflags',
        '+faststart',
        outputPath,
      ],
      outputPath: outputPath,
      totalDuration: item.duration,
    );
  }

  Future<String> createPreviewProxy(
    MediaItem item, {
    FfmpegPreviewProxyProgressCallback? onProgress,
  }) async {
    _previewProxyCancellationRequested = false;
    final sourceFile = File(item.filePath);
    if (!await sourceFile.exists()) {
      throw FfmpegProcessException(
        'Arquivo de origem nao encontrado: ${item.filePath}',
      );
    }

    final sourceStat = await sourceFile.stat();
    final outputPath = await previewProxyCacheService.proxyPathFor(item);
    if (await previewProxyCacheService.isReusable(outputPath, sourceStat)) {
      onProgress?.call(1);
      return outputPath;
    }

    final temporaryPath =
        '$outputPath.${DateTime.now().microsecondsSinceEpoch}.tmp.mp4';
    final command = buildPreviewProxyCommand(item, temporaryPath);
    final outputFile = File(temporaryPath);
    await outputFile.parent.create(recursive: true);

    final toolchain = await resolveToolchain();
    final process = await _startMediaProcess(
      toolchain.ffmpegPath,
      command.arguments,
    );
    _activePreviewProxyProcess = process;
    if (_previewProxyCancellationRequested) {
      unawaited(process.cancel());
    }

    onProgress?.call(0);
    final stderrBuffer = StringBuffer();
    var lastProgress = 0.0;
    final stderrDone = process.stderr.transform(systemEncoding.decoder).listen((
      chunk,
    ) {
      stderrBuffer.write(chunk);
      final progressTime = _parseFfmpegProgressTime(chunk);
      if (progressTime == null || command.totalDuration <= Duration.zero) {
        return;
      }
      final progress =
          progressTime.inMilliseconds / command.totalDuration.inMilliseconds;
      final clamped = progress.clamp(0.0, 0.99);
      if (clamped >= lastProgress + 0.01 || clamped > 0.98) {
        lastProgress = clamped;
        onProgress?.call(clamped);
      }
    }).asFuture<void>();
    final stdoutDone = process.stdout.drain<void>();

    try {
      final exitCode = await process.exitCode;
      await stdoutDone;
      await stderrDone;

      if (_previewProxyCancellationRequested) {
        if (await outputFile.exists()) {
          await outputFile.delete();
        }
        throw const FfmpegProcessException('Otimizacao do preview cancelada.');
      }

      if (exitCode != 0 ||
          !await outputFile.exists() ||
          await outputFile.length() == 0) {
        throw FfmpegProcessException(
          'Nao foi possivel otimizar o preview.',
          _lastOutputLines(stderrBuffer.toString()),
        );
      }

      await MediaDiskCache.publish(outputFile, File(outputPath));
      onProgress?.call(1);
      return outputPath;
    } finally {
      if (await outputFile.exists()) await outputFile.delete();
      if (identical(_activePreviewProxyProcess, process)) {
        _activePreviewProxyProcess = null;
      }
    }
  }

  Future<VideoMetadata> inspectVideo(File file) async {
    if (!await file.exists()) {
      throw FfmpegProcessException('Arquivo nao encontrado: ${file.path}');
    }

    final toolchain = await resolveToolchain();
    final inspection = await _inspectVideoMetadata(
      toolchain.ffprobePath,
      file.path,
    );
    final thumbnailPath = await _createThumbnail(
      toolchain.ffmpegPath,
      file.path,
      inspection.duration,
    );

    return VideoMetadata(
      duration: inspection.duration,
      hasAudio: inspection.hasAudio,
      thumbnailPath: thumbnailPath,
      width: inspection.dimensions?.width,
      height: inspection.dimensions?.height,
    );
  }

  Future<Duration> inspectDuration(File file) async {
    if (!await file.exists()) {
      throw FfmpegProcessException('Arquivo nao encontrado: ${file.path}');
    }

    final toolchain = await resolveToolchain();
    return _readDuration(toolchain.ffprobePath, file.path);
  }

  Future<FfmpegGrayFrameBatch> extractGrayTrackingFrames(
    String inputPath, {
    required Duration sourceStart,
    required Duration sourceDuration,
    int width = 320,
    int height = 180,
    double framesPerSecond = 4,
    int maximumFrames = 240,
  }) async {
    if (!await File(inputPath).exists()) {
      throw FfmpegProcessException(
        'Arquivo de origem nao encontrado: $inputPath',
      );
    }
    final safeWidth = width.clamp(96, 640);
    final safeHeight = height.clamp(54, 360);
    final safeFps = framesPerSecond.clamp(1.0, 12.0).toDouble();
    final safeMaximumFrames = maximumFrames.clamp(2, 720);
    final maximumDuration = Duration(
      microseconds: (safeMaximumFrames / safeFps * 1000000).round(),
    );
    final duration = sourceDuration < maximumDuration
        ? sourceDuration
        : maximumDuration;
    final toolchain = await resolveToolchain();
    final rawOutputFile = _usesEmbeddedMobileFfmpeg
        ? File(
            _join(
              Directory.systemTemp.path,
              'tgi_tracking_${DateTime.now().microsecondsSinceEpoch}.raw',
            ),
          )
        : null;
    final process = await _startMediaProcess(toolchain.ffmpegPath, [
      if (rawOutputFile != null) '-y',
      '-hide_banner',
      '-loglevel',
      'error',
      '-nostdin',
      '-ss',
      _seconds(sourceStart),
      '-t',
      _seconds(duration),
      '-i',
      inputPath,
      '-an',
      '-vf',
      'fps=${_filterNumber(safeFps)},scale=$safeWidth:$safeHeight',
      '-frames:v',
      '$safeMaximumFrames',
      '-pix_fmt',
      'gray',
      '-f',
      'rawvideo',
      rawOutputFile?.path ?? 'pipe:1',
    ]);
    final bytes = BytesBuilder(copy: false);
    final stdoutDone = process.stdout.listen(bytes.add).asFuture<void>();
    final stderr = await process.stderr
        .transform(systemEncoding.decoder)
        .join();
    final exitCode = await process.exitCode;
    await stdoutDone;
    if (exitCode == 0 && rawOutputFile != null) {
      if (await rawOutputFile.exists()) {
        bytes.add(await rawOutputFile.readAsBytes());
        await rawOutputFile.delete();
      }
    }
    if (exitCode != 0) {
      if (rawOutputFile != null && await rawOutputFile.exists()) {
        await rawOutputFile.delete();
      }
      throw FfmpegProcessException(
        'Nao foi possivel extrair quadros para o rastreamento.',
        _lastOutputLines(stderr),
      );
    }
    final data = bytes.takeBytes();
    final frameSize = safeWidth * safeHeight;
    final frameCount = math.min(safeMaximumFrames, data.length ~/ frameSize);
    if (frameCount < 2) {
      throw const FfmpegProcessException(
        'O clipe nao possui quadros suficientes para rastrear.',
      );
    }
    return FfmpegGrayFrameBatch(
      width: safeWidth,
      height: safeHeight,
      framesPerSecond: safeFps,
      frames: [
        for (var index = 0; index < frameCount; index++)
          Uint8List.sublistView(
            data,
            index * frameSize,
            (index + 1) * frameSize,
          ),
      ],
    );
  }

  Future<void> extractAudioAsMp3(
    String inputPath,
    String outputPath, {
    FfmpegExportProgressCallback? onProgress,
  }) {
    return exportAudioFile(inputPath, outputPath, onProgress: onProgress);
  }

  Future<List<FfmpegAudioChunk>> extractAudioChunksForTranscription(
    String inputPath,
    String outputDirectoryPath, {
    Duration chunkDuration = const Duration(minutes: 5),
    FfmpegExportProgressCallback? onProgress,
  }) async {
    _transcriptionPreparationCancelled = false;
    final inputFile = File(inputPath);
    if (!await inputFile.exists()) {
      throw FfmpegProcessException(
        'Arquivo de origem nao encontrado: $inputPath',
      );
    }

    final toolchain = await resolveToolchain();
    final hasAudio = await _hasAudioStream(toolchain.ffprobePath, inputPath);
    if (!hasAudio) {
      throw const FfmpegProcessException(
        'O arquivo selecionado nao tem trilha de audio.',
      );
    }

    final duration = await _readDuration(toolchain.ffprobePath, inputPath);
    if (duration <= Duration.zero) {
      throw const FfmpegProcessException(
        'Nao foi possivel ler a duracao do audio.',
      );
    }

    final outputDirectory = Directory(outputDirectoryPath);
    await outputDirectory.create(recursive: true);

    final safeChunkDuration = chunkDuration < const Duration(seconds: 30)
        ? const Duration(seconds: 30)
        : chunkDuration;
    final chunkCount = math.max(
      1,
      (duration.inMicroseconds / safeChunkDuration.inMicroseconds).ceil(),
    );
    final chunks = <FfmpegAudioChunk>[];
    var offset = Duration.zero;
    var index = 0;
    onProgress?.call(0);

    while (offset < duration) {
      final remaining = duration - offset;
      final currentDuration = remaining < safeChunkDuration
          ? remaining
          : safeChunkDuration;
      final outputPath = _join(
        outputDirectory.path,
        'caption_chunk_${index.toString().padLeft(3, '0')}.wav',
      );
      final result = await _runTranscriptionPreparation(toolchain.ffmpegPath, [
        '-y',
        '-hide_banner',
        '-nostdin',
        '-ss',
        _seconds(offset),
        '-t',
        _seconds(currentDuration),
        '-i',
        inputPath,
        '-vn',
        '-map',
        '0:a:0',
        '-ac',
        '1',
        '-ar',
        '16000',
        '-c:a',
        'pcm_s16le',
        outputPath,
      ]);

      final outputFile = File(outputPath);
      final outputExists = await outputFile.exists();
      final outputHasBytes = outputExists && await outputFile.length() > 0;
      if (result.exitCode != 0 || !outputHasBytes) {
        throw FfmpegProcessException(
          'Nao foi possivel extrair o audio para transcricao.',
          _lastOutputLines(result.stderr.toString()),
        );
      }

      chunks.add(
        FfmpegAudioChunk(
          path: outputPath,
          offset: offset,
          duration: currentDuration,
        ),
      );
      index++;
      offset += currentDuration;
      onProgress?.call((index / chunkCount).clamp(0.0, 1.0).toDouble());
    }

    return chunks;
  }

  Future<void> exportAudioFile(
    String inputPath,
    String outputPath, {
    double volume = 1,
    FfmpegExportProgressCallback? onProgress,
  }) async {
    if (!await File(inputPath).exists()) {
      throw FfmpegProcessException(
        'Arquivo de origem nao encontrado: $inputPath',
      );
    }

    final outputFile = File(outputPath);
    await outputFile.parent.create(recursive: true);

    final toolchain = await resolveToolchain();
    final duration = await _readDuration(toolchain.ffprobePath, inputPath);
    final process = await _startMediaProcess(
      toolchain.ffmpegPath,
      _buildAudioExportArguments(inputPath, outputPath, volume: volume),
    );

    onProgress?.call(0);
    final stderrBuffer = StringBuffer();
    var lastProgress = 0.0;
    final stderrDone = process.stderr.transform(systemEncoding.decoder).listen((
      chunk,
    ) {
      stderrBuffer.write(chunk);
      final progressTime = _parseFfmpegProgressTime(chunk);
      if (progressTime == null || duration <= Duration.zero) {
        return;
      }
      final progress = progressTime.inMilliseconds / duration.inMilliseconds;
      final clamped = progress.clamp(0.0, 0.99);
      if (clamped >= lastProgress + 0.01 || clamped > 0.98) {
        lastProgress = clamped;
        onProgress?.call(clamped);
      }
    }).asFuture<void>();
    final stdoutDone = process.stdout.drain<void>();

    final exitCode = await process.exitCode;
    await stdoutDone;
    await stderrDone;

    final outputExists = await outputFile.exists();
    final outputHasBytes = outputExists && await outputFile.length() > 0;
    if (exitCode != 0 || !outputHasBytes) {
      throw FfmpegProcessException(
        'Nao foi possivel exportar o audio.',
        _lastOutputLines(stderrBuffer.toString()),
      );
    }

    onProgress?.call(1);
  }

  // ────────────────────────────────────────────────────────
  //  Audio studio operations
  // ────────────────────────────────────────────────────────

  Future<void> trimAudio({
    required String inputPath,
    required String outputPath,
    required Duration start,
    required Duration end,
    FfmpegExportProgressCallback? onProgress,
  }) async {
    await _runAudioProcessingTask(
      inputPath: inputPath,
      outputPath: outputPath,
      buildArgs: (input, output) => [
        '-y',
        '-hide_banner',
        '-nostdin',
        '-i',
        input,
        '-vn',
        '-map',
        '0:a:0',
        '-ss',
        _seconds(start),
        '-to',
        _seconds(end),
        '-c:a',
        _audioCodecForPath(output),
        ..._audioCodecBitrateArgs(output),
        '-ar',
        '44100',
        '-ac',
        '2',
        output,
      ],
      onProgress: onProgress,
      taskLabel: 'Aparar audio',
    );
  }

  Future<void> changeAudioSpeed({
    required String inputPath,
    required String outputPath,
    required double speed,
    FfmpegExportProgressCallback? onProgress,
  }) async {
    final clampedSpeed = speed.clamp(0.25, 4.0);
    await _runAudioProcessingTask(
      inputPath: inputPath,
      outputPath: outputPath,
      buildArgs: (input, output) => [
        '-y',
        '-hide_banner',
        '-nostdin',
        '-i',
        input,
        '-vn',
        '-map',
        '0:a:0',
        '-filter:a',
        'atempo=${clampedSpeed.toStringAsFixed(6)}',
        '-c:a',
        _audioCodecForPath(output),
        ..._audioCodecBitrateArgs(output),
        '-ar',
        '44100',
        '-ac',
        '2',
        output,
      ],
      onProgress: onProgress,
      taskLabel: 'Alterar velocidade',
    );
  }

  Future<void> changeAudioPitch({
    required String inputPath,
    required String outputPath,
    required double semitones,
    FfmpegExportProgressCallback? onProgress,
  }) async {
    final clampedSemitones = semitones.clamp(-24.0, 24.0);
    final pitchRatio = math.pow(2, clampedSemitones / 12).toDouble();
    await _runAudioProcessingTask(
      inputPath: inputPath,
      outputPath: outputPath,
      buildArgs: (input, output) => [
        '-y',
        '-hide_banner',
        '-nostdin',
        '-i',
        input,
        '-vn',
        '-map',
        '0:a:0',
        '-filter:a',
        'asetrate=44100,atempo=1.0,'
            'rubberband=pitch=${pitchRatio.toStringAsFixed(6)}',
        '-c:a',
        _audioCodecForPath(output),
        ..._audioCodecBitrateArgs(output),
        '-ar',
        '44100',
        '-ac',
        '2',
        output,
      ],
      onProgress: onProgress,
      taskLabel: 'Alterar tom',
    );
  }

  Future<void> applyAudioEQ({
    required String inputPath,
    required String outputPath,
    required List<double> bandGains,
    FfmpegExportProgressCallback? onProgress,
  }) async {
    final eqFilters = <String>[];
    final frequencies = const [60, 230, 910, 3600, 14000];
    for (var i = 0; i < bandGains.length && i < frequencies.length; i++) {
      final freq = frequencies[i];
      final gain = bandGains[i].clamp(-20.0, 20.0);
      if (gain.abs() < 0.1) {
        continue;
      }
      final width = switch (i) {
        0 => 35,
        1 => 70,
        2 => 200,
        3 => 500,
        _ => 4000,
      };
      eqFilters.add(
        'equalizer=f=$freq:t=h:w=$width:g=${gain.toStringAsFixed(1)}',
      );
    }
    final filter = eqFilters.isEmpty ? 'anull' : eqFilters.join(',');

    await _runAudioProcessingTask(
      inputPath: inputPath,
      outputPath: outputPath,
      buildArgs: (input, output) => [
        '-y',
        '-hide_banner',
        '-nostdin',
        '-i',
        input,
        '-vn',
        '-map',
        '0:a:0',
        '-filter:a',
        filter,
        '-c:a',
        _audioCodecForPath(output),
        ..._audioCodecBitrateArgs(output),
        '-ar',
        '44100',
        '-ac',
        '2',
        output,
      ],
      onProgress: onProgress,
      taskLabel: 'Aplicar equalizador',
    );
  }

  Future<void> reverseAudio({
    required String inputPath,
    required String outputPath,
    FfmpegExportProgressCallback? onProgress,
  }) async {
    await _runAudioProcessingTask(
      inputPath: inputPath,
      outputPath: outputPath,
      buildArgs: (input, output) => [
        '-y',
        '-hide_banner',
        '-nostdin',
        '-i',
        input,
        '-vn',
        '-map',
        '0:a:0',
        '-filter:a',
        'areverse',
        '-c:a',
        _audioCodecForPath(output),
        ..._audioCodecBitrateArgs(output),
        '-ar',
        '44100',
        '-ac',
        '2',
        output,
      ],
      onProgress: onProgress,
      taskLabel: 'Reverter audio',
    );
  }

  FfmpegFrameExtractCommand buildFrameExtractCommand({
    required String inputPath,
    required Duration position,
    required String outputPath,
  }) {
    return FfmpegFrameExtractCommand(
      arguments: [
        '-y',
        '-hide_banner',
        '-nostdin',
        '-ss',
        _seconds(position),
        '-i',
        inputPath,
        '-frames:v',
        '1',
        '-q:v',
        '2',
        outputPath,
      ],
      outputPath: outputPath,
      position: position,
    );
  }

  FfmpegVideoStabilizationCommands buildVideoStabilizationCommands({
    required String inputPath,
    required String outputPath,
    required String transformFilePath,
  }) {
    final escapedTransformPath = _escapeFilterPath(transformFilePath);
    return FfmpegVideoStabilizationCommands(
      detectArguments: [
        '-y',
        '-hide_banner',
        '-nostdin',
        '-i',
        inputPath,
        '-vf',
        "vidstabdetect=shakiness=5:accuracy=15:result='$escapedTransformPath'",
        '-f',
        'null',
        '-',
      ],
      transformArguments: [
        '-y',
        '-hide_banner',
        '-nostdin',
        '-i',
        inputPath,
        '-vf',
        "vidstabtransform=input='$escapedTransformPath':smoothing=30,"
            'unsharp=5:5:0.8:3:3:0.4',
        '-c:v',
        'libx264',
        '-preset',
        'veryfast',
        '-crf',
        '18',
        '-c:a',
        'copy',
        outputPath,
      ],
      transformFilePath: transformFilePath,
      outputPath: outputPath,
    );
  }

  Future<void> extractVideoFrame({
    required String inputPath,
    required Duration position,
    required String outputPath,
  }) async {
    if (!await File(inputPath).exists()) {
      throw FfmpegProcessException(
        'Arquivo de origem nao encontrado: $inputPath',
      );
    }

    final command = buildFrameExtractCommand(
      inputPath: inputPath,
      position: position < Duration.zero ? Duration.zero : position,
      outputPath: outputPath,
    );
    final outputFile = File(outputPath);
    await outputFile.parent.create(recursive: true);
    final toolchain = await resolveToolchain();
    final process = await _startMediaProcess(
      toolchain.ffmpegPath,
      command.arguments,
    );
    final stderrBuffer = StringBuffer();
    final stdoutDone = process.stdout.drain<void>();
    final stderrDone = process.stderr
        .transform(systemEncoding.decoder)
        .listen(stderrBuffer.write)
        .asFuture<void>();
    final exitCode = await process.exitCode;
    await stdoutDone;
    await stderrDone;

    final outputExists = await outputFile.exists();
    final outputHasBytes = outputExists && await outputFile.length() > 0;
    if (exitCode != 0 || !outputHasBytes) {
      throw FfmpegProcessException(
        'Nao foi possivel congelar o quadro.',
        _lastOutputLines(stderrBuffer.toString()),
      );
    }
  }

  Future<void> createFreezeFrameVideo({
    required String framePath,
    required Duration duration,
    required String outputPath,
    int width = 1280,
    int height = 720,
    int framesPerSecond = 30,
  }) async {
    if (!await File(framePath).exists()) {
      throw FfmpegProcessException(
        'Quadro congelado nao encontrado: $framePath',
      );
    }
    if (duration <= Duration.zero) {
      throw const FfmpegProcessException(
        'Duracao invalida para o quadro congelado.',
      );
    }

    final outputFile = File(outputPath);
    await outputFile.parent.create(recursive: true);
    final toolchain = await resolveToolchain();
    final durationSeconds = _seconds(duration);
    final evenWidth = _evenDimension(math.max(2, width));
    final evenHeight = _evenDimension(math.max(2, height));
    final process = await _startMediaProcess(toolchain.ffmpegPath, [
      '-y',
      '-hide_banner',
      '-nostdin',
      '-loop',
      '1',
      '-t',
      durationSeconds,
      '-i',
      framePath,
      '-f',
      'lavfi',
      '-t',
      durationSeconds,
      '-i',
      'anullsrc=channel_layout=stereo:sample_rate=48000',
      '-vf',
      'scale=$evenWidth:$evenHeight:force_original_aspect_ratio=decrease,'
          'pad=$evenWidth:$evenHeight:(ow-iw)/2:(oh-ih)/2:color=black,'
          'fps=$framesPerSecond,format=yuv420p',
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      '-crf',
      '18',
      '-c:a',
      'aac',
      '-b:a',
      '96k',
      '-shortest',
      outputPath,
    ]);
    final stderrBuffer = StringBuffer();
    final stdoutDone = process.stdout.drain<void>();
    final stderrDone = process.stderr
        .transform(systemEncoding.decoder)
        .listen(stderrBuffer.write)
        .asFuture<void>();
    final exitCode = await process.exitCode;
    await stdoutDone;
    await stderrDone;

    final outputExists = await outputFile.exists();
    final outputHasBytes = outputExists && await outputFile.length() > 0;
    if (exitCode != 0 || !outputHasBytes) {
      throw FfmpegProcessException(
        'Nao foi possivel criar o clipe de quadro congelado.',
        _lastOutputLines(stderrBuffer.toString()),
      );
    }
  }

  Future<void> mergeAudioFiles({
    required List<String> inputPaths,
    required String outputPath,
    FfmpegExportProgressCallback? onProgress,
  }) async {
    if (inputPaths.isEmpty) {
      throw const FfmpegProcessException(
        'Pelo menos um arquivo de audio e necessario.',
      );
    }
    if (inputPaths.length == 1) {
      await File(inputPaths.first).copy(outputPath);
      onProgress?.call(1);
      return;
    }

    for (final path in inputPaths) {
      if (!await File(path).exists()) {
        throw FfmpegProcessException('Arquivo de origem nao encontrado: $path');
      }
    }

    final outputFile = File(outputPath);
    await outputFile.parent.create(recursive: true);

    final toolchain = await resolveToolchain();
    var totalDuration = Duration.zero;
    for (final path in inputPaths) {
      final duration = await _readDuration(toolchain.ffprobePath, path);
      if (duration > totalDuration) {
        totalDuration = duration;
      }
    }

    final filterInputs = StringBuffer();
    for (var i = 0; i < inputPaths.length; i++) {
      filterInputs.write('[$i:a]');
    }
    final mixFilter =
        '${filterInputs}amix=inputs=${inputPaths.length}:'
        'duration=longest:dropout_transition=0';

    final args = <String>[
      '-y',
      '-hide_banner',
      '-nostdin',
      for (final path in inputPaths) ...['-i', path],
      '-filter_complex',
      mixFilter,
      '-c:a',
      _audioCodecForPath(outputPath),
      ..._audioCodecBitrateArgs(outputPath),
      '-ar',
      '44100',
      '-ac',
      '2',
      outputPath,
    ];

    final process = await _startMediaProcess(toolchain.ffmpegPath, args);

    onProgress?.call(0);
    final stderrBuffer = StringBuffer();
    var lastProgress = 0.0;
    final stderrDone = process.stderr.transform(systemEncoding.decoder).listen((
      chunk,
    ) {
      stderrBuffer.write(chunk);
      final progressTime = _parseFfmpegProgressTime(chunk);
      if (progressTime == null || totalDuration <= Duration.zero) {
        return;
      }
      final progress =
          progressTime.inMilliseconds / totalDuration.inMilliseconds;
      final clamped = progress.clamp(0.0, 0.99).toDouble();
      if (clamped >= lastProgress + 0.05) {
        lastProgress = clamped;
        onProgress?.call(clamped);
      }
    }).asFuture<void>();
    final stdoutDone = process.stdout.drain<void>();

    final exitCode = await process.exitCode;
    await stdoutDone;
    await stderrDone;

    final outputExists = await outputFile.exists();
    final outputHasBytes = outputExists && await outputFile.length() > 0;
    if (exitCode != 0 || !outputHasBytes) {
      throw FfmpegProcessException(
        'Nao foi possivel mesclar os audios.',
        _lastOutputLines(stderrBuffer.toString()),
      );
    }

    onProgress?.call(1);
  }

  FfmpegAudioTimelineCommand buildAudioTimelineCommand({
    required List<FfmpegAudioTimelineClip> clips,
    required String outputPath,
    Duration? totalDuration,
  }) {
    final activeClips = clips
        .where((clip) => clip.duration > Duration.zero)
        .toList(growable: false);
    if (activeClips.isEmpty) {
      throw const FfmpegProcessException(
        'Adicione pelo menos um audio na timeline.',
      );
    }

    var renderDuration = totalDuration ?? Duration.zero;
    for (final clip in activeClips) {
      if (clip.timelineEnd > renderDuration) {
        renderDuration = clip.timelineEnd;
      }
    }
    if (renderDuration <= Duration.zero) {
      throw const FfmpegProcessException('Timeline de audio vazia.');
    }

    final totalSeconds = _seconds(renderDuration);
    final filters = <String>[];
    final mixInputs = StringBuffer();
    for (var i = 0; i < activeClips.length; i++) {
      final clip = activeClips[i];
      final startMs = math.max(0, clip.timelineStart.inMilliseconds);
      final clipSeconds = _seconds(clip.duration);
      final volume = clip.volume.clamp(0.0, 2.0).toStringAsFixed(6);
      final label = 'tl$i';
      filters.add(
        '[$i:a]atrim=duration=$clipSeconds,asetpts=PTS-STARTPTS,'
        'volume=$volume,adelay=$startMs:all=1,asetpts=N/SR/TB,apad,'
        'atrim=duration=$totalSeconds,asetpts=PTS-STARTPTS[$label]',
      );
      mixInputs.write('[$label]');
    }
    filters.add(
      '${mixInputs}amix=inputs=${activeClips.length}:'
      'duration=longest:dropout_transition=0:normalize=0,'
      'atrim=duration=$totalSeconds,asetpts=PTS-STARTPTS[a]',
    );

    return FfmpegAudioTimelineCommand(
      arguments: [
        '-y',
        '-hide_banner',
        '-nostdin',
        for (final clip in activeClips) ...['-i', clip.inputPath],
        '-filter_complex',
        filters.join(';'),
        '-map',
        '[a]',
        '-c:a',
        _audioCodecForPath(outputPath),
        ..._audioCodecBitrateArgs(outputPath),
        '-ar',
        '44100',
        '-ac',
        '2',
        outputPath,
      ],
      totalDuration: renderDuration,
      clipCount: activeClips.length,
    );
  }

  Future<void> renderAudioTimeline({
    required List<FfmpegAudioTimelineClip> clips,
    required String outputPath,
    Duration? totalDuration,
    FfmpegExportProgressCallback? onProgress,
  }) async {
    final command = buildAudioTimelineCommand(
      clips: clips,
      outputPath: outputPath,
      totalDuration: totalDuration,
    );

    for (final clip in clips) {
      if (clip.duration <= Duration.zero) {
        continue;
      }
      if (!await File(clip.inputPath).exists()) {
        throw FfmpegProcessException(
          'Arquivo de origem nao encontrado: ${clip.inputPath}',
        );
      }
    }

    final outputFile = File(outputPath);
    await outputFile.parent.create(recursive: true);

    final toolchain = await resolveToolchain();
    final process = await _startMediaProcess(
      toolchain.ffmpegPath,
      command.arguments,
    );

    onProgress?.call(0);
    final stderrBuffer = StringBuffer();
    var lastProgress = 0.0;
    final stderrDone = process.stderr.transform(systemEncoding.decoder).listen((
      chunk,
    ) {
      stderrBuffer.write(chunk);
      final progressTime = _parseFfmpegProgressTime(chunk);
      if (progressTime == null || command.totalDuration <= Duration.zero) {
        return;
      }
      final progress =
          progressTime.inMilliseconds / command.totalDuration.inMilliseconds;
      final clamped = progress.clamp(0.0, 0.99).toDouble();
      if (clamped >= lastProgress + 0.03 || clamped > 0.97) {
        lastProgress = clamped;
        onProgress?.call(clamped);
      }
    }).asFuture<void>();
    final stdoutDone = process.stdout.drain<void>();

    final exitCode = await process.exitCode;
    await stdoutDone;
    await stderrDone;

    final outputExists = await outputFile.exists();
    final outputHasBytes = outputExists && await outputFile.length() > 0;
    if (exitCode != 0 || !outputHasBytes) {
      throw FfmpegProcessException(
        'Nao foi possivel atualizar o preview da timeline.',
        _lastOutputLines(stderrBuffer.toString()),
      );
    }

    onProgress?.call(1);
  }

  Future<FfmpegRecordingSession> startAudioRecording({
    required String outputPath,
    int sampleRate = 44100,
    int channels = 2,
    String? inputDevice,
  }) async {
    final outputFile = File(outputPath);
    await outputFile.parent.create(recursive: true);

    if (Platform.isAndroid || Platform.isIOS) {
      final recorder = AudioRecorder();
      if (!await recorder.hasPermission()) {
        await recorder.dispose();
        throw const FfmpegProcessException(
          'Permita o acesso ao microfone para iniciar a gravacao.',
        );
      }
      try {
        await recorder.start(
          RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 192000,
            sampleRate: sampleRate,
            numChannels: channels,
            autoGain: true,
            noiseSuppress: true,
          ),
          path: outputPath,
        );
      } catch (_) {
        await recorder.dispose();
        rethrow;
      }
      return FfmpegRecordingSession.mobile(
        recorder: recorder,
        outputPath: outputPath,
      );
    }

    if (!Platform.isWindows) {
      throw const FfmpegProcessException(
        'A gravacao direta nao esta disponivel nesta plataforma.',
      );
    }

    final toolchain = await resolveToolchain();
    final audioInputDevice = await _resolveAudioInputDevice(
      toolchain,
      inputDevice,
    );
    final args = <String>[
      '-y',
      '-hide_banner',
      '-f',
      'dshow',
      '-i',
      audioInputDevice,
      '-ac',
      channels.toString(),
      '-ar',
      sampleRate.toString(),
      '-c:a',
      _audioCodecForPath(outputPath),
      ..._audioCodecBitrateArgs(outputPath),
      outputPath,
    ];

    final process = await Process.start(
      toolchain.ffmpegPath,
      args,
      runInShell: !_isAbsoluteWindowsPath(toolchain.ffmpegPath),
    );

    final stderrBuffer = StringBuffer();
    final stderrDone = process.stderr.transform(systemEncoding.decoder).listen((
      chunk,
    ) {
      stderrBuffer.write(chunk);
    }).asFuture<void>();
    final stdoutDone = process.stdout.drain<void>();

    final earlyExitCode = await Future.any<int?>([
      process.exitCode,
      Future<int?>.delayed(const Duration(milliseconds: 600)),
    ]);
    if (earlyExitCode != null) {
      await stdoutDone;
      await stderrDone;
      throw FfmpegProcessException(
        'Nao foi possivel iniciar a gravacao de audio.',
        _lastOutputLines(stderrBuffer.toString()),
      );
    }

    return FfmpegRecordingSession.desktopdesktop(
      process: process,
      outputPath: outputPath,
      stdoutDone: stdoutDone,
      stderrDone: stderrDone,
      stderrBuffer: stderrBuffer,
    );
  }

  Future<String> recordAudio({
    required String outputPath,
    int sampleRate = 44100,
    int channels = 2,
  }) async {
    final session = await startAudioRecording(
      outputPath: outputPath,
      sampleRate: sampleRate,
      channels: channels,
    );
    return session.pid.toString();
  }

  Future<String> _resolveAudioInputDevice(
    FfmpegToolchain toolchain,
    String? inputDevice,
  ) async {
    final preferred = inputDevice?.trim();
    if (preferred != null && preferred.isNotEmpty) {
      return _normalizeDirectShowAudioInput(preferred);
    }

    final devices = await _listDirectShowAudioDevices(toolchain.ffmpegPath);
    if (devices.isNotEmpty) {
      return _normalizeDirectShowAudioInput(devices.first);
    }

    return 'audio=Microfone (Dispositivo de High Definition Audio)';
  }

  Future<List<String>> _listDirectShowAudioDevices(String ffmpegPath) async {
    if (!Platform.isWindows) {
      return const <String>[];
    }

    try {
      final process = await Process.start(ffmpegPath, const [
        '-hide_banner',
        '-list_devices',
        'true',
        '-f',
        'dshow',
        '-i',
        'dummy',
      ], runInShell: !_isAbsoluteWindowsPath(ffmpegPath));
      final output = StringBuffer();
      final stdoutDone = process.stdout
          .transform(systemEncoding.decoder)
          .listen(output.write)
          .asFuture<void>();
      final stderrDone = process.stderr
          .transform(systemEncoding.decoder)
          .listen(output.write)
          .asFuture<void>();

      try {
        await process.exitCode.timeout(const Duration(seconds: 4));
      } on TimeoutException {
        Process.killPid(process.pid);
        await process.exitCode;
      }
      await Future.wait<void>([stdoutDone, stderrDone], eagerError: false);

      return _parseDirectShowAudioDevices(output.toString());
    } catch (_) {
      return const <String>[];
    }
  }

  List<String> _parseDirectShowAudioDevices(String output) {
    final devices = <String>[];
    final seen = <String>{};
    final pattern = RegExp(r'"([^"]+)"\s+\(audio\)');
    for (final match in pattern.allMatches(output)) {
      final device = match.group(1)?.trim();
      if (device == null || device.isEmpty || !seen.add(device)) {
        continue;
      }
      devices.add(device);
    }
    return devices;
  }

  String _normalizeDirectShowAudioInput(String inputDevice) {
    if (inputDevice.toLowerCase().startsWith('audio=')) {
      return inputDevice;
    }
    return 'audio=$inputDevice';
  }

  // ────────────────────────────────────────────────────────
  //  Shared audio helpers
  // ────────────────────────────────────────────────────────

  Future<void> _runAudioProcessingTask({
    required String inputPath,
    required String outputPath,
    required List<String> Function(String input, String output) buildArgs,
    FfmpegExportProgressCallback? onProgress,
    String taskLabel = 'Processar audio',
  }) async {
    if (!await File(inputPath).exists()) {
      throw FfmpegProcessException(
        'Arquivo de origem nao encontrado: $inputPath',
      );
    }

    final outputFile = File(outputPath);
    await outputFile.parent.create(recursive: true);

    final toolchain = await resolveToolchain();
    final args = buildArgs(inputPath, outputPath);
    final process = await _startMediaProcess(toolchain.ffmpegPath, args);

    onProgress?.call(0);
    final stderrBuffer = StringBuffer();
    var lastProgress = 0.0;
    final stderrDone = process.stderr.transform(systemEncoding.decoder).listen((
      chunk,
    ) {
      stderrBuffer.write(chunk);
      final progressTime = _parseFfmpegProgressTime(chunk);
      if (progressTime == null) {
        return;
      }
      final ms = progressTime.inMilliseconds;
      final clamped = (ms / (ms + 500)).clamp(0.0, 0.99);
      if (clamped >= lastProgress + 0.02 || clamped > 0.97) {
        lastProgress = clamped;
        onProgress?.call(clamped);
      }
    }).asFuture<void>();
    final stdoutDone = process.stdout.drain<void>();

    final exitCode = await process.exitCode;
    await stdoutDone;
    await stderrDone;

    final outputExists = await outputFile.exists();
    final outputHasBytes = outputExists && await outputFile.length() > 0;
    if (exitCode != 0 || !outputHasBytes) {
      throw FfmpegProcessException(
        'Nao foi possivel $taskLabel.',
        _lastOutputLines(stderrBuffer.toString()),
      );
    }

    onProgress?.call(1);
  }

  String _audioCodecForPath(String outputPath) {
    final extension = _fileExtension(outputPath);
    switch (extension) {
      case 'wav':
        return 'pcm_s16le';
      case 'aac':
      case 'm4a':
        return 'aac';
      default:
        return 'libmp3lame';
    }
  }

  List<String> _audioCodecBitrateArgs(String outputPath) {
    final extension = _fileExtension(outputPath);
    switch (extension) {
      case 'wav':
        return const [];
      case 'aac':
      case 'm4a':
        return ['-b:a', '192k'];
      default:
        return ['-b:a', '192k'];
    }
  }

  Future<TgiProject> _preprocessStabilizedVideoClips(
    TgiProject project,
    Directory tempRoot,
  ) async {
    final stabilizationTargets = <Clip>[];
    for (final track in project.tracks) {
      if (track.isHidden) continue;
      for (final clip in track.clips) {
        if (clip.trackType != TrackType.video) continue;
        if (clip.stabilizationEnabled && clip.duration > Duration.zero) {
          stabilizationTargets.add(clip);
        }
      }
    }
    if (stabilizationTargets.isEmpty) {
      return project;
    }

    final stabilizedBySource = <String, MediaItem>{};
    for (final clip in stabilizationTargets) {
      _checkExportCancellation();
      final sourceItem = project.mediaItemById(clip.mediaItemId);
      if (sourceItem == null || sourceItem.type != MediaType.video) {
        continue;
      }
      final existing = stabilizedBySource[sourceItem.filePath];
      if (existing != null) {
        continue;
      }

      final sourceKey = _sanitizeFileName(_fileStem(sourceItem.filePath));
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final transformPath =
          '${tempRoot.path}${Platform.pathSeparator}${sourceKey}_$stamp.trf';
      final outputPath =
          '${tempRoot.path}${Platform.pathSeparator}${sourceKey}_$stamp.mp4';
      final commands = buildVideoStabilizationCommands(
        inputPath: sourceItem.filePath,
        outputPath: outputPath,
        transformFilePath: transformPath,
      );
      await _runExportPass(
        commands.detectArguments,
        failureMessage: 'Nao foi possivel analisar a estabilizacao do video.',
      );
      await _runExportPass(
        commands.transformArguments,
        failureMessage: 'Nao foi possivel estabilizar o video.',
      );
      final outputFile = File(outputPath);
      if (!await outputFile.exists() || await outputFile.length() == 0) {
        throw const FfmpegProcessException(
          'Nao foi possivel gerar o video estabilizado.',
        );
      }
      stabilizedBySource[sourceItem.filePath] = sourceItem.copyWith(
        id: 'stabilized_${sourceItem.id}_$stamp',
        filePath: outputPath,
        name: '${sourceItem.name} estabilizado',
        previewProxyPath: null,
      );
    }

    if (stabilizedBySource.isEmpty) {
      return project;
    }

    final stabilizedByOriginalId = <String, MediaItem>{};
    for (final item in project.mediaPool) {
      final stabilized = stabilizedBySource[item.filePath];
      if (stabilized != null) {
        stabilizedByOriginalId[item.id] = stabilized;
      }
    }

    final stabilizedGroups = {
      for (final clip in stabilizationTargets) clip.timelineGroupId,
    };
    final updatedTracks = project.tracks.map((track) {
      final updatedClips = track.clips.map((clip) {
        if (!stabilizedGroups.contains(clip.timelineGroupId)) {
          return clip;
        }
        final stabilized = stabilizedByOriginalId[clip.mediaItemId];
        if (stabilized == null) {
          return clip;
        }
        return clip.copyWith(mediaItemId: stabilized.id);
      }).toList();
      return track.copyWith(clips: updatedClips);
    }).toList();

    return project.copyWith(
      mediaPool: [...project.mediaPool, ...stabilizedBySource.values],
      tracks: updatedTracks,
    );
  }

  void _checkExportCancellation() {
    if (_exportCancellationRequested) {
      throw const FfmpegExportCancelledException();
    }
  }

  Future<void> _runExportPass(
    List<String> arguments, {
    required String failureMessage,
    Duration? totalDuration,
    FfmpegExportProgressCallback? onProgress,
  }) async {
    _checkExportCancellation();
    final process = await startCommand(arguments);
    _activeExportProcess = process;
    // A cancellation can arrive while the native process is starting.
    if (_exportCancellationRequested) {
      unawaited(process.cancel());
    }
    var diagnosticTail = '';
    var progressTail = '';
    var lastProgress = 0.0;
    final stderrDone = process.stderr.transform(systemEncoding.decoder).listen((
      chunk,
    ) {
      diagnosticTail += chunk;
      if (diagnosticTail.length > 32768) {
        diagnosticTail = diagnosticTail.substring(
          diagnosticTail.length - 32768,
        );
      }
      final progressText = progressTail + chunk;
      final time = _parseFfmpegProgressTime(progressText);
      progressTail = progressText.length > 128
          ? progressText.substring(progressText.length - 128)
          : progressText;
      if (!_exportCancellationRequested &&
          time != null &&
          totalDuration != null &&
          totalDuration > Duration.zero) {
        final progress = (time.inMicroseconds / totalDuration.inMicroseconds)
            .clamp(0.0, 0.99);
        if (progress >= lastProgress + 0.01) {
          lastProgress = progress;
          onProgress?.call(progress);
        }
      }
    }).asFuture<void>();
    final stdoutDone = process.stdout.drain<void>();
    try {
      final exitCode = await process.exitCode;
      await Future.wait([stdoutDone, stderrDone]);
      _checkExportCancellation();
      if (exitCode != 0) {
        throw FfmpegProcessException(
          failureMessage,
          _lastOutputLines(diagnosticTail),
        );
      }
    } finally {
      if (identical(_activeExportProcess, process)) {
        _activeExportProcess = null;
      }
    }
  }

  Future<void> exportProject(
    TgiProject project,
    String outputPath, {
    FfmpegExportSettings settings = FfmpegExportSettings.defaultSettings,
    FfmpegExportProgressCallback? onProgress,
  }) async {
    if (_exportInProgress) {
      throw const FfmpegProcessException(
        'Ja existe uma exportacao em andamento.',
      );
    }
    _exportInProgress = true;
    lastExportNotice = null;
    _exportCancellationRequested = false;
    Directory? exportDirectory;
    try {
      final outputFile = File(outputPath).absolute;
      await outputFile.parent.create(recursive: true);
      exportDirectory = await outputFile.parent.createTemp(
        '.tgi_editor_export_',
      );
      final renderPath = _join(
        exportDirectory.path,
        settings.audioOnly ? 'render.wav' : 'render.mp4',
      );
      await EditorFontService.prepare(
        project.tracks
            .where((track) => !track.isHidden)
            .expand((track) => track.clips)
            .where((clip) => clip.trackType == TrackType.text)
            .map((clip) => clip.fontFamily),
      );
      final exportProject = await _preprocessStabilizedVideoClips(
        project,
        exportDirectory,
      );
      _checkExportCancellation();
      final selectedEncoder = settings.audioOnly
          ? FfmpegVideoEncoder.software
          : await _resolveExportEncoder(settings.encoder);
      _checkExportCancellation();
      lastExportEncoder = selectedEncoder;
      final command = buildExportCommand(
        exportProject,
        renderPath,
        settings: settings.copyWith(encoder: selectedEncoder),
        drawTextDirectoryPath: exportDirectory.path,
      );
      await _validateExportInputs(command);
      final arguments = List<String>.of(command.arguments);
      final graphIndex = arguments.indexOf('-filter_complex');
      if (graphIndex >= 0) {
        final graphPath = _join(exportDirectory.path, 'filters.ffgraph');
        await File(
          graphPath,
        ).writeAsString(arguments[graphIndex + 1], flush: true);
        arguments[graphIndex] = '-filter_complex_script';
        arguments[graphIndex + 1] = graphPath;
      }
      try {
        await _runExportPass(
          arguments,
          failureMessage: 'Nao foi possivel exportar o video.',
          totalDuration: command.totalDuration,
          onProgress: onProgress,
        );
      } on FfmpegProcessException {
        _checkExportCancellation();
        if (selectedEncoder == FfmpegVideoEncoder.software) rethrow;
        lastExportNotice =
            'A GPU não concluiu a exportação. O arquivo foi renderizado pela CPU.';
        lastExportEncoder = FfmpegVideoEncoder.software;
        onProgress?.call(0);
        await _runExportPass(
          _replaceVideoEncoder(
            arguments,
            FfmpegVideoEncoder.software,
            settings.quality,
          ),
          failureMessage: 'Nao foi possivel exportar o video.',
          totalDuration: command.totalDuration,
          onProgress: onProgress,
        );
      }
      final renderedFile = File(renderPath);
      if (!await renderedFile.exists() || await renderedFile.length() == 0) {
        throw const FfmpegProcessException(
          'Nao foi possivel exportar o video.',
        );
      }
      _checkExportCancellation();
      // Publish only a finished render. Cancelled/failed exports keep an older
      // destination intact; this rename stays on the same filesystem.
      await renderedFile.rename(outputFile.path);
      onProgress?.call(1);
    } finally {
      _activeExportProcess = null;
      try {
        if (exportDirectory != null && await exportDirectory.exists()) {
          await exportDirectory.delete(recursive: true);
        }
      } on FileSystemException {
        // Cleanup must not hide the original export result.
      } finally {
        _exportInProgress = false;
      }
    }
  }

  List<String> _buildAudioExportArguments(
    String inputPath,
    String outputPath, {
    double volume = 1,
  }) {
    final extension = _fileExtension(outputPath);
    final normalizedVolume = volume.clamp(0.0, 2.0).toDouble();
    final volumeFilter = 'volume=${normalizedVolume.toStringAsFixed(3)}';
    final codecArguments = <String>[];
    if (extension == 'wav') {
      codecArguments.addAll(['-c:a', 'pcm_s16le']);
    } else if (extension == 'aac' || extension == 'm4a') {
      codecArguments.addAll(['-c:a', 'aac', '-b:a', '192k']);
    } else {
      codecArguments.addAll(['-c:a', 'libmp3lame', '-b:a', '192k']);
    }

    return [
      '-y',
      '-hide_banner',
      '-nostdin',
      '-i',
      inputPath,
      '-vn',
      '-map',
      '0:a:0',
      '-filter:a',
      volumeFilter,
      ...codecArguments,
      '-ar',
      '44100',
      '-ac',
      '2',
      outputPath,
    ];
  }

  Future<FfmpegToolchain> resolveToolchain() async {
    if (_usesEmbeddedMobileFfmpeg) {
      return const FfmpegToolchain(
        ffmpegPath: 'embedded-ffmpeg',
        ffprobePath: 'embedded-ffprobe',
      );
    }
    final cached = _cachedToolchain;
    if (cached != null && await _isValidToolchain(cached)) {
      return cached;
    }

    for (final candidate in await _buildCandidates()) {
      if (await _isValidToolchain(candidate)) {
        _cachedToolchain = candidate;
        await _saveConfig(candidate);
        return candidate;
      }
    }

    throw const FfmpegNotFoundException();
  }

  Future<List<FfmpegToolchain>> _buildCandidates() async {
    final candidates = <FfmpegToolchain>[];
    final saved = await _readSavedConfig();
    if (saved != null) {
      candidates.add(saved);
    }

    candidates.add(
      const FfmpegToolchain(ffmpegPath: 'ffmpeg', ffprobePath: 'ffprobe'),
    );

    final appDir = File(Platform.resolvedExecutable).parent.path;
    final currentDir = Directory.current.path;
    final directories = <String>{
      appDir,
      _join(appDir, 'ffmpeg'),
      _join(appDir, 'ffmpeg', 'bin'),
      _join(appDir, 'tools', 'ffmpeg', 'bin'),
      currentDir,
      _join(currentDir, 'ffmpeg'),
      _join(currentDir, 'ffmpeg', 'bin'),
      _join(currentDir, 'tools', 'ffmpeg', 'bin'),
      r'C:\ffmpeg\bin',
      r'C:\Program Files\ffmpeg\bin',
      r'C:\Program Files (x86)\ffmpeg\bin',
    };

    for (final directory in directories) {
      candidates.add(_toolchainFromDirectory(directory));
    }

    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null && localAppData.isNotEmpty) {
      candidates.addAll(
        await _wingetPackageCandidates(
          _join(localAppData, 'Microsoft', 'WinGet', 'Packages'),
        ),
      );
    }

    return candidates;
  }

  Future<List<FfmpegToolchain>> _wingetPackageCandidates(
    String rootPath,
  ) async {
    final root = Directory(rootPath);
    if (!await root.exists()) {
      return const [];
    }

    final candidates = <FfmpegToolchain>[];
    await for (final packageDir in root.list(followLinks: false)) {
      if (packageDir is! Directory ||
          !_fileName(packageDir.path).toLowerCase().contains('gyan.ffmpeg')) {
        continue;
      }

      await for (final buildDir in packageDir.list(followLinks: false)) {
        if (buildDir is Directory) {
          candidates.add(_toolchainFromDirectory(_join(buildDir.path, 'bin')));
        }
      }
    }

    return candidates;
  }

  FfmpegToolchain _toolchainFromDirectory(String directory) {
    return FfmpegToolchain(
      ffmpegPath: _join(directory, 'ffmpeg.exe'),
      ffprobePath: _join(directory, 'ffprobe.exe'),
    );
  }

  Future<FfmpegToolchain?> _readSavedConfig() async {
    try {
      final file = File(_configPath);
      if (!await file.exists()) {
        return null;
      }

      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final ffmpegPath = decoded['ffmpegPath'];
      final ffprobePath = decoded['ffprobePath'];
      if (ffmpegPath is String && ffprobePath is String) {
        return FfmpegToolchain(
          ffmpegPath: ffmpegPath,
          ffprobePath: ffprobePath,
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> _saveConfig(FfmpegToolchain toolchain) async {
    try {
      final file = File(_configPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'ffmpegPath': toolchain.ffmpegPath,
          'ffprobePath': toolchain.ffprobePath,
        }),
      );
    } catch (_) {
      // Importing media should not fail only because the config cache is read-only.
    }
  }

  String get _configPath {
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      return _join(appData, 'TGI App Suite', 'ffmpeg_config.json');
    }
    return _join(Directory.current.path, 'ffmpeg_config.json');
  }

  Future<bool> _isValidToolchain(FfmpegToolchain toolchain) async {
    return _toolExists(toolchain.ffmpegPath) &&
        _toolExists(toolchain.ffprobePath) &&
        await _hasValidVersion(toolchain.ffmpegPath) &&
        await _hasValidVersion(toolchain.ffprobePath);
  }

  bool _toolExists(String executable) {
    if (!_isAbsoluteWindowsPath(executable)) {
      return true;
    }
    return File(executable).existsSync();
  }

  Future<bool> _hasValidVersion(String executable) async {
    try {
      final result = await _runTool(executable, const ['-version']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _hasAudioStream(String ffprobePath, String filePath) async {
    final result = await _runTool(ffprobePath, [
      '-v',
      'error',
      '-select_streams',
      'a:0',
      '-show_entries',
      'stream=index',
      '-of',
      'csv=p=0',
      filePath,
    ]);

    if (result.exitCode != 0) {
      throw FfmpegProcessException(
        'Nao foi possivel verificar o audio do video.',
        result.stderr.toString(),
      );
    }

    return result.stdout.toString().trim().isNotEmpty;
  }

  Future<({Duration duration, bool hasAudio, VideoDimensions? dimensions})>
  _inspectVideoMetadata(String ffprobePath, String filePath) async {
    final result = await _runTool(ffprobePath, [
      '-v',
      'error',
      '-show_entries',
      'format=duration:stream=codec_type,width,height,duration',
      '-of',
      'json',
      filePath,
    ]);

    if (result.exitCode != 0) {
      throw FfmpegProcessException(
        'Nao foi possivel ler as informacoes do video.',
        result.stderr.toString(),
      );
    }

    try {
      final decoded = jsonDecode(result.stdout.toString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Resposta do ffprobe invalida.');
      }
      final rawStreams = decoded['streams'];
      final streams = rawStreams is List
          ? rawStreams.whereType<Map<String, dynamic>>().toList()
          : const <Map<String, dynamic>>[];
      final format = decoded['format'];
      final formatDuration = format is Map<String, dynamic>
          ? _parseProbeSeconds(format['duration'])
          : null;
      final streamDuration = streams
          .map((stream) => _parseProbeSeconds(stream['duration']))
          .whereType<double>()
          .fold<double?>(null, (current, value) {
            if (current == null || value > current) {
              return value;
            }
            return current;
          });
      final seconds = formatDuration ?? streamDuration;
      if (seconds == null || seconds.isNaN || seconds.isInfinite) {
        throw const FormatException('Duracao invalida retornada pelo ffprobe.');
      }

      VideoDimensions? dimensions;
      var hasAudio = false;
      for (final stream in streams) {
        final type = stream['codec_type']?.toString();
        if (type == 'audio') {
          hasAudio = true;
        } else if (type == 'video' && dimensions == null) {
          final width = _parseProbeInt(stream['width']);
          final height = _parseProbeInt(stream['height']);
          if (width != null && height != null && width > 0 && height > 0) {
            dimensions = VideoDimensions(width: width, height: height);
          }
        }
      }

      return (
        duration: Duration(milliseconds: (seconds * 1000).round()),
        hasAudio: hasAudio,
        dimensions: dimensions,
      );
    } catch (error) {
      throw FfmpegProcessException(
        'Nao foi possivel interpretar as informacoes do video.',
        error.toString(),
      );
    }
  }

  double? _parseProbeSeconds(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return value == null ? null : double.tryParse(value.toString());
  }

  int? _parseProbeInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return value == null ? null : int.tryParse(value.toString());
  }

  Future<Duration> _readDuration(String ffprobePath, String filePath) async {
    final result = await _runTool(ffprobePath, [
      '-v',
      'error',
      '-show_entries',
      'format=duration',
      '-of',
      'default=noprint_wrappers=1:nokey=1',
      filePath,
    ]);

    if (result.exitCode != 0) {
      throw FfmpegProcessException(
        'Nao foi possivel ler a duracao do video.',
        result.stderr.toString(),
      );
    }

    final parts = result.stdout.toString().trim().split(RegExp(r'\s+'));
    final rawDuration = parts.isEmpty || parts.first.isEmpty
        ? null
        : parts.first;
    final seconds = rawDuration == null ? null : double.tryParse(rawDuration);
    if (seconds == null || seconds.isNaN || seconds.isInfinite) {
      throw const FfmpegProcessException(
        'Duracao invalida retornada pelo ffprobe.',
      );
    }

    return Duration(milliseconds: (seconds * 1000).round());
  }

  Future<String?> _createThumbnail(
    String ffmpegPath,
    String filePath,
    Duration duration,
  ) async {
    File target;
    try {
      target = await thumbnailCache.entry(
        filePath,
        'thumbnail-v2-320:${duration > const Duration(seconds: 1) ? 1 : 0}',
        'jpg',
      );
      if (await target.exists() &&
          image.decodeJpg(await target.readAsBytes()) != null) {
        thumbnailCacheHits++;
        return target.path;
      }
    } catch (_) {
      final directory = await Directory.systemTemp.createTemp(
        'editor_thumbnail_',
      );
      target = File(_join(directory.path, 'thumbnail.jpg'));
    }
    final outputPath =
        '${target.path}.${DateTime.now().microsecondsSinceEpoch}.tmp.jpg';
    final seekPositions = duration > const Duration(seconds: 1)
        ? const ['00:00:01', '00:00:00']
        : const ['00:00:00'];

    for (final seek in seekPositions) {
      final ok = await _tryCreateThumbnail(
        ffmpegPath,
        filePath,
        outputPath,
        seek,
      );
      if (ok) {
        try {
          await MediaDiskCache.publish(File(outputPath), target);
          return target.path;
        } on FileSystemException {
          return outputPath;
        }
      }
    }
    final partial = File(outputPath);
    if (await partial.exists()) await partial.delete();
    return null;
  }

  Future<bool> _tryCreateThumbnail(
    String ffmpegPath,
    String filePath,
    String outputPath,
    String seek,
  ) async {
    final result = await _runTool(ffmpegPath, [
      '-y',
      '-hide_banner',
      '-loglevel',
      'error',
      '-ss',
      seek,
      '-i',
      filePath,
      '-frames:v',
      '1',
      '-vf',
      'scale=320:-1',
      '-q:v',
      '2',
      outputPath,
    ]);

    return result.exitCode == 0 && File(outputPath).existsSync();
  }

  Future<void> _validateExportInputs(FfmpegExportCommand command) async {
    final inputPaths = <String>[];
    var nextInputIsGenerated = false;
    for (var index = 0; index < command.arguments.length; index++) {
      if (command.arguments[index] == '-f' &&
          index + 1 < command.arguments.length &&
          command.arguments[index + 1] == 'lavfi') {
        nextInputIsGenerated = true;
        index++;
        continue;
      }
      if (command.arguments[index] == '-i' &&
          index + 1 < command.arguments.length) {
        if (nextInputIsGenerated) {
          nextInputIsGenerated = false;
          continue;
        }
        inputPaths.add(command.arguments[index + 1]);
      }
    }

    for (final path in inputPaths.toSet()) {
      if (!await File(path).exists()) {
        throw FfmpegProcessException('Arquivo de origem nao encontrado: $path');
      }
    }
  }

  bool _isAbsoluteWindowsPath(String value) {
    return value.startsWith(r'\\') ||
        RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(value);
  }

  String _join(String first, String second, [String? third, String? fourth]) {
    final parts = <String>[first, second];
    if (third != null) {
      parts.add(third);
    }
    if (fourth != null) {
      parts.add(fourth);
    }
    return parts.join(Platform.pathSeparator);
  }

  String _fileName(String value) {
    return value.split(RegExp(r'[\\/]')).last;
  }

  String _fileExtension(String value) {
    final name = _fileName(value);
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) {
      return '';
    }
    return name.substring(dot + 1).toLowerCase();
  }

  String _fileStem(String value) {
    final name = _fileName(value);
    final dot = name.lastIndexOf('.');
    if (dot <= 0) {
      return name;
    }
    return name.substring(0, dot);
  }

  String _sanitizeFileName(String value) =>
      value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');

  String _seconds(Duration duration) {
    return (duration.inMicroseconds / Duration.microsecondsPerSecond)
        .toStringAsFixed(6);
  }

  String _filterNumber(double value) => value.toStringAsFixed(6);

  String _lastOutputLines(String value, {int maxLines = 18}) {
    final lines = value
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.length <= maxLines) {
      return lines.join('\n');
    }
    return lines.sublist(lines.length - maxLines).join('\n');
  }

  String _escapeFilterPath(String value) {
    final normalized = value.replaceAll('\\', '/');
    // Callers wrap the result in filtergraph single quotes. A literal quote
    // must survive both graph parsing and the filter's option parsing.
    return normalized.replaceAll(':', r'\:').replaceAll("'", r"'\\\''");
  }

  int _evenDimension(num value) {
    final rounded = math.max(2, value.round());
    return rounded.isEven ? rounded : rounded + 1;
  }
}
