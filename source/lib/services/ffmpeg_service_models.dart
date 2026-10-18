part of 'ffmpeg_service.dart';

class VideoMetadata {
  const VideoMetadata({
    required this.duration,
    required this.hasAudio,
    this.thumbnailPath,
    this.width,
    this.height,
  });

  final Duration duration;
  final bool hasAudio;
  final String? thumbnailPath;
  final int? width;
  final int? height;
}

class _VideoDimensions {
  const _VideoDimensions({required this.width, required this.height});

  final int width;
  final int height;
}

class FfmpegToolchain {
  const FfmpegToolchain({required this.ffmpegPath, required this.ffprobePath});

  final String ffmpegPath;
  final String ffprobePath;
}

class FfmpegExportCommand {
  const FfmpegExportCommand({
    required this.arguments,
    required this.totalDuration,
    required this.clipCount,
  });

  final List<String> arguments;
  final Duration totalDuration;
  final int clipCount;
}

class FfmpegPreviewProxyCommand {
  const FfmpegPreviewProxyCommand({
    required this.arguments,
    required this.outputPath,
    required this.totalDuration,
  });

  final List<String> arguments;
  final String outputPath;
  final Duration totalDuration;
}

class FfmpegFrameExtractCommand {
  const FfmpegFrameExtractCommand({
    required this.arguments,
    required this.outputPath,
    required this.position,
  });

  final List<String> arguments;
  final String outputPath;
  final Duration position;
}

class FfmpegGrayFrameBatch {
  const FfmpegGrayFrameBatch({
    required this.width,
    required this.height,
    required this.framesPerSecond,
    required this.frames,
  });

  final int width;
  final int height;
  final double framesPerSecond;
  final List<Uint8List> frames;
}

class FfmpegVideoStabilizationCommands {
  const FfmpegVideoStabilizationCommands({
    required this.detectArguments,
    required this.transformArguments,
    required this.transformFilePath,
    required this.outputPath,
  });

  final List<String> detectArguments;
  final List<String> transformArguments;
  final String transformFilePath;
  final String outputPath;
}

class FfmpegAudioTimelineClip {
  const FfmpegAudioTimelineClip({
    required this.inputPath,
    required this.timelineStart,
    required this.duration,
    this.volume = 1,
  });

  final String inputPath;
  final Duration timelineStart;
  final Duration duration;
  final double volume;

  Duration get timelineEnd => timelineStart + duration;
}

class FfmpegAudioChunk {
  const FfmpegAudioChunk({
    required this.path,
    required this.offset,
    required this.duration,
  });

  final String path;
  final Duration offset;
  final Duration duration;
}

class FfmpegAudioTimelineCommand {
  const FfmpegAudioTimelineCommand({
    required this.arguments,
    required this.totalDuration,
    required this.clipCount,
  });

  final List<String> arguments;
  final Duration totalDuration;
  final int clipCount;
}

typedef FfmpegExportProgressCallback = void Function(double progress);
typedef FfmpegPreviewProxyProgressCallback = void Function(double progress);

class FfmpegNotFoundException implements Exception {
  const FfmpegNotFoundException();

  @override
  String toString() {
    return 'FFmpeg e ffprobe nao foram encontrados. Coloque ffmpeg.exe/ffprobe.exe em C:\\ffmpeg\\bin, na pasta do app, ou adicione ambos ao PATH.';
  }
}

class FfmpegProcessException implements Exception {
  const FfmpegProcessException(this.message, [this.details]);

  final String message;
  final String? details;

  @override
  String toString() {
    if (details == null || details!.trim().isEmpty) {
      return message;
    }
    return '$message\n$details';
  }
}

class FfmpegExportCancelledException implements Exception {
  const FfmpegExportCancelledException();

  @override
  String toString() => 'Exportacao cancelada.';
}

class FfmpegRecordingSession {
  FfmpegRecordingSession._desktop({
    required this._process,
    required this.outputPath,
    required this._stdoutDone,
    required this._stderrDone,
    required this._stderrBuffer,
  }) : _mobileRecorder = null;

  FfmpegRecordingSession._mobile({
    required AudioRecorder recorder,
    required this.outputPath,
  }) : _process = null,
       _mobileRecorder = recorder,
       _stdoutDone = Future<void>.value(),
       _stderrDone = Future<void>.value(),
       _stderrBuffer = StringBuffer();

  final Process? _process;
  final AudioRecorder? _mobileRecorder;
  final Future<void> _stdoutDone;
  final Future<void> _stderrDone;
  final StringBuffer _stderrBuffer;
  bool _stopped = false;

  final String outputPath;

