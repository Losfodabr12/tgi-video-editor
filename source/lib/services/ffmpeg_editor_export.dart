part of 'ffmpeg_service.dart';

extension _EditorExport on FfmpegService {
  List<String> _replaceVideoEncoder(
    List<String> arguments,
    FfmpegVideoEncoder encoder,
    FfmpegExportQuality quality,
  ) =>
      FfmpegFiltergraphBuilder.replaceVideoEncoder(arguments, encoder, quality);

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
