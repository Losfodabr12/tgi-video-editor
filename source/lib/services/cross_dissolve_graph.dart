import '../domain/models/cross_dissolve.dart';
import 'ffmpeg_service_models.dart';

/// Appends an A/B transition to the rendered, unencoded timeline. The v14
/// transition is global, so every composited layer participates at the edit.
abstract final class CrossDissolveGraph {
  static FfmpegExportCommand apply(
    FfmpegExportCommand command,
    List<CrossDissolve> cuts,
    int fps,
  ) {
    if (cuts.isEmpty) return command;
    final args = [...command.arguments];
    final graph = args.indexOf('-filter_complex') + 1;
    final maps = <int>[
      for (var i = 0; i < args.length - 1; i++)
        if (args[i] == '-map') i + 1,
    ];
    final video = args[maps[0]], audio = args[maps[1]];
    final count = cuts.length + 1;
    final filters = <String>[
      '$video'
          'split=$count${List.generate(count, (i) => '[dvi$i]').join()}',
      '$audio'
          'asplit=$count${List.generate(count, (i) => '[dai$i]').join()}',
    ];
    String sec(Duration value) =>
        (value.inMicroseconds / 1000000).toStringAsFixed(6);
    for (var i = 0; i < count; i++) {
      final start = i == 0 ? Duration.zero : cuts[i - 1].boundary;
      final end = i == cuts.length ? command.totalDuration : cuts[i].boundary;
      final duration = end - start;
      final before = i == 0 ? Duration.zero : cuts[i - 1].incoming;
      final after = i == cuts.length ? Duration.zero : cuts[i].outgoing;
      filters.add(
        '[dvi$i]trim=start=${sec(start)}:end=${sec(end)},setpts=PTS-STARTPTS,'
        'fps=$fps,settb=AVTB,tpad=start_mode=clone:stop_mode=clone:start_duration=${sec(before)}:stop_duration=${sec(after)},format=yuv444p[dv$i]',
      );
      // Repeat a short source handle at each edge; padding with silence would
      // cause an audible hole at the center of the crossfade.
      final branches =
          1 +
          (before > Duration.zero ? 1 : 0) +
          (after > Duration.zero ? 1 : 0);
      filters.add(
        '[dai$i]atrim=start=${sec(start)}:end=${sec(end)},asetpts=PTS-STARTPTS,'
        'aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo,apad,'
        'atrim=duration=${sec(duration)},asplit=$branches[dab$i]'
        '${before > Duration.zero ? '[dah$i]' : ''}${after > Duration.zero ? '[dat$i]' : ''}',
      );
      if (before > Duration.zero) {
        filters.add(
          '[dah$i]atrim=duration=${sec(before)},asetpts=PTS-STARTPTS[head$i]',
        );
      }
      if (after > Duration.zero) {
        filters.add(
          '[dat$i]atrim=start=${sec(duration - after)},asetpts=PTS-STARTPTS[tail$i]',
        );
      }
      filters.add(
        '${before > Duration.zero ? '[head$i]' : ''}[dab$i]${after > Duration.zero ? '[tail$i]' : ''}concat=n=$branches:v=0:a=1[da$i]',
      );
    }
    var v = 'dv0', a = 'da0';
    for (var i = 1; i < count; i++) {
      final cut = cuts[i - 1];
      filters.add(
        '[$v][dv$i]xfade=transition=fade:duration=${sec(cut.duration)}:offset=${sec(cut.start)}[dmv$i]',
      );
      filters.add(
        '[$a][da$i]acrossfade=d=${sec(cut.duration)}:c1=tri:c2=tri[dma$i]',
      );
      v = 'dmv$i';
      a = 'dma$i';
    }
    args[graph] = '${args[graph]};${filters.join(';')}';
    args[maps[0]] = '[$v]';
    args[maps[1]] = '[$a]';
    return FfmpegExportCommand(
      arguments: args,
      totalDuration: command.totalDuration,
      clipCount: command.clipCount,
      textFiles: command.textFiles,
    );
  }
}
