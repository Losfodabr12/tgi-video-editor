# Auditoria do pipeline de transcrição e legendas

Data: 22/10/2026, America/Sao_Paulo. Código auditado: `3c376a80d5dc0fa4e26f652b6121c8f8e7033729`.
Escopo: inspeção do código, arquivos locais e medições isoladas; **nenhuma implementação, configuração, mídia ou timeline foi alterada nesta auditoria**. Esta seção descreve o estado anterior à implementação; as etapas executadas estão registradas ao final. Os programas de medição e suas saídas ficam fora dele.

## 1. Engine, versão e modelo distribuído

| Item | Evidência local |
| --- | --- |
| Engine | **whisper.cpp**, processo CLI local, não serviço de nuvem nem pacote Python Whisper |
| Executável instalado | `aplicativo/whisper/bin/whisper-cli.exe` |
| Versão executada | **1.9.1**, obtida com `--version` |
| Modelo no aplicativo local | **Base multilíngue**, `aplicativo/whisper/models/ggml-base.bin`; não é `base.en` |
| Tamanho real do Base | **147.951.465 bytes = 147,951 MB = 141,098 MiB** |
| SHA-256 do Base | `60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe` |
| SHA-256 do CLI instalado | `58245314fb73b30fbd0cf0542c5c172e23f02b6eb7cad7b51e792439cf5e1755` |
| Segundo modelo usado só no benchmark | **Small multilíngue**, arquivo local já existente no projeto TGI original, acessado somente para leitura |
| Tamanho real do Small | **487.601.967 bytes = 487,602 MB = 465,013 MiB** |
| SHA-256 do Small | `1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b` |

