import '../../domain/models/clip.dart';
import '../../domain/models/timeline_transition.dart';

Map<String, dynamic> objectSchema(
  Map<String, dynamic> fields, [
  List<String> required = const [],
]) => {
  'type': 'object',
  'properties': fields,
  'required': required,
  'additionalProperties': false,
};
Map<String, dynamic> numberSchema(
  double min,
  double max, [
  String description = '',
]) => {
  'type': 'number',
  'minimum': min,
  'maximum': max,
  if (description.isNotEmpty) 'description': description,
};
Map<String, dynamic> stringSchema([List<String>? values]) => {
  'type': 'string',
  'minLength': 1,
  'maxLength': 10000,
  'enum': ?values,
};
final secondsSchema = numberSchema(
  0,
  86400 * 30,
  'Tempo em segundos; timeline salvo quando indicado como source.',
);
final clipIdSchema = {
  ...stringSchema(),
  'description':
      'ID de clipe retornado por get_project/get_clip. Grupos vinculados são preservados.',
};
final styleFields = <String, dynamic>{
  'font_family': stringSchema(),
  'font_size': numberSchema(12, 160),
  'text_color': {'type': 'integer', 'minimum': 0, 'maximum': 0xFFFFFFFF},
  'background_color': {'type': 'integer', 'minimum': 0, 'maximum': 0xFFFFFFFF},
  'opacity': numberSchema(0, 1),
  'animation': stringSchema(
    TextClipAnimation.values.map((e) => e.name).toList(),
  ),
};

class CommandDefinition {
  const CommandDefinition(
    this.description,
    this.schema, {
    this.destructive = false,
  });
  final String description;
  final Map<String, dynamic> schema;
  final bool destructive;
}

final remapScopeFields = <String, dynamic>{
  'scope': {
    ...stringSchema(['all_tracks', 'main_track_only']),
    'default': 'all_tracks',
  },
  'locked_tracks': {
    ...stringSchema(['fail', 'skip', 'unlock']),
    'default': 'fail',
  },
};

