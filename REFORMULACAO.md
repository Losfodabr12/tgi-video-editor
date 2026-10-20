# TGI Video Editor — reformulação 0.2.0+2

Atualização de 20/10/2026: o código desta reformulação foi preparado para
publicação na branch `main`, com [revisão e testes repetidos](ANALISE_RAPIDA.md).
As referências abaixo a alterações somente locais descrevem a entrega de
18/10/2026; a release executável pública continua em `v0.1.0`.

Implementação local em 18/10/2026, somente em `PROJETO EDITOR DE VIDEO`.
O projeto `INICIAR PROJETO TGI APP` não foi alterado. Nenhum projeto de mídia
do usuário foi usado como arquivo de teste ou sobrescrito. Não houve clone,
criação de outro aplicativo ou troca do renderizador por uma simulação.

O executável atualizado está em `aplicativo/VideoEditor.exe`; o atalho
`INICIAR EDITOR.cmd` continua abrindo essa cópia. A versão pública v0.1.0 no
GitHub ainda é a base anterior; estas alterações estão no diretório local.

## Problemas confirmados na análise e correções

- `TrackType` servia ao mesmo tempo para conteúdo e compatibilidade da pista.
  Agora `TrackKind.visual/audio` define a pista e `ClipKind` identifica o
  conteúdo. `ClipKind` é um alias de `TrackType` para preservar as APIs e os
  nomes serializados anteriores. Vídeo, imagem e texto convivem na mesma pista.
- A adição de vídeo criava áudio incondicionalmente. Agora `hasAudio` decide a
  criação do companheiro; uma pista sonora disponível é reutilizada. Vídeo
  silencioso não cria áudio. Projeto vazio começa sem pistas.
- Vídeos e grupos vinculados tinham restrições de movimento vertical.
  Operações de domínio transacionais agora movem os grupos completos, mantêm
  offsets, fontes e duração, respeitam compatibilidade, colisões e bloqueios.
  Falhas devolvem o snapshot original, sem deixar metade da operação aplicada.
- Preview e exportação tinham passagens rígidas por tipo de mídia; selecionar
  uma sobreposição podia elevá-la no preview. Agora as duas composições seguem
  a ordem visual das pistas, de baixo para cima, independentemente da seleção.
- O vídeo principal era tratado como fundo opaco mesmo com opacidade animada.
  A composição agora conserva alpha, keyframes e fades, permitindo ver camadas
  inferiores. Os fades de vídeos sobrepostos e textos também entram no FFmpeg.
- Ripple delete de seleções descontínuas removia um intervalo maior que o
  conteúdo escolhido. Agora utiliza a união dos intervalos efetivamente removidos.
- Colar/duplicar podia sobrepor vídeos na mesma pista. Agora a colagem cria uma
  camada vizinha compatível quando a pista está ocupada; mantém vínculos e
  conteúdo mesmo se a pista de origem foi excluída. Undo restaura a operação toda.
- Ajustes de duração/velocidade/slip/slide agora validam os spans alterados
  contra pistas bloqueadas e sobreposições. Áudio independente muda de velocidade
  sem deslocar conteúdo visual; áudio vinculado usa a operação do conjunto.
- Um filtro de 50 ms impedia seeks explícitos de um frame a 30/60 fps. Foi
  removido desse caminho; o controle de ecos de reprodução permanece separado.
- Após editar texto, clicar na timeline agora restaura o foco dos atalhos.
  O seletor de fontes deixou de exceder a largura do inspetor.
- A persistência do layout usava o diretório antigo `TGIAPP`. Agora usa
  `%LOCALAPPDATA%/TGI_VIDEO_EDITOR`, com versão 3 do layout e visibilidade dos painéis.

## Timeline e interação implementadas

Pistas criadas conforme o conteúdo, faixa vazia para criar uma camada por
arraste, movimento vertical/horizontal de vídeos e áudios, grupos selecionados,
vínculos, snapping e indicadores de drop. Mídia arrastada mostra posição e
destino; colisões são recusadas. Shift + drop insere mídia em uma emenda e
desloca conjuntos vinculados; inserir dentro de um clipe é recusado.

