# MCP do editor

O app expõe **33 tools** e o resource `editor://project/summary` para editar o
projeto aberto. Funciona inteiramente local, com FFmpeg e Whisper já usados pelo
editor. Não precisa de chave de API de IA no aplicativo.

## Ligar e conectar

1. Abra o projeto e entre em **Arquivo → Configurações de IA (MCP)**.
2. Escolha a porta (padrão **47321**). Para exportar, escolha também uma pasta.
3. Mantenha **Aprovar plano antes de aplicar** ligado para revisar cada edição.
4. Ligue **Servidor MCP local**. O endpoint é `http://127.0.0.1:47321/mcp`.
5. Use **Copiar configuração do Codex**, cole o trecho no seu
   `%USERPROFILE%\.codex\config.toml` e preserve as demais configurações.

```toml
[mcp_servers.frame_studio]
url = "http://127.0.0.1:47321/mcp"
bearer_token_env_var = "FRAME_STUDIO_MCP_TOKEN"
tool_timeout_sec = 120
```

Em seguida, use **Copiar token** e, no PowerShell que iniciará o Codex:

```powershell
$env:FRAME_STUDIO_MCP_TOKEN = (Get-Clipboard).Trim()
codex
```

A variável precisa existir no processo do cliente. Se o cliente já estava aberto,
reinicie-o a partir desse ambiente. O botão de configuração copia apenas TOML;
o segredo é copiado separadamente. Referência dos campos:
[documentação oficial do Codex](https://developers.openai.com/codex/mcp).

Para outro cliente, como Claude com suporte a MCP HTTP local, configure o mesmo
endpoint com `Authorization: Bearer <token>`. O cliente precisa rodar nesta
máquina; um ambiente remoto não alcança o loopback do seu computador.

O indicador **IA conectada** aparece após a inicialização MCP do cliente.
**Desligar IA agora**, nas configurações ou no cabeçalho quando ligado, fecha
conexões, invalida planos e cancela jobs e leituras em andamento. Desfazer as
edições já aplicadas continua disponível pelo histórico do editor.

O servidor **sempre inicia desligado**, inclusive após reiniciar o app. Porta,
modo de aprovação e pasta de exportação persistem nas preferências; o token
persiste no armazenamento seguro do sistema. **Rotacionar token** encerra as
sessões e exige reconectar com o novo segredo. Troque a porta com o servidor desligado.

## Revisões, histórico e aprovação

Comece com `get_project`. Use IDs reais e a `revision` retornada. Tempos são
segundos, cores são inteiros ARGB e keyframes usam tempo normalizado de 0 a 1.
Revisão defasada ou ausente em uma edição é rejeitada, inclusive depois de undo.
A revisão é monotônica na sessão do editor, também acompanha alterações pela
UI e abertura de outro projeto, e **não acrescenta campos ao arquivo v14**.
Após reiniciar/reconectar, consulte a revisão novamente.

Cada edição ou lote publica um único snapshot no histórico existente, com
rótulo `IA: ...`. **Um Ctrl+Z desfaz o lote inteiro**. Se qualquer comando falhar,
o projeto e o histórico permanecem iguais. Gestos interativos de trim/arraste
precisam terminar antes de aplicar comandos externos.

```json
{
  "name": "preview_plan",
  "arguments": {
    "base_revision": 7,
    "label": "Cortar e ajustar áudio",
    "commands": [
      {"command": "set_volume", "arguments": {"clip_id": "audio_1", "volume": 0.7}},
      {"command": "split_clip", "arguments": {"clip_id": "video_1", "at": 4.5}}
    ]
  }
}
```

O dry-run retorna `plan_id`, revisão de origem, antes/depois, comandos e mudanças
nos clipes, incluindo propriedades de efeitos e keyframes. Não altera o projeto
nem cria undo. `apply_plan` reutiliza o **snapshot exato** do preview; não executa
novamente a macro. Planos vencem após 15 minutos ou qualquer alteração de revisão
e só podem ser aplicados uma vez. São retidos até 30 planos.

```json
{"name":"apply_plan","arguments":{"plan_id":"plan_1","base_revision":7}}
```

Com aprovação ligada, tools de edição retornam planos pendentes. Revise-os em
**Atividade da IA → Revisar plano → Aprovar e aplicar**. A IA não possui uma tool
para conceder aprovação. Com aprovação desligada, a IA pode usar `apply_plan`;
com aprovação ligada, a ação da UI aprova e aplica de uma vez. As quatro macros
sempre produzem previews, mesmo com aprovação desligada.
`undo`/`redo` também passam pela aprovação quando chamados pela IA.

O painel mostra chamadas, erros, planos e jobs. **Desfazer** aparece para a última
transação da IA ainda no topo do histórico. Edições posteriores exigem navegar
no histórico com Ctrl+Z. A aprovação e o desfazer humanos entram na auditoria.

## Tools e exemplos

Os exemplos abaixo são objetos `arguments` para `tools/call`. Substitua os IDs e
a revisão de exemplo. O catálogo exato de campos, limites e enums fica em
`tools/list`; campos desconhecidos são rejeitados.

| Tool | Comportamento | Exemplo de argumentos |
| --- | --- | --- |
| `split_clip` | Divide vídeo/áudio/texto/imagem e vínculos; o tempo deve estar dentro do clipe. IDs mudam. | `{"clip_id":"video_1","at":4.5,"base_revision":7}` |
| `trim_clip` | Ajusta fonte de vídeo/áudio; mínimo 0,1 s na timeline; respeita espaço e bloqueios. | `{"clip_id":"video_1","source_start":1,"source_duration":6,"base_revision":7}` |
| `delete_clip` | Exclui grupo; ripple fecha espaço e ajusta marcadores/transições. | `{"clip_id":"video_1","ripple":true,"base_revision":7}` |
| `move_clip` | Move grupo, opcionalmente pista e multisseleção de grupos. | `{"clip_id":"video_1","timeline_start":10,"track_id":"track_2","group_ids":["group_1"],"base_revision":7}` |
| `set_clip_speed` | Velocidade 0,25–4; vídeo e vínculos fazem ripple; áudio independente mantém outras posições. | `{"clip_id":"video_1","speed":1.25,"base_revision":7}` |
| `add_text` | Texto ou legenda, mínimo 1 s. Estilo opcional. | `{"text":"Olá","timeline_start":2,"duration":3,"is_caption":true,"base_revision":7}` |
| `set_caption_style` | Estilo de texto/legenda; conteúdo opcional. | `{"clip_id":"text_1","font_size":64,"background_color":2684354560,"base_revision":7}` |
| `apply_effect` | Cor/filtro/reverso/chroma/estabilização em vídeo; crop também em imagem. | `{"clip_id":"video_1","brightness":0.1,"filter":"cinematic","base_revision":7}` |
| `set_keyframe` | Insere/substitui propriedade em tempo normalizado; valida limites da propriedade. | `{"clip_id":"video_1","property":"opacity","time":0.5,"value":0.7,"base_revision":7}` |
| `add_transition` | Transição global nativa v14 por preset; duração 0,2–2 s. | `{"at":4,"duration":0.7,"preset":"dissolve","base_revision":7}` |
| `set_volume` | Ganho de um clipe, 0–2. Use o ID do clipe de áudio para mixagem. | `{"clip_id":"audio_1","volume":0.8,"base_revision":7}` |
| `add_marker` | Marcador nomeado na timeline. | `{"at":5,"name":"Revisar fala","base_revision":7}` |
| `undo` | Desfaz a última transação compartilhada. | `{"base_revision":7}` |
| `redo` | Refaz a última transação desfeita. | `{"base_revision":8}` |
| `apply_commands` | Lote atômico; em modo de aprovação retorna plano. Não mistura undo/redo. | `{"base_revision":7,"commands":[{"command":"add_marker","arguments":{"at":1,"name":"Início"}}]}` |
| `get_project` | Resumo paginado, revisão, pistas, clipes, marcadores, transições e resolução. | `{"limit":20}`; próxima: `{"cursor":"7:20","limit":20}` |
| `get_clip` | Tempos, grupo, pista, estilo, efeitos e keyframes. | `{"clip_id":"video_1"}` |
| `get_transcript` | Sem mídia: legendas da timeline. Com mídia: transcrição concluída na fonte. | `{"media_id":"media_1","offset":0,"limit":50}` |
| `list_media` | Metadados das mídias importadas, sem caminhos. | `{"offset":0,"limit":50}` |
| `get_loudness` | LUFS integrado, LRA e true peak da mídia fonte com ebur128. | `{"media_id":"media_1"}` |
| `get_frames` | Até 8 PNGs de até 320×180. Tempos de fonte com `media_id`, de timeline sem ele. | `{"media_id":"media_1","times":[0,2.5,5]}` |
| `detect_silence` | Job de silêncio; intervalos em segundos da fonte. | `{"media_id":"media_1","threshold_db":-35,"minimum":0.5}` |
| `detect_scenes` | Job de mudanças de cena na fonte. | `{"media_id":"media_1","threshold":0.3}` |
| `transcribe` | Job Whisper local; disponibiliza cues para get_transcript/macros. | `{"media_id":"media_1","language":"pt"}` |
| `export` | Job de exportação do snapshot/revisão, com configurações atuais do app. | `{"filename":"resultado.mp4","base_revision":7}` |
| `get_job` | Status, progresso, resultado ou erro. | `{"job_id":"job_1"}` |
| `cancel_job` | Cancela análise/exportação; resultado cancelado não é publicado. | `{"job_id":"job_1"}` |
| `preview_plan` | Dry-run de lote com antes/depois. | `{"base_revision":7,"commands":[{"command":"add_marker","arguments":{"at":1,"name":"Revisão"}}]}` |
| `apply_plan` | Aplica snapshot aprovado na mesma revisão, em uma transação. | `{"plan_id":"plan_1","base_revision":7}` |
| `remove_silences` | Preview usando job de silêncio concluído na revisão atual, do mesmo media_id. | `{"clip_id":"video_1","job_id":"job_1","padding":0.08,"base_revision":7}` |
| `cut_by_transcript` | Preview mantendo cues escolhidos da transcrição fonte; cortes ripple no grupo. | `{"clip_id":"video_1","keep_cue_indices":[0,2,3],"base_revision":7}` |
| `auto_captions` | Preview de legendas para o clipe usando transcrição já concluída. | `{"clip_id":"video_1","base_revision":7}` |
| `reframe_9x16` | Preview de crop central estático e saída 1080×1920; resolução entra no mesmo undo. | `{"clip_id":"video_1","base_revision":7}` |

Tools trazem `readOnlyHint`, `destructiveHint`, `idempotentHint` e
`openWorldHint`. Previews e análises não alteram o projeto. Exportação escreve
um arquivo novo e cancelamento altera o estado de um job.

Jobs: `queued → running → completed/failed/cancelled`. Consulte `get_job` com
intervalo de pelo menos 1 segundo. A fila executa um job por vez, aceita até 8
pendentes e retém até 50 registros. Resultados identificam projeto/revisão de
origem. Transcrição fica em cache na sessão, associada à mídia fonte.

Erros de tools usam `isError: true`, com o mesmo objeto no texto e em
`structuredContent`. IDs válidos, campos aceitos e limites aparecem em `details`:

```json
{"error":{"code":"revision_conflict","message":"Leia get_project e refaça o plano usando a revisão atual.","details":{"base_revision":6,"current_revision":7}}}
```

## Transporte e segurança

- Streamable HTTP com respostas JSON, sessões e versões `2025-03-26`,
  `2025-06-18`, `2025-11-25`. Inicialização/notification MCP obrigatórias antes
  das tools. `GET /mcp` retorna 405, pois o stream SSE independente é opcional;
  `DELETE /mcp` encerra a sessão. Progresso é consultado por jobs.
- Implementação direta do protocolo: `dart_mcp 0.5.2` consultado não oferece
  [Streamable HTTP nem autorização](https://pub.dev/packages/dart_mcp).
  Base: [especificação de transporte](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports).
- Bind exclusivo em `127.0.0.1`, bearer obrigatório, Host e Origin restritos ao
  loopback/porta escolhida. Sem CORS aberto ou autenticação por query string.
- 120 requisições/minuto por instância, até 8 requisições simultâneas,
  16 sessões, corpo máximo de 1 MiB e expiração de sessão após 30 minutos inativa.
- Tools não importam arquivos nem aceitam caminhos de leitura. Mídias são IDs
  do projeto; referências importadas pela UI recebem autorização para o alvo
  canônico. Retarget de links e arquivos fora da autorização são rejeitados.
  UNC, URLs, caminhos relativos e streams NTFS não são aceitos por essa API.
- Exportação recebe apenas basename `.mp4`/`.wav`, na pasta escolhida na UI.
  Diretórios são resolvidos canonicamente e destinos existentes são rejeitados.
  Fontes e assets do projeto são conferidos novamente antes da exportação.
- Preferências: `%LOCALAPPDATA%\TGI_VIDEO_EDITOR\mcp_settings.json`.
  Token: `flutter_secure_storage`, separado das preferências e do projeto.
  Auditoria: `mcp_audit.jsonl` no mesmo diretório de dados; rotação em 5 MiB,
  mantendo um arquivo anterior. Registra tool, campos/IDs, revisões e resultado;
  não grava bearer, conteúdo de transcrição nem bytes de miniaturas.

## Limitações

- A mídia original não é modificada; edição opera no modelo da timeline.
  O arquivo continua no formato **v14**, com a persistência existente.
- Miniaturas mostram a fonte escolhida na timeline, com trim/speed/reverso,
  sem renderizar a composição final de textos, efeitos ou camadas.
  Loudness mede a fonte, sem volume/efeitos/mixagem da timeline.
- `reframe_9x16` é central e estático, aplicado ao clipe escolhido, com resolução
  vertical compartilhada pelo projeto; não rastreia pessoas nem reenquadra os
  demais clipes. Use o preview do editor para revisar o conjunto.
- Legendas usam a transcrição existente; `transcribe` não aplica edições.
  Cues muito curtos são agrupados quando possível. Uma legenda final abaixo
  de 1 s gera erro útil, respeitando o mínimo do modelo v14.
- `add_transition` mantém o modelo global de transições v14; não cria um novo
  modelo de transição por par/pista. Split troca IDs; releia os clipes depois.
- Páginas contêm até 100 clipes/mídias/cues. O resumo inclui até 100 marcadores
  e transições, com suas contagens totais. Diff de plano exibe até 200 clipes;
  a resposta identifica truncamento e a UI permite revisar todos os comandos.
- FFmpeg e o modelo Whisper local precisam estar instalados pelos mecanismos
  existentes do editor. Não há download de modelos pelo MCP.
- Sem stdio, SSE independente, assinaturas de resources, OAuth ou transporte
  stateless 2026. Clientes precisam suportar uma das versões de sessão acima.

## Validação executada e como reproduzir

Foram executados contratos HTTP reais, testes de UI e testes com FFmpeg real.
O cliente independente usou `@modelcontextprotocol/sdk 1.32.1`; o
**MCP Inspector 2.11.0** passou em `tools/list --strict` e `get_project`, sem avisos.
Também foram executados plano/aplicação/undo, rejeição de revisão antiga, token
inválido, exportação fora da pasta, miniaturas, LUFS, jobs de análise, exportação
nativa e transcrição com **Whisper Base real**, produzindo 3 cues de fala sintética.
O host Flutter confirmou que o JSON do projeto voltou idêntico após undo.
O resultado sem credenciais está em [validation/MCP_CLIENT_RESULT.json](validation/MCP_CLIENT_RESULT.json).

Esse teste externo usou um host Flutter de teste com os mesmos módulos do app,
um projeto sintético e credenciais temporárias. Não foi uma sessão interativa
no Codex/Claude nem uma validação audiovisual na janela nativa do editor.

```powershell
# Na pasta source:
flutter analyze --no-pub
flutter test --no-pub --concurrency=1
flutter test --no-pub --concurrency=1 --dart-define=TGI_RUN_FFMPEG_INTEGRATION_TESTS=true

# Na raiz, dependências de validação isoladas e ignoradas pelo Git:
npm install --prefix .work/mcp-client --no-audit --no-fund @modelcontextprotocol/inspector@2.11.0 @modelcontextprotocol/sdk@1.32.1
```

Para repetir o teste externo, crie uma pasta nova em `.work/`. Em um terminal
de `source`, defina `MCP_VALIDATION_DIR` para essa pasta absoluta e execute
`flutter test --no-pub tool/mcp_inspector_host_test.dart`. Opcionalmente defina
`MCP_SPEECH_FILE` com uma fala local para testar Whisper real. Aguarde o arquivo
`session.json`. Em outro terminal, na raiz:

```powershell
node tool/mcp_client_smoke.mjs '<pasta absoluta de validação>' '.work/mcp-client/node_modules'
```

O script usa o SDK, executa o Inspector CLI, salva `report.json` sem credenciais
e sinaliza a parada do host. `session.json` contém um token **temporário de teste**
e deve permanecer na pasta ignorada. O teste tem limite de 5 minutos.

Na validação final: análise limpa, **215 testes padrão aprovados / 13 opcionais
ignorados**; com o dart-define acima, **228 aprovados / zero ignorados**. Testes
anteriores foram preservados sem edição. O build Windows release foi copiado
para `aplicativo/`, com 66 arquivos conferidos por SHA-256, zero divergências.
Evidência do build: [validation/MCP_BUILD_RESULT.json](validation/MCP_BUILD_RESULT.json).