  int get pid => _process?.pid ?? -1;

  Future<void> stop({
    Duration gracefulTimeout = const Duration(seconds: 4),
  }) async {
    final mobileRecorder = _mobileRecorder;
    if (mobileRecorder != null) {
      if (_stopped) return;
      _stopped = true;
      await mobileRecorder.stop();
      await mobileRecorder.dispose();
      return;
    }
    final process = _process!;
    if (_stopped) {
      await process.exitCode;
      await _waitForStreams();
      return;
    }
    _stopped = true;

    var forcedKill = false;
    try {
      process.stdin.writeln('q');
      await process.stdin.flush();
      await process.stdin.close();
    } catch (_) {
      forcedKill = true;
      Process.killPid(pid);
    }

    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(gracefulTimeout);
    } on TimeoutException {
      forcedKill = true;
      Process.killPid(pid);
      exitCode = await process.exitCode;
    }
    await _waitForStreams();

    if (exitCode != 0 && !forcedKill) {
      throw FfmpegProcessException(
        'Nao foi possivel finalizar a gravacao de audio.',
        _lastOutputLines(_stderrBuffer.toString()),
      );
    }
  }

  Future<void> _waitForStreams() async {
    await Future.wait<void>([_stdoutDone, _stderrDone], eagerError: false);
  }

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
}

class FfmpegCommandProcess {
  const FfmpegCommandProcess._(this._handle);

  final _MediaProcessHandle _handle;

  int get pid => _handle.pid;
  Stream<List<int>> get stdout => _handle.stdout;
  Stream<List<int>> get stderr => _handle.stderr;
  Future<int> get exitCode => _handle.exitCode;

  Future<bool> cancel() => _handle.cancel();
}

abstract class _MediaProcessHandle {
  int get pid;
  Stream<List<int>> get stdout;
  Stream<List<int>> get stderr;
  Future<int> get exitCode;

  Future<bool> cancel();
}

class _DesktopMediaProcessHandle implements _MediaProcessHandle {
  const _DesktopMediaProcessHandle(this.process);

  final Process process;

  @override
  int get pid => process.pid;

  @override
  Stream<List<int>> get stdout => process.stdout;

  @override
  Stream<List<int>> get stderr => process.stderr;

  @override
  Future<int> get exitCode => process.exitCode;

  @override
  Future<bool> cancel() async => Process.killPid(process.pid);
}

class _MobileMediaProcessHandle implements _MediaProcessHandle {
  _MobileMediaProcessHandle._({
    required this._session,
    required this._stdoutController,
    required this._stderrController,
    required this._exitCodeCompleter,
  });

  final FFmpegSession _session;
  final StreamController<List<int>> _stdoutController;
  final StreamController<List<int>> _stderrController;
  final Completer<int> _exitCodeCompleter;

  static Future<_MobileMediaProcessHandle> start(List<String> arguments) async {
    final stdoutController = StreamController<List<int>>();
    final stderrController = StreamController<List<int>>();
    final exitCodeCompleter = Completer<int>();
    final session = await FFmpegKit.executeWithArgumentsAsync(
      arguments,
      (completedSession) async {
        final returnCode = await completedSession.getReturnCode();
        if (!exitCodeCompleter.isCompleted) {
          exitCodeCompleter.complete(returnCode?.getValue() ?? -1);
        }
        await stdoutController.close();
        await stderrController.close();
      },
      (log) {
        if (!stderrController.isClosed) {
          stderrController.add(utf8.encode(log.getMessage()));
        }
      },
      (statistics) {
        if (stderrController.isClosed) return;
        final elapsed = Duration(milliseconds: statistics.getTime());
        final hours = elapsed.inHours.toString().padLeft(2, '0');
        final minutes = (elapsed.inMinutes % 60).toString().padLeft(2, '0');
        final seconds = (elapsed.inMilliseconds % 60000) / 1000;
        stderrController.add(
          utf8.encode(
            'time=$hours:$minutes:${seconds.toStringAsFixed(3).padLeft(6, '0')}\n',
          ),
        );
      },
    );
    return _MobileMediaProcessHandle._(
      session: session,
      stdoutController: stdoutController,
      stderrController: stderrController,
      exitCodeCompleter: exitCodeCompleter,
    );
  }

  @override
  int get pid => _session.getSessionId() ?? -1;

  @override
  Stream<List<int>> get stdout => _stdoutController.stream;

  @override
  Stream<List<int>> get stderr => _stderrController.stream;

  @override
  Future<int> get exitCode => _exitCodeCompleter.future;

  @override
  Future<bool> cancel() async {
    await _session.cancel();
    return true;
  }
}