Cabeçalhos compactos, menus reais para renomear, excluir, bloquear, subir/descer
camadas e mudar altura. Alturas de 44 a 180 px, com ajuste por arraste e histórico
consolidado. Exclusão de pista com conteúdo pede confirmação; Ctrl+Z restaura.

Mantidos cortes sincronizados, trim, excluir com lacuna, ripple delete, seleção
múltipla, copiar/colar, duplicar, mute/solo, miniaturas e waveforms existentes.
Arrastar áudio move o clipe; Alt + arraste na linha ajusta volume. Zoom com
Ctrl + roda conserva o instante sob o cursor. Busca de clipes visíveis usa índice.

Ctrl+S salva, Ctrl+O abre, Ctrl+Z desfaz, Ctrl+Y e Ctrl+Shift+Z refazem. Setas
esquerda/direita navegam um frame conforme o FPS configurado. Espaço alterna
reprodução; Delete exclui. Campos de texto conservam sua edição nativa e as
configurações de atalhos existentes continuam tendo prioridade.

## Interface implementada

- Barra superior com nome do projeto, Arquivo/Editar/Exibir, histórico,
  salvar, importar e exportar; progresso e cancelamento das operações existentes.
- Biblioteca à esquerda: Mídia, Áudio, Títulos, Transições, Efeitos e Legendas.
  Busca e filtro de mídias; títulos adicionam texto real, sem botões simulados.
- Preview central e controles de reprodução; seleção entre original/proxy
  usa os arquivos reais e permite preparar proxies.
- Inspetor à direita acompanha o clipe clicado, inclusive áudio vinculado.
  Vídeos/imagens abrem transformação; texto mostra conteúdo e fonte primeiro,
  atualizando o modelo/preview durante a digitação. Ferramentas de cor, máscara,
  chroma, velocidade, animação e áudio reaproveitam os controles implementados.
- Timeline inferior permanece visível junto com a prévia. Divisores redimensionam
  os painéis; em janelas menores os painéis secundários se recolhem. Biblioteca
  e inspetor podem ser ocultados e o layout é persistido.
- Tema escuro neutro, destaque azul, tipografia Segoe UI, controles desktop
  compactos, estados de foco/hover/desabilitado, menos molduras e cartões.
  Cores, tipografia e tamanhos reutilizam os tokens/tema do aplicativo.

## Arquitetura e compatibilidade

O `EditorController` continua usando `ChangeNotifier`, com projetos imutáveis
como snapshots de undo/redo. Regras estruturais saíram dos widgets para
`project_timeline.dart`; cabeçalhos, workspace e operações de controle têm
arquivos próprios. Media import, media_kit, FFmpeg, fontes, caches e serviços
existentes foram reaproveitados. Nenhuma dependência nova foi adicionada.

Formato de projeto **14**, com `kind` e `height` por pista. Leitura dos formatos
anteriores continua disponível. A migração em memória transforma as pistas
antigas em visuais/áudio e reproduz a ordem de composição antiga (textos,
imagens e vídeos) na nova ordem explícita. Preserva IDs, posições, durações,
grupos, efeitos, keyframes, transições e propriedades existentes. Carregar um
projeto não grava seu arquivo de origem. Gravar uma edição usa o fluxo normal
de salvamento/backup já existente.

Projetos antigos com vídeos sobrepostos dentro da mesma pista continuam
carregáveis e editáveis. Como o concatenador dessa pista não representa tais
vídeos simultâneos, a exportação agora informa o problema e pede outra camada,
em vez de produzir silenciosamente um vídeo com timing errado.

## Testes executados

Ambiente: Windows, Flutter 3.44.4 / Dart 3.12.2, FFmpeg/ffprobe 8.1.2 locais.
O build usa a cópia existente via caminho curto temporário para evitar MAX_PATH.

