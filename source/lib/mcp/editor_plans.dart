import 'dart:convert';
import 'dart:math' as math;
import '../core/commands/command_engine.dart';
import '../core/commands/command_transaction.dart';
import '../core/commands/timeline_time_map.dart';
import '../domain/models/clip.dart';
import '../domain/models/project.dart';
import '../domain/models/track.dart';
import '../features/editor/application/editor_caption_timing.dart';
import '../features/editor/application/editor_controller.dart';
import '../services/auto_caption_service.dart';
import '../services/ffmpeg_export_settings.dart';
import 'editor_read_service.dart';
import 'project_reads.dart';

class EditorPlan {
  EditorPlan({
    required this.id,
    required this.label,
    required this.revision,
    required this.before,
    required this.after,
    required this.commands,
    this.exportSettings,
    this.effects = const {},
  });
  final String id, label;
  final int revision;
  final TgiProject before, after;
  final List<EditorCommand> commands;
  final FfmpegExportSettings? exportSettings;
  final Map<String, Object?> effects;
  final createdAt = DateTime.now();
  bool approved = false, applied = false;
  Map<String, Object?> toJson() {
    final old = {
      for (final t in before.tracks)
        for (final c in t.clips) c.id: c,
    };
    final updated = {
      for (final t in after.tracks)
        for (final c in t.clips) c.id: c,
    };
    final changes = <Map<String, Object?>>[
      for (final id in {...old.keys, ...updated.keys})
        if (!identical(old[id], updated[id]))
          {
            'clip_id': id,
            'before': old[id] == null ? null : clipEditState(before, old[id]!),
            'after': updated[id] == null
                ? null
                : clipEditState(after, updated[id]!),
          },
    ];
    return {
      'plan_id': id,
      ...effects,
      'label': label,
      'base_revision': revision,
      'approved': approved,
      'applied': applied,
      'before': projectSummary(before, revision),
      'after': projectSummary(after, revision),
      'change_count': changes.length,
      'changes': changes.take(200).toList(),
      'changes_truncated': changes.length > 200,
      'command_count': commands.length,
      'commands': commands.take(100).map((c) => c.toJson()).toList(),
      'commands_truncated': commands.length > 100,
      if (exportSettings != null)
        'export_resolution': exportSettings!.resolution.id,
    };
  }
}

/// Plans hold the exact candidate snapshot: apply never reruns a macro.
class EditorPlans {
  EditorPlans(this.controller, this.reads, {this.onChanged});
  final EditorController controller;
  final EditorReadService reads;
  final void Function()? onChanged;
  bool requireApproval = true;
  int _counter = 0;
  final Map<String, EditorPlan> _plans = {};
  Iterable<EditorPlan> get all => _plans.values;
  EditorPlan get(String id) =>
      _plans[id] ??
      (throw CommandError('plan_not_found', 'Plano desconhecido ou expirado.', {
        'valid_plan_ids': _plans.keys.toList(),
      }));
  void clear() {
    _plans.clear();
    onChanged?.call();
  }

  void approve(String id) {
    final plan = get(id);
    _check(plan);
    plan.approved = true;
    onChanged?.call();
  }

  void _check(EditorPlan plan) {
    checkRevision(plan.revision, controller.projectRevision);
    if (plan.applied ||
        DateTime.now().difference(plan.createdAt) >
            const Duration(minutes: 15) ||
        !identical(plan.before, controller.project)) {
      throw const CommandError(
        'plan_expired',
        'O plano foi aplicado, expirou ou o projeto mudou. Gere outro preview_plan.',
      );
    }
  }