MB = 1.000.000 bytes; MiB = 1.048.576 bytes. O catálogo da interface usa estimativas; os números acima são tamanhos dos arquivos. O hash do Small local coincide com o publicado pelo [distribuidor do modelo](https://huggingface.co/ggerganov/whisper.cpp/blob/main/ggml-small.bin).

**Há divergência entre o runtime instalado e a receita de distribuição.** O [setup](../tool/setup_tools.ps1) fixa `b5454/whisper-bin-x64.zip`, CPU x64, e Base. Baixei esse ZIP apenas para inspeção na pasta temporária: SHA-256 `6ba69e3482d7826214f90a6a9c84ca07782aec1e1d0c6a7c30c994fd5d816ccb`; seu CLI informa **1.9.5**, SHA-256 `331dba46d6427105d2b802cdbc7eae916ea1c5abf9b0d3b5cfe460d8db8e4366`. A [release b5454](https://github.com/ggml-org/whisper.cpp/releases/tag/b5454) também identifica esse asset e hash.

O setup só instala o runtime quando o executável não existe. Assim, uma instalação local antiga pode continuar em 1.9.1, enquanto um ambiente limpo obtém 1.9.5. **As medições deste documento são do 1.9.1 instalado**, sem substituí-lo. Não extrapolam para 1.9.5 ou para um ZIP publicado que não tenha sido executado.

O build local também tem metadados antigos: `BUILD_INFO.json` declara versão 0.3.0/build 3 e um hash de app.so diferente do arquivo atual; o código declara 0.4.0+4. Isso impede usar aquele manifesto como prova de correspondência integral entre fonte e aplicativo. O CLI de `source/tools/whisper/bin` tem o mesmo hash do CLI instalado.

## 2. Pipeline e parâmetros atuais

O [serviço local](../source/lib/services/auto_caption_service.dart#L154) resolve CLI/modelo, extrai o áudio, processa blocos sequenciais de até **300 s**, lê JSON completo e segmenta o texto. Os blocos de áudio não têm sobreposição configurada. Há fila serial no serviço e timeout padrão de 30 minutos por processo.

A [extração FFmpeg](../source/lib/services/ffmpeg_service.dart#L434) usa a primeira faixa de áudio, mono, 16 kHz e PCM signed 16-bit. Não encontrei nessa etapa normalização de loudness, redução de ruído ou filtro de voz.

Argumentos efetivamente montados pelo serviço:

~~~text
whisper-cli.exe -m MODELO -f CHUNK.wav -ojf -of PREFIXO -pp
                 [-l IDIOMA] [-t THREADS]
~~~

| Parâmetro | Comportamento do código / padrão do CLI instalado |
| --- | --- |
| Modelo | Nome explícito da UI; depois `TGI_WHISPER_MODEL`; senão `base`. O caminho explícito `TGI_WHISPER_MODEL_PATH` pode substituir o arquivo escolhido |
| Idioma na UI | Campo editável, inicialmente **pt**; não está bloqueado em português |
| Idioma no MCP | `transcribe.language` é opcional. Se omitido/vazio, não se passa `-l` e o CLI usa **en**, não detecção automática |
| Detecção automática | Só ocorre solicitando explicitamente `auto`. Campo vazio não equivale a `auto` |
| Beam size | Não definido pelo app; **5**, padrão exibido pelo CLI |
| Best of | Não definido pelo app; **5** |
| Temperatura | Não definida pelo app; inicial **0,0**, incremento de fallback **0,2**; fallback não é desativado |
| Threads | `TGI_WHISPER_THREADS` se válido. Sem override: Base/Small herdam o CLI, **4 nesta máquina**; Medium tem tratamento especial de **2** |
| Processors | **1**, padrão do CLI |
| VAD neural | **Desligado**: não passa `--vad` nem modelo VAD |
| Prompt inicial | **Vazio**: não passa `--prompt` |
| Tokens/tempos | `-ojf` habilita JSON completo e timestamps por token; DTW não configurado |
| GPU solicitada | O CLI tem `use_gpu=true` por padrão, pois o app não passa `-ng` |
| GPU efetivamente usada | **Nenhuma**. Log: `loaded CPU backend ... ggml-cpu-haswell.dll` e `no GPU found` |
| Backend efetivo | **CPU**, AVX2/FMA; sem CUDA/OpenVINO/Core ML nos logs da medição |

A diferença entre pedir GPU e efetivamente usar GPU importa: a presença de uma RTX não torna este pacote acelerado. A pasta Whisper distribuída localmente tem bibliotecas de CPU, sem `ggml-cuda.dll` ou backend Vulkan. As DLLs gráficas do editor não demonstram aceleração do Whisper.

A máquina tem **Ryzen 5 5500, 6 cores/12 threads**, 17.043.693.568 bytes de RAM física visível e **RTX 3050, 6.144 MiB de VRAM**, driver NVIDIA **621.01**. O valor de VRAM foi obtido com `nvidia-smi`, não com o campo WMI de 32 bits.

Os padrões foram conferidos em `--help`, nos logs reais e no [CLI da versão 1.9.1](https://raw.githubusercontent.com/ggml-org/whisper.cpp/v1.9.1/examples/cli/cli.cpp). Não havia variáveis `TGI_WHISPER*` no ambiente do benchmark. Não capturei novamente um processo de transcrição dentro do aplicativo nesta rodada.

## 3. Tempos por palavra: existem, mas não sobrevivem até a legenda

### Origem e armazenamento

O JSON `-ojf` contém segmentos, tokens, offsets em milissegundos e probabilidades por token. No upstream, `output_jsn_full` ativa `token_timestamps`; isso não significa que DTW/forced alignment esteja ativo.

O [parser](../source/lib/services/auto_caption_service.dart#L679):

- Cria `CaptionCue` e `CaptionWord(start, end, text)`.
- Aceita `words` quando presentes; caso contrário junta subpalavras de `tokens`, usando espaços para encontrar palavras.
- Usa os tempos dos tokens e adiciona o offset do bloco. Não divide uniformemente a duração de uma frase para inventar tempos de palavras.
- Descarta probabilidades/IDs dos tokens no objeto `CaptionWord`. Os tempos são estimativas do reconhecedor, não alinhamento validado contra referência humana.

Os JSONs temporários são apagados ao terminar o serviço. No [MCP](../source/lib/mcp/editor_read_service.dart#L153), os cues ficam no mapa **em memória** `_transcripts`, chaveado por projeto, mídia, caminho e duração. Não há persistência dessa transcrição no projeto nem chave por modelo/idioma/hash do conteúdo. Uma nova transcrição da mesma mídia substitui a entrada anterior.

### Exposição MCP

| Tool | O que expõe |
| --- | --- |
| `transcribe` | Entrada: `media_id`, `language` opcional. Retorna `job_id`; ao concluir, o job informa mídia, quantidade de cues e `scope=source`. Não devolve as palavras diretamente |
| `get_transcript(media_id=...)` | Retorna os cues da fonte e `words: [{start,end,text}]` quando disponíveis; segundos absolutos da fonte |
| `get_transcript` sem mídia | Lê legendas da timeline; os cues reconstruídos dos clipes não mantêm `words` |
| Paginação | `offset` e `limit`, entre 1 e 100; não há parâmetro MCP para selecionar modelo, threads, prompt, VAD ou backend |

A captura anterior desta mesma sessão mostrou **129 cues com palavras** em `get_transcript`. Comparei todos os objetos dessa captura com os cues do novo benchmark Base: **igualdade exata**, incluindo textos e timestamps. Durante esta auditoria o endpoint MCP deixou de responder; não executei outro `transcribe` no app para evitar alterar seu cache.

### Perda confirmada de metadados

As seguintes etapas constroem um novo `CaptionCue` apenas com início/fim/texto:

- [Alinhamento por waveform e resolução de overlaps](../source/lib/features/editor/application/editor_caption_timing.dart#L21).
- [Conversão fonte → timeline](../source/lib/features/editor/application/editor_controller.dart#L5300).
- [Macro MCP auto_captions](../source/lib/mcp/editor_plans.dart#L373).

O modelo de clipe não armazena a lista de palavras da transcrição. Exportar SRT/VTT também preserva apenas os tempos dos blocos.

Um probe controlado com uma palavra mediu **1 palavra antes → 0 após o alinhamento por waveform**, e **1 → 0 após resolveCaptionCueOverlaps**. Nos dados reais do Base, **805 palavras → 0** após essa resolução. Portanto, “o reconhecedor gera tempos por palavra” e “a legenda suporta palavra destacada” são capacidades distintas; a segunda ainda não está implementada.

## 4. Como são criados os clipes de legenda e como editar

### Segmentação textual

A regra de [segmentCaptionCues](../source/lib/services/auto_caption_service.dart#L517) é:

1. Normalizar espaços.
2. Agrupar palavras até **44 caracteres por cue** por padrão; serviço limita a configuração a 24–60, UI oferece 32–52.
3. Para texto longo, dividir a duração do segmento **proporcionalmente à quantidade de palavras de cada bloco**. Não usa os tempos individuais das palavras para determinar cada novo limite.
4. Tentar linhas de `ceil(limite/2)` caracteres, 22 no padrão. Se produz mais de duas linhas, juntar todas as posteriores na segunda linha.
5. Associar a cada cue as palavras cujo intervalo cruza o intervalo calculado; uma palavra que cruza uma borda pode aparecer em dois cues.

Consequências medidas: o máximo de duas linhas é respeitado nesta amostra, mas 22 caracteres **por linha** não é limite rígido. O número de caracteres também não mede largura real em pixels; uma palavra longa pode exceder o alvo.

| Medida após o parser e a segmentação | Base | Small |
| --- | ---: | ---: |
| Segmentos do CLI | 24 | 51 |
| Cues do serviço | 129 | 149 |
| Palavras com tempo, antes de segmentar | 805 | 807 |
| Ocorrências de palavras nos cues segmentados | 896 | 892 |
| Ocorrências duplicadas por cruzar bordas | 91 | 85 |
| Cues com duração inferior a 1 s | 12 | 38 |
| Máximo de caracteres por cue nesta amostra | 44 | 44 |
| Máximo de linhas | 2 | 2 |
| Maior linha / linhas acima de 22 caracteres | 30 / 29 | 33 / 34 |

Duplicação aqui é de **metadados** entre cues vizinhos, não prova de palavras repetidas na fala.

Exemplo Base: o primeiro cue termina em **2,577778 s** e contém “aqui a”, mas “aqui” tem tempo **2,64–3,00 s** e “a” **3,00–3,05 s**. Esses tempos acabam no cue seguinte, cujo texto já começa com “Guia de Arsenal”. Há desacordo mensurável entre o texto exibido e o agrupamento temporal das palavras.

### Caminhos UI e MCP são diferentes

A UI aplica uma heurística de amplitude da waveform após a transcrição: janela de busca de ±900 ms, limiar máximo entre 0,08 e 24% do pico local, lead de 80 ms e tail de 260 ms; depois resolve overlaps com gap de 80 ms. Isso **não é VAD neural**. Ao criar texto, a UI estende a duração para no mínimo **1 s**.

A macro MCP resolve overlaps e junta um cue curto ao **seguinte** até chegar a 1 s. Se o último continuar curto, lança `caption_too_short` e não entrega o plano. No Base, o último cue bruto é `292,44–293,00`, duração **0,56 s**; após a resolução fica `292,52–293,12`, **0,60 s**. O erro observado antes nesta sessão corresponde a esse caminho. Esse fluxo não funde o último cue com o anterior. Não executei uma mutação para “testar a correção”.

### Edição de texto

**Existe edição no editor.** A aba Legendas mostra um [TextField por cue](../source/lib/features/editor/presentation/widgets/captions_panel.dart#L283), com commit ao pressionar Enter/concluir ou perder o foco. O controlador usa `set_caption_style` com `text` e registra histórico para undo. O MCP também permite editar texto por `set_caption_style`.

Não existe vínculo de edição com uma sequência persistente de palavras/tempos. Atualmente alterar a frase não recalcula alinhamento por palavra. Não há karaoke por palavra implementado no widget de legenda ou no formato de clipe.

### Seleção e download de modelos já existentes no código

A UI já oferece **Base/Small**, com padrão Base e verificação de modelos instalados. Não é correto propor esse seletor como se ele não existisse.

Há [WhisperModelService](../source/lib/services/whisper_model_service.dart), com catálogo tiny/base/small/medium, download para arquivo temporário, progresso/cancelamento e SHA-256 **somente para Small**. Base é verificado por SHA-256 no setup do pacote, mas não tem hash obrigatório nesse catálogo de download.

A integração de Downloads herdada está desativada no modo standalone: [showPremiumDownloadsDialog retorna imediatamente](../source/lib/features/hub/presentation/premium_downloads_dialog.dart#L20), e `installModel` chama `requireOnlineIntegrations`, que rejeita esse modo. Portanto, selecionar Small ausente não resulta num download funcional nesse caminho. No standalone, `_hasPaidPlan` já retorna verdadeiro; o bloqueio aqui não é uma licença paga.

A URL do serviço usa `resolve/main`; “instalado” não exige hash verificado e existe até um teste de tamanho aproximado de 75% do catálogo. O resolver de transcrição e o instalador também têm caminhos/overrides distintos. Essas partes precisam ser unificadas.

## 5. Medição real de 5 minutos

### Protocolo

Execução em Windows 11, Ryzen 5 5500, CPU/4 threads. **Três processos novos por modelo**, sequenciais: Base 1–3, depois Small 1–3. Não limpei o cache do sistema; navegador e demais processos não foram isolados. Os testes Dart foram executados **depois** das seis medições.

Áudio: vídeo “EU REFIZ TODA A INTERFACE DO MEU JOGO NO ROBLOX!.mp4”, duração declarada **293,547 s**. A extração produziu **293,5466875 s** de PCM; acrescentei **6,4533125 s de silêncio ao final somente na cópia de benchmark**, formando exatamente **300,000 s**, 4.800.000 amostras, mono/16 kHz/16-bit. Não são cinco minutos de fala contínua. O vídeo original não foi alterado.

- SHA-256 da mídia: `03dd5e39914505716c00be5e9bb58bfc6854939f50114fbd80b6ceeb10cfa1f2`.
- SHA-256 do WAV de 300 s: `16533371c7cdb2117f672491366fd90b313c497217e472a5fa76bb1c3cf0690c`.
- Tamanho do WAV: 9.600.044 bytes.
- Janela das seis execuções: **04:59:34–05:04:56, UTC−03**, 22/10/2026.
- Small já estava disponível localmente; não instalei esse modelo no Frame Studio.

Comando medido, para cada modelo:

~~~powershell
& $cli -m $modelo -f $wav300 -ojf -of $saida -pp -l pt
~~~

O cronômetro mede **criação do processo + carregamento do modelo + inferência + escrita do JSON**. A extração e o parser são etapas separadas; estes números não são uma medição ponta a ponta da UI ou do job MCP.

A memória vem de `GetProcessMemoryInfo` do Windows, consultado a cada 20 ms:
**PeakWorkingSetSize** é o pico de páginas residentes do processo; **PeakPagefileUsage** é pico de commit, não quantidade de RAM física nem páginas efetivamente gravadas em disco. Editor, Python, FFmpeg e VRAM não são somados ao RSS do Whisper.

### Resultados

| Modelo / execução | Tempo real (s) | Pico residente (MiB) | Pico de commit (MiB) | RTF = tempo / 300 |
| --- | ---: | ---: | ---: | ---: |
| Base 1 | 30,2416 | 451,21 | 852,10 | 0,10081 |
| Base 2 | 32,7872 | 451,93 | 852,89 | 0,10929 |
| Base 3 | 30,2749 | 449,57 | 850,45 | 0,10092 |
| **Base: mediana** | **30,2749** | **451,21** | **852,10** | **0,10092** |
| Small 1 | 76,1936 | 921,07 | 1.322,42 | 0,25398 |
| Small 2 | 75,4980 | 922,01 | 1.323,79 | 0,25166 |
| Small 3 | 75,3977 | 920,25 | 1.321,32 | 0,25133 |
| **Small: mediana** | **75,4980** | **921,07** | **1.322,42** | **0,25166** |

Todos retornaram exit code 0. O texto foi idêntico entre as três repetições de cada modelo. Isso mede repetibilidade neste caso, não precisão.

A preparação FFmpeg da fonte levou **0,3406 s**, pico residente **19,74 MiB**, em uma execução. O padding foi feito separadamente e não entrou no cronômetro de inferência.

**Conclusão permitida pela medição:** Small foi mais demorado e consumiu mais memória nesta máquina, nesta amostra e com esses parâmetros. Não foi medido ganho geral de qualidade, GPU, VAD, prompt ou outra configuração.

### Amostra de problemas em português

As expressões abaixo são saídas literais das primeiras execuções. Os tempos referem-se aproximadamente à fonte. A tabela ilustra problemas lexicais/segmentação a revisar; não constitui corpus anotado nem classificação de frequência do português.

| Trecho | Base | Small | Padrão observado |
| --- | --- | --- | --- |
| 0–29 s | “rapazada” | “rapazada” na abertura | Grafia/forma coloquial ainda problemática |
| 23–29 s | “pura e a”, “entrigência artificial” | “pura e a”, “a inteligência artificial” | Sigla e deformação lexical |
| 45–81 s | “ocutar bandeiras” | “ocultar bandeiras” | Consoante omitida na saída Base |
| 45–81 s | “Guia Interior” | “guia anterior” | Substituição de palavra |
| 112–180 s | “mais 3” | “maestria” | Termo de jogo interpretado como números |
| 169–179 s | “belajeitada” | “bela ajeitada” | Junção indevida de palavras |
| 182–201 s | “visual bem mais cliente” | “visual bem mais clean” | Anglicismo substituído |
| Ao longo do vídeo | “Mario Shaw” / “Mari Chalk” | “marixol” / “marechal” | Nome próprio inconsistente entre trechos e modelos |

A grafia oficial de nomes próprios não foi confirmada com o autor. Não há transcrição humana de referência, nem WER/CER, nem avaliação auditiva cega nesta auditoria. Os exemplos podem orientar revisão e vocabulário, mas **não autorizam afirmar que Small tem qualidade superior em geral**. Há casos problemáticos em ambas as saídas.

## 6. Plano proposto, sem implementação

Cada etapa deve entregar evidência própria. Não atribuir ganho de qualidade a modelo maior, VAD, prompt ou GPU antes do ensaio correspondente.

| Etapa | Trabalho proposto | Critério de conclusão |
| --- | --- | --- |
| **0 — Baseline e proveniência** | Corrigir a geração do manifesto; registrar engine/versão/hash, modelo/hash, idioma, decoder, threads e backend efetivo por job. Validar binários existentes no setup. Criar corpus PT-BR consentido com fala limpa, gírias, gameplay/ruído, silêncios e nomes próprios, com referência revisada | Reprodução por hashes; protocolo de normalização WER/CER fixado; tempo, RSS e erros por categoria medidos antes das mudanças |
| **1 — Modelos e download sob demanda** | Aproveitar o seletor existente; unificar o resolver e o instalador. Base incluído; Small opcional, demais modelos só após validação. Catálogo com URL em revisão imutável, tamanho exato e SHA-256 obrigatório para **todos**. Download explícito independente do legado de planos, cancelamento/progresso, espaço livre e arquivo parcial fora da lista de instalados | Arquivo truncado/adulterado nunca é aceito; falha preserva o modelo anterior; modelo instalado funciona offline; UI e MCP selecionam o mesmo arquivo |
| **2 — Idioma e parâmetros explícitos** | Português `pt` como padrão persistido no projeto, mesma semântica na UI/MCP; Auto como opção explícita. Expor modelo e configurações suportadas no MCP. Passar e registrar beam/temperatura/threads explicitamente, começando pelos valores do baseline | Omissão de idioma não resulta em inglês; argumentos registrados correspondem à seleção; A/B altera uma variável por vez |
| **3 — Palavras e tempos persistentes** | Guardar transcrição canônica separada do layout: IDs, texto, tempos da fonte, origem, modelo/hash, idioma e confiança quando disponível. Persistir no projeto/sidecar versionado. Preservar e remapear os tempos em trim/speed/reverse/cortes, salvar/reabrir, UI e MCP. Invalidar cache quando conteúdo/modelo/idioma mudar | Round-trip não perde palavras; transformação de tempo é testada; correção textual marca alinhamento para revisão, sem fabricar precisão |
| **4 — Segmentação e clipes** | Criar cues pelos limites reais das palavras e pausas/pontuação, com alvo de leitura e largura em pixels. Unificar UI/MCP. Fundir também uma sobra curta final com o cue anterior quando adequado; redefinir a restrição de 1 s para legendas sem alongar às cegas | Caso “fui, tchau!” não aborta todo o job; sem duplicar IDs de palavra; sem texto antes/depois da fala por divisão proporcional; limites de linhas/largura verificados em 16:9 e 9:16 |
| **5 — VAD** | Experimentar Silero com runtime/modelo compatíveis, versão e SHA fixados; registrar limiar, padding, overlap e mapa fonte→fala. Preservar palavras próximas a bordas; distinguir VAD da heurística de amplitude atual | Medir falso corte de palavras, inserções em silêncio, tempo/RSS e WER/CER. Só habilitar por padrão após comparação com baseline no corpus |
| **6 — Vocabulário inicial** | Campo opcional por projeto para termos fornecidos pelo usuário; converter para `--prompt` com limite de tokens e registro. Considerar Roblox, Arsenal, slots, maestria e nomes do jogo somente com grafia confirmada | Medir erros dos termos e alucinações com/sem prompt; não substituir globalmente o texto nem tratar prompt como dicionário garantido |
| **7 — GPU** | Seleção Auto/CPU/CUDA e avaliação posterior de Vulkan. Runtimes/DLLs compatíveis, hashes e fallback CPU explícito. Para esta RTX 3050, testar CUDA antes de decidir distribuição | Log confirma backend efetivo; medir wall time, RSS, VRAM, falhas e diferenças de texto. Ter GPU não conta como teste de uso, e menor tempo não implica melhor qualidade |
| **8 — Palavra destacada** | Consumir os dados persistentes da etapa 3; cor/estilo por palavra no preview e exportação, sem criar um clipe por palavra. Projetar renderização equivalente em Flutter e FFmpeg, por exemplo ASS com tempos controlados. Preservar legenda estática como alternativa | Palavra correta destacada nos limites temporais; paridade preview/export; seek, velocidade, corte, reverse e edição textual cobertos; medir desvio temporal contra referência |

O upstream documenta [VAD e seus parâmetros](https://github.com/ggml-org/whisper.cpp/blob/master/README.md#voice-activity-detection-vad) e [backends GPU](https://github.com/ggml-org/whisper.cpp/blob/master/README.md#nvidia-gpu-support). São possibilidades técnicas para experimentos futuros; não resultados medidos neste editor. A implementação deve conferir a compatibilidade com a versão efetivamente distribuída, em vez de assumir a documentação de master.

Para avaliar qualidade, publicar WER/CER total **e por categoria**, contagem de erros de nomes próprios/siglas, inserções durante silêncio e erro temporal das palavras anotadas. Usar o mesmo áudio e referência, reportar tamanho do corpus e resultados por arquivo, e evitar escolher a configuração apenas pelos exemplos favoráveis desta amostra.

## 7. Evidências, limites e preservação do estado

Artefatos locais: `C:\Windows\Temp\frame-transcricao-audit-20261022\`.

- `benchmark.py`, `report.json`, seis `*.metrics.json`, seis JSONs completos do Whisper e logs stdout/stderr.
- `parser_probe.dart`, `extracted_parser.dart`, `parser-extraction-manifest.json`, `parser-report.json` e os cues Base/Small.
- `mcp-correlation.json` registra a igualdade da captura MCP anterior com o novo Base.
- ZIP b5454 e executável extraído somente nessa pasta temporária.

O probe Dart executou cópias **literais** das classes/funções de parsing, segmentação e timing do código auditado, sem alterar os originais ou instanciar o editor. A tentativa anterior pelo runner Flutter falhou por cache de native assets apontando para a unidade inexistente `V:\`. Não corrigi esse cache nem atribuí sucesso ao teste Flutter; seu log foi guardado junto dos artefatos temporários. Isso limita a comprovação de integração UI nesta rodada, não as medições dos processos CLI.

SHA-256 dos fontes usados:
- `auto_caption_service.dart`: `d518bad8f29aa7bb50378a124756d0592e0b93d5d2f157f2f1ee8ac97b3f03ec`.
- `editor_caption_timing.dart`: `f1a581f4cfe1ce4f6f782760f7471c3ece854c0bbf3cbf0795f9755a7651157d`.

Os hashes do rascunho e das configurações MCP permaneceram iguais antes/depois das seis transcrições:
- `project_recovery.json`: `ed0894689afb8ee25a862e3f793caa64e0f043a0b631a2f046fd779d708a964b`.
- `mcp_settings.json`: `7a4e681a04e5cfc5e3bbf6ede067fe5562dd9a74a833f0a3dd7bcccc3a939148`.

Não foi executado apply_plan, geração de legendas na timeline, atualização do runtime instalado, instalação de modelo no editor, mudança de idioma ou alteração da opção de aprovação durante esta auditoria.


## Implementação — etapa 1 (22/10/2026)

Idioma omitido no MCP usa a configuração do projeto (padrão pt) e o resultado
de transcribe/get_transcript informa language. Tempos por palavra persistem
em <projeto>.words.json, separados do v14, com SHA-256 integral da mídia;
mídia alterada invalida a transcrição. Projetos ainda sem caminho usam dados
locais privados e migram no salvamento. Arquivo ausente/corrompido não impede abrir v14.

Segmentação usa início/fim das palavras, sem distribuição proporcional e sem
realinhamento de waveform para palavras já temporizadas. Reparticiona as palavras
para respeitar 44 caracteres, duas linhas e mínimo de 1 s no MCP; a cauda curta
é agrupada com palavras anteriores sem prolongar artificialmente o fim da fala.
Se as restrições forem incompatíveis, retorna erro para revisão. Tempos
ausentes não são inventados; tokens de duração zero são preservados no agrupamento.
O limite de ±1 frame é verificado contra timestamps fornecidos pelo engine,
não contra alinhamento humano ainda não disponível.

Setup substitui CLI antigo pelo **1.9.5/b5454**, SHA-256
331dba46d6427105d2b802cdbc7eae916ea1c5abf9b0d3b5cfe460d8db8e4366.
O app verifica esse hash e o empacotador rejeita outro CLI. Teste executa o mesmo
arquivo usado como origem do ZIP. A confirmação do ZIP final será registrada
após empacotamento. Nenhum novo modelo padrão foi escolhido.

Validação: analyze sem problemas; testes de limites de palavras, cauda de
0,60 s, idioma omitido/configurado, persistência em novo controller/MCP,
invalidação por hash e v14. As regressões de salvamento foram corrigidas:
projeto sem transcrição/configuração adicional não exige gravar arquivo lateral.

### Rascunho privado para revisão

Primeiro minuto extraído para .work/validation/referencia-1min.wav (60 s,
mono, 16 kHz, PCM16), fora do Git. Rascunho em
docs/validation/referencia-1min.rascunho.txt, uma frase por linha sem timestamps,
gerado por **Small multilíngue**, o maior modelo instalado, CPU, whisper.cpp 1.9.5,
idioma pt. Não é gabarito revisado. Usá-lo como base favorece esse modelo na
comparação; a revisão humana deve corrigir ouvindo o áudio.
Ainda não existe referência revisada referencia-1min.txt; WER/CER não foram medidos.
Toda a pasta docs/validation/ e os arquivos .words.json estão ignorados no Git.
`analyze`: zero problemas. Suite da etapa 1: 262 testes passaram, 16 ignorados (condicionais já existentes), nenhuma falha.

## Implementação — etapa 2: VAD e vocabulário

VAD Silero v5.1.2 é incluído pelo setup (885.098 bytes, repositório oficial
ggml-org/whisper-vad, revisão 9ffd54a1e1ee413ddf265af9913beaf518d1639b,
SHA-256 29940d98d42b91fbd05ce489f3ecf7c72f0a42f027e4875919a28fb4c04ea2cf).
O app verifica esse hash, sem download automático. Interface oferece VAD ligado
por padrão e opção de desligar; vocabulário/prompt inicial por projeto, até 2.000
caracteres. Ambos persistem no arquivo lateral. MCP aceita vocabulary/vad opcionais,
herdando configurações do projeto; não altera as configurações quando há override.

Antes da troca do padrão, executei o mesmo áudio privado de 300 s no Base CPU
1.9.5, pt, 4 threads, prompt vazio: VAD desligado **28,811 s / 449,727 MiB RSS
pico**; ligado **27,251 s / 476,101 MiB**. Uma execução por condição: teste de
compatibilidade/custo, não prova de velocidade nem qualidade. Os valores exatos
de RSS são 471.572.480 e 499.228.672 bytes; commit pico 891.719.680 e
1.002.348.544 bytes. Ambas terminaram com código zero.
O padrão foi ativado conforme solicitado após essa verificação operacional.
WER permanece pendente de referência humana; nenhum ganho de qualidade é afirmado.

Etapa 2 validada: analyze sem problemas; 263 testes passaram, 16 ignorados; orçamento MCP aprovado nos testes.

## Implementação — etapa 3: backends e medição 1.9.5
Release b5454 oferece CPU x64 e CUDA 11.8/12.4 x64; não oferece Vulkan x64 pronto. CUDA 11.8 foi selecionado para avaliação pelo menor asset (284.761.231 bytes, contra 684.913.404 do 12.4). Nenhum build alternativo foi compilado. [Assets oficiais](https://github.com/ggml-org/whisper.cpp/releases/tag/b5454).
CUDA 11.8 ZIP SHA-256 e81c86c542be6e3d7b7245392d4e1c52ab6e5c61dbe38721754bc0ab59d4d027; CLI SHA-256 80fe839a13f5fd70d7511e6f714498de12522e59da2a5333c6efea40fe05ee51. CLI informa 1.9.5. Runtime separado em whisper/cuda/bin, CPU permanece em whisper/bin. Setup e empacotamento verificam ambos os CLIs; o app detecta NVIDIA localmente e só confirma backend pelo log de inferência. Configuração TGI_WHISPER_BACKEND=cpu força CPU. Interface mostra backend; MCP retorna backend efetivo.
**GPU não funcionou nesta máquina.** RTX 3050 6.144 MiB, driver 621.01 detectado pelo nvidia-smi. Import table de ggml-cuda.dll exige cublas64_11.dll; arquivo ausente no asset oficial e nos caminhos de carregamento locais. LoadLibraryExW com LOAD_WITH_ALTERED_SEARCH_PATH retornou NULL, erro Windows 126. Logs de todas as tentativas: loaded CPU backend / no GPU found; nenhuma alocação CUDA do modelo. Não instalei cuBLAS/Toolkit, não tentei outro backend para contornar. App detecta essa dependência ausente antes da transcrição e faz fallback CPU; falha posterior do CUDA também retorna a CPU com motivo visível.
### 300 s privados, três execuções por condição
Mesmo WAV SHA-256 16533371c7cdb2117f672491366fd90b313c497217e472a5fa76bb1c3cf0690c (293,547 s originais + 6,453 s silêncio); pt, 4 threads, beam/best-of 5, temperatura 0 e fallback 0,2, VAD Silero ligado, prompt vazio. Cronômetro inclui carga/inferência e JSON; exclui extração. RSS/commit pico nativos Windows amostrados a cada 20 ms; não são memória total da máquina. Sem aquecimento descartado; execução sequencial. Small CPU terceira execução apresentou maior tempo; mantida na amostra, sem exclusão.
| Modelo | Solicitado → efetivo | Tempo s (1 / 2 / 3) | RSS pico MiB (1 / 2 / 3) | Commit pico MiB (1 / 2 / 3) |
|---|---|---|---|---|
| base | cpu → CPU | 27.518 / 27.189 / 27.066 | 477.184 / 478.469 / 475.582 | 957.203 / 958.508 / 955.480 |
| small | cpu → CPU | 71.319 / 70.516 / 85.371 | 940.711 / 941.523 / 942.512 | 1421.004 / 1421.621 / 1423.070 |
| base | cuda → CPU | 27.515 / 27.595 / 27.209 | 476.527 / 474.527 / 474.348 | 955.887 / 954.531 / 954.375 |
| small | cuda → CPU | 71.913 / 71.361 / 71.839 | 946.270 / 937.094 / 942.074 | 1426.559 / 1421.922 / 1422.168 |

As linhas CUDA são **tentativas com fallback CPU**, não benchmarks GPU. Tempo, RAM e WER de GPU efetiva: indisponíveis. nvidia-smi mediu memória do dispositivo inteiro incluindo outros aplicativos; não atribuí esses valores ao Whisper. A ferramenta tool/benchmark_transcription.py preserva os logs e reporta backend solicitado/efetivo. Os arquivos brutos permanecem em .work/benchmark-b5454, privados. Nenhum ganho de qualidade nem troca do modelo padrão foi derivado desses tempos.

Etapa 3: analyze sem problemas; 263 testes passaram, 16 ignorados. GPU efetiva indisponível conforme diagnóstico acima.

## Implementação — etapa 4: gerenciador sob demanda

Interface: Legendas automáticas → Gerenciar modelos. Base permanece padrão.
Small, Medium, Large-v3-turbo q5_0 e Large-v3 q5_0 estão no catálogo selecionável;
nenhum desses pesos foi baixado automaticamente nesta implementação.
Downloads exigem ação explícita (também protegida na API por userInitiated),
têm progresso, pausa, retomada via Range/Content-Range, tratamento de servidor
que responde 200 em vez de 206, checagem prévia de espaço (restante + 64 MiB)
e tamanho/SHA-256 final. Erro de rede/pausa preserva parcial; hash incorreto o
descarta. Modelo só recebe nome definitivo após validação.
Remoção alcança os modelos baixados pelo gerenciador e parciais; modelos incluídos
no pacote são identificados e preservados.

Origem: [GGML oficial](https://huggingface.co/ggerganov/whisper.cpp/tree/5359861c739e955e79d9a303bcbc70fb988958b1),
revisão fixada 5359861c739e955e79d9a303bcbc70fb988958b1, sem consulta de catálogo
remoto em runtime. Caminhos de modelos são compartilhados com o transcritor,
incluindo TGI_WHISPER_MODELS_PATH.

| Modelo | Bytes | SHA-256 |
|---|---:|---|
| small | 487601967 | 1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b |
| medium | 1533763059 | 6c14d5adee5f86394037b4e4e8b59f1673b6cee10e3cf0b11bbdbee79c156208 |
| large-v3-turbo-q5_0 | 574041195 | 394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2 |
| large-v3-q5_0 | 1081140203 | d75795ecff3f83b5faa89d1900604ad8c780abd5739fae406de19f23ecd98ad1 |

Sugestão de capacidade usa RAM e, quando GPU Whisper foi confirmada ativa,
VRAM. É heurística de recursos, não classificação de qualidade, e não muda
o padrão. Sem WER revisado não se afirma ganho por escolher modelo maior.

Testes locais usam servidor HTTP de loopback com payload sintético, sem baixar
pesos: retomada 206, reinício correto com 200, SHA inválido, espaço insuficiente
antes da requisição, cancelamento preservando parcial, bloqueio sem ação explícita,
remoção e catálogo/heurística de RAM/GPU.

Etapa 4: analyze sem problemas; 268 testes passaram, 16 ignorados. Nenhum peso opcional baixado.

## Revalidação da etapa 1 e benchmark de 60 s (22/10/2026)

`git log --stat` e a implementação atual confirmam que os três itens pedidos
da etapa 1 já estavam implementados; nenhuma mudança adicional foi necessária:

- `segmentCaptionCues`/`timedCaptionCues` particionam pelos limites das palavras.
- `minimumCaptionCues`, usado no plano MCP, reparte novamente as palavras com
  duração mínima de 1 s, incluindo a última legenda, ou pede revisão quando
  não existe partição válida. O teste cobre a cauda final de 0,60 s.
- Setup, verificação do runtime e empacotamento fixam whisper.cpp 1.9.5/b5454
  para CPU e CUDA. O teste verifica os dois CLIs instalados.

Revalidação local: os 9 testes de transcrição/modelos passaram; `analyze`
sem problemas e suite completa com 268 testes passando, 16 ignorados.

### Protocolo do benchmark de 60 s

Áudio privado `.work/validation/referencia-1min.wav`: 60,000 s, mono, 16 kHz.
Base é o modelo instalado neste editor; Small está disponível na instalação
local do projeto TGI original e foi incluído sem copiar ou baixar pesos.
Não há outros modelos de transcrição no diretório de componentes do editor;
Silero é um modelo VAD, não um transcritor.

Máquina: Ryzen 5 5500, 6 núcleos/12 threads, 15,87 GiB de RAM, RTX 3050.
Mesmo CLI fixado, idioma `pt`, 4 threads, VAD Silero v5.1.2, JSON completo,
3 execuções sequenciais por modelo/backend; CPU com `-ng`, CUDA sem `-ng`.
Medição pelo `tool/benchmark_transcription.py`, incluindo inicialização e VAD,
com memória do processo amostrada a cada 20 ms. Resultados brutos privados em
`.work/accuracy-1min-final/`. A rodada preliminar foi descartada porque coincidiu
com a suite local; a rodada final começou depois do término dos testes.

### Resultados de 60 s

Medianas das 3 execuções; RAM em MiB (1.048.576 bytes), pico de working set
(RSS) e pico de commit do processo, medidos separadamente do tempo.

| Modelo | Backend solicitado → efetivo | Tempo (s) | Pico RSS (MiB) | Pico commit (MiB) | WER | CER |
|---|---|---:|---:|---:|---|---|
| Base | CPU → CPU | 5,240 | 382,320 | 897,641 | pendente | pendente |
| Small (instalação TGI original) | CPU → CPU | 13,754 | 850,137 | 1.366,918 | pendente | pendente |
| Base | CUDA → CPU (fallback) | 5,376 | 381,484 | 897,152 | pendente | pendente |
| Small (instalação TGI original) | CUDA → CPU (fallback) | 13,609 | 849,301 | 1.366,031 | pendente | pendente |

**Backend realmente usado: CPU nas 12 execuções.** Os logs CUDA registram
`loaded CPU backend` e `whisper_backend_init_gpu: no GPU found`, sem confirmação
de inferência CUDA. A dependência `cublas64_11.dll` continua ausente dos caminhos
pesquisados pelo aplicativo. Tempos e memória acima são de CPU, inclusive nas
tentativas CUDA; tempo/RAM/VRAM de inferência GPU não estão disponíveis.
Nenhuma comparação de qualidade é derivada desses tempos.

### Scorer fornecido e preparação do rascunho

O código fornecido foi salvo literalmente em `tools/wer.dart`, sem extrair
ou reescrever a lógica. Linha de comando preservada:
`dart tools/wer.dart referencia.txt hipotese.txt`.
A normalização ignora maiúsculas e pontuação, preserva acentos e compacta
espaços; CER usa code points Unicode, incluindo os espaços normalizados.

`source/test/wer_tool_test.dart` executa a CLI com cinco pares sintéticos e
confere as duas linhas de saída, as contagens e os percentuais esperados:
textos iguais (0%), palavra trocada (WER 50%), palavra omitida (WER 50%),
apenas acento (WER 100%, CER 25%) e apenas caixa/pontuação (0%).

Rascunho regenerado diretamente de 0:00 a 1:00 do vídeo original do projeto,
com **Small multilíngue**, whisper.cpp **1.9.5/b5454**, português `pt`,
**CPU**, 4 threads, sem VAD. O recorte em
`.work/validation/referencia-1min.wav` tem exatamente 960.000 amostras:
60,000 s, mono, 16 kHz, PCM16. Não inclui o padding da amostra de 300 s.
A hipótese completa foi agrupada por pontuação em uma frase por linha,
sem timestamps nem correções lexicais, e salva em
`docs/validation/referencia-1min.rascunho.txt`.
Logs, JSON e proveniência ficam privados em `.work/wer-validation/`.

**O rascunho foi gerado por Small e favorece Small na comparação.**
Na preparação do rascunho ainda não havia `referencia-1min.txt`; as métricas
da referência recebida depois constam na seção seguinte, com a limitação
de sua origem. Os cinco testes usam somente textos sintéticos.
`.work/` e os dois arquivos de referência estão explicitamente no `.gitignore`;
a regra preexistente para a pasta de validação também foi preservada.

Validação local desta etapa: `dart analyze tools/wer.dart` e `flutter analyze`
sem problemas; suite completa com **273 testes passando**, **16 ignorados**,
incluindo os cinco testes da CLI. O código do scorer foi conferido byte a byte
contra o texto fornecido, e o áudio foi validado como PCM16 mono/16 kHz, 60 s.

## WER/CER das 12 hipóteses com a referência fornecida (22/10/2026)

**Todas as 12 execuções rodaram efetivamente em CPU.** As seis tentativas
com o CLI CUDA terminaram em fallback CPU; os logs registram backend CPU e
`no GPU found`, sem confirmação de inferência CUDA. Não há medição de GPU
ativa nem de VRAM atribuída ao Whisper nesta rodada.

Foram avaliados todos os modelos de transcrição encontrados nas instalações
locais: Base e Small multilíngues, deduplicando as cópias de Base. Small
permanece no projeto TGI original e foi lido sem baixar ou instalar pesos
adicionais. Silero é VAD e não foi contado como modelo de transcrição.

O recorte privado de 0:00 a 1:00 tem 60,000 s, mono, 16 kHz, PCM16.
As hipóteses desta série foram geradas com whisper.cpp 1.9.5/b5454,
idioma `pt`, 4 threads, **sem VAD**, três processos sequenciais por combinação
modelo/backend solicitado. Esta série é distinta da tabela anterior com VAD.
CPU foi forçada com `-ng`; a tentativa CUDA usou o CLI CUDA sem esse argumento.
O tempo inclui inicialização, carregamento, inferência e escrita do JSON;
extração, exportação da hipótese textual e scorer ficam fora do cronômetro.

Tempo e memória abaixo são medianas **separadas** de três execuções por
linha. Memória é o pico de working set/RSS do processo, em MiB
(1.048.576 bytes), consultado via GetProcessMemoryInfo a cada 20 ms;
não inclui VRAM nem memória do editor. Os picos de commit também estão nos
artefatos privados. Cache do sistema e outros aplicativos não foram isolados.

| Modelo | Backend efetivo (solicitação) | Tempo mediano (s) | Memória mediana do pico RSS (MiB) | WER | CER |
|---|---|---:|---:|---:|---:|
| Base | CPU (-ng) | 5,875 | 367,109 | 17,95% | 11,95% |
| Base | CPU (CUDA solicitada; fallback) | 6,017 | 367,973 | 17,95% | 11,95% |
| Small | CPU (-ng) | 15,828 | 865,566 | 0,00% | 0,00% |
| Small | CPU (CUDA solicitada; fallback) | 16,144 | 865,281 | 0,00% | 0,00% |

Cada uma das 12 hipóteses foi pontuada por `tools/wer.dart`, sem modificar
seu código, contra `docs/validation/referencia-1min.txt` (156 palavras
após normalização). Os três WER/CER de cada linha foram idênticos;
por isso a mediana dos percentuais coincide com cada resultado individual.
Maiúsculas/pontuação são ignoradas, acentos são preservados e CER inclui
os espaços normalizados, conforme o scorer fornecido.

As 12 hipóteses `.hypothesis.txt`, resultados individuais `.wer.txt`, JSON,
logs, tempos, contadores de memória e a cópia da referência usada ficam em
`.work/accuracy-measured-20261022-081525/`, fora do Git. Nenhum conteúdo do vídeo
foi incluído nesta atualização do relatório.

### Recomendação e limites desta comparação

A referência fornecida é **idêntica byte a byte ao rascunho gerado por
Small**. Isso favorece Small: seus 0% medem concordância com o rascunho do
próprio modelo, e não demonstram superioridade em uma referência independente.
Diferenças de Base em relação a esse rascunho não foram classificadas por
avaliação auditiva independente. A amostra tem somente um minuto de um
vídeo, com modelos e idioma fixos; não representa um corpus de português
nem mede alinhamento temporal, inserções em silêncio ou desempenho de GPU.

Recomendo **manter Base para priorizar tempo e RAM nesta CPU**: na condição
CPU explícita, 5,875 s e 367,109 MiB, contra 15,828 s e 865,566 MiB de Small.
Small é uma opção para avaliar com referências independentes e mais áudios
antes de recomendar uma troca por qualidade. **O modelo padrão permanece Base;
nenhuma configuração do aplicativo foi alterada.**

## Preciso (turbo): modelo verificado e candidato Vulkan (22/10/2026)

O gerenciador e o seletor apresentam **Preciso (turbo)** para
`large-v3-turbo-q5_0` (Large-v3-turbo quantizado Q5_0). O identificador interno
permanece o mesmo. O modelo foi instalado no diretório de componentes do
usuário, detectado pelo gerenciador, sem selecionar automaticamente o modelo.
**Base permanece como modelo padrão.**

### Origem e verificação do SHA-256

O SHA-256 do catálogo foi comparado com o campo `lfs.oid` dos
[metadados oficiais do repositório ggerganov/whisper.cpp](https://huggingface.co/api/models/ggerganov/whisper.cpp/tree/5359861c739e955e79d9a303bcbc70fb988958b1?recursive=false&expand=false),
na revisão imutável já fixada pelo catálogo. Depois foi conferido contra
os bytes de um **download real** da mesma revisão. As duas verificações
coincidiram: **574.041.195 bytes**, SHA-256
`394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2`.
O arquivo instalado é
`%LOCALAPPDATA%/TGI_VIDEO_EDITOR/components/whisper/models/ggml-large-v3-turbo-q5_0.bin`.
Metadados e recibo da verificação estão em
`.work/turbo-evaluation/official-model-metadata.json` e `model-install.json`.

### Três transcrições por backend efetivo

Recorte privado de 60,000 s em `.work/validation/referencia-1min.wav`,
português `pt`, 4 threads, sem VAD, mesmo modelo Q5_0. O runtime CPU é o
1.9.5/b5454 fixado pelo projeto. O candidato Vulkan foi compilado do mesmo
[b5454, em commit fixado](https://github.com/ggml-org/whisper.cpp/tree/d1be6fde11ac6e0407606b4e42fe72d34add8037),
com `GGML_VULKAN=ON`, `GGML_CUDA=OFF`, `GGML_NATIVE=OFF`,
`GGML_BACKEND_DL=ON` e `WHISPER_BUILD_IS_DEV=OFF`; o CLI final informa **1.9.5**.
Cada execução cria um processo novo. Tempo inclui carregar o modelo,
transcrever e gravar JSON; extração e conversão para texto ficam de fora.

| Modelo | Backend realmente usado | Execuções 1 / 2 / 3 (s) | Tempo mediano (s) | Pico RSS mediano (MiB) |
|---|---|---|---:|---:|
| Preciso (turbo) | CPU (-ng) | 54,175 / 52,554 / 53,367 | 53,367 | 883,086 |
| Preciso (turbo) | Vulkan / RTX 3050 | 3,617 / 3,637 / 3,473 | 3,617 | 271,957 |

O log das três execuções Vulkan identifica **NVIDIA GeForce RTX 3050** e
`whisper_backend_init_gpu: using Vulkan0 backend`, com pesos no dispositivo.
**Vulkan usou a GPU; CPU foi usada nas três execuções forçadas com -ng.**
RSS é memória residente do processo no host, medida a cada 20 ms, e não VRAM.

As seis saídas finais, JSON, logs e métricas estão em
`.work/turbo-evaluation/measurements/`: `turbo-cpu-1..3` e
`turbo-vulkan-release-1..3`, incluindo `.hypothesis.txt`, fora do Git.
Não há conteúdo do vídeo nesta atualização.

Os caches do sistema e do driver não foram limpos. O build Vulkan final foi
medido com cache de shaders já aquecido: uma execução exploratória anterior
levou 12,761 s na inicialização fria. As medianas representam esta máquina e
este recorte; a primeira execução em outra instalação pode levar mais tempo.

### Causa exata do fallback CUDA e proposta de menor pacote

A auditoria da tabela de imports PE encontrou dependência direta de
`cublas64_11.dll` em `ggml-cuda.dll`. A DLL não existe na pasta CUDA,
System32 ou PATH pesquisados. `LoadLibraryExW` falha com **erro Windows 126**
para ela e, consequentemente, para `ggml-cuda.dll`. O probe do CLI CUDA
termina em CPU com `no GPU found`, apesar da RTX 3050 e do driver NVIDIA
621.01 presentes. O loader Vulkan existente reconhece Vulkan 1.4.357.
A lista de arquivos preservados pelo setup atual também não inclui CuBLAS;
uma correção CUDA precisaria tratar essa dependência e sua preservação.
Evidências privadas: `cuda-dependency-audit.json`, `cuda-loader-probe.log`
e `vulkan-summary.log` no diretório desta avaliação.

**Proposta: integrar o runtime Vulkan validado**, o menor pacote GPU
funcional entre os candidatos avaliados nesta máquina. Ele ocupa
**48,92 MB** (48,919,552 bytes sem compressão)
e **15,18 MB em ZIP** (15,182,626 bytes).
Os seis arquivos são CLI, whisper.dll, ggml.dll, ggml-base.dll,
ggml-cpu.dll e ggml-vulkan.dll; o loader Vulkan vem do driver já instalado.
Pesos, driver e SDK de compilação ficam fora desses tamanhos.

O menor [asset CUDA oficial de b5454](https://github.com/ggml-org/whisper.cpp/releases/tag/b5454)
é o CUDA 11.8 de 284.761.231 bytes; o CUDA 12.4 tem 684.913.404 bytes.
A distribuição CuBLAS 11.8 para Windows x64 tem mais 420.850.025 bytes,
conforme o [manifesto oficial NVIDIA](https://developer.download.nvidia.com/compute/cuda/redist/redistrib_11.8.0.json).
A comparação usa esses assets oficiais e o pacote mínimo Vulkan compilado,
sem afirmar um mínimo absoluto entre todos os builds customizados possíveis.

O candidato testado está em `.work/turbo-evaluation/vulkan-runtime/`;
o ZIP e `vulkan-build-provenance.json` registram seus componentes e a origem
dos headers Khronos e do compilador glslc Google. O script local
`.work/build_vulkan_candidate.py` reproduz a compilação. Esta validação usa
CLI local; a integração ao resolver, download e empacotamento do app é a
proposta decorrente. O código do app continua aceitando os runtimes CPU/CUDA
fixados anteriormente, e **o padrão Base permanece intacto**.

Validação local: analyze sem problemas e **273 testes passando**, com
16 ignorados. O teste do catálogo confere o rótulo Preciso (turbo), seu
identificador, tamanho e presença do SHA-256 fixado.


## Integração Vulkan no aplicativo — etapa 1

Runtime whisper.cpp 1.9.5/b5454 compilado da mesma revisão fixada, com
`GGML_VULKAN=ON`, CUDA desativado e sem alteração do código upstream.
`tool/build_whisper_vulkan.py` verifica SHA-256 dos quatro arquivos baixados
(fonte, Vulkan-Headers, SPIRV-Headers e shaderc), mede cada executável/DLL real
e gera o manifesto incorporado à aplicação por `tool/editor_paths.ps1`.
O app verifica todos os sete binários antes de executar o detector ou o CLI.
O driver fornece o loader Vulkan; não é necessário instalar o SDK no usuário.

Acréscimo medido: **48.947.200 bytes (48,95 MB)**, sete arquivos; ZIP isolado
**15.192.213 bytes**. Está abaixo de ~50 MB e segue no ZIP, sem download de
pacote de aceleração. O pacote CUDA incompleto deixou de ser distribuído.
Detecção executa em subprocesso limitado a oito segundos; erro, ausência ou
incompatibilidade do driver/GPU usa CPU. Durante inferência, falta de saída por
45 segundos encerra o subprocesso e tenta CPU uma vez; cancelamento continua
cancelando, e trechos seguintes não repetem uma GPU que já falhou.
Backend GPU só é confirmado pela mensagem de seleção efetiva do engine.
A versão v14 e o catálogo MCP não foram alterados nesta etapa.

Validação da etapa 1: analyze sem avisos; 276 testes passaram, 16 integrações
condicionais ignoradas. Inclui integridade das DLLs, detecção sem falsa
confirmação de GPU, fallback por runtime ausente, v14 e orçamento MCP.


## Seleção de dispositivo — etapa 2

Arquivo → Transcrição (GPU) lista as GPUs compatíveis vistas pelo próprio
backend Vulkan, com memória livre/total informada pelo driver. Automático
prioriza dedicada, depois RTX e memória livre; CPU e escolha manual de GPU
ficam em configurações globais, pelo identificador PCI quando disponível.
Uma GPU escolhida que desaparece usa CPU; a preferência não é redirecionada
silenciosamente a outra GPU. A mudança vale para a próxima transcrição.

Telas de legendas mostram backend e dispositivo da inferência. O resultado do
job MCP `transcribe` inclui `backend`, `device`, `device_id`, `model` e `fallback`
da execução concluída, sem depender de outro job que atualize o estado global.
Nenhum campo foi adicionado aos schemas de entrada MCP nem ao projeto v14.

Validação da etapa 2: analyze sem avisos; 279 testes passaram, 16 integrações
condicionais ignoradas. Inclui troca na UI, persistência, prioridade RTX, GPU
removida, v14 e os limites do catálogo MCP.
