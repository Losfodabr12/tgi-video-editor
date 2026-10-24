# MCP do editor

O app expõe **39 tools** e o resource `editor://project/summary` para editar o
projeto aberto. Funciona inteiramente local, com FFmpeg e Whisper já usados pelo
editor. Não precisa de chave de API de IA no aplicativo.

## Pastas autorizadas e importação de assets

Em **Arquivo → Configurações de IA (MCP)**, a lista de pastas de importação
começa **vazia**, inclusive ao carregar configurações antigas. Só o usuário
pode adicionar/remover pastas nessa tela. **Adicionar pasta** abre o seletor;
**Adicionar Desktop\\FrameStudio_Assets** cria essa pasta após o clique, se
necessário, e a autoriza. Nenhuma pasta é criada ou autorizada ao abrir o app.
As permissões ficam em `mcp_settings.json`, fora do projeto v14.

`import_media` aceita apenas caminhos locais absolutos dentro das pastas
autorizadas. Rejeita caminhos relativos, componentes `.`/`..`, rede/URL/UNC,
streams alternativos do Windows, links simbólicos e junctions, inclusive em
qualquer diretório ancestral ou na própria raiz autorizada. Um prefixo parecido
com a pasta autorizada não concede acesso a uma pasta irmã.
Raízes autorizadas com nomes curtos 8.3 do Windows são resolvidas para o caminho
canônico, que pode ser revalidado ao aplicar o plano; junctions continuam proibidas.

Limites de cada chamada de importação:

- **32 caminhos**, **512 MiB por arquivo**, **2 GiB no conjunto**; arquivo vazio
  é rejeitado. MiB/GiB usam potências de 1024.
- Formatos: **png, jpg, webp, mp4, mov, webm, mp3, wav**. O tipo de stream precisa
  corresponder ao formato informado pela extensão.
- ffprobe executa antes de aceitar a mídia, com demuxer escolhido pela extensão,
  somente protocolo local `file`, limite de análise/saída e timeout de **15 s**.
  O arquivo de entrada nunca é executado como programa ou script.
- Imagens recebem duração inicial de **5 s**, com dimensões detectadas e arquivo
  original preservado. Vídeo/áudio recebem a duração retornada pelo ffprobe.
- Uma falha em qualquer item rejeita o lote inteiro. A prévia guarda os hashes;
  ao aplicar, os arquivos e as permissões são conferidos novamente. Revogação,
  substituição por link, remoção ou mudança do conteúdo impedem a aplicação.

Exemplo, depois de autorizar a pasta e ler a revisão em `get_project`:

```json
{
  "tool": "import_media",
  "arguments": {
    "paths": ["C:/Users/voce/Desktop/FrameStudio_Assets/mascote.png"],
    "base_revision": 0
  }
}
```

A resposta inclui `imported_media`, com `media_id`, `duration` em segundos e
`type`. Com aprovação ativa, esses IDs são **prospectivos** até `apply_plan`:
a biblioteca e o histórico permanecem intactos durante a prévia. Os IDs são
estáveis para o mesmo caminho/conteúdo, permitindo preparar um segundo plano
que combine importação e inserção. Não é permitido fornecer metadados de mídia
por JSON para pular o ffprobe. Mídias já importadas pela interface continuam
seguindo as autorizações de leitura do projeto; essas novas pastas controlam
as **novas importações pela IA**.

## Inserção e sobreposições transacionais

As cinco tools novas aceitam `base_revision`, entram em `preview_plan` e
`apply_commands`, respeitam a aprovação no app e usam rótulos `IA: ...`.
`apply_plan` aplica o snapshot exato em uma transação. **Um Ctrl+Z** restaura
a biblioteca e todos os clipes do lote, sem excluir os arquivos de origem.
O formato de projeto continua **v14**, com os campos de clipe já existentes.

| Tool | Argumentos específicos |
| --- | --- |
| `import_media` | `paths`: lista de caminhos autorizados |
| `add_clip` | `media_id`, `track`, `at`, `in`, `out` |
| `add_clips_sequence` | `media_ids`, `track`, `at` |
| `add_image_overlay` | `media_id`, `at`, `duration`, `position`, `scale`; fades/volume opcionais |
| `add_video_overlay` | Mesmos argumentos de overlay; cria o áudio vinculado quando existe |

