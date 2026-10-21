import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../core/commands/command_engine.dart';
import '../domain/models/media_item.dart';
import '../domain/models/project.dart';
import '../domain/models/track.dart';
import '../features/editor/application/editor_controller.dart';
import '../services/auto_caption_service.dart';
import '../services/ffmpeg_service.dart';
import 'editor_jobs.dart';
import 'project_reads.dart';

typedef MediaPathCheck = Future<String> Function(MediaItem media);

class EditorReadService {
  EditorReadService(
    this.controller, {
    FfmpegService? ffmpeg,
    this.captions,
    EditorJobs? jobs,
    MediaPathCheck? checkMedia,
  }) : ffmpeg = ffmpeg ?? FfmpegService(),
       jobs = jobs ?? EditorJobs(),
       checkMedia = checkMedia ?? _existingMedia;
  final EditorController controller;
  final FfmpegService ffmpeg;
  final EditorJobs jobs;
  final AutoCaptionService? captions;
  final MediaPathCheck checkMedia;
  final Map<String, List<CaptionCue>> _transcripts = {};
  static Future<String> _existingMedia(MediaItem item) async {
    final file = File(item.filePath);
    if (!await file.exists()) {
      throw CommandError(
        'media_missing',
        'Mídia indisponível; reconecte pela interface.',
        {'media_id': item.id},
      );
    }
    return file.resolveSymbolicLinks();
  }

  String _key(TgiProject p, MediaItem item) =>
      '${p.id}|${item.id}|${item.filePath}|${item.duration.inMicroseconds}';
  MediaItem media(String id, [TgiProject? project]) {
    final p = project ?? controller.project;
    return p.mediaItemById(id) ??
        (throw CommandError(
          'media_not_found',
          'Mídia desconhecida. Use list_media.',
          {'valid_media_ids': p.mediaPool.map((m) => m.id).toList()},
        ));
  }

  Map<String, Object?> getProject({String? cursor, int limit = 50}) {
    var offset = 0;
    if (cursor != null) {
      final parts = cursor.split(':');
      if (parts.length != 2 ||
          int.tryParse(parts[0]) == null ||
          int.tryParse(parts[1]) == null) {
        throw const CommandError(
          'invalid_cursor',
          'Use next_cursor retornado por get_project.',
        );
      }
      checkRevision(int.parse(parts[0]), controller.projectRevision);
      offset = int.parse(parts[1]);
    }
    return projectSummary(
      controller.project,
      controller.projectRevision,
      offset: offset,
      limit: limit,
    );
  }

  Map<String, Object?> getClip(String id) {
    final p = controller.project, c = p.clipById(id);
    if (c == null) {
      throw CommandError('clip_not_found', 'Clipe desconhecido.', {
        'valid_clip_ids': p.tracks
            .expand((t) => t.clips)
            .map((c) => c.id)
            .toList(),
      });
    }
    return {
      ...clipSummary(p, c),
      'revision': controller.projectRevision,
      'style': {
        'font_family': c.fontFamily,
        'font_size': c.fontSize,
        'text_color': c.textColor,
        'background_color': c.backgroundColor,
        'opacity': c.opacity,
        'animation': c.textAnimation.name,
      },
      'effects': {
        'brightness': c.brightness,
        'contrast': c.contrast,
        'saturation': c.saturation,
        'exposure': c.exposure,
        'hue': c.hue,
        'filter': c.filterPreset.name,
        'crop_left': c.cropLeft,
        'crop_right': c.cropRight,
        'crop_top': c.cropTop,
        'crop_bottom': c.cropBottom,
      },
      'keyframes': [
        for (final k in c.keyframes)
          {
            'id': k.id,
            'property': k.property.name,
            'time': k.time,
            'value': k.value,
          },
      ],
    };
  }

