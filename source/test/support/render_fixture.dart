import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/domain/models/clip.dart';
import 'package:tgi_video_editor/domain/models/media_item.dart';
import 'package:tgi_video_editor/domain/models/project.dart';
import 'package:tgi_video_editor/domain/models/track.dart';
import 'package:tgi_video_editor/services/ffmpeg_service.dart';

class RenderFixture {
  final service = FfmpegService();
  late Directory directory;
  static const settings = FfmpegExportSettings(
    resolution: FfmpegExportResolution(
      id: 'fixture',
      label: 'Fixture',
      width: 160,
      height: 90,
    ),
    framesPerSecond: 20,
    quality: FfmpegExportQuality.maximum,
  );

  Future<void> open() async {
    directory = await Directory.systemTemp.createTemp('editor_pixels_');
  }

  Future<void> close() => directory.delete(recursive: true);

  Future<MediaItem> color(
    String name, {
    double seconds = 1,
    String? audio,
  }) async {
    final path = '${directory.path}/$name.mp4';
    await run([
      '-y',
      '-v',
      'error',
      '-f',
      'lavfi',
      '-i',
      'color=$name:s=160x90:r=20:d=$seconds',
      if (audio != null) ...[
        '-f',
        'lavfi',
        '-i',
        'sine=frequency=$audio:duration=$seconds',
      ],
      '-c:v',
      'libx264',
      '-pix_fmt',
      'yuv420p',
      if (audio != null) ...['-c:a', 'aac', '-shortest'],
      path,
    ]);
    return MediaItem(
      id: name,
      filePath: path,
      name: name,
      type: MediaType.video,
      duration: Duration(microseconds: (seconds * 1000000).round()),
      importedAt: DateTime(2026),
      hasAudio: audio != null,
    );
  }

  Clip clip(MediaItem item, {Duration start = Duration.zero}) => Clip(
    id: item.id,
    mediaItemId: item.id,
    timelineGroupId: item.id,
    trackType: TrackType.video,
    timelineStart: start,
    sourceStart: Duration.zero,
    duration: item.duration,
    overlayX: .5,
    overlayY: .5,
    overlayScale: 4,
  );

  TgiProject project(List<MediaItem> media, List<Clip> clips) =>
      TgiProject.empty(name: 'Pixels').copyWith(
        mediaPool: media,
        tracks: [
          for (final clip in clips)
            Track(
              id: clip.id,
              name: clip.id,
              kind: TrackKind.visual,
              clips: [clip],
            ),
        ],
      );

  Future<String> export(TgiProject project, String name) async {
    final output = '${directory.path}/$name.mp4';
    await service.exportProject(project, output, settings: settings);
    return output;
  }

  Future<Uint8List> pixel(
    String path,
    double time, {
    int x = 80,
    int y = 44,
  }) async {
    final bytes =
        (await run([
              '-v',
              'error',
              '-ss',
              '$time',
              '-i',
              path,
              '-vf',
              'crop=2:2:$x:$y,scale=1:1',
              '-frames:v',
              '1',
              '-pix_fmt',
              'rgb24',
              '-f',
              'rawvideo',
              'pipe:1',
            ])).stdout
            as List<int>;
    expect(bytes.length, 3, reason: 'frame at $time');
    return Uint8List.fromList(bytes);
  }

  Future<ProcessResult> run(List<String> args) async {
    final result = await Process.run(
      (await service.resolveToolchain()).ffmpegPath,
      args,
      stdoutEncoding: null,
      stderrEncoding: null,
    );
    expect(
      result.exitCode,
      0,
      reason: String.fromCharCodes(result.stderr as List<int>),
    );
    return result;
  }
}