`track` é um ID de pista **existente**, retornado por `get_project`, não seu
rótulo visual. `at` é a posição absoluta na timeline; `in` e `out` são os limites
da fonte, intervalo `[in,out)`, todos em segundos. O trecho precisa ter pelo
menos 0,1 s e caber na fonte. `add_clips_sequence` insere as mídias completas,
na ordem recebida, sem espaços. Bloqueios, pista incompatível ou colisões
rejeitam o lote inteiro. Vídeo com áudio preserva o grupo A/V vinculado.

Overlays criam uma **nova camada visual acima das anteriores**, incluindo a
trilha principal. Imagens preservam o alpha original; não são achatadas sobre
um fundo. Parâmetros:

- `position={"x":1,"y":1}` alinha ao canto inferior direito; cada coordenada
  varia de 0 a 1 no espaço livre do quadro. `0,0` é o canto superior esquerdo.
- `scale` varia de **0,1 a 1** e define uma caixa proporcional ao quadro:
  `0.18` usa até 18% da largura/altura, mantendo a proporção da mídia.
- `duration` tem mínimo de 0,1 s; para vídeo, não excede a fonte. Imagens podem
  permanecer por uma duração diferente dos 5 s iniciais da biblioteca.
- `fade_in_ms` e `fade_out_ms`: inteiros de **0 a 60.000**, padrão **0**.
  A soma não pode exceder a duração. Usam os fades nativos de vídeo/alpha e áudio.
- `volume`: **0 a 2**, padrão **0**; no vídeo, também configura seu áudio
  vinculado. Imagens não possuem áudio.

Exemplo de lote, usando IDs recebidos anteriormente:

```json
{
  "base_revision": 3,
  "label": "IA: sequência e mascote",
  "commands": [
    {"tool":"add_clips_sequence","arguments":{"media_ids":["media_1","media_2"],"track":"track_default_video","at":0}},
    {"tool":"add_image_overlay","arguments":{"media_id":"media_mascote","at":2,"duration":3,"position":{"x":1,"y":1},"scale":0.18,"fade_in_ms":200,"fade_out_ms":200}}
  ]
}
```

Esse objeto é passado a `preview_plan`; revise o resultado e use seu `plan_id`
com a mesma revisão em `apply_plan`. Com aprovação desativada, as tools diretas
e `apply_commands` podem publicar o lote; `preview_plan` continua sem editar.

Medição atual, por `dart tool/mcp_catalog_metrics.dart`: **39 tools,
29.102 bytes UTF-8** no envelope JSON-RPC compacto; maior schema **1.807 bytes**.
O script e o CI rejeitam catálogo **≥30.000** ou schema **≥4.000 bytes**.

## Cortes: presets e proteção

Os presets de `remove_silences` são `mode="suave"|"normal"|"agressivo"`:

| Modo | `threshold_db` | `minimum` (s da fonte) | `padding` (s por borda) |
| --- | --- | --- | --- |
| suave | -40 | 0,7 | 0,14 |
| normal (padrão; detecção anterior) | -35 | 0,5 | 0,08 |
| agressivo | -30 | 0,3 | 0,04 |

Valores explícitos substituem o preset. Um `job_id` reutilizado precisa ter o
mesmo limiar e duração mínima; não reutilize a análise de outro modo.
`min_keep_ms=250` restaura o intervalo até o vizinho mais próximo para fundir
um trecho mantido curto, preservando fala; isso pode reduzir os segundos removidos.
Empates preferem o vizinho anterior. `0` desativa. Também vale para
`cut_by_transcript`, onde a fusão pode manter conteúdo entre falas escolhidas.