final commandCatalog = <String, CommandDefinition>{
  'remap_timeline': CommandDefinition(
    'Remove intervalos absolutos da timeline em uma única transformação. Remapeia camadas, vínculos A/V, keyframes, marcadores e transições; all_tracks por padrão. Bloqueios falham antes de editar, salvo skip/unlock explícito.',
    objectSchema(
      {
        'clip_id': clipIdSchema,
        'removed_ranges': {
          'type': 'array',
          'minItems': 1,
          'maxItems': 10000,
          'items': objectSchema(
            {'start': secondsSchema, 'end': secondsSchema},
            ['start', 'end'],
          ),
        },
        ...remapScopeFields,
      },
      ['clip_id', 'removed_ranges'],
    ),
    destructive: true,
  ),
  'split_clip': CommandDefinition(
    'Divide o grupo vinculado em um tempo absoluto da timeline, estritamente dentro do clipe. IDs novos são retornados no projeto.',
    objectSchema(
      {'clip_id': clipIdSchema, 'at': secondsSchema},
      ['clip_id', 'at'],
    ),
  ),
  'trim_clip': CommandDefinition(
    'Ajusta início e duração na mídia fonte de vídeo/áudio e seus vínculos. Não altera timeline_start.',
    objectSchema(
      {
        'clip_id': clipIdSchema,
        'source_start': secondsSchema,
        'source_duration': numberSchema(0.001, 2592000),
      },
      ['clip_id', 'source_start', 'source_duration'],
    ),
    destructive: true,
  ),
  'delete_clip': CommandDefinition(
    'Exclui o grupo vinculado; ripple=true fecha o espaço em todas as pistas, marcadores e transições.',
    objectSchema(
      {
        'clip_id': clipIdSchema,
        'ripple': {'type': 'boolean'},
      },
      ['clip_id'],
    ),
    destructive: true,
  ),
  'move_clip': CommandDefinition(
    'Move o grupo vinculado para timeline_start, opcionalmente para track_id compatível; colisões e pistas bloqueadas são rejeitadas.',
    objectSchema(
      {
        'clip_id': clipIdSchema,
        'timeline_start': secondsSchema,
        'track_id': stringSchema(),
        'group_ids': {
          'type': 'array',
          'minItems': 1,
          'maxItems': 500,
          'items': stringSchema(),
        },
      },
      ['clip_id', 'timeline_start'],
    ),
  ),
  'set_clip_speed': CommandDefinition(
    'Define velocidade 0.25–4 de áudio/vídeo, mantendo vínculos. Vídeo desloca conteúdo posterior (ripple).',
    objectSchema(
      {'clip_id': clipIdSchema, 'speed': numberSchema(0.25, 4)},
      ['clip_id', 'speed'],
    ),
  ),
  'add_text': CommandDefinition(
    'Cria texto ou legenda em uma camada de texto disponível. Cores são inteiros ARGB.',
    objectSchema(
      {
        'text': stringSchema(),
        'timeline_start': secondsSchema,
        'duration': numberSchema(1, 2592000),
        'is_caption': {'type': 'boolean'},
        ...styleFields,
      },
      ['text', 'timeline_start', 'duration'],
    ),
  ),
  'set_caption_style': CommandDefinition(
    'Atualiza estilo de um clipe de texto/legenda sem alterar seu conteúdo.',
    objectSchema(
      {'clip_id': clipIdSchema, 'text': stringSchema(), ...styleFields},
      ['clip_id'],
    ),
  ),
  'apply_effect': CommandDefinition(
    'Ajusta cor, filtro ou reenquadramento/crop de um clipe visual. Todos os valores são absolutos.',
    objectSchema(
      {
        'clip_id': clipIdSchema,
        'brightness': numberSchema(-1, 1),
        'contrast': numberSchema(0, 3),
        'saturation': numberSchema(0, 3),
        'exposure': numberSchema(-1, 1),
        'hue': numberSchema(-180, 180),
        for (final key in [
          'temperature',
          'tint',
          'shadows',
          'highlights',
          'curve_shadows',
          'curve_midtones',
          'curve_highlights',
        ])
          key: numberSchema(-1, 1),
        'reverse': {'type': 'boolean'},
        'chroma_key_enabled': {'type': 'boolean'},
        'chroma_key_color': {
          'type': 'integer',
          'minimum': 0,
          'maximum': 0xFFFFFFFF,
        },
        'chroma_key_similarity': numberSchema(0, 1),
        'chroma_key_blend': numberSchema(0, 1),
        'stabilization': {'type': 'boolean'},
        'filter': stringSchema(
          VideoFilterPreset.values.map((e) => e.name).toList(),
        ),
        'crop_left': numberSchema(0, 0.95),
        'crop_right': numberSchema(0, 0.95),
        'crop_top': numberSchema(0, 0.95),
        'crop_bottom': numberSchema(0, 0.95),
      },
      ['clip_id'],
    ),
  ),
  'set_keyframe': CommandDefinition(
    'Insere/substitui keyframe: time é normalizado de 0 a 1 na duração do clipe; property usa o nome do modelo v14.',
    objectSchema(
      {
        'clip_id': clipIdSchema,
        'property': stringSchema(
          ClipKeyframeProperty.values.map((e) => e.name).toList(),
        ),
        'time': numberSchema(0, 1),
        'value': numberSchema(-180, 180),
      },
      ['clip_id', 'property', 'time', 'value'],
    ),
  ),
  'add_transition': CommandDefinition(
    'Adiciona transição nativa v14 na posição absoluta da timeline (preset sem caminho de arquivo).',
    objectSchema(
      {
        'at': secondsSchema,
        'duration': numberSchema(0.2, 2),
        'name': stringSchema(),
        'placement': stringSchema(
          TimelineTransitionPlacement.values.map((e) => e.name).toList(),
        ),
        'direction': stringSchema(
          TimelineTransitionDirection.values.map((e) => e.name).toList(),
        ),
        'color': {'type': 'integer', 'minimum': 0, 'maximum': 0xFFFFFFFF},
        'intensity': numberSchema(0, 2),
        'preset': stringSchema(
          TimelineTransitionPreset.values.map((e) => e.name).toList(),
        ),
      },
      ['at', 'duration', 'preset'],
    ),
  ),
  'set_volume': CommandDefinition(
    'Define ganho do clipe entre 0 (mudo) e 2. Não normaliza o arquivo de mídia.',
    objectSchema(
      {'clip_id': clipIdSchema, 'volume': numberSchema(0, 2)},
      ['clip_id', 'volume'],
    ),
  ),
  'add_marker': CommandDefinition(
    'Adiciona marcador com nome e posição absoluta na timeline.',
    objectSchema({'at': secondsSchema, 'name': stringSchema()}, ['at', 'name']),
  ),
  'undo': CommandDefinition(
    'Desfaz a última transação do histórico compartilhado com Ctrl+Z.',
    objectSchema({}),
    destructive: true,
  ),
  'redo': CommandDefinition(
    'Refaz a última transação desfeita.',
    objectSchema({}),
    destructive: true,
  ),
};
