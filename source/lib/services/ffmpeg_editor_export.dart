part of 'ffmpeg_service.dart';

extension _EditorExport on FfmpegService {
  FfmpegExportCommand _applyEditorExportOptions(
    FfmpegExportCommand command,
    FfmpegExportSettings settings,
  ) {
    final duration = settings.exportDuration(command.totalDuration);
    final arguments =
        settings.encoder == FfmpegVideoEncoder.software ||
            settings.encoder == FfmpegVideoEncoder.automatic
        ? List<String>.of(command.arguments)
        : _replaceVideoEncoder(
            command.arguments,
            settings.encoder,
            settings.quality,
          );
    if (settings.hasRange) {
      // Output seeking preserves the timeline clock used by fades, text,
      // transitions and ducking, then resets the timestamps in the output.
      arguments.insertAll(arguments.length - 1, [
        '-ss',
        _seconds(settings.rangeStart ?? Duration.zero),
        '-t',
        _seconds(duration),
      ]);
    }
    return FfmpegExportCommand(
      arguments: arguments,
      totalDuration: duration,
      clipCount: command.clipCount,
    );
  }

  List<String> _replaceVideoEncoder(
    List<String> source,
    FfmpegVideoEncoder encoder,
    FfmpegExportQuality quality,
  ) {
    final args = List<String>.of(source);
    final codecIndex = args.indexOf('-c:v');
    if (codecIndex < 0) return args;
    args[codecIndex + 1] = encoder.codec;
    const options = {
      '-preset',
      '-crf',
      '-rc',
      '-cq',
      '-b:v',
      '-global_quality',
      '-quality',
      '-qp_i',
      '-qp_p',
    };
    for (var i = codecIndex + 2; i < args.length - 1;) {
      if (options.contains(args[i])) {
        args.removeRange(i, i + 2);
      } else {
        i++;
      }
    }
    final q = quality.crf.toString();
    final flags = switch (encoder) {
      FfmpegVideoEncoder.nvidia => [
        '-preset',
        'p4',
        '-rc',
        'vbr',
        '-cq',
        q,
        '-b:v',
        '0',
      ],
      FfmpegVideoEncoder.intel => ['-preset', 'medium', '-global_quality', q],
      FfmpegVideoEncoder.amd => [
        '-quality',
        'balanced',
        '-rc',
        'cqp',
        '-qp_i',
        q,
        '-qp_p',
        q,
      ],
      _ => ['-preset', quality.encoderPreset, '-crf', q],
    };
    args.insertAll(codecIndex + 2, flags);
    return args;
  }

  Future<FfmpegVideoEncoder> _resolveExportEncoder(
    FfmpegVideoEncoder requested,
  ) async {
    if (requested == FfmpegVideoEncoder.software) return requested;
    final candidates = requested == FfmpegVideoEncoder.automatic
        ? [
            FfmpegVideoEncoder.nvidia,
            FfmpegVideoEncoder.intel,
            FfmpegVideoEncoder.amd,
          ]
        : [requested];
    for (final encoder in candidates) {
      _checkExportCancellation();
      if (await _probeEncoder(encoder)) return encoder;
    }
    lastExportNotice =
        'Aceleração indisponível nesta máquina. Exportação realizada pela CPU.';
    return FfmpegVideoEncoder.software;
  }

  Future<bool> _probeEncoder(FfmpegVideoEncoder encoder) async {
    final cached = _encoderAvailability[encoder];
    if (cached != null) return cached;
    FfmpegCommandProcess? process;
    try {
      process = await startCommand([
        '-hide_banner',
        '-nostdin',
        '-v',
        'error',
        '-f',
        'lavfi',
        '-i',
        'color=black:s=640x360:r=30:d=0.1',
        '-frames:v',
        '1',
        '-c:v',
        encoder.codec,
        '-pix_fmt',
        'yuv420p',
        '-f',
        'null',
        '-',
      ]);
      _activeExportProcess = process;
      if (_exportCancellationRequested) {
        unawaited(process.cancel());
      }
      final streams = Future.wait([
        process.stdout.drain<void>(),
        process.stderr.drain<void>(),
      ]);
      final exit = await process.exitCode.timeout(const Duration(seconds: 8));
      await streams;
      _checkExportCancellation();
      return _encoderAvailability[encoder] = exit == 0;
    } on FfmpegExportCancelledException {
      rethrow;
    } catch (_) {
      await process?.cancel();
      return _encoderAvailability[encoder] = false;
    } finally {
      if (identical(_activeExportProcess, process)) _activeExportProcess = null;
    }
  }
}
