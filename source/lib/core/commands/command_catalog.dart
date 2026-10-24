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
// Units and ID discovery are shared server instructions; avoid repeating them
// in every tool schema while retaining all validation constraints.
final secondsSchema = numberSchema(0, 86400 * 30);
final clipIdSchema = stringSchema();
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
    'description':
        'all_tracks remapeia tudo; main_track_only preserva outras pistas.',
  },
  'locked_tracks': {
    ...stringSchema(['fail', 'skip', 'unlock']),
    'default': 'fail',
    'description':
        'fail rejeita; skip preserva bloqueadas; unlock destrava no lote.',
  },
};

final mediaOverlaySchema = objectSchema(
  {
    'media_id': stringSchema(),
    'at': secondsSchema,
    'duration': numberSchema(0.1, 2592000),
    'position': objectSchema(
      {'x': numberSchema(0, 1), 'y': numberSchema(0, 1)},
      ['x', 'y'],
    ),
    'scale': numberSchema(0.1, 1),
    'fade_in_ms': {'type': 'integer', 'minimum': 0, 'maximum': 60000},
    'fade_out_ms': {'type': 'integer', 'minimum': 0, 'maximum': 60000},
    'volume': numberSchema(0, 2),
  },
  ['media_id', 'at', 'duration', 'position', 'scale'],
);

final commandCatalog = <String, CommandDefinition>{
  'add_library_asset': CommandDefinition(
    'Importa e insere asset_id de list_library; track=new padrão. download=true baixa faltantes; overlay=true sobrepõe visual.',
    objectSchema(
      {
        'asset_id': stringSchema(),
        'at': secondsSchema,
        'duration': numberSchema(.1, 2592000),
        'in': secondsSchema,
        'track': stringSchema(),
        'download': {'type': 'boolean', 'default': false},
        'text': stringSchema(),
        'overlay': {'type': 'boolean'},
        for (final key in [
          'position',
          'scale',
          'fade_in_ms',
          'fade_out_ms',
          'volume',
        ])
          key: (mediaOverlaySchema['properties'] as Map<String, dynamic>)[key],
      },
      ['asset_id', 'at'],
    ),
  ),
  'add_image_overlay': CommandDefinition(
    'Imagem acima do vídeo, com alpha. position em 0–1; scale é fração do quadro. Fades em ms; volume padrão 0.',
    mediaOverlaySchema,
  ),
  'add_video_overlay': CommandDefinition(
    'Vídeo acima da principal com áudio vinculado. position em 0–1; scale é fração do quadro. Fades em ms; volume padrão 0.',
    mediaOverlaySchema,
  ),
  'add_clip': CommandDefinition(
    'Insere mídia [in,out) em at (segundos). track: ID ou new para nova pista. Preserva A/V e rejeita colisões.',
    objectSchema(
      {
        'media_id': stringSchema(),
        'track': stringSchema(),
        'at': secondsSchema,
        'in': secondsSchema,
        'out': secondsSchema,
      },
      ['media_id', 'track', 'at', 'in', 'out'],
    ),
  ),
  'add_clips_sequence': CommandDefinition(
    'Insere mídias inteiras em sequência desde at. track: ID ou new; um undo desfaz o lote.',
    objectSchema(
      {
        'media_ids': {
          'type': 'array',
          'minItems': 1,
          'maxItems': 100,
          'items': stringSchema(),
        },
        'track': stringSchema(),
        'at': secondsSchema,
      },
      ['media_ids', 'track', 'at'],
    ),
  ),
  'import_media': CommandDefinition(
    'Importa após ffprobe: pastas autorizadas, 512 MiB/arquivo, 2 GiB/lote. Retorna ID, duração e tipo.',
    objectSchema(
      {
        'paths': {
          'type': 'array',
          'minItems': 1,
          'maxItems': 32,
          'items': {'type': 'string', 'minLength': 1, 'maxLength': 4096},
        },
      },
      ['paths'],
    ),
  ),
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
        'join_fade_ms': {
          'type': 'integer',
          'minimum': 0,
          'maximum': 100,
          'default': 0,
        },
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
    'Velocidade 0.25–4 com vínculos A/V; vídeo desloca conteúdo posterior.',
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
    'Ajusta estilo ou texto de uma legenda/clipe de texto.',
    objectSchema(
      {'clip_id': clipIdSchema, 'text': stringSchema(), ...styleFields},
      ['clip_id'],
    ),
  ),
  'apply_effect': CommandDefinition(
    'Cor, filtro e crop absolutos do clipe visual.',
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
    'Keyframe: time em 0–1 da duração; property usa o modelo v14.',
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
    'Insere preset nativo de transição em at, sem arquivo externo.',
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
