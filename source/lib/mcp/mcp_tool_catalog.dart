import '../core/commands/command_engine.dart';
import 'compact_schema.dart';

final revisionSchema = <String, dynamic>{'type': 'integer', 'minimum': 0};
final pageFields = <String, dynamic>{
  'offset': {'type': 'integer', 'minimum': 0},
  'limit': {'type': 'integer', 'minimum': 1, 'maximum': 100},
};
final commandListSchema = <String, dynamic>{
  'type': 'array',
  'minItems': 1,
  'maxItems': 500,
  'items': {
    'type': 'object',
    'properties': {
      'tool': stringSchema(
        commandCatalog.keys
            .where((name) => !['undo', 'redo', 'remap_timeline'].contains(name))
            .toList(),
      ),
      'command': {
        ...stringSchema(),
        'description': 'Alias legado de tool; não combine os dois.',
      },
      'arguments': {'type': 'object', 'additionalProperties': true},
      'base_revision': revisionSchema,
    },
    'required': ['arguments'],
    'additionalProperties': false,
    'oneOf': [
      {
        'required': ['tool'],
      },
      {
        'required': ['command'],
      },
    ],
  },
};

class McpToolDefinition {
  const McpToolDefinition(
    this.name,
    this.description,
    this.schema, {
    this.readOnly = false,
    this.destructive = false,
    this.idempotent,
  });
  final String name, description;
  final Map<String, dynamic> schema;
  final bool readOnly, destructive;
  final bool? idempotent;
  Map<String, Object?> toJson() => {
    'name': name,
    'description': description,
    'inputSchema': compactSchema(schema),
    'annotations': {
      'readOnlyHint': readOnly,
      'destructiveHint': destructive,
      'idempotentHint': idempotent ?? readOnly,
      'openWorldHint': false,
    },
  };
}

final removeSilencesArguments = objectSchema(
  {
    'clip_id': clipIdSchema,
    'mode': {
      ...stringSchema(['suave', 'normal', 'agressivo']),
      'default': 'normal',
      'description': 'Preset; parâmetros explícitos prevalecem.',
    },
    'job_id': {
      ...stringSchema(),
      'description':
          'Job detect_silence desta revisão; ausente inicia análise.',
    },
    'threshold_db': {
      ...numberSchema(-80, 0, 'Limiar dB; igual ao job.'),
      'default': -35,
    },
    'minimum': {
      ...numberSchema(0.1, 10, 'Segundos da fonte; igual ao job.'),
      'default': 0.5,
    },
    'padding': {
      ...numberSchema(0, 1, 'Segundos da fonte por borda.'),
      'default': 0.08,
    },
    ...remapScopeFields,
    ...cutJoinFields,
  },
  ['clip_id'],
);

final cutJoinFields = <String, dynamic>{
  'min_keep_ms': {
    'type': 'integer',
    'minimum': 0,
    'maximum': 10000,
    'default': 250,
    'description': 'Funde trechos curtos; 0 desativa.',
  },
  'protect_words': {
    'type': 'boolean',
    'description': 'Protege palavras/frases se há transcrição; padrão ativo.',
  },
  'word_margin': {
    ...numberSchema(0, .5),
    'default': .05,
    'description': 'Margem de palavras na fonte (s).',
  },
  'join_fade_ms': {
    'type': 'integer',
    'minimum': 0,
    'maximum': 100,
    'default': 8,
    'description': 'Fade de áudio nas emendas (ms); 0 desativa.',
  },
};