  Map<String, Object?> apply(String id, {required int baseRevision}) {
    final plan = get(id);
    checkRevision(baseRevision, controller.projectRevision);
    _check(plan);
    if (requireApproval && !plan.approved) {
      throw CommandError(
        'approval_required',
        'Aprove o plano no painel de atividade da IA dentro do app.',
        {'plan_id': id},
      );
    }
    final history =
        plan.commands.length == 1 &&
        ['undo', 'redo'].contains(plan.commands.single.name);
    final result = history
        ? controller.executeCommands(
            plan.commands,
            baseRevision: plan.revision,
            label: plan.label,
          )
        : controller.commitCommandProject(
            plan.after,
            baseRevision: plan.revision,
            label: plan.label,
            commandCount: plan.commands.length,
            exportSettings: plan.exportSettings,
          );
    plan.applied = true;
    onChanged?.call();
    return {...result, 'plan_id': id};
  }

  EditorPlan previewCommands(
    List<EditorCommand> commands, {
    required int baseRevision,
    String label = 'IA: lote',
  }) {
    checkRevision(baseRevision, controller.projectRevision);
    final before = controller.project;
    final history =
        commands.length == 1 && ['undo', 'redo'].contains(commands.single.name);
    if (history) {
      validateArguments(
        commands.single.arguments,
        commandCatalog[commands.single.name]!.schema,
      );
    }
    final after = history
        ? controller.previewHistoryCommand(commands.single.name)
        : const CommandTransaction().evaluate(
            before,
            commands,
            revision: baseRevision,
          );
    return _save(before, after, commands, baseRevision, label);
  }

  EditorPlan _save(
    TgiProject before,
    TgiProject after,
    List<EditorCommand> commands,
    int revision,
    String label, {
    FfmpegExportSettings? settings,
    Map<String, Object?> effects = const {},
  }) {
    if (identical(before, after) &&
        settings != null &&
        settings != controller.commandExportSettings) {
      after = after.copyWith(updatedAt: DateTime.now());
    }
    if (commands.length > 500) {
      throw const CommandError(
        'plan_limit',
        'Plano excede 500 comandos. Divida a edição.',
      );
    }
    _plans.removeWhere(
      (_, p) =>
          p.applied ||
          DateTime.now().difference(p.createdAt) > const Duration(minutes: 15),
    );
    if (_plans.length >= 30) {
      _plans.remove(_plans.keys.first);
    }
    final plan = EditorPlan(
      id: 'plan_${++_counter}',
      label: label.startsWith('IA:') ? label : 'IA: $label',
      revision: revision,
      before: before,
      after: after,
      commands: List.unmodifiable(commands),
      exportSettings: settings,
      effects: effects,
    );
    _plans[plan.id] = plan;
    onChanged?.call();
    return plan;
  }

