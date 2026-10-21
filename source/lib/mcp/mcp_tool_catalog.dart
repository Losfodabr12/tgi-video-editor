import '../core/commands/command_engine.dart';

final revisionSchema = <String, dynamic>{
  'type': 'integer',
  'minimum': 0,
  'description':
      'Revisão atual de get_project; obrigatória para editar. Uma transação incrementa a revisão uma vez.',
};
final pageFields = <String, dynamic>{
  'offset': {'type': 'integer', 'minimum': 0},
  'limit': {'type': 'integer', 'minimum': 1, 'maximum': 100},
};
final commandListSchema = <String, dynamic>{
  'type': 'array',
  'minItems': 1,
  'maxItems': 500,
  'items': {
    'oneOf': [
      for (final e in commandCatalog.entries.where(
        (e) => !['undo', 'redo'].contains(e.key),
      ))
        objectSchema(
          {
            'command': stringSchema([e.key]),
            'arguments': e.value.schema,
            'base_revision': revisionSchema,
          },
          ['command', 'arguments'],
        ),
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
  });
  final String name, description;
  final Map<String, dynamic> schema;
  final bool readOnly, destructive;
  Map<String, Object?> toJson() => {
    'name': name,
    'description': description,
    'inputSchema': schema,
    'annotations': {
      'readOnlyHint': readOnly,
      'destructiveHint': destructive,
      'idempotentHint': readOnly,
      'openWorldHint': false,
    },
  };
}

final mcpToolCatalog = <String, McpToolDefinition>{
  for (final e in commandCatalog.entries)
    e.key: McpToolDefinition(
      e.key,
      '${e.value.description} Exige base_revision. Se aprovação estiver ativa, devolve plano pendente para aprovação dentro do app.',
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
    'Aplica um lote atômico: todos os comandos são validados antes de publicar. Um Ctrl+Z desfaz o lote. Em modo de aprovação devolve um plano.',
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
    'Resumo compacto do projeto aberto, pistas, marcadores e uma página de clipes. Use next_cursor; cursor fica inválido se a revisão mudar.',
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
    'Legendas da timeline, ou cues na fonte de media_id após um job transcribe concluído. Índices são offset + posição na página.',
    objectSchema({'media_id': stringSchema(), ...pageFields}),
    readOnly: true,
  ),
  'list_media': McpToolDefinition(
    'list_media',
    'Lista paginada das mídias importadas; devolve IDs e metadados sem caminhos de disco.',
    objectSchema(pageFields),
    readOnly: true,
  ),
  'get_loudness': McpToolDefinition(
    'get_loudness',
    'Mede LUFS integrado, LRA e true peak da fonte com FFmpeg ebur128. Não inclui ganho, efeitos ou mixagem da timeline.',
    objectSchema({'media_id': stringSchema()}, ['media_id']),
    readOnly: true,
  ),
  'get_frames': McpToolDefinition(
    'get_frames',
    'Miniaturas PNG até 320x180, 1–8 tempos. Com media_id os tempos são da fonte; sem ele são da timeline. São frames de fonte, sem composição de textos/efeitos.',
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
    'Inicia transcrição local com Whisper instalado. Retorna job_id. Ao concluir, leia cues com get_transcript. Não adiciona legendas automaticamente.',
    objectSchema(
      {'media_id': stringSchema(), 'language': stringSchema()},
      ['media_id'],
    ),
    readOnly: true,
  ),
  'export': McpToolDefinition(
    'export',
    'Exporta snapshot da revisão indicada usando as configurações atuais. Apenas filename .mp4/.wav, sem diretórios. O usuário precisa escolher a pasta no app. Não sobrescreve arquivo.',
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
    'Dry-run de um lote: devolve plan_id, antes/depois e alterações sem editar projeto/histórico. Aplicar reutiliza o snapshot exato, válido por 15 minutos na mesma revisão.',
    objectSchema(
      {
        'commands': commandListSchema,
        'base_revision': revisionSchema,
        'label': stringSchema(),
      },
      ['commands', 'base_revision'],
    ),
    readOnly: true,
  ),
  'apply_plan': McpToolDefinition(
    'apply_plan',
    'Aplica o plano exato em uma transação. Se aprovação estiver ativa, precisa de aprovação humana no app. Uma IA não pode conceder aprovação.',
    objectSchema(
      {'plan_id': stringSchema(), 'base_revision': revisionSchema},
      ['plan_id', 'base_revision'],
    ),
    destructive: true,
  ),
  'remove_silences': McpToolDefinition(
    'remove_silences',
    'PREVIEW: plano de cortes ripple no clipe/grupo usando job detect_silence concluído na revisão atual. Padding preserva bordas da fala. Aplique com apply_plan.',
    objectSchema(
      {
        'clip_id': clipIdSchema,
        'job_id': stringSchema(),
        'padding': numberSchema(0, 1),
        'base_revision': revisionSchema,
      },
      ['clip_id', 'job_id', 'base_revision'],
    ),
    readOnly: true,
  ),
  'cut_by_transcript': McpToolDefinition(
    'cut_by_transcript',
    'PREVIEW: mantém apenas falas escolhidas por índices de get_transcript(media_id). Usa transcrição existente; corta o clipe/grupo e fecha os espaços. Aplique com apply_plan.',
    objectSchema(
      {
        'clip_id': clipIdSchema,
        'keep_cue_indices': {
          'type': 'array',
          'minItems': 1,
          'maxItems': 500,
          'items': {'type': 'integer', 'minimum': 0},
        },
        'base_revision': revisionSchema,
      },
      ['clip_id', 'keep_cue_indices', 'base_revision'],
    ),
    readOnly: true,
  ),
  'auto_captions': McpToolDefinition(
    'auto_captions',
    'PREVIEW: converte transcrição existente em legendas para o trecho/speed/reverso do clipe. Trechos abaixo de 1s são agrupados quando possível (limite v14). Aplique com apply_plan.',
    objectSchema(
      {'clip_id': clipIdSchema, 'base_revision': revisionSchema},
      ['clip_id', 'base_revision'],
    ),
    readOnly: true,
  ),
  'reframe_9x16': McpToolDefinition(
    'reframe_9x16',
    'PREVIEW: crop central estático do clipe e saída 1080x1920. Não rastreia pessoas. Crop e resolução compartilham undo. Aplique com apply_plan.',
    objectSchema(
      {'clip_id': clipIdSchema, 'base_revision': revisionSchema},
      ['clip_id', 'base_revision'],
    ),
    readOnly: true,
  ),
};