| Verificação | Resultado executado |
| --- | --- |
| `flutter analyze --no-pub` | Sem problemas |
| `flutter test --no-pub --dart-define=TGI_RUN_FFMPEG_INTEGRATION_TESTS=true --reporter expanded` | **145 aprovados, zero falhas, zero ignorados** |
| Verificação final de workspace/índice após ajuste tipográfico | **12 aprovados** |
| `flutter build windows --release --no-pub` | Release Windows compilada, versão **0.2.0+2** |
| `git diff --check` | Sem erros de whitespace |
| Distribuição local | 63 arquivos conferidos por SHA-256 contra o build, sem divergências; runtimes preservados |

Os testes novos incluem 23 cenários de domínio/controlador, 9 testes de widgets,
6 testes de composição com FFmpeg real e 3 testes de índice. Há também uma nova
regressão de Ctrl+S. As verificações existentes de salvamento, recuperação,
persistência, fontes, áudio e timing de exportação foram executadas.

| Cenário pedido | Evidência |
| --- | --- |
| Primeiro vídeo em projeto vazio | Domínio: criação de pista visual |
| Vídeo sem áudio | Domínio: nenhuma pista/clipe de áudio criado |
| Vídeo com áudio | Vínculos, cortes, movimento e bloqueio de companheiro |
| Imagem sobre vídeo | Exportação real: pixels e ordem de composição |
| Texto sobre imagem | Exportação real: pixels de texto acima/abaixo |
| Duas camadas de vídeo | Exportação real e seleção sem alterar z-order |
| Movimento vertical | Arrastes reais nos widgets, vídeo e áudio |
| Nova faixa por arrastar | Arraste para a região de nova camada |
| Exclusão de faixa | Domínio/controlador e restauração por undo |
| Pista bloqueada | Arraste de widget e rejeição atômica de vínculo |
| Undo/redo estrutural | Altura, exclusão e colagem vinculada |
| Salvar/reabrir | Testes de persistência e round-trip do formato 14 |
| Projeto antigo | Migração com payload, IDs, tempos e keyframes preservados |
| Exportação em camadas | FFmpeg real: vídeos/imagens/textos, fades e alpha |

Os testes de FFmpeg inspecionam frames e amostras de áudio, não apenas a
presença de argumentos. Incluem opacidade/keyframes do vídeo principal, fades
de vídeo/texto e conteúdo misto sequencial na mesma pista.

### Medição de consultas da timeline

300 consultas com os mesmos resultados antes/depois, comparando varredura
linear com o índice de intervalos. Última execução de medição:

| Clipes | Linear | Com índice | Construção inicial do índice |
| --- | ---: | ---: | ---: |
| 20 | 2,470 ms | 1,916 ms | 0,497 ms |
| 20.000 | 58,608 ms | 0,693 ms | 33,959 ms |

São tempos desse trecho e dessa máquina, sujeitos à carga do ambiente. Não são
uma medição de FPS, memória, decodificação 4K ou desempenho de exportação.
O índice é imutável por snapshot; o custo de construção é pago uma vez por
versão da pista. A virtualização e os caches já existentes foram mantidos.

### Limite da revisão gráfica nativa

O executável final foi iniciado com perfil separado em `.work/native_review`,
usando mídia sintética. A janela abriu com o nome correto, o processo permaneceu
ativo e media_kit inicializou a textura de vídeo. Porém as capturas da superfície
nativa ficaram em branco neste ambiente, tanto na versão anterior quanto na
nova, por captura da área da janela e por PrintWindow. A tentativa com renderização
por software também não permitiu validar a imagem nativa. Portanto não foi
declarada aprovação visual do preview/GPU nem da reprodução audiovisual manual.

O layout foi renderizado pelos widgets reais do editor, capturado e inspecionado
em `.work/editor-desktop-review.png`. Testes verificaram preview/timeline visíveis
simultaneamente em 1440×900, 1280×720, 1024×768, 900×600 e 640×480, sem overflow.

## Pendências e limites reais