`join_fade_ms=8` aplica micro-fades apenas no áudio das novas emendas, usando os
campos de fade existentes; `0` desativa. Fades externos maiores são preservados.
`protect_words` fica ativo por padrão quando há transcrição; `word_margin=0.05`
protege cada palavra na fonte, antes de mapear velocidade/reverso. Sem tempos
por palavra, `remove_silences` protege frases inteiras conservadoramente;
`cut_by_transcript` mantém seus limites de frase e informa a falta de precisão.
Sem transcrição, o plano avisa que a proteção não foi aplicada e mantém o padding.

## Métricas do plano

Planos das macros de corte incluem `cut_summary`: `cut_count` (intervalos de
remoção efetivos, incluindo bordas), `internal_join_count`, `seconds_removed`,
`duration_before`, `duration_after`, `shortest_keep_seconds`,
`longest_keep_seconds`, `retained_segment_count`, `first_cuts` (até 10 intervalos
com tempos antigos, novo ponto e timestamps `HH:MM:SS.mmm`),
`word_protection_active`, `join_fade_ms`, `join_fade_active` e
`faded_audio_join_count`. Todos os segundos são da timeline; o padding e a margem
de palavras são da fonte. `time_map` contém os intervalos completos. A revisão
local também exibe métricas e avisos. Planos sem cortes retornam contagens zero.

## Ouvir antes de aprovar

Depois de `preview_plan`, chame `export_cut_check` com `plan_id`,
`base_revision` e um nome `.wav` (áudio) ou `.mp4` (vídeo/áudio). Consulte
`get_job`/`cancel_job`. A composição usa o snapshot simulado, incluindo fades,
mixagem e camadas, sem aplicar/aprovar o plano ou alterar revisão/histórico.
Captura ±0,5 s de cada um dos dez primeiros pontos (bordas são limitadas à
timeline). Janelas sobrepostas são unidas para não repetir conteúdo; a saída
tem até cerca de 10 s. `result.windows` informa os intervalos da timeline simulada.
Não adiciona fades nas junções entre amostras. A autorização revalida mídias e
pasta escolhida; caminhos, sobrescrita e planos antigos/expirados são rejeitados.
É somente leitura do projeto (`readOnlyHint=true`), porém grava esse arquivo;
`idempotentHint=false`. Somente o usuário pode avaliar o resultado de ouvido.

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
      {"tool": "set_volume", "arguments": {"clip_id": "audio_1", "volume": 0.7}},
      {"tool": "split_clip", "arguments": {"clip_id": "video_1", "at": 4.5}}
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
planejam sem editar, mesmo com aprovação desligada. `remove_silences` sem
`job_id` inicia primeiro a análise assíncrona e devolve `analysis_pending`.
`undo`/`redo` também passam pela aprovação quando chamados pela IA.

O painel mostra chamadas, erros, planos e jobs. **Desfazer** aparece para a última
transação da IA ainda no topo do histórico. Edições posteriores exigem navegar
no histórico com Ctrl+Z. A aprovação e o desfazer humanos entram na auditoria.

## Tools e exemplos

### Decisão de compatibilidade: lotes e planos

O fluxo recomendado é `preview_plan → apply_plan`: primeiro se inspeciona o
snapshot e depois se aplica exatamente o resultado, com a aprovação local
existente. `apply_commands` permanece como atalho de compatibilidade: com
aprovação ligada cria um plano; desligada executa o lote atômico imediatamente.
Há sobreposição na entrada dos comandos, mas a interação tem efeitos diferentes.
Remover ou transformar esse atalho em uma aplicação automática de planos mudaria
o comportamento de clientes existentes e a política de aprovação. Não faremos
essa mudança nesta versão. Uma futura API pode concentrar a documentação no
fluxo de planos e manter `apply_commands` como adaptador, sem retirar seu nome.

Já foram unificados o formato de entrada e os validadores: ambos aceitam
`commands: [{"tool": "add_marker", "arguments": {"at": 1, "name": "Fala"}}]`.
`tool` é o nome de uma ferramenta de edição anunciada, excluindo `undo`/`redo`.
O alias legado `command` continua aceito, inclusive para os lotes antigos com
`remap_timeline`; não combine `tool` e `command` no mesmo item. A resposta dos
planos mantém `command` para não quebrar leitores existentes.

