import 'dart:convert';
import '../core/commands/command_engine.dart';
import '../core/commands/timeline_time_map.dart';
import '../core/commands/silence_options.dart';
import '../domain/models/project.dart';
import '../features/editor/application/editor_controller.dart';
import 'editor_read_service.dart';
import 'editor_plans.dart';
import 'mcp_tool_catalog.dart';
import 'cut_check.dart';
import 'mcp_command_input.dart';

typedef McpActivityCallback =
    void Function(
      String tool,
      Map<String, Object?> args,
      Map<String, Object?> result,
      int before,
      int after,
    );

class McpToolRouter {
  McpToolRouter(
    this.reads,
    this.plans, {
    this.resolveExport,
    this.authorizeExport,
    this.onActivity,
  });
  final EditorReadService reads;
  final EditorPlans plans;
  final Future<String> Function(String filename)? resolveExport;
  final Future<void> Function(TgiProject project, String path)? authorizeExport;
  final McpActivityCallback? onActivity;
  List<Map<String, Object?>> listTools() =>
      mcpRuntimeToolCatalog.values.map((t) => t.toJson()).toList();
  Future<Map<String, Object?>> call(
    String name,
    Map<String, Object?> args,
  ) async {
    final before = reads.controller.projectRevision;
    Map<String, Object?> result;
    try {
      final definition = mcpRuntimeToolCatalog[name];
      if (definition == null) {
        throw CommandError('unknown_tool', 'Tool desconhecida.', {
          'valid_tools': mcpRuntimeToolCatalog.keys.toList(),
        });
      }
      validateValue(args, definition.schema, 'arguments');
      if (name == 'preview_plan' && args.containsKey('macro')) {
        validateArguments(
          Map<String, Object?>.from(args['arguments'] as Map),
          removeSilencesArguments,
        );
        if (args.containsKey('commands') || args.containsKey('label')) {
          throw const CommandError(
            'invalid_argument',
            'Não combine macro com commands ou label.',
          );
        }
      } else if (name == 'preview_plan' && args.containsKey('arguments')) {
        throw const CommandError('invalid_argument', 'arguments exige macro.');
      }
      result = await _call(name, Map<String, Object?>.of(args));
    } on CommandError catch (e) {
      result = {'error': mcpInputError(e, name, args).toJson()};
    } catch (e) {
      result = {
        'error': const CommandError(
          'internal_error',
          'A operação falhou. Consulte o painel do app.',
        ).toJson(),
      };
    }
    onActivity?.call(
      name,
      args,
      result,
      before,
      reads.controller.projectRevision,
    );
    final content = <Map<String, Object?>>[];
    if (name == 'get_frames' && result['frames'] is List) {
      final frames = result['frames'] as List;
      for (final raw in frames) {
        final frame = raw as Map<String, Object?>;
        if (frame['data'] != null) {
          content.add({
            'type': 'image',
            'mimeType': frame['mimeType'],
            'data': frame.remove('data'),
          });
        }
      }
    }
    content.insert(0, {'type': 'text', 'text': jsonEncode(result)});
    return {
      'content': content,
      'structuredContent': result,
      'isError': result.containsKey('error'),
    };
  }

  Map<String, Object?> _silencePreview(
    Map<String, Object?> args,
    int revision,
  ) {
    final c = reads.controller;
    checkRevision(revision, c.projectRevision);
    final clip = c.project.clipById(args['clip_id'] as String);
    if (clip == null) {
      throw CommandError(
        'clip_not_found',
        'Selecione um clipe do projeto aberto.',
        {
          'valid_clip_ids': c.project.tracks
              .expand((t) => t.clips)
              .map((c) => c.id)
              .toList(),
        },
      );
    }
    const TimelineRemapper().preflight(
      c.project,
      clip,
      scope: args['scope'] as String? ?? 'all_tracks',
      lockedTracks: args['locked_tracks'] as String? ?? 'fail',
    );
    if (args['job_id'] == null) {
      final options = SilenceOptions(args);
      final job = reads.detectSilence(
        clip.mediaItemId,
        thresholdDb: options.thresholdDb,
        minimum: options.minimum,
      );
      return {
        ...job.toJson(),
        'analysis_pending': true,
        'next_step':
            'Aguarde get_job e repita a macro com este job_id e a mesma base_revision. Nenhuma edição foi aplicada.',
      };
    }
    return plans
        .previewMacro('remove_silences', args, baseRevision: revision)
        .toJson();
  }

