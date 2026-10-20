import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/domain/models/media_item.dart';
import 'package:tgi_video_editor/domain/models/project.dart';
import 'package:tgi_video_editor/services/audio_waveform_service.dart';
import 'package:tgi_video_editor/services/ffmpeg_service.dart';
import 'package:tgi_video_editor/services/media_disk_cache.dart';
import 'package:tgi_video_editor/services/preview_proxy_cache_service.dart';

void main() {
  test(
    'measure real media operations with a 1080p source',
    () async {
      final root = Directory('../.work/performance')
        ..createSync(recursive: true);
      final run = await root.createTemp('run_');
      final disk = MediaDiskCache(directoryPath: '${run.path}/cache');
      final proxies = PreviewProxyCacheService(
        cacheDirectoryPath: '${run.path}/proxies',
      );
      final service = FfmpegService(
        thumbnailCache: disk,
        previewProxyCacheService: proxies,
      );
      final measurements = <String, double>{};
      Future<T> measure<T>(String name, Future<T> Function() action) async {
        final watch = Stopwatch()..start();
        final result = await action();
        watch.stop();
        measurements[name] = watch.elapsedMicroseconds / 1000;
        return result;
      }

      final source = '${run.path}/source.mp4';
      final generated = await service.runCommand([
        '-y',
        '-v',
        'error',
        '-f',
        'lavfi',
        '-i',
        'testsrc2=s=1920x1080:r=30:d=5',
        '-f',
        'lavfi',
        '-i',
        'sine=frequency=440:sample_rate=48000:duration=5',
        '-c:v',
        'libx264',
        '-preset',
        'ultrafast',
        '-crf',
        '20',
        '-c:a',
        'aac',
        '-shortest',
        source,
      ]);
      expect(generated.exitCode, 0, reason: '${generated.stderr}');
      final media = MediaItem(
        id: 'bench',
        filePath: source,
        name: 'Benchmark',
        type: MediaType.video,
        duration: const Duration(seconds: 5),
        importedAt: DateTime.now(),
        width: 1920,
        height: 1080,
        hasAudio: true,
      );
      await measure(
        'metadata_thumbnail_cold_ms',
        () => service.inspectVideo(File(source)),
      );
      final second = FfmpegService(
        thumbnailCache: disk,
        previewProxyCacheService: proxies,
      );
      await second.resolveToolchain();
      await measure(
        'metadata_thumbnail_disk_ms',
        () => second.inspectVideo(File(source)),
      );
      final waveform = AudioWaveformService(
        ffmpegService: service,
        diskCache: disk,
      );
      await measure('waveform_cold_ms', () => waveform.extractWaveform(media));
      final warmWaveform = AudioWaveformService(
        ffmpegService: service,
        diskCache: disk,
      );
      await measure(
        'waveform_disk_ms',
        () => warmWaveform.extractWaveform(media),
      );
      final proxy = await measure(
        'proxy_build_ms',
        () => service.createPreviewProxy(media),
      );
      await measure('proxy_disk_ms', () => second.createPreviewProxy(media));
      for (final entry in {'original': source, 'proxy': proxy}.entries) {
        final decoded = await measure(
          'decode_${entry.key}_ms',
          () => service.runCommand([
            '-v',
            'error',
            '-i',
            entry.value,
            '-an',
            '-f',
            'null',
            '-',
          ]),
        );
        expect(decoded.exitCode, 0, reason: '${decoded.stderr}');
      }
      final project = TgiProject.empty(name: 'Benchmark')
          .copyWith(mediaPool: [media])
          .addMediaItemToTimeline(media, timelineStart: Duration.zero);
      await measure(
        'export_720p_cpu_ms',
        () => service.exportProject(project, '${run.path}/output.mp4'),
      );
      expect(second.thumbnailCacheHits, 1);
      expect(warmWaveform.diskCacheHits, 1);
      final result = {
        'timestampUtc': DateTime.now().toUtc().toIso8601String(),
        'os': Platform.operatingSystemVersion,
        'logicalProcessors': Platform.numberOfProcessors,
        'source':
            'Synthetic testsrc2 + 440 Hz, 1920x1080, 30 fps, 5 s, H.264/AAC',
        'runsPerOperation': 1,
        'sourceBytes': await File(source).length(),
        'proxyBytes': await File(proxy).length(),
        'measurementsMs': measurements,
        'thumbnailDiskHits': second.thumbnailCacheHits,
        'waveformDiskHits': warmWaveform.diskCacheHits,
        'encoder': service.lastExportEncoder.name,
      };
      await File(
        '../.work/performance-results.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(result));
      // ignore: avoid_print
      print('BENCHMARK_RESULT=${jsonEncode(result)}');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