final _mcpToolDefinitions = <String, McpToolDefinition>{
  for (final e in commandCatalog.entries.where(
    (e) => e.key != 'remap_timeline',
  ))
    e.key: McpToolDefinition(
      e.key,
      e.value.description,
      objectSchema(
        {
          ...e.value.schema['properties'] as Map<String, dynamic>,
          'base_revision': revisionSchema,
        },
        [...e.value.schema['required'] as List<String>, 'base_revision'],
      ),
      destructive: e.value.destructive,
    ),
  'apply_commands': McpToolDefinition(
    'apply_commands',
    'Aplica lote atômico com um undo; aprovação ativa devolve plano. Aceita tool/arguments e o alias legado command.',
    objectSchema(
      {
        'commands': commandListSchema,
        'base_revision': revisionSchema,
        'label': stringSchema(),
      },
      ['commands', 'base_revision'],
    ),
    destructive: true,
  ),
  'get_project': McpToolDefinition(
    'get_project',
    'Lê resumo, revisão, pistas e página de clipes. Paginação por next_cursor; revisão alterada invalida cursor.',
    objectSchema({
      'cursor': stringSchema(),
      'limit': {'type': 'integer', 'minimum': 1, 'maximum': 100},
    }),
    readOnly: true,
  ),
  'get_clip': McpToolDefinition(
    'get_clip',
    'Detalhes, efeitos, estilo e keyframes de um clipe por ID. Tempos em segundos.',
    objectSchema({'clip_id': clipIdSchema}, ['clip_id']),
    readOnly: true,
  ),
  'get_transcript': McpToolDefinition(
    'get_transcript',
    'Lê legendas da timeline ou cues da fonte após transcribe. Índices: offset + posição.',
    objectSchema({'media_id': stringSchema(), ...pageFields}),
    readOnly: true,
  ),
  'list_media': McpToolDefinition(
    'list_media',
    'Lista paginada das mídias importadas; devolve IDs e metadados sem caminhos de disco.',
    objectSchema(pageFields),
    readOnly: true,
  ),
  'browse_media_files': McpToolDefinition(
    'browse_media_files',
    'Lista arquivos importáveis e subpastas autorizadas; sem directory lista as raízes. Não segue links.',
    objectSchema({
      'directory': {...stringSchema(), 'maxLength': 4096},
      ...pageFields,
    }),
    readOnly: true,
  ),
  'list_library': McpToolDefinition(
    'list_library',
    'Busca itens da biblioteca do editor, com asset_id, tipo, licença e cache. Não baixa nem edita.',
    objectSchema({
      'query': {...stringSchema(), 'maxLength': 200},
      'kind': stringSchema(['audio', 'image', 'video', 'title', 'transition']),
      ...pageFields,
    }),
    readOnly: true,
  ),
  'get_loudness': McpToolDefinition(
    'get_loudness',
    'Mede LUFS, LRA e true peak da fonte, sem efeitos/mixagem da timeline.',
    objectSchema({'media_id': stringSchema()}, ['media_id']),
    readOnly: true,
  ),
  'get_frames': McpToolDefinition(
    'get_frames',
    'Gera 1–8 PNGs 320x180 da fonte, sem composição. Tempos: fonte com media_id; timeline sem ele.',
    objectSchema(
      {
        'media_id': stringSchema(),
        'times': {
          'type': 'array',
          'minItems': 1,
          'maxItems': 8,
          'items': secondsSchema,
        },
      },
      ['times'],
    ),
    readOnly: true,
  ),
  'detect_silence': McpToolDefinition(
    'detect_silence',
    'Inicia análise local de silêncio. Retorna job_id; consulte get_job. Intervalos em segundos da fonte.',
    objectSchema(
      {
        'media_id': stringSchema(),
        'threshold_db': numberSchema(-80, 0),
        'minimum': numberSchema(0.1, 10),
      },
      ['media_id'],
    ),
    readOnly: true,
  ),
  'detect_scenes': McpToolDefinition(
    'detect_scenes',
    'Inicia detecção local de mudanças de cena. Retorna job_id; tempos são da fonte.',
    objectSchema(
      {'media_id': stringSchema(), 'threshold': numberSchema(0.01, 1)},
      ['media_id'],
    ),
    readOnly: true,
  ),
  'transcribe': McpToolDefinition(
    'transcribe',
    'Job Whisper local; guarda transcrição para get_transcript, sem criar legendas.',
    objectSchema(
      {
        'media_id': stringSchema(),
        'language': stringSchema(),
        'model': {
          'type': 'string',
          'enum': [
            'tiny',
            'base',
            'small',
            'medium',
            'large-v3',
            'large-v3-turbo-q5_0',
            'large-v3-q5_0',
          ],
        },
        'vocabulary': {'type': 'string', 'maxLength': 2000},
        'vad': {'type': 'boolean'},
      },
      ['media_id'],
    ),
    readOnly: true,
  ),
  'export': McpToolDefinition(
    'export',
    'Job de exportação .mp4/.wav na pasta escolhida, com configurações atuais. Grava arquivo novo; não sobrescreve.',
    objectSchema(
      {'filename': stringSchema(), 'base_revision': revisionSchema},
      ['filename', 'base_revision'],
    ),
  ),
  'get_job': McpToolDefinition(
    'get_job',
    'Lê status/progresso/resultado/erro de um job. Status: queued, running, completed, failed, cancelled.',
    objectSchema({'job_id': stringSchema()}, ['job_id']),
    readOnly: true,
  ),
  'cancel_job': McpToolDefinition(
    'cancel_job',
    'Cancela um job pendente ou ativo. Resultados cancelados não são publicados.',
    objectSchema({'job_id': stringSchema()}, ['job_id']),
  ),
  'preview_plan': McpToolDefinition(
    'preview_plan',
    'Prévia de commands ou macro remove_silences; retorna plan_id sem editar. Expira em 15 min/mudança de revisão.',
    {
      'type': 'object',
      'additionalProperties': false,
      'properties': {
        'commands': commandListSchema,
        'macro': stringSchema(['remove_silences']),
        'arguments': {'type': 'object', 'additionalProperties': true},
        'base_revision': revisionSchema,
        'label': stringSchema(),
      },
      'oneOf': [
        {
          'required': ['commands'],
        },
        {
          'required': ['macro', 'arguments'],
        },
      ],
      'required': ['base_revision'],
    },
    readOnly: true,
  ),
  'apply_plan': McpToolDefinition(
    'apply_plan',
    'Aplica snapshot exato com um undo; exige aprovação no app quando ativa.',
    objectSchema(
      {'plan_id': stringSchema(), 'base_revision': revisionSchema},
      ['plan_id', 'base_revision'],
    ),
    destructive: true,
  ),
  'remove_silences': McpToolDefinition(
    'remove_silences',
    'Corta silêncio com proteção de fala e camadas. Sem job_id analisa; com job pronto planeja. Aplicar: apply_plan.',
    objectSchema(
      {
        ...removeSilencesArguments['properties'] as Map<String, dynamic>,
        'base_revision': revisionSchema,
      },
      ['clip_id', 'base_revision'],
    ),
    readOnly: true,
  ),
  'cut_by_transcript': McpToolDefinition(
    'cut_by_transcript',
    'Mantém cues escolhidos com proteção de palavras e camadas. Prévia; aplicar: apply_plan.',
    objectSchema(
      {
        'clip_id': clipIdSchema,
        'keep_cue_indices': {
          'type': 'array',
          'minItems': 1,
          'maxItems': 500,
          'items': {'type': 'integer', 'minimum': 0},
        },
        ...cutJoinFields,
        'base_revision': revisionSchema,
      },
      ['clip_id', 'keep_cue_indices', 'base_revision'],
    ),
    readOnly: true,
  ),
  'auto_captions': McpToolDefinition(
    'auto_captions',
    'Planeja legendas brancas sincronizadas; exige transcrição pronta. Pode criar camadas. Aplicar: apply_plan.',
    objectSchema(
      {'clip_id': clipIdSchema, 'base_revision': revisionSchema},
      ['clip_id', 'base_revision'],
    ),
    readOnly: true,
  ),
  'reframe_9x16': McpToolDefinition(
    'reframe_9x16',
    'Prévia de crop central 1080x1920. apply_plan aplica; um undo.',
    objectSchema(
      {'clip_id': clipIdSchema, 'base_revision': revisionSchema},
      ['clip_id', 'base_revision'],
    ),
    readOnly: true,
  ),
};