`arguments` é um objeto aberto apenas no envelope compacto. O servidor valida
cada item com o mesmo schema e os mesmos validadores das edições individuais;
campos desconhecidos, tipos, limites, IDs, bloqueios e revisões seguem rejeitados.
Erros preservam `code`, `message` e os detalhes anteriores e acrescentam
`details.expected_schema` e `details.example` (item mínimo), além de
`command_index` quando disponível. IDs/textos do exemplo são placeholders: use
os IDs reais de `get_project`. Falhas não publicam parte do lote nem criam undo.
O alias `preview_plan` com `macro="remove_silences"` também permanece aceito,
validando os argumentos pelo schema da macro. Schemas repetidos são anunciados
por `$defs`/`$ref` locais ao respectivo `inputSchema`; não há referência externa.
Nenhuma dessas alterações acrescenta campos ou muda o formato de projeto v14.

Os exemplos abaixo são objetos `arguments` para `tools/call`. Substitua os IDs e
a revisão de exemplo. O catálogo exato de campos, limites e enums fica em
`tools/list`; campos desconhecidos são rejeitados.

| Tool | Comportamento | Exemplo de argumentos |
| --- | --- | --- |
| `get_project` | Resumo paginado, revisão, pistas, clipes, marcadores, transições e resolução. | `{"limit":20}`; próxima: `{"cursor":"7:20","limit":20}` |
| `remove_silences` | Analisa ou cria prévia de remoção com remapeamento; padrão todas as camadas e falha em bloqueios. | `{"clip_id":"video_1","job_id":"job_1","padding":0.12,"scope":"all_tracks","locked_tracks":"fail","base_revision":7}` |
| `cut_by_transcript` | Prévia mantendo cues escolhidos e remapeando todas as camadas; falha em bloqueios. | `{"clip_id":"video_1","keep_cue_indices":[0,2,3],"base_revision":7}` |
| `auto_captions` | Preview de legendas para o clipe usando transcrição já concluída. | `{"clip_id":"video_1","base_revision":7}` |
| `reframe_9x16` | Preview de crop central estático e saída 1080×1920; resolução entra no mesmo undo. | `{"clip_id":"video_1","base_revision":7}` |
| `preview_plan` | Prévia de lote ou da macro remove_silences, sem editar. | `{"macro":"remove_silences","arguments":{"clip_id":"video_1","job_id":"job_1","padding":0.12},"base_revision":7}` |
| `apply_plan` | Aplica snapshot aprovado na mesma revisão, em uma transação. | `{"plan_id":"plan_1","base_revision":7}` |
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
| `apply_commands` | Lote atômico; em modo de aprovação retorna plano. Não mistura undo/redo. | `{"base_revision":7,"commands":[{"tool":"add_marker","arguments":{"at":1,"name":"Início"}}]}` |
| `get_clip` | Tempos, grupo, pista, estilo, efeitos e keyframes. | `{"clip_id":"video_1"}` |
| `get_transcript` | Sem mídia: legendas da timeline. Com mídia: transcrição concluída na fonte. | `{"media_id":"media_1","offset":0,"limit":50}` |
| `list_media` | Metadados das mídias importadas, sem caminhos. | `{"offset":0,"limit":50}` |
| `get_loudness` | LUFS integrado, LRA e true peak da mídia fonte com ebur128. | `{"media_id":"media_1"}` |
| `get_frames` | Até 8 PNGs de até 320×180. Tempos de fonte com `media_id`, de timeline sem ele. | `{"media_id":"media_1","times":[0,2.5,5]}` |
| `detect_silence` | Job de silêncio; intervalos em segundos da fonte. | `{"media_id":"media_1","threshold_db":-35,"minimum":0.5}` |
| `detect_scenes` | Job de mudanças de cena na fonte. | `{"media_id":"media_1","threshold":0.3}` |
| `transcribe` | Job Whisper local; disponibiliza cues para get_transcript/macros. | `{"media_id":"media_1","language":"pt"}` |
| `get_job` | Status, progresso, resultado ou erro. | `{"job_id":"job_1"}` |
| `cancel_job` | Cancela análise/exportação; resultado cancelado não é publicado. | `{"job_id":"job_1"}` |
| `export_cut_check` | Job de amostra dos dez primeiros cortes do plano, sem editar. Pasta de export escolhida; não sobrescreve. | `{"plan_id":"plan_1","filename":"ouvir-cortes.wav","base_revision":7}` |
| `export` | Job de exportação do snapshot/revisão, com configurações atuais do app. | `{"filename":"resultado.mp4","base_revision":7}` |

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