- Falta uma sessão visual de uso na janela nativa, com captura funcional, para
  avaliar fluidez de reprodução, GPU, sincronismo percebido e edição prolongada.
  Não foram medidos CPU/GPU/memória com projetos reais extensos ou mídia 4K.
- Transições existentes continuam sendo efeitos globais ao redor das emendas;
  não foi implementado um novo motor de cross-dissolve A/B por pares de clipes.
- O preview interativo e FFmpeg usam caminhos diferentes para alguns filtros.
  A estabilização continua como pós-processamento de exportação; não há garantia
  de igualdade de pixels de todos os filtros avançados durante a prévia.
- Mantidos os limites mínimos existentes de trim: 100 ms para mídia e 1 s para
  ajuste de duração de imagem/texto. Projetos carregados conservam seus tempos.
- Pistas vazias remanescentes de edição manual podem ser excluídas pelo menu;
  o editor não apaga automaticamente nomes e configurações de pistas do usuário.
- Binários/componentes de FFmpeg e Whisper continuam locais. A reformulação
  não foi publicada como nova release no GitHub nesta tarefa.

## Arquivos modificados/adicionados

Relação de código, testes e documentação desta reformulação (artefatos de
compilação e logs locais são ignorados pelo Git):

- `.gitignore`
- `LEIA-ME.txt`
- `PROJECT_HANDOFF.md`
- `README.md`
- `REFORMULACAO.md`
- `VALIDACAO.txt`
- `source/README.md`
- `source/lib/app/app.dart`
- `source/lib/app/theme/app_theme.dart`
- `source/lib/app/theme/design_tokens.dart`
- `source/lib/domain/models/clip.dart`
- `source/lib/domain/models/project.dart`
- `source/lib/domain/models/project_timeline.dart`
- `source/lib/domain/models/timeline_clip_index.dart`
- `source/lib/domain/models/track.dart`
- `source/lib/features/editor/application/editor_controller.dart`
- `source/lib/features/editor/application/editor_controller_timeline.dart`
- `source/lib/features/editor/presentation/editor_clip_properties.dart`
- `source/lib/features/editor/presentation/editor_desktop_workspace.dart`
- `source/lib/features/editor/presentation/editor_header.dart`
- `source/lib/features/editor/presentation/editor_screen.dart`
- `source/lib/features/editor/presentation/editor_screen_support.dart`
- `source/lib/features/editor/presentation/editor_shell.dart`
- `source/lib/features/editor/presentation/editor_workspace_layout.dart`
- `source/lib/features/editor/presentation/widgets/media_pool_list.dart`
- `source/lib/features/editor/presentation/widgets/timeline_clip_widgets.dart`
- `source/lib/features/editor/presentation/widgets/timeline_content.dart`
- `source/lib/features/editor/presentation/widgets/timeline_index.dart`
- `source/lib/features/editor/presentation/widgets/timeline_lanes.dart`
- `source/lib/features/editor/presentation/widgets/timeline_panel.dart`
- `source/lib/features/editor/presentation/widgets/timeline_track_headers.dart`
- `source/lib/features/editor/presentation/widgets/timeline_tracks.dart`
- `source/lib/features/editor/presentation/widgets/video_preview_panel.dart`
- `source/lib/features/editor/presentation/widgets/video_preview_stage.dart`
- `source/lib/main.dart`
- `source/lib/services/ffmpeg_service.dart`
- `source/lib/services/ffmpeg_service_segments.dart`
- `source/lib/services/project_io_service.dart`
- `source/pubspec.yaml`
- `source/test/desktop_workspace_test.dart`
- `source/test/dynamic_timeline_test.dart`
- `source/test/editor_controller_test.dart`
- `source/test/editor_save_regression_test.dart`
- `source/test/ffmpeg_export_timing_regression_test.dart`
- `source/test/layer_composition_export_test.dart`
- `source/test/timeline_index_test.dart`
- `source/windows/runner/Runner.rc`
- `source/windows/runner/main.cpp`
