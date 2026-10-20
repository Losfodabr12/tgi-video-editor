import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/services/audio_waveform_service.dart';
import 'package:tgi_video_editor/services/ffmpeg_service.dart';
import 'package:tgi_video_editor/services/media_disk_cache.dart';
import 'package:tgi_video_editor/services/preview_proxy_cache_service.dart';

import 'support/render_fixture.dart';

class _UnavailableFfmpeg extends FfmpegService {
  @override
  Future<FfmpegToolchain> resolveToolchain() =>
      throw StateError('Decoder must not run for a disk hit');
}

void main() {
  final fixture = RenderFixture();
  setUp(fixture.open);
  tearDown(fixture.close);

  test(
    'vertical proxies preserve aspect ratio without baked letterboxing',
    () async {
      final original = await fixture.color('red');
      final vertical = '${fixture.directory.path}/vertical.mp4';
      await fixture.run([
        '-y',
        '-v',
        'error',
        '-f',
        'lavfi',
        '-i',
        'color=red:s=90x160:r=20:d=1',
        '-c:v',
        'libx264',
        vertical,
      ]);
      final media = original.copyWith(
        filePath: vertical,
        width: 90,
        height: 160,
      );
      final service = FfmpegService(
        previewProxyCacheService: PreviewProxyCacheService(
          cacheDirectoryPath: '${fixture.directory.path}/vertical-cache',
        ),
      );
      final proxy = await service.createPreviewProxy(media);
      final metadata = await service.inspectVideo(File(proxy));
      expect(metadata.width! / metadata.height!, closeTo(90 / 160, .005));
      expect((await fixture.pixel(proxy, .5, x: 4, y: 4))[0], greaterThan(225));
    },
  );

  test(
    'waveform survives a new service, invalidates parameters and repairs corruption',
    () async {
      final media = await fixture.color('red', audio: '440');
      final disk = MediaDiskCache(
        directoryPath: '${fixture.directory.path}/cache',
      );
      final first = AudioWaveformService(
        ffmpegService: fixture.service,
        diskCache: disk,
      );
      final waveform = await first.extractWaveform(media);
      expect(waveform.samples, isNotEmpty);
      final reopened = AudioWaveformService(
        ffmpegService: _UnavailableFfmpeg(),
        diskCache: disk,
      );
      expect((await reopened.extractWaveform(media)).samples, waveform.samples);
      expect(reopened.diskCacheHits, 1);
      expect(reopened.extractions, 0);
      final changed = AudioWaveformService(
        ffmpegService: fixture.service,
        diskCache: disk,
        sampleInterval: const Duration(milliseconds: 200),
      );
      expect(
        (await changed.extractWaveform(media)).samples.length,
        lessThan(waveform.samples.length),
      );
      final entry = await disk.entry(
        media.filePath,
        'waveform-v1:100000:100',
        'json',
      );
      await entry.writeAsString('{corrupt');
      final repaired = AudioWaveformService(
        ffmpegService: fixture.service,
        diskCache: disk,
      );
      expect((await repaired.extractWaveform(media)).samples, waveform.samples);
      expect(repaired.extractions, 1);
      final before = await MediaDiskCache.fingerprint(
        media.filePath,
        'waveform',
      );
      await File(
        media.filePath,
      ).setLastModified(DateTime.now().add(const Duration(seconds: 2)));
      expect(
        await MediaDiskCache.fingerprint(media.filePath, 'waveform'),
        isNot(before),
      );
    },
  );

  test(
    'thumbnails and proxies are reusable across service instances',
    () async {
      final media = await fixture.color('blue');
      final disk = MediaDiskCache(
        directoryPath: '${fixture.directory.path}/thumbs',
      );
      final proxy = PreviewProxyCacheService(
        cacheDirectoryPath: '${fixture.directory.path}/proxies',
      );
      final first = FfmpegService(
        thumbnailCache: disk,
        previewProxyCacheService: proxy,
      );
      final metadata = await first.inspectVideo(File(media.filePath));
      final proxyPath = await first.createPreviewProxy(media);
      final reopened = FfmpegService(
        thumbnailCache: disk,
        previewProxyCacheService: proxy,
      );
      expect(
        (await reopened.inspectVideo(File(media.filePath))).thumbnailPath,
        metadata.thumbnailPath,
      );
      expect(reopened.thumbnailCacheHits, 1);
      final modified = await File(proxyPath).lastModified();
      expect(await reopened.createPreviewProxy(media), proxyPath);
      expect(await File(proxyPath).lastModified(), modified);
      expect(
        await Directory(
          proxy.cacheDirectoryPath,
        ).list().where((f) => f.path.contains('.tmp.')).length,
        0,
      );
    },
  );
}
