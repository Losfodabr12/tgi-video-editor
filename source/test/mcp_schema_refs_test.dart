import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/core/commands/editor_command.dart';
import 'package:tgi_video_editor/mcp/mcp_tool_catalog.dart';

void main() {
  test(
    'local refs preserve color, effects, keyframes and strict style validation',
    () {
      for (final sample in <String, Map<String, Object?>>{
        'add_text': {
          'text': 'Legenda',
          'timeline_start': 0,
          'duration': 2,
          'text_color': 0xFFFFFFFF,
          'background_color': 0,
          'base_revision': 0,
        },
        'apply_effect': {
          'clip_id': 'video',
          'brightness': .2,
          'temperature': -.5,
          'saturation': 2,
          'crop_left': .2,
          'base_revision': 0,
        },
        'set_keyframe': {
          'clip_id': 'video',
          'property': 'opacity',
          'time': .5,
          'value': .7,
          'base_revision': 0,
        },
        'preview_plan': {
          'base_revision': 0,
          'commands': [
            {
              'tool': 'add_marker',
              'arguments': {'at': 1, 'name': 'x'},
            },
          ],
        },
      }.entries) {
        final tool = mcpRuntimeToolCatalog[sample.key]!;
        final wire = tool.toJson()['inputSchema'] as Map<String, dynamic>;
        validateValue(sample.value, wire, 'arguments');
        expect(
          () => validateValue(
            {...sample.value, 'unexpected': true},
            wire,
            'arguments',
          ),
          throwsA(isA<CommandError>()),
          reason: sample.key,
        );
      }
      final style =
          mcpRuntimeToolCatalog['add_text']!.toJson()['inputSchema']
              as Map<String, dynamic>;
      expect(style[r'$defs'], isNotEmpty);
      expect((style['properties'] as Map)['text_color'], contains(r'$ref'));
      for (final field in ['text_color', 'background_color']) {
        expect(
          () => validateValue(
            {
              'text': 'x',
              'timeline_start': 0,
              'duration': 1,
              'base_revision': 0,
              field: -1,
            },
            style,
            'arguments',
          ),
          throwsA(isA<CommandError>()),
        );
      }
      final effect =
          mcpRuntimeToolCatalog['apply_effect']!.toJson()['inputSchema']
              as Map<String, dynamic>;
      expect(effect[r'$defs'], isNotEmpty);
      for (final field in [
        'temperature',
        'tint',
        'shadows',
        'highlights',
        'curve_shadows',
      ]) {
        expect(
          () => validateValue(
            {'clip_id': 'video', 'base_revision': 0, field: 2},
            effect,
            'arguments',
          ),
          throwsA(isA<CommandError>()),
        );
      }
    },
  );
}