/// Intent-level tools stay ahead of individual edits.
const macroToolNames = [
  'remove_silences',
  'cut_by_transcript',
  'auto_captions',
  'reframe_9x16',
  'preview_plan',
  'apply_plan',
];
const mcpToolOrder = [
  'get_project',
  ...macroToolNames,
  'split_clip',
  'trim_clip',
  'delete_clip',
  'move_clip',
  'set_clip_speed',
  'add_text',
  'set_caption_style',
  'apply_effect',
  'set_keyframe',
  'add_transition',
  'set_volume',
  'add_marker',
  'undo',
  'redo',
  'apply_commands',
  'get_clip',
  'get_transcript',
  'list_media',
  'browse_media_files',
  'list_library',
  'add_library_asset',
  'import_media',
  'add_clip',
  'add_clips_sequence',
  'add_image_overlay',
  'add_video_overlay',
  'get_loudness',
  'get_frames',
  'detect_silence',
  'detect_scenes',
  'transcribe',
  'get_job',
  'cancel_job',
  'export_cut_check',
  'export',
];
final mcpToolCatalog = <String, McpToolDefinition>{
  for (final name in mcpToolOrder)
    if (_mcpToolDefinitions.containsKey(name)) name: _mcpToolDefinitions[name]!,
};

/// Original public catalog remains stable for consumers of the base tool set.
/// The server advertises this full registry, including file-output readers.
final _cutCheckDefinition = McpToolDefinition(
  'export_cut_check',
  'Job .mp4/.wav dos 10 primeiros cortes do plano na pasta escolhida; não sobrescreve nem edita.',
  objectSchema(
    {
      'plan_id': stringSchema(),
      'filename': stringSchema(),
      'base_revision': revisionSchema,
    },
    ['plan_id', 'filename', 'base_revision'],
  ),
  readOnly: true,
  idempotent: false,
);
final mcpRuntimeToolCatalog = <String, McpToolDefinition>{
  for (final name in mcpToolOrder)
    name: name == 'export_cut_check'
        ? _cutCheckDefinition
        : mcpToolCatalog[name]!,
};
