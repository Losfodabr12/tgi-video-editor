import 'ffmpeg_service_models.dart';

abstract final class FfmpegAudioExport {
  static FfmpegExportCommand apply(FfmpegExportCommand command) {
    final args = [...command.arguments];
    final graph = args.indexOf('-filter_complex') + 1;
    final map = args.indexOf('-map');
    final video = args[map + 1];
    args[graph] = '${args[graph]};${video}nullsink';
    args.removeRange(map, map + 2);
    const videoOptions = {
      '-c:v',
      '-pix_fmt',
      '-preset',
      '-crf',
      '-rc',
      '-cq',
      '-b:v',
      '-global_quality',
      '-quality',
      '-qp_i',
      '-qp_p',
      '-movflags',
      '-b:a',
    };
    for (var i = 0; i < args.length - 1;) {
      if (videoOptions.contains(args[i])) {
        args.removeRange(i, i + 2);
      } else {
        i++;
      }
    }
    args[args.indexOf('-c:a') + 1] = 'pcm_s16le';
    args.insertAll(args.length - 1, [
      '-vn',
      '-ar',
      '48000',
      '-ac',
      '2',
      '-f',
      'wav',
    ]);
    return FfmpegExportCommand(
      arguments: args,
      totalDuration: command.totalDuration,
      clipCount: command.clipCount,
      textFiles: command.textFiles,
    );
  }
}