## Remoção de silêncios por remapeamento

`get_project` abre a descoberta MCP, seguido das quatro macros, `preview_plan`
e `apply_plan`. Para remover silêncios, escolha o vídeo/áudio principal e leia a
revisão atual. Limiar e duração mínima são parâmetros da análise da fonte:

```json
{"name":"preview_plan","arguments":{"macro":"remove_silences","arguments":{"clip_id":"video_1","threshold_db":-35,"minimum":0.5,"padding":0.12,"scope":"all_tracks","locked_tracks":"fail"},"base_revision":7}}
```

Sem `job_id`, a resposta contém `analysis_pending: true` e o job iniciado.
Aguarde `get_job` completar e repita com o mesmo objeto `arguments`, acrescentando
o `job_id`. Um job reutilizado precisa pertencer à mesma mídia, projeto e revisão.
Se informar `threshold_db` ou `minimum`, os valores precisam coincidir com os do
job. `padding` preserva segundos da fonte nas duas bordas de cada silêncio.

A prévia une os intervalos removidos, calcula os trechos mantidos e retorna
`time_map`, `removed_duration`, escopo, camadas afetadas/ignoradas/desbloqueadas e
antes/depois. A função é contínua e monotônica não decrescente:
`F(t) = t − Σ clamp(t − início, 0, fim − início)`. Dentro de um silêncio removido,
o tempo fica constante. Os cálculos usam microssegundos inteiros.

| Tempo antigo, com remoções [2,4] e [7,8] | Tempo novo |
| --- | --- |
| 1 s | 1 s |
| 3 s | 2 s |
| 6 s | 4 s |
| 9 s | 6 s |
| Duração 10 s | 7 s |

Em `all_tracks`, cada vídeo/áudio é cortado nos limites dos trechos mantidos,
preservando fonte, velocidade, reverso e os grupos A/V. Textos, legendas e
overlays estáticos totalmente removidos desaparecem; os que cruzam cortes são
aparados, e os que atravessam vários cortes permanecem um único clipe encurtado.
Os keyframes mantêm valores interpolados nos limites e são renormalizados;
descontinuidades de curvas lineares v14 usam um passo de 1 µs na junção.
Marcadores dentro de silêncios vão à junção do corte. Transições são aparadas,
encurtadas ou removidas conforme o mesmo mapa.

`scope="main_track_only"` inclui a camada principal e seus companheiros
vinculados. As demais preservam os tempos originais, e a prévia avisa sobre a
possível perda de sincronismo e a duração global.

`locked_tracks` aceita `fail` (padrão), `skip` ou `unlock`. O padrão lista todos
os bloqueios do escopo **antes de iniciar análise ou transformação**. `skip`
preserva também as camadas vinculadas às bloqueadas, impedindo editar metade
de um grupo; se isso excluir o principal, a operação falha. `unlock` inclui o
desbloqueio na mesma transação, restaurado pelo undo. Com camadas ignoradas, a
duração global pode permanecer maior. No modo padrão, a duração final é a
original menos a soma dos silêncios efetivamente removidos.

O comando serializável `remap_timeline` aceita intervalos absolutos da timeline
e os mesmos parâmetros de escopo/bloqueio dentro de `commands`. Ele permite
combinar a remoção com `set_caption_style` no mesmo `preview_plan`. Não é uma
tool separada. Aplique o snapshot aprovado com `apply_plan`; um Ctrl+Z restaura
todo o projeto, incluindo bloqueios, keyframes, marcadores e estilos.

