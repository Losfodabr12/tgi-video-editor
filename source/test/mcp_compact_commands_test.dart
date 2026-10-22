import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/core/commands/command_engine.dart';
import 'package:tgi_video_editor/features/editor/application/editor_controller.dart';
import 'package:tgi_video_editor/mcp/editor_plans.dart';
import 'package:tgi_video_editor/mcp/editor_read_service.dart';
import 'package:tgi_video_editor/mcp/mcp_tool_router.dart';
import 'package:tgi_video_editor/services/ffmpeg_service.dart';
import 'package:tgi_video_editor/services/media_import_service.dart';
import 'package:tgi_video_editor/services/project_io_service.dart';
import 'command_engine_test.dart' show commandFixture;

void main() {
  late EditorController controller;
  late EditorReadService reads;
  late EditorPlans plans;
  late McpToolRouter router;
  setUp(() {
    controller = EditorController(
      mediaImportService: MediaImportService(ffmpegService: FfmpegService()),
      initialProject: commandFixture(),
    );
    reads = EditorReadService(controller);
    plans = EditorPlans(controller, reads);
    router = McpToolRouter(reads, plans);
  });
  tearDown(() async {
    await reads.dispose();
    controller.dispose();
  });
  String snapshot() =>
      jsonEncode(ProjectIOService().serializeProject(controller.project));
  Future<Map> call(String tool, Map<String, Object?> arguments) async =>
      (await router.call(tool, arguments))['structuredContent'] as Map;

  test(
    'compact and legacy batch forms share approval, exact snapshots and undo',
    () async {
      final before = snapshot();
      final preview = await call('preview_plan', {
        'base_revision': 0,
        'commands': [
          {
            'tool': 'add_marker',
            'arguments': {'at': 1, 'name': 'compact'},
          },
          {
            'command': 'add_marker',
            'arguments': {'at': 2, 'name': 'legacy'},
          },
        ],
      });
      expect(preview['error'], isNull);
      expect(snapshot(), before);
      expect(
        (await call('apply_plan', {
          'plan_id': preview['plan_id'],
          'base_revision': 0,
        }))['error']['code'],
        'approval_required',
      );
      plans.approve(preview['plan_id'] as String);
      final applied = await call('apply_plan', {
        'plan_id': preview['plan_id'],
        'base_revision': 0,
      });
      expect(applied['error'], isNull);
      expect(controller.project.markers, hasLength(2));
      controller.undo();
      expect(snapshot(), before);
      plans.requireApproval = false;
      final batch = await call('apply_commands', {
        'base_revision': controller.projectRevision,
        'commands': [
          {
            'tool': 'add_marker',
            'arguments': {'at': 3, 'name': 'batch'},
          },
        ],
      });
      expect(batch['error'], isNull);
      controller.undo();
      expect(snapshot(), before);
    },
  );

  test(
    'batch arguments use individual validators and include actionable correction',
    () async {
      final before = snapshot();
      for (final entry in commandCatalog.entries.where(
        (e) => !['undo', 'redo', 'remap_timeline'].contains(e.key),
      )) {
        final direct = await call(entry.key, {
          'base_revision': 0,
          'misspelled': true,
        });
        final batch = await call('preview_plan', {
          'base_revision': 0,
          'commands': [
            {
              'tool': entry.key,
              'arguments': {'misspelled': true},
            },
          ],
        });
        expect(
          batch['error']['code'],
          direct['error']['code'],
          reason: entry.key,
        );
        final details = batch['error']['details'] as Map;
        expect(details['command_index'], 0);
        expect(details['expected_schema'], entry.value.schema);
        final example = details['example'] as Map;
        expect(example['tool'], entry.key);
        validateArguments(
          Map<String, Object?>.from(example['arguments'] as Map),
          entry.value.schema,
        );
      }
      expect(snapshot(), before);
      expect(controller.canUndo, isFalse);
    },
  );

  test(
    'late invalid edits roll back and keep structured bounds plus schema',
    () async {
      plans.requireApproval = false;
      final clip = controller.project.tracks.expand((t) => t.clips).first;
      final before = snapshot();
      final result = await call('apply_commands', {
        'base_revision': 0,
        'commands': [
          {
            'tool': 'add_marker',
            'arguments': {'at': 1, 'name': 'must roll back'},
          },
          {
            'tool': 'split_clip',
            'arguments': {'clip_id': clip.id, 'at': 10},
          },
        ],
      });
      expect(result['error']['code'], 'out_of_range');
      expect(result['error']['details']['command_index'], 1);
      expect(result['error']['details']['exclusive_max'], 10);
      expect(result['error']['details']['expected_schema'], isNotEmpty);
      expect(result['error']['details']['example']['tool'], 'split_clip');
      expect(snapshot(), before);
      expect(controller.canUndo, isFalse);
    },
  );

  test(
    'open argument objects still reject unknown fields, invalid types and aliases',
    () async {
      for (final item in [
        {
          'tool': 'add_marker',
          'arguments': {'at': 1, 'name': 'x', 'extra': true},
        },
        {
          'tool': 'add_marker',
          'arguments': {'at': '1', 'name': 'x'},
        },
        {
          'tool': 'add_marker',
          'command': 'add_marker',
          'arguments': {'at': 1, 'name': 'x'},
        },
        {'tool': 'undo', 'arguments': <String, Object?>{}},
        {'command': 'redo', 'arguments': <String, Object?>{}},
      ]) {
        final result = await call('preview_plan', {
          'base_revision': 0,
          'commands': [item],
        });
        expect(result['error'], isNotNull, reason: item.toString());
      }
      expect(controller.projectRevision, 0);
      expect(plans.all, isEmpty);
    },
  );
}