  Map<String, Object?> listMedia({int offset = 0, int limit = 50}) {
    final p = controller.project;
    if (offset < 0 || offset > p.mediaPool.length || limit < 1 || limit > 100) {
      throw const CommandError(
        'invalid_page',
        'Use offset válido e limit entre 1 e 100.',
      );
    }
    return {
      'revision': controller.projectRevision,
      'total': p.mediaPool.length,
      'media': [
        for (final m in p.mediaPool.skip(offset).take(limit))
          {
            'id': m.id,
            'name': m.name,
            'type': m.type.name,
            'duration': seconds(m.duration),
            'width': m.width,
            'height': m.height,
            'has_audio': m.hasAudio,
          },
      ],
      'next_offset': offset + limit < p.mediaPool.length
          ? offset + limit
          : null,
    };
  }

  List<CaptionCue> transcriptCues(String mediaId, [TgiProject? project]) {
    final p = project ?? controller.project, item = media(mediaId, project);
    final cached = _transcripts[_key(p, item)];
    if (cached == null) {
      throw const CommandError(
        'transcript_unavailable',
        'Execute transcribe e aguarde get_job antes de pedir a transcrição.',
      );
    }
    return cached;
  }

  Map<String, Object?> getTranscript({
    String? mediaId,
    int offset = 0,
    int limit = 100,
  }) {
    if (offset < 0 || limit < 1 || limit > 100) {
      throw const CommandError(
        'invalid_page',
        'Use offset >= 0 e limit entre 1 e 100.',
      );
    }
    final cues = mediaId == null
        ? controller.generatedCaptionCues
        : transcriptCues(mediaId);
    return {
      'revision': controller.projectRevision,
      'scope': mediaId == null ? 'timeline' : 'source',
      'media_id': mediaId,
      'total': cues.length,
      'cues': cues.skip(offset).take(limit).map((c) => c.toJson()).toList(),
      'next_offset': offset + limit < cues.length ? offset + limit : null,
    };
  }

  Future<Map<String, Object?>> getLoudness(String id) async {
    final generation = _readGeneration;
    final revision = controller.projectRevision;
    final item = media(id);
    final path = await checkMedia(item);
    _checkReadGeneration(generation);
    _requireAudio(item);
    final output = await _run([
      '-hide_banner',
      '-nostdin',
      '-i',
      path,
      '-vn',
      '-af',
      'ebur128=peak=true',
      '-f',
      'null',
      '-',
    ], EditorJobContext());
    double? metric(String expression) {
      final matches = RegExp(expression).allMatches(output);
      return matches.isEmpty ? null : double.tryParse(matches.last.group(1)!);
    }

    return {
      'media_id': id,
      'scope': 'source',
      'revision': revision,
      'integrated_lufs': metric(r'I:\s+(-?[\d.]+) LUFS'),
      'loudness_range_lu': metric(r'LRA:\s+([\d.]+) LU'),
      'true_peak_dbfs': metric(r'Peak:\s+(-?[\d.]+) dBFS'),
    };
  }

  Future<Map<String, Object?>> getFrames(
    List<double> times, {
    String? mediaId,
  }) async {
    if (times.isEmpty ||
        times.length > 8 ||
        times.any((t) => !t.isFinite || t < 0)) {
      throw const CommandError(
        'invalid_argument',
        'Peça de 1 a 8 tempos finitos >= 0.',
      );
    }
    final p = controller.project, revision = controller.projectRevision;
    final generation = _readGeneration;
    final frames = <Map<String, Object?>>[];
    for (final at in times) {
      _checkReadGeneration(generation);
      final position = Duration(microseconds: (at * 1e6).round());
      final clip = mediaId == null
          ? p
                .visualClipsAt(position)
                .where((c) => c.trackType != TrackType.text)
                .firstOrNull
          : null;
      if (mediaId == null && clip == null) {
        frames.add({'at': at, 'empty': true});
        continue;
      }
      final item = media(mediaId ?? clip!.mediaItemId, p);
      if (item.type != MediaType.video && item.type != MediaType.image) {
        throw const CommandError(
          'unsupported_media_type',
          'Frames requerem vídeo/imagem.',
        );
      }
      final source = clip == null
          ? at
          : clip.reverseVideo
          ? seconds(clip.sourceEnd) -
                0.000001 -
                (at - seconds(clip.timelineStart)) * clip.playbackSpeed
          : seconds(clip.sourceStart) +
                (at - seconds(clip.timelineStart)) * clip.playbackSpeed;
      if (source >= seconds(item.duration) && item.type != MediaType.image) {
        throw CommandError('out_of_range', 'Tempo fora da mídia.', {
          'media_id': item.id,
          'exclusive_max': seconds(item.duration),
        });
      }
      final path = await checkMedia(item), bytes = <int>[];
      _checkReadGeneration(generation);
      await _run(
        [
          '-hide_banner',
          '-nostdin',
          '-ss',
          '${item.type == MediaType.image ? 0 : source}',
          '-i',
          path,
          '-frames:v',
          '1',
          '-vf',
          'scale=320:180:force_original_aspect_ratio=decrease',
          '-f',
          'image2pipe',
          '-vcodec',
          'png',
          'pipe:1',
        ],
        EditorJobContext(),
        bytes: bytes,
      );
      if (bytes.isEmpty) {
        throw const CommandError(
          'frame_unavailable',
          'FFmpeg não devolveu miniatura.',
        );
      }
      frames.add({
        'at': at,
        'media_id': item.id,
        'source_time': source,
        'mimeType': 'image/png',
        'data': base64Encode(bytes),
      });
    }
    return {
      'revision': revision,
      'scope': mediaId == null ? 'timeline_source_thumbnails' : 'source',
      'frames': frames,
    };
  }