  EditorPlan previewMacro(
    String name,
    Map<String, Object?> args, {
    required int baseRevision,
  }) {
    checkRevision(baseRevision, controller.projectRevision);
    final before = controller.project,
        clip = before.clipById(args['clip_id'] as String? ?? '');
    if (clip == null) {
      throw CommandError('clip_not_found', 'Selecione clip_id válido.', {
        'valid_clip_ids': before.tracks
            .expand((t) => t.clips)
            .map((c) => c.id)
            .toList(),
      });
    }
    var next = before;
    final commands = <EditorCommand>[];
    void run(String name, Map<String, Object?> a) {
      final command = EditorCommand(name, a);
      next = const CommandEngine().apply(next, command);
      commands.add(command);
    }

    FfmpegExportSettings? settings;
    Map<String, Object?> effects = const {};
    switch (name) {
      case 'remove_silences':
        const TimelineRemapper().preflight(
          before,
          clip,
          scope: args['scope'] as String? ?? 'all_tracks',
          lockedTracks: args['locked_tracks'] as String? ?? 'fail',
        );
        final job = reads.jobs.get(args['job_id'] as String? ?? '');
        if (job.kind != 'detect_silence' ||
            job.status != 'completed' ||
            job.projectId != before.id ||
            job.revision != baseRevision) {
          throw const CommandError(
            'analysis_stale',
            'Use um job detect_silence concluído na revisão atual.',
          );
        }
        final result = job.result as Map;
        if (result['media_id'] != clip.mediaItemId) {
          throw const CommandError(
            'analysis_mismatch',
            'Job pertence a outra mídia.',
          );
        }
        for (final key in ['threshold_db', 'minimum']) {
          if (args.containsKey(key) && args[key] != result[key]) {
            throw CommandError(
              'analysis_mismatch',
              'O job precisa usar os mesmos parâmetros da macro.',
              {
                'parameter': key,
                'requested': args[key],
                'analysis_value': result[key],
                'suggestion':
                    'Execute detect_silence com threshold_db e minimum desejados e use o novo job_id.',
              },
            );
          }
        }
        final padding = (args['padding'] as num?)?.toDouble() ?? 0.08;
        if (!padding.isFinite || padding < 0 || padding > 1) {
          throw const CommandError(
            'out_of_range',
            'Padding deve estar entre 0 e 1 segundo.',
          );
        }
        final ranges = <(double, double)>[
          for (final interval in result['intervals'] as List)
            (
              (interval['start'] as num).toDouble() + padding,
              (interval['end'] as num).toDouble() - padding,
            ),
        ];
        final remap = _remapRanges(before, clip, ranges, args);
        next = remap.project;
        effects = remap.toJson();
        if (remap.timeMap.removed.isNotEmpty) {
          commands.add(
            EditorCommand('remap_timeline', {
              'clip_id': clip.id,
              'removed_ranges': remap.timeMap.toJson()['removed_ranges'],
              'scope': args['scope'] ?? 'all_tracks',
              'locked_tracks': args['locked_tracks'] ?? 'fail',
            }),
          );
        }
      case 'cut_by_transcript':
        final cues = reads.transcriptCues(clip.mediaItemId),
            indices = args['keep_cue_indices'];
        if (indices is! List ||
            indices.isEmpty ||
            indices.any((i) => i is! int || i < 0 || i >= cues.length)) {
          throw CommandError(
            'invalid_argument',
            'Use índices de cues retornados por get_transcript para manter falas.',
            {
              'valid_indices': [for (var i = 0; i < cues.length; i++) i],
            },
          );
        }
        final keep = <(double, double)>[
          for (final i in indices)
            (seconds(cues[i as int].start), seconds(cues[i].end)),
        ]..sort((a, b) => a.$1.compareTo(b.$1));
        final remove = <(double, double)>[];
        var cursor = seconds(clip.sourceStart);
        for (final range in keep) {
          if (range.$1 > cursor) {
            remove.add((cursor, range.$1));
          }
          cursor = math.max(cursor, range.$2);
        }
        if (cursor < seconds(clip.sourceEnd)) {
          remove.add((cursor, seconds(clip.sourceEnd)));
        }
        _removeRanges(clip, remove, () => next, run);
      case 'auto_captions':
        final source = reads.transcriptCues(clip.mediaItemId);
        final timeline = <CaptionCue>[];
        for (final cue in source) {
          final range = _timelineRange(
            clip,
            seconds(cue.start),
            seconds(cue.end),
          );
          if (range != null) {
            timeline.add(
              CaptionCue(
                start: Duration(microseconds: (range.$1 * 1e6).round()),
                end: Duration(microseconds: (range.$2 * 1e6).round()),
                text: cue.text,
              ),
            );
          }
        }
        final cues = const EditorCaptionTiming().resolveCaptionCueOverlaps(
          timeline,
          timelineLimit: clip.timelineEnd,
        );
        for (var i = 0; i < cues.length; i++) {
          var cue = cues[i];
          while (cue.duration < const Duration(seconds: 1) &&
              i + 1 < cues.length) {
            i++;
            cue = CaptionCue(
              start: cue.start,
              end: cues[i].end,
              text: '${cue.text} ${cues[i].text}',
            );
          }
          if (cue.duration < const Duration(seconds: 1)) {
            // v14 text clips have a one second minimum. Report the limitation.
            throw const CommandError(
              'caption_too_short',
              'A última legenda tem menos de 1s. Ajuste a transcrição ou a velocidade antes de gerar.',
            );
          }
          run('add_text', {
            'text': cue.text,
            'timeline_start': seconds(cue.start),
            'duration': seconds(cue.duration),
            'is_caption': true,
            'font_family': 'Arial',
            'font_size': 52,
            'background_color': 0xA0000000,
          });
        }
      case 'reframe_9x16':
        final media = reads.media(clip.mediaItemId, before);
        if (media.width == null ||
            media.height == null ||
            media.width! <= 0 ||
            media.height! <= 0 ||
            (clip.trackType != TrackType.video &&
                clip.trackType != TrackType.image)) {
          throw const CommandError(
            'dimensions_unavailable',
            'Reenquadramento requer vídeo/imagem com dimensões conhecidas.',
          );
        }
        final aspect = media.width! / media.height!, target = 9 / 16;
        final horizontal = aspect > target ? (1 - target / aspect) / 2 : 0.0;
        final vertical = aspect < target ? (1 - aspect / target) / 2 : 0.0;
        run('apply_effect', {
          'clip_id': clip.id,
          'crop_left': horizontal,
          'crop_right': horizontal,
          'crop_top': vertical,
          'crop_bottom': vertical,
        });
        settings = controller.commandExportSettings.copyWith(
          resolution: FfmpegExportResolution.shorts1080,
        );
      default:
        throw const CommandError('unknown_macro', 'Macro desconhecida.', {
          'valid_macros': [
            'remove_silences',
            'cut_by_transcript',
            'auto_captions',
            'reframe_9x16',
          ],
        });
    }
    if (commands.isEmpty) {
      throw const CommandError(
        'empty_plan',
        'A macro não encontrou alterações para aplicar.',
      );
    }
    return _save(
      before,
      next,
      commands,
      baseRevision,
      'IA: $name',
      settings: settings,
      effects: effects,
    );
  }