`placement_conflict.details` inclui `cause`, `clip_ids`, `track_ids`,
`group_ids`, `interval.start/end` em segundos e `suggestion`. Causas possíveis:
`overlap`, `incompatible_track`, `locked_track`, `locked_clip`, `linked_group`.
O modelo v14 atual guarda bloqueios por camada; não foi criado um campo de
bloqueio individual de clipe. Esses detalhes existem apenas nas respostas.

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
  de 1 s gera erro útil, respeitando o mínimo aplicado pelo gerador de legendas.
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

Na validação inicial do servidor: análise limpa, **215 testes padrão aprovados / 13 opcionais
ignorados**; com o dart-define acima, **228 aprovados / zero ignorados**. Testes
anteriores foram preservados sem edição. O build Windows release foi copiado
para `aplicativo/`, com 66 arquivos conferidos por SHA-256, zero divergências.
Evidência do build: [validation/MCP_BUILD_RESULT.json](validation/MCP_BUILD_RESULT.json).

### Validação da correção de silêncios

A reprodução usou uma **cópia privada do projeto real**, com 132 clipes, cinco
camadas e os 45 silêncios capturados no teste anterior. O ripple antigo criou
uma sobreposição entre `clip_124_txt` e `clip_123_txt`, na camada
`track_video_manual_2`, de 278,300522 s a 278,58 s. Registro estruturado:
[REMOVE_SILENCES_DIAGNOSIS.json](validation/REMOVE_SILENCES_DIAGNOSIS.json).

O novo plano removeu 24,406688 s com padding 0,12 s, passando de 293,547 s para
269,140312 s. Foram executados `preview_plan → apply_plan → undo` por HTTP MCP;
o JSON completo voltou exatamente ao original. FFmpeg exportou cinco segundos
da mídia real remapeada e FFprobe mediu **5,000 s**, a 30 fps. O arquivo privado
não foi versionado, e o arquivo original foi preservado:
[REMOVE_SILENCES_REAL_RESULT.json](validation/REMOVE_SILENCES_REAL_RESULT.json).

A fixture pública tem a mesma distribuição de 132 clipes, com conteúdo sintético.
Testes cobrem vídeo isolado, cruzamentos de legendas, bloqueios fail/skip/unlock,
vínculos A/V, keyframes, marcadores, transições, speed/reverso, padding e
sincronismo de palavras/legendas dentro de um frame. Um teste nativo independente
analisou uma fonte A/V sintética de 6 s e exportou **3,000 s**, para duração
calculada de 2,999916 s, dentro de um frame a 20 fps:
[REMOVE_SILENCES_FFMPEG_RESULT.json](validation/REMOVE_SILENCES_FFMPEG_RESULT.json).

MCP Inspector 2.11.0 passou novamente em `tools/list --strict` e `get_project`,
sem avisos; SDK 1.32.1 passou no smoke independente. A ordem histórica das seis
primeiras tools, anterior à compactação, está registrada em
[REMOVE_SILENCES_INSPECTOR_RESULT.json](validation/REMOVE_SILENCES_INSPECTOR_RESULT.json).
O Inspector verifica catálogo/leitura; os contratos de remoção e undo foram
executados separadamente pelo cliente MCP de teste, incluindo a cópia real.

O build Windows foi recompilado em 46,2 s e copiado para `aplicativo/`: 66
arquivos conferidos por SHA-256, sem divergências. A janela nativa abriu outra
cópia privada dos 132 clipes. O SDK conectado ao servidor dentro do app fez uma
nova análise (45 silêncios), e `preview_plan` retornou o mesmo resultado de
269,140312 s. O plano foi revisado e aprovado em **Aprovar e aplicar**; a timeline
passou a 221 clipes, incluindo 46 trechos de vídeo e 46 de áudio vinculados.
Um Ctrl+Z válido pela interface restaurou os 132 clipes e os 293,547 s. Depois
de salvar, o arquivo ficou idêntico byte a byte à cópia inicial, com SHA-256
`838673b2a964c5ccc1c3ca870bf9b131bd3a20ed4171121d128d18ae43e57596`.

