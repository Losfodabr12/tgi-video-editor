import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../domain/models/audio_waveform.dart';
import '../domain/models/media_item.dart';
import 'ffmpeg_service.dart';
import 'media_disk_cache.dart';

class AudioWaveformService {
  AudioWaveformService({
    required this.ffmpegService,
    this.sampleInterval = const Duration(milliseconds: 100),
    this.rawSampleRate = 100,
    MediaDiskCache? diskCache,
  }) : diskCache = diskCache ?? MediaDiskCache();

  final FfmpegService ffmpegService;
  final Duration sampleInterval;
  final int rawSampleRate;
  final MediaDiskCache diskCache;
  int diskCacheHits = 0;
  int extractions = 0;
  final Map<String, Future<AudioWaveform>> _cache = {};

  Future<AudioWaveform> extractWaveform(MediaItem item) {
    if (item.type != MediaType.video && item.type != MediaType.audio) {
      return Future.value(_emptyWaveform());
    }
    return extractFileWaveform(item.filePath);
  }

  Future<AudioWaveform> extractFileWaveform(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return _emptyWaveform();
    }

    final stat = await file.stat();
    final key = [
      file.path,
      stat.modified.microsecondsSinceEpoch,
      stat.size,
      sampleInterval.inMilliseconds,
      rawSampleRate,
    ].join('|');

    final cached = _cache[key];
    if (cached != null) {
      return cached;
    }

    final future = _extractOrRead(file.path).catchError((Object error) {
      _cache.remove(key);
      throw error;
    });
    _cache[key] = future;
    return future;
  }

  Future<AudioWaveform> _extractOrRead(String path) async {
    File? entry;
    try {
      entry = await diskCache.entry(
        path,
        'waveform-v1:${sampleInterval.inMicroseconds}:$rawSampleRate',
        'json',
      );
      if (await entry.exists()) {
        final data = jsonDecode(await entry.readAsString()) as Map;
        final values = (data['samples'] as List)
            .map((v) => (v as num).toDouble())
            .toList();
        if (data['version'] == 1 &&
            data['intervalUs'] == sampleInterval.inMicroseconds &&
            values.every((v) => v.isFinite && v >= 0 && v <= 1)) {
          diskCacheHits++;
          return AudioWaveform(samples: values, sampleInterval: sampleInterval);
        }
      }
    } catch (_) {
      // Corrupt/unwritable caches must not prevent media import.
    }
    extractions++;
    final waveform = await _extract(path);
    if (entry != null && waveform.samples.isNotEmpty) {
      final temporary = File(
        '${entry.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
      );
      try {
        await temporary.writeAsString(
          jsonEncode({
            'version': 1,
            'intervalUs': sampleInterval.inMicroseconds,
            'samples': waveform.samples,
          }),
          flush: true,
        );
        await MediaDiskCache.publish(temporary, entry);
      } on FileSystemException {
        // The waveform remains usable when the cache is full or read-only.
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    }
    return waveform;
  }

  Future<AudioWaveform> _extract(String filePath) async {
    if (sampleInterval <= Duration.zero || rawSampleRate <= 0) {
      return _emptyWaveform();
    }

    final arguments = <String>[
      '-hide_banner',
      '-nostdin',
      '-v',
      'error',
      '-i',
      filePath,
      '-vn',
      '-map',
      '0:a:0?',
      '-ac',
      '1',
      '-ar',
      rawSampleRate.toString(),
      '-f',
      'f32le',
    ];
    if (Platform.isAndroid || Platform.isIOS) {
      final outputFile = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'tgi_waveform_${DateTime.now().microsecondsSinceEpoch}.raw',
      );
      arguments
        ..insert(0, '-y')
        ..add(outputFile.path);
      try {
        final result = await ffmpegService.runCommand(arguments);
        if (result.exitCode != 0 || !await outputFile.exists()) {
          return _emptyWaveform();
        }
        return _waveformFromPcmBytes(await outputFile.readAsBytes());
      } finally {
        if (await outputFile.exists()) {
          await outputFile.delete();
        }
      }
    }

    arguments.add('pipe:1');
    final toolchain = await ffmpegService.resolveToolchain();
    final result = await Process.run(
      toolchain.ffmpegPath,
      arguments,
      runInShell: !_isAbsoluteWindowsPath(toolchain.ffmpegPath),
      stdoutEncoding: null,
      stderrEncoding: systemEncoding,
    );
    if (result.exitCode != 0 || result.stdout is! List<int>) {
      return _emptyWaveform();
    }

    return _waveformFromPcmBytes(result.stdout as List<int>);
  }

  AudioWaveform _waveformFromPcmBytes(List<int> bytes) {
    final byteCount = bytes.length - (bytes.length % 4);
    if (byteCount <= 0) {
      return _emptyWaveform();
    }

    final framesPerSample = math.max(
      1,
      (rawSampleRate * sampleInterval.inMilliseconds / 1000).round(),
    );
    final frameCount = byteCount ~/ 4;
    final outputCount = (frameCount / framesPerSample).ceil();
    final peaks = List<double>.filled(outputCount, 0);
    final data = ByteData.sublistView(Uint8List.fromList(bytes), 0, byteCount);
    var globalPeak = 0.0;

    for (var frame = 0; frame < frameCount; frame++) {
      final value = data.getFloat32(frame * 4, Endian.little).abs();
      if (value.isNaN || value.isInfinite) {
        continue;
      }
      final index = frame ~/ framesPerSample;
      if (value > peaks[index]) {
        peaks[index] = value;
      }
      if (value > globalPeak) {
        globalPeak = value;
      }
    }

    if (globalPeak <= 0) {
      return AudioWaveform(
        samples: List<double>.unmodifiable(peaks),
        sampleInterval: sampleInterval,
      );
    }

    return AudioWaveform(
      samples: List<double>.unmodifiable(
        peaks.map((peak) => (peak / globalPeak).clamp(0.0, 1.0).toDouble()),
      ),
      sampleInterval: sampleInterval,
    );
  }

  AudioWaveform _emptyWaveform() {
    return AudioWaveform(
      samples: const <double>[],
      sampleInterval: sampleInterval,
    );
  }

  bool _isAbsoluteWindowsPath(String value) {
    return RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(value) ||
        value.startsWith(r'\\');
  }
}
