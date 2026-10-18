import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'ffmpeg_service.dart';

class AudioLevelFrame {
  const AudioLevelFrame(this.peak, this.rms);
  final double peak;
  final double rms;
}

class AudioLevels {
  const AudioLevels(
    this.frames, {
    this.interval = const Duration(milliseconds: 100),
  });
  final List<AudioLevelFrame> frames;
  final Duration interval;
  AudioLevelFrame at(Duration position) {
    final index = position.inMicroseconds ~/ interval.inMicroseconds;
    return index < 0 || index >= frames.length
        ? const AudioLevelFrame(0, 0)
        : frames[index];
  }

  AudioLevelFrame measure(Duration start, Duration duration) {
    if (duration <= Duration.zero || frames.isEmpty) {
      return const AudioLevelFrame(0, 0);
    }
    final first = (start.inMicroseconds ~/ interval.inMicroseconds).clamp(
      0,
      frames.length,
    );
    final end = ((start + duration).inMicroseconds / interval.inMicroseconds)
        .ceil()
        .clamp(first, frames.length);
    var peak = 0.0, square = 0.0;
    for (var i = first; i < end; i++) {
      peak = math.max(peak, frames[i].peak);
      square += frames[i].rms * frames[i].rms;
    }
    return AudioLevelFrame(
      peak,
      end > first ? math.sqrt(square / (end - first)) : 0,
    );
  }
}

/// Streaming PCM measurements keep real amplitudes (unlike normalized waveform
/// thumbnails), with only ten peak/RMS pairs per second retained in memory.
class AudioLevelService {
  AudioLevelService(this.ffmpeg);
  final FfmpegService ffmpeg;
  final _cache = <String, Future<AudioLevels>>{};
  final _active = <FfmpegCommandProcess>{};
  Future<void> _tail = Future<void>.value();
  bool _disposed = false;

  Future<AudioLevels> analyze(String path) async {
    if (_disposed) throw StateError('Análise de áudio encerrada.');
    final file = File(path);
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      throw FileSystemException('Áudio não encontrado', path);
    }
    final key =
        '${file.absolute.path}|${stat.size}|${stat.modified.microsecondsSinceEpoch}';
    if (_cache.containsKey(key)) return _cache[key]!;
    final future = _tail.then((_) => _analyze(file.path));
    _tail = future.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    _cache[key] = future;
    try {
      return await future;
    } catch (_) {
      _cache.remove(key);
      rethrow;
    }
  }

  Future<AudioLevels> _analyze(String path) async {
    if (_disposed) throw StateError('Análise cancelada.');
    // A temporary PCM file also works with the embedded FFmpeg on mobile.
    final mobile = Platform.isAndroid || Platform.isIOS;
    final temp = mobile
        ? await Directory.systemTemp.createTemp('tgi_audio_levels_')
        : null;
    final output = temp == null ? 'pipe:1' : '${temp.path}/samples.f32';
    final process = await ffmpeg.startCommand([
      '-hide_banner',
      '-nostdin',
      '-v',
      'error',
      '-i',
      path,
      '-vn',
      '-map',
      '0:a:0',
      '-ac',
      '2',
      '-ar',
      '48000',
      '-f',
      'f32le',
      output,
    ]);
    _active.add(process);
    if (_disposed) await process.cancel();
    final errors = <int>[];
    final errorDrain = process.stderr.listen((bytes) {
      if (errors.length < 16000) {
        errors.addAll(bytes.take(16000 - errors.length));
      }
    });
    try {
      late AudioLevels levels;
      if (temp == null) {
        levels = await decodePcm(process.stdout);
      } else {
        await process.stdout.drain<void>();
      }
      final code = await process.exitCode;
      if (_disposed) throw StateError('Análise cancelada.');
      if (code != 0) {
        throw const FfmpegProcessException(
          'Não foi possível medir o áudio deste arquivo.',
        );
      }
      if (temp != null) levels = await decodePcm(File(output).openRead());
      return levels;
    } finally {
      _active.remove(process);
      await errorDrain.cancel();
      if (temp != null) await temp.delete(recursive: true);
    }
  }

  static Future<AudioLevels> decodePcm(Stream<List<int>> stream) async {
    const samplesPerFrame = 4800 * 2;
    final frames = <AudioLevelFrame>[];
    var count = 0;
    var peak = 0.0, square = 0.0;
    var remaining = <int>[];
    await for (final chunk in stream) {
      final bytes = Uint8List.fromList([...remaining, ...chunk]);
      final valid = bytes.length - bytes.length % 4;
      final data = ByteData.sublistView(bytes);
      for (var offset = 0; offset < valid; offset += 4) {
        final sample = data.getFloat32(offset, Endian.little);
        final value = sample.isFinite ? sample : 0.0;
        peak = math.max(peak, value.abs());
        square += value * value;
        if (++count == samplesPerFrame) {
          frames.add(AudioLevelFrame(peak, math.sqrt(square / count)));
          count = 0;
          peak = 0;
          square = 0;
        }
      }
      remaining = bytes.sublist(valid);
    }
    if (count > 0) frames.add(AudioLevelFrame(peak, math.sqrt(square / count)));
    return AudioLevels(List.unmodifiable(frames));
  }

  void dispose() {
    _disposed = true;
    for (final process in _active.toList()) {
      unawaited(process.cancel());
    }
    _cache.clear();
  }
}