  EditorJob detectSilence(
    String id, {
    double thresholdDb = -35,
    double minimum = 0.5,
  }) {
    final p = controller.project, item = media(id, p);
    _requireAudio(item);
    if (!thresholdDb.isFinite ||
        thresholdDb < -80 ||
        thresholdDb > 0 ||
        !minimum.isFinite ||
        minimum < 0.1 ||
        minimum > 10) {
      throw const CommandError(
        'out_of_range',
        'Use threshold_db -80..0 e minimum 0.1..10.',
      );
    }
    return jobs.start('detect_silence', controller.projectRevision, p.id, (
      ctx,
    ) async {
      final path = await checkMedia(item);
      final output = await _run([
        '-hide_banner',
        '-nostdin',
        '-i',
        path,
        '-vn',
        '-af',
        'silencedetect=noise=${thresholdDb}dB:d=$minimum',
        '-f',
        'null',
        '-',
      ], ctx);
      final intervals = <Map<String, double>>[];
      double? start;
      for (final match in RegExp(
        r'silence_(start|end):\s*([\d.]+)',
      ).allMatches(output)) {
        final value = double.parse(match.group(2)!);
        if (match.group(1) == 'start') {
          start = value;
        } else if (start != null) {
          intervals.add({'start': start, 'end': value});
          start = null;
        }
      }
      if (start != null) {
        intervals.add({'start': start, 'end': seconds(item.duration)});
      }
      return {
        'media_id': id,
        'scope': 'source',
        'threshold_db': thresholdDb,
        'minimum': minimum,
        'intervals': intervals,
      };
    });
  }

  EditorJob detectScenes(String id, {double threshold = 0.3}) {
    final p = controller.project, item = media(id, p);
    if (item.type != MediaType.video ||
        !threshold.isFinite ||
        threshold < 0.01 ||
        threshold > 1) {
      throw const CommandError(
        'invalid_argument',
        'Use mídia de vídeo e threshold entre 0.01 e 1.',
      );
    }
    return jobs.start('detect_scenes', controller.projectRevision, p.id, (
      ctx,
    ) async {
      final path = await checkMedia(item);
      final output = await _run([
        '-hide_banner',
        '-nostdin',
        '-i',
        path,
        '-an',
        '-vf',
        "select='gt(scene,$threshold)',showinfo",
        '-fps_mode',
        'vfr',
        '-f',
        'null',
        '-',
      ], ctx);
      return {
        'media_id': id,
        'scope': 'source',
        'times': [
          for (final m in RegExp(r'pts_time:([\d.]+)').allMatches(output))
            double.parse(m.group(1)!),
        ],
      };
    });
  }