Uma primeira tentativa de injeção de tecla estava sem scan codes e não acionou
o undo. O helper de automação foi corrigido; o código de atalhos do app não foi
alterado. Evidências sem token ou conteúdo privado:
[REMOVE_SILENCES_BUILD_RESULT.json](validation/REMOVE_SILENCES_BUILD_RESULT.json)
e [REMOVE_SILENCES_NATIVE_APP_RESULT.json](validation/REMOVE_SILENCES_NATIVE_APP_RESULT.json).

Para reproduzir a cópia privada, defina `MCP_REPRO_PROJECT`, `MCP_REPRO_ANALYSIS`,
`MCP_REPRO_OUTPUT` e `MCP_REPRO_EXPECT_SUCCESS=1`, em `source/`, e execute
`flutter test --no-pub tool/reproduce_silence_test.dart`. O arquivo de análise
contém `arguments` e o resultado capturado de `detect_silence`. Opcionalmente
`MCP_REPRO_EXPORT` escolhe um destino local para exportar cinco segundos.
Sem os arquivos privados, execute os testes públicos em
`test/remove_silences_regression_test.dart` e `test/remove_silences_ffmpeg_test.dart`.

Na verificação final desta correção: `flutter analyze --no-pub` sem problemas e
**252 testes aprovados / zero ignorados**, com
`--dart-define=TGI_RUN_FFMPEG_INTEGRATION_TESTS=true`. Os testes anteriores
permaneceram sem edição. Contagens e evidências:
[REMOVE_SILENCES_VALIDATION.json](validation/REMOVE_SILENCES_VALIDATION.json).

## Catálogo compacto — 22/10/2026

Medição real do corpo JSON-RPC de `tools/list`, salvo diretamente de HTTP:
**75.308 → 24.358 bytes UTF-8**, redução de **67.66%**, mantendo as
**34 tools**. O `inputSchema` de `preview_plan` caiu de **32.519 para 1.080 bytes**;
`apply_commands`, de **13.742 para 877 bytes**. As descrições têm no máximo
**166 bytes**. Não houve alteração no formato v14 nem no arquivo ProjectIOService.

A ordem atual começa por `get_project`, quatro macros, `preview_plan`,
`apply_plan` e `split_clip`. Depois vêm as demais edições, leituras auxiliares,
jobs e exports. Os nomes e aliases antigos permanecem disponíveis.

Os valores abaixo são bytes UTF-8: tool completa com nome/descrição/schema/
annotations, e apenas `inputSchema`, serializados por `jsonEncode` compacto.
A soma das tools mais o envelope/pontuação corresponde ao corpo HTTP.
As duas capturas usam IDs de requisição com um dígito. Descrições individuais e
valores completos estão em [MCP_COMPACT_CATALOG_SIZE_RESULT.json](validation/MCP_COMPACT_CATALOG_SIZE_RESULT.json).

| Tool | Tool antes | Tool depois | Schema antes | Schema depois |
| --- | ---: | ---: | ---: | ---: |
| `get_project` | 483 | 458 | 187 | 187 |
| `remove_silences` | 2861 | 2135 | 2478 | 1807 |
| `cut_by_transcript` | 1572 | 1151 | 1216 | 867 |
| `auto_captions` | 780 | 519 | 427 | 251 |
| `reframe_9x16` | 770 | 526 | 427 | 251 |
| `preview_plan` | 32857 | 1400 | 32519 | 1080 |
| `apply_plan` | 632 | 476 | 327 | 207 |
| `split_clip` | 959 | 642 | 568 | 357 |
| `trim_clip` | 1046 | 729 | 678 | 467 |
| `delete_clip` | 820 | 538 | 455 | 279 |
| `move_clip` | 1163 | 846 | 768 | 557 |
| `set_clip_speed` | 868 | 586 | 490 | 314 |
| `add_text` | 1365 | 1110 | 1019 | 870 |
| `set_caption_style` | 1254 | 978 | 911 | 741 |
| `apply_effect` | 2174 | 1681 | 1812 | 1425 |
| `set_keyframe` | 1251 | 969 | 871 | 695 |
| `add_transition` | 1388 | 1127 | 1021 | 866 |
| `set_volume` | 833 | 551 | 491 | 315 |
| `add_marker` | 787 | 526 | 462 | 307 |
| `undo` | 583 | 357 | 257 | 137 |
| `redo` | 552 | 326 | 257 | 137 |
| `apply_commands` | 14046 | 1153 | 13742 | 877 |
| `get_clip` | 476 | 420 | 244 | 188 |
| `get_transcript` | 521 | 479 | 229 | 229 |
| `list_media` | 410 | 410 | 168 | 168 |
| `get_loudness` | 421 | 374 | 146 | 146 |
| `get_frames` | 654 | 552 | 333 | 298 |
| `detect_silence` | 529 | 529 | 266 | 266 |
| `detect_scenes` | 448 | 448 | 205 | 205 |
| `transcribe` | 512 | 444 | 207 | 207 |
| `get_job` | 397 | 397 | 142 | 142 |
| `cancel_job` | 378 | 378 | 142 | 142 |
| `export_cut_check` | 770 | 585 | 399 | 279 |
| `export` | 669 | 479 | 329 | 209 |