  (double, double)? _timelineRange(Clip clip, double start, double end) {
    start = math.max(start, seconds(clip.sourceStart));
    end = math.min(end, seconds(clip.sourceEnd));
    if (end <= start) {
      return null;
    }
    if (clip.reverseVideo) {
      return (
        seconds(clip.timelineStart) +
            (seconds(clip.sourceEnd) - end) / clip.playbackSpeed,
        seconds(clip.timelineStart) +
            (seconds(clip.sourceEnd) - start) / clip.playbackSpeed,
      );
    }
    return (
      seconds(clip.timelineStart) +
          (start - seconds(clip.sourceStart)) / clip.playbackSpeed,
      seconds(clip.timelineStart) +
          (end - seconds(clip.sourceStart)) / clip.playbackSpeed,
    );
  }

  TimelineRemapResult _remapRanges(
    TgiProject before,
    Clip clip,
    List<(double, double)> source,
    Map<String, Object?> args,
  ) {
    final reversed =
        clip.reverseVideo ||
        before.tracks
            .expand((t) => t.clips)
            .any(
              (c) =>
                  c.timelineGroupId == clip.timelineGroupId &&
                  c.trackType == TrackType.video &&
                  c.reverseVideo,
            );
    final reference = reversed ? clip.copyWith(reverseVideo: true) : clip;
    final ranges = source
        .map((r) => _timelineRange(reference, r.$1, r.$2))
        .whereType<(double, double)>()
        .map((r) => ((r.$1 * 1e6).round(), (r.$2 * 1e6).round()));
    return const TimelineRemapper().apply(
      before,
      clip,
      TimelineTimeMap(ranges, end: before.timelineDuration.inMicroseconds),
      scope: args['scope'] as String? ?? 'all_tracks',
      lockedTracks: args['locked_tracks'] as String? ?? 'fail',
    );
  }

  void _removeRanges(
    Clip clip,
    List<(double, double)> source,
    TgiProject Function() current,
    void Function(String, Map<String, Object?>) run,
  ) {
    final remap = _remapRanges(current(), clip, source, const {});
    if (remap.timeMap.removed.isNotEmpty) {
      run('remap_timeline', {
        'clip_id': clip.id,
        'removed_ranges': remap.timeMap.toJson()['removed_ranges'],
      });
    }
  }

  @override
  String toString() => jsonEncode({'pending_plans': _plans.length});
}
