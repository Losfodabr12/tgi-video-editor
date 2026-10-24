import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/core/commands/editor_command.dart';
import 'package:tgi_video_editor/mcp/mcp_tool_catalog.dart';

void main() {
  test(
    'macro discovery precedes all low-level edits and keeps accurate safety hints',
    () {
      final tools =
          jsonDecode(
                jsonEncode(
                  mcpToolCatalog.values.map((t) => t.toJson()).toList(),
                ),
              )
              as List;
      final names = tools.map((t) => t['name']).toList();
      expect(names.take(7), [
        'get_project',
        'remove_silences',
        'cut_by_transcript',
        'auto_captions',
        'reframe_9x16',
        'preview_plan',
        'apply_plan',
      ]);
      expect(names.toSet(), hasLength(39));
      for (final macro in tools.take(6)) {
        expect(macro['annotations']['readOnlyHint'], true);
        expect(
          utf8.encode(macro['description'] as String).length,
          lessThan(300),
        );
      }
      expect(tools[6]['annotations']['destructiveHint'], true);
      expect(
        names.indexOf('apply_plan'),
        lessThan(names.indexOf('split_clip')),
      );
      final runtime = mcpRuntimeToolCatalog.keys.toList();
      expect(runtime, mcpToolOrder);
      expect(runtime.take(8).last, 'split_clip');
      expect(runtime.sublist(runtime.length - 4), [
        'get_job',
        'cancel_job',
        'export_cut_check',
        'export',
      ]);
    },
  );
  test(
    'macro schemas document defaults, accept both preview forms and reject ambiguous input',
    () {
      final silence = mcpToolCatalog['remove_silences']!.schema;
      final properties = silence['properties'] as Map;
      expect(properties['scope']['default'], 'all_tracks');
      expect(properties['locked_tracks']['enum'], ['fail', 'skip', 'unlock']);
      expect(properties['threshold_db']['minimum'], -80);
      expect(properties['minimum']['minimum'], .1);
      expect(properties['padding']['description'], contains('fonte'));
      validateValue(
        {'clip_id': 'video', 'base_revision': 0},
        silence,
        'arguments',
      );
      final preview = mcpToolCatalog['preview_plan']!.schema;
      validateValue(
        {
          'macro': 'remove_silences',
          'arguments': {
            'clip_id': 'video',
            'scope': 'all_tracks',
            'locked_tracks': 'unlock',
          },
          'base_revision': 0,
        },
        preview,
        'arguments',
      );
      validateValue(
        {
          'commands': [
            {
              'command': 'add_marker',
              'arguments': {'at': 0, 'name': 'marker'},
            },
          ],
          'base_revision': 0,
        },
        preview,
        'arguments',
      );
      expect(
        () => validateValue(
          {
            'macro': 'remove_silences',
            'arguments': {'clip_id': 'video'},
            'commands': [
              {
                'command': 'add_marker',
                'arguments': {'at': 0, 'name': 'marker'},
              },
            ],
            'base_revision': 0,
          },
          preview,
          'arguments',
        ),
        throwsA(isA<CommandError>()),
      );
      expect(
        () => validateValue(
          {'clip_id': 'video', 'locked_tracks': 'ignore', 'base_revision': 0},
          silence,
          'arguments',
        ),
        throwsA(isA<CommandError>()),
      );
    },
  );
}