`test/mcp_catalog_budget_test.dart` falha em **30.000 bytes ou mais** na resposta
JSON-RPC, **4.000 ou mais por schema** e em descrições com **300 bytes ou mais**.
Os números desta seção são da validação anterior de 34 tools. O catálogo atual
inclui as cinco tools de mídia descritas no início; os schemas de
`preview_plan`/`apply_commands` continuam **<3.000**. Não há limite sobre uma versão
pretty-printed do catálogo; a medição é da resposta HTTP compacta real.

### Clientes externos e arquivo restaurado

SDK oficial **1.32.1** e MCP Inspector **2.11.0** executados contra um host Flutter
isolado que usa servidor, roteador, controlador e persistência de produção, com
mídia A/V criada por FFmpeg. As 34 entradas também compilaram como JSON Schema
2020-12, incluindo os refs locais. Inspector `tools/list --strict` e
`get_project` terminaram com exit 0 e sem avisos:
[MCP_COMPACT_CLIENT_RESULT.json](validation/MCP_COMPACT_CLIENT_RESULT.json).

O SDK executou `preview_plan → apply_plan → undo` com `tool/arguments`, conferiu
o volume alterado e a revisão preservada pelo preview, testou os erros com schema
e exemplo (inclusive `arguments` de tipo inválido), e executou o alias legado de
`apply_commands` seguido de undo. O host salvou arquivos v14 antes e depois:
**5.896 bytes em ambos**, comparação byte a byte aprovada e SHA-256 igual.
A aprovação é desativada apenas nesse host de teste; as regras do app e o projeto
aberto do usuário são preservados:
[MCP_COMPACT_ROUNDTRIP_RESULT.json](validation/MCP_COMPACT_ROUNDTRIP_RESULT.json).

Referências dos clientes: [SDK oficial](https://ts.sdk.modelcontextprotocol.io/client)
e [MCP Inspector](https://modelcontextprotocol.io/docs/tools/inspector).

Para reproduzir, instale as versões indicadas conforme a seção de validação,
prepare uma pasta nova ignorada em `.work/`, defina `MCP_VALIDATION_DIR` para ela
e inicie, em `source/` pelo caminho curto do projeto:

```powershell
flutter test --no-pub --reporter=expanded tool/mcp_inspector_host_test.dart
```

Após o host escrever `session.json`, execute na raiz, em outro terminal:

```powershell
node tool/mcp_catalog_smoke.mjs '<pasta de validação>' '.work/mcp-client/node_modules'
dart tool/mcp_catalog_sizes.dart '<captura HTTP anterior>' '<pasta de validação>/tools-list-after.json' '.work/catalog-sizes.json'
```

O script de medição lê as capturas brutas, confere que a captura posterior
coincide com o catálogo do código atual e calcula tamanhos por tool/schema.
O host compara os arquivos e grava `roundtrip.json`; o cliente grava
`report.json`, captura o catálogo sem despejá-lo no terminal e sinaliza a parada.
Credenciais temporárias e arquivos de mídia/projeto ficam apenas em `.work/`.