  Future<Map<String, Object?>> _call(
    String name,
    Map<String, Object?> a,
  ) async {
    final c = reads.controller;
    int page(String key, int fallback) => (a[key] as int?) ?? fallback;
    List<EditorCommand> commands() => parseMcpCommands(a['commands'] as List);
    if (commandCatalog.containsKey(name)) {
      final revision = a.remove('base_revision') as int;
      final cmd = EditorCommand(name, a, baseRevision: revision);
      if (plans.requireApproval) {
        return plans
            .previewCommands([cmd], baseRevision: revision, label: 'IA: $name')
            .toJson();
      }
      return c.executeCommands(
        [cmd],
        baseRevision: revision,
        label: 'IA: $name',
      );
    }
    switch (name) {
      case 'get_project':
        return {
          ...reads.getProject(
            cursor: a['cursor'] as String?,
            limit: page('limit', 50),
          ),
          'approval_required': plans.requireApproval,
          'export_resolution': c.commandExportSettings.resolution.id,
        };
      case 'get_clip':
        return reads.getClip(a['clip_id'] as String);
      case 'get_transcript':
        return reads.getTranscript(
          mediaId: a['media_id'] as String?,
          offset: page('offset', 0),
          limit: page('limit', 100),
        );
      case 'list_media':
        return reads.listMedia(
          offset: page('offset', 0),
          limit: page('limit', 50),
        );
      case 'get_loudness':
        return reads.getLoudness(a['media_id'] as String);
      case 'get_frames':
        return reads.getFrames(
          (a['times'] as List).map((n) => (n as num).toDouble()).toList(),
          mediaId: a['media_id'] as String?,
        );
      case 'detect_silence':
        return reads
            .detectSilence(
              a['media_id'] as String,
              thresholdDb: (a['threshold_db'] as num?)?.toDouble() ?? -35,
              minimum: (a['minimum'] as num?)?.toDouble() ?? 0.5,
            )
            .toJson();
      case 'detect_scenes':
        return reads
            .detectScenes(
              a['media_id'] as String,
              threshold: (a['threshold'] as num?)?.toDouble() ?? 0.3,
            )
            .toJson();
      case 'transcribe':
        return reads
            .transcribe(
              a['media_id'] as String,
              language: a['language'] as String?,
              model: a['model'] as String?,
              vocabulary: a['vocabulary'] as String?,
              vad: a['vad'] as bool?,
            )
            .toJson();
      case 'get_job':
        return reads.jobs.get(a['job_id'] as String).toJson();
      case 'cancel_job':
        await reads.jobs.cancel(a['job_id'] as String);
        return reads.jobs.get(a['job_id'] as String).toJson();
      case 'apply_commands':
        if (plans.requireApproval) {
          return plans
              .previewCommands(
                commands(),
                baseRevision: a['base_revision'] as int,
                label: a['label'] as String? ?? 'IA: lote',
              )
              .toJson();
        }
        return c.executeCommands(
          commands(),
          baseRevision: a['base_revision'] as int,
          label: 'IA: ${a['label'] ?? 'lote'}',
        );
      case 'preview_plan':
        if (a.containsKey('macro')) {
          return _silencePreview(
            Map<String, Object?>.from(a['arguments'] as Map),
            a['base_revision'] as int,
          );
        }
        return plans
            .previewCommands(
              commands(),
              baseRevision: a['base_revision'] as int,
              label: a['label'] as String? ?? 'IA: lote',
            )
            .toJson();
      case 'apply_plan':
        return plans.apply(
          a['plan_id'] as String,
          baseRevision: a['base_revision'] as int,
        );
      case 'remove_silences':
        final revision = a.remove('base_revision') as int;
        return _silencePreview(a, revision);
      case 'cut_by_transcript':
      case 'auto_captions':
      case 'reframe_9x16':
        final revision = a.remove('base_revision') as int;
        return plans.previewMacro(name, a, baseRevision: revision).toJson();
      case 'export_cut_check':
        checkRevision(a['base_revision'] as int, c.projectRevision);
        final plan = plans.inspect(a['plan_id'] as String);
        final check = buildCutCheck(plan);
        if (resolveExport == null) {
          throw const CommandError(
            'export_directory_required',
            'Escolha a pasta de exportação nas configurações MCP do app.',
          );
        }
        final path = await resolveExport!(a['filename'] as String);
        plans.inspect(plan.id);
        return reads
            .export(
              path,
              snapshot: check.project,
              revision: plan.revision,
              kind: 'export_cut_check',
              settings: c.commandExportSettings.copyWith(
                clearRange: true,
                audioOnly: path.toLowerCase().endsWith('.wav'),
              ),
              resultDetails: {
                'plan_id': plan.id,
                'cut_count': check.cutCount,
                'window_count': check.windows.length,
                'duration': check.project.timelineDuration.inMicroseconds / 1e6,
                'windows': [
                  for (final w in check.windows)
                    {'start': w.$1 / 1e6, 'end': w.$2 / 1e6},
                ],
                'project_edited': false,
              },
              authorize: (project, path) async {
                plans.inspect(plan.id);
                await authorizeExport?.call(project, path);
              },
            )
            .toJson();
      case 'export':
        checkRevision(a['base_revision'] as int, c.projectRevision);
        if (resolveExport == null) {
          throw const CommandError(
            'export_directory_required',
            'Escolha a pasta de exportação nas configurações MCP do app.',
          );
        }
        final revision = c.projectRevision;
        final path = await resolveExport!(a['filename'] as String);
        checkRevision(revision, c.projectRevision);
        return reads
            .export(
              path,
              settings: c.commandExportSettings.copyWith(
                audioOnly: path.toLowerCase().endsWith('.wav'),
              ),
              authorize: (project, path) async {
                await authorizeExport?.call(project, path);
              },
            )
            .toJson();
      default:
        throw const CommandError('unknown_tool', 'Tool desconhecida.');
    }
  }
}
