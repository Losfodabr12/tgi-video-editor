import 'dart:convert';
import 'dart:math' as math;
import '../core/commands/command_engine.dart';
import '../core/commands/command_transaction.dart';
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
  });
  final String id, label;
  final int revision;
  final TgiProject before, after;
  final List<EditorCommand> commands;
  final FfmpegExportSettings? exportSettings;
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
            'before': old[id] == null ? null : clipSummary(before, old[id]!),
            'after': updated[id] == null
                ? null
                : clipSummary(after, updated[id]!),
          },
    ];
    return {
      'plan_id': id,
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
  }) {
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
    switch (name) {
      case 'remove_silences':
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
        _removeRanges(clip, ranges, () => next, run);
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

  void _removeRanges(
    Clip clip,
    List<(double, double)> source,
    TgiProject Function() current,
    void Function(String, Map<String, Object?>) run,
  ) {
    final trackId = current().clipTrackById(clip.id)!.id;
    final ranges =
        source
            .map((r) => _timelineRange(clip, r.$1, r.$2))
            .whereType<(double, double)>()
            .toList()
          ..sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(double, double)>[];
    for (final r in ranges) {
      if (merged.isEmpty || merged.last.$2 < r.$1) {
        merged.add(r);
      } else {
        merged[merged.length - 1] = (
          merged.last.$1,
          math.max(merged.last.$2, r.$2),
        );
      }
    }
    // Work backwards so ripple never changes the remaining cut positions.
    for (final r in merged.reversed) {
      Clip locate(double at) => current()
          .trackById(trackId)!
          .clips
          .firstWhere(
            (c) =>
                c.mediaItemId == clip.mediaItemId &&
                c.trackType == clip.trackType &&
                seconds(c.timelineStart) <= at + 1e-6 &&
                seconds(c.timelineEnd) > at + 1e-6,
          );
      var target = locate((r.$1 + r.$2) / 2);
      if (r.$2 < seconds(target.timelineEnd) - 1e-6) {
        run('split_clip', {'clip_id': target.id, 'at': r.$2});
      }
      target = locate((r.$1 + r.$2) / 2);
      if (r.$1 > seconds(target.timelineStart) + 1e-6) {
        run('split_clip', {'clip_id': target.id, 'at': r.$1});
      }
      target = locate((r.$1 + r.$2) / 2);
      run('delete_clip', {'clip_id': target.id, 'ripple': true});
    }
  }

  @override
  String toString() => jsonEncode({'pending_plans': _plans.length});
}
