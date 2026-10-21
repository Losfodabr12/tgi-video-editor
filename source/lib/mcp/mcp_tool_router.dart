import 'dart:convert';
import '../core/commands/command_engine.dart';
import '../domain/models/project.dart';
import '../features/editor/application/editor_controller.dart';
import 'editor_read_service.dart';
import 'editor_plans.dart';
import 'mcp_tool_catalog.dart';

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
      mcpToolCatalog.values.map((t) => t.toJson()).toList();
  Future<Map<String, Object?>> call(
    String name,
    Map<String, Object?> args,
  ) async {
    final before = reads.controller.projectRevision;
    Map<String, Object?> result;
    try {
      final definition = mcpToolCatalog[name];
      if (definition == null) {
        throw CommandError('unknown_tool', 'Tool desconhecida.', {
          'valid_tools': mcpToolCatalog.keys.toList(),
        });
      }
      validateArguments(args, definition.schema);
      result = await _call(name, Map<String, Object?>.of(args));
    } on CommandError catch (e) {
      result = {'error': e.toJson()};
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

  Future<Map<String, Object?>> _call(
    String name,
    Map<String, Object?> a,
  ) async {
    final c = reads.controller;
    int page(String key, int fallback) => (a[key] as int?) ?? fallback;
    List<EditorCommand> commands() => (a['commands'] as List)
        .map((e) => EditorCommand.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
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
      case 'cut_by_transcript':
      case 'auto_captions':
      case 'reframe_9x16':
        final revision = a.remove('base_revision') as int;
        return plans.previewMacro(name, a, baseRevision: revision).toJson();
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