  EditorJob transcribe(String id, {String? language}) {
    final p = controller.project, item = media(id, p);
    _requireAudio(item);
    return jobs.start('transcribe', controller.projectRevision, p.id, (
      ctx,
    ) async {
      final path = await checkMedia(item);
      final service =
          captions ?? LocalWhisperAutoCaptionService(ffmpegService: ffmpeg);
      ctx.onCancel = () {
        if (service is LocalWhisperAutoCaptionService) {
          service.cancel();
        }
        ffmpeg.cancelActiveTranscriptionPreparation();
      };
      ctx.check();
      final cues = await service.generateCaptionsForMedia(
        item.copyWith(filePath: path),
        languageCode: language,
        onProgress: ctx.update,
      );
      ctx.check();
      _transcripts[_key(p, item)] = List.unmodifiable(cues);
      return {'media_id': id, 'cue_count': cues.length, 'scope': 'source'};
    });
  }

  EditorJob export(
    String outputPath, {
    FfmpegExportSettings settings = FfmpegExportSettings.uiDefault,
    Future<void> Function(TgiProject, String)? authorize,
  }) {
    final p = controller.project;
    return jobs.start('export', controller.projectRevision, p.id, (ctx) async {
      await authorize?.call(p, outputPath);
      ctx.check();
      ctx.onCancel = () {
        ffmpeg.cancelActiveExport();
      };
      await ffmpeg.exportProject(
        p,
        outputPath,
        settings: settings,
        onProgress: (v) => ctx.update(v),
      );
      ctx.check();
      return {
        'filename': outputPath.split(Platform.pathSeparator).last,
        'resolution': settings.resolution.id,
      };
    });
  }

  void _requireAudio(MediaItem item) {
    if (!item.hasAudio ||
        (item.type != MediaType.video && item.type != MediaType.audio)) {
      throw CommandError('no_audio', 'Mídia sem áudio.', {'media_id': item.id});
    }
  }

  final Set<EditorJobContext> _activeReads = {};
  int _readGeneration = 0;
  void _checkReadGeneration(int generation) {
    if (generation != _readGeneration) {
      throw const CommandError('cancelled', 'Leitura cancelada pelo app.');
    }
  }

  Future<void> cancelAll() async {
    _readGeneration++;
    for (final ctx in _activeReads.toList()) {
      ctx.cancelled = true;
      await ctx.onCancel?.call();
    }
    await jobs.cancelAll();
  }

  Future<String> _run(
    List<String> arguments,
    EditorJobContext ctx, {
    List<int>? bytes,
  }) async {
    _activeReads.add(ctx);
    try {
      return await _runOwned(arguments, ctx, bytes: bytes);
    } finally {
      _activeReads.remove(ctx);
      ctx.onCancel = null;
    }
  }

  Future<String> _runOwned(
    List<String> arguments,
    EditorJobContext ctx, {
    List<int>? bytes,
  }) async {
    ctx.check();
    final process = await ffmpeg.startCommand([
      '-protocol_whitelist',
      'file,pipe',
      ...arguments,
    ]);
    ctx.onCancel = () async {
      await process.cancel();
    };
    if (ctx.cancelled) {
      await process.cancel();
    }
    final output = StringBuffer();
    var received = 0;
    final out = process.stdout.listen((chunk) {
      received += chunk.length;
      if (received > 2 * 1024 * 1024) {
        unawaited(process.cancel());
      } else {
        bytes?.addAll(chunk);
      }
    }).asFuture<void>();
    final err = process.stderr.transform(utf8.decoder).listen((text) {
      output.write(text);
      if (output.length > 4 * 1024 * 1024) {
        unawaited(process.cancel());
      }
    }).asFuture<void>();
    int code;
    try {
      code = await process.exitCode.timeout(const Duration(minutes: 30));
    } on TimeoutException {
      await process.cancel();
      throw const CommandError('timeout', 'Análise excedeu 30 minutos.');
    }
    await Future.wait([out, err]);
    ctx.check();
    if (code != 0) {
      throw CommandError('ffmpeg_failed', 'Falha na análise da mídia.', {
        'exit_code': code,
        'output': output
            .toString()
            .split('\n')
            .reversed
            .take(8)
            .toList()
            .reversed
            .join('\n'),
      });
    }
    return output.toString();
  }

  Future<void> dispose() async {
    await cancelAll();
    await jobs.close();
  }
}
