# Relatório de alterações

Execução por etapas na ordem solicitada (a lista recebida não contém etapa 2).
Formato de projeto preservado em v14. Resultados abaixo são de comandos
executados nesta máquina; logs completos ficam em `.work/`, ignorada pelo Git.

| Etapa | analyze --no-pub | test --no-pub | Resultado |
| --- | --- | --- | --- |
| 1 — Paridade | exit 0, sem problemas | exit 0, 138 aprovados / 13 ignorados | Frames FFmpeg, correção de dessaturação por máscara e docs/PARIDADE.md |
| 3 - Refatoracao | exit 0, sem problemas | exit 0, 141 aprovados / 13 ignorados | Builder puro, executor/parser, historico, legendas, preview e atalhos |
| 4 — Independente | exit 0, sem problemas | exit 0, 144 aprovados / 13 ignorados | Flag standalone padrão, 4K livre, rede TGI bloqueada e identidade central |
| 5 — Transições | exit 0, sem problemas | exit 0, 146 aprovados / 13 ignorados | xfade/acrossfade com pixels, duração e espectro de áudio; preview A/B aproximado |
| 6 — Projetos antigos | exit 0, sem problemas | exit 0, 148 aprovados / 13 ignorados | Sobreposições migradas em memória; formatos 13/14 e round-trip testados |
| 7 — Build e CI | exit 0, sem problemas | exit 0, 148 aprovados / 13 ignorados | Integração adicional: 161 aprovados; build release exit 0 (116,0 s) |
| 8 — Desempenho | exit 0, sem problemas | exit 0, 151 aprovados / 13 ignorados | Caches persistentes e benchmark FFmpeg executado; dados em docs/DESEMPENHO.md |
| 9 — Extras e entrega | exit 0, sem problemas | exit 0, 160 aprovados / 13 ignorados | Integração: 173 aprovados, zero ignorados; build release exit 0 (110,4 s) |

Os 13 testes históricos opcionais dependem de um dart-define e são ignorados
pelo comando padrão pedido. Os seis novos testes de pixels rodam por padrão.
A etapa 1 teve falhas intermediárias nos testes novos; foram corrigidas e os
dois comandos repetidos antes do commit. Asserções de máscara respeitam o
escurecimento por luminância YUV, que difere do preview RGB.

Ainda requer teste manual: janela nativa, reprodução, GPU, sincronismo
audiovisual percebido e diferenças de rasterização descritas em docs/PARIDADE.md.

## Etapa 3

<!-- Resultados das etapas 10/11 e capturas estão no fim deste relatório. -->

APIs de FfmpegService e EditorController preservadas. Testes anteriores
permanecem sem edicao. O builder nao escreve arquivos nem inicia processos;
os textos do drawtext sao retornados no comando e escritos pelo executor.
Novos testes verificam ausencia de escrita, determinismo, parser e historico.
Controlador e tela continuam orquestrando varios fluxos. Os novos modulos sao
bibliotecas importaveis, com dependencias explicitas, alem dos parts existentes.

## Etapa 4

`app/app_identity.dart` concentra nome, nome curto, diretório de dados e
`kStandalone` (padrão true). A marca exibida é Frame Studio. O diretório antigo
foi preservado para manter rascunhos/configurações. O nome pode ser configurado
por `EDITOR_NAME` / `EDITOR_SHORT_NAME` nos dart-defines.

No modo independente, 4K não exige conta/plano; autenticação, anúncios,
downloads TGI e instalação de modelos pela interface não fazem requisições.
Importação/edição/exportação usam arquivos locais. Catálogos remotos não são
necessários; o painel Áudio abre a biblioteca local. Assets já em cache ainda
podem ser usados. Instalar dependências exige preparação online ou cópia dos
runtimes; execução offline pressupõe esses componentes instalados.

Testes novos verificam 4K, autenticação sem HTTP e rejeição de downloads antes
da requisição. Não foi executada uma sessão nativa com o adaptador de rede
desligado; esse teste manual continua pendente.

## Etapa 5

Dissolve em emendas de vídeos adjacentes usa xfade/acrossfade antes da
codificação; duração da timeline preservada. O modelo v14 de transição global
foi mantido. O preview usa dois vídeos com mistura alfa. Handles repetem bordas;
os limites e diferenças estão em docs/PARIDADE.md. Não foi implementado um
modelo novo de transições por par/pista nem edição de handles fora do trim.

## Etapa 6

A migração agora separa vídeos sobrepostos automaticamente, incluindo v14
anteriores, sem mudar o número do formato. IDs de clipe, vínculos, tempos e
propriedades preservados; IDs das pistas adicionais não colidem com existentes.
O teste antigo de rejeição foi alterado nesta etapa porque o comportamento
pedido mudou. Detalhes em docs/MIGRACAO.md.

## Etapa 7

Scripts compartilhando o mesmo caminho curto; setup automático com versões e
SHA-256 fixados; CI Windows/Flutter 3.44.4. Download completo de FFmpeg, Whisper
e Base executado em `.work/setup-verification`, seguido de segunda execução
idempotente. FFmpeg/ffprobe `-version` e Whisper `--help` retornaram 0; hash do
Base conferido. A primeira verificação de ffprobe interrompia seu stdout com
Select-Object; foi corrigida e o setup repetido com sucesso.

`tool/test_editor.ps1 -Integration -Build` executou pub get, analyze, suíte
padrão, integração e build release. Houve avisos CMake CMP0175 do plugin
media_kit, sem falha de build. Prova de limpeza após exceção também executada
com o helper de caminho curto. Scripts PowerShell passaram pelo parser.
O resultado remoto do workflow será registrado separadamente ao final.

## Etapa 8

Proxies existentes foram aprimorados: diretório persistente, chave SHA-256,
publicação somente após conclusão e proporção vertical preservada. Miniaturas
e waveform agora usam cache em disco, com testes de reabertura, invalidação e
corrupção. Benchmark real de geração/decodificação/exportação de fonte sintética
1080p/5 s executado: uma medição por operação, números brutos publicados.
Não se mediram FPS nativo, consumo de GPU/RAM ou desempenho prolongado em 4K.

## Etapa 9

Presets YouTube/4K/9:16/1:1/WAV na interface; seleção de CPU/NVENC/QSV/AMF
mantida com probe e retry CPU. Testes renderizaram as quatro dimensões reais,
inclusive 3840×2160, e conferiram WAV PCM estéreo sem vídeo. Falhas simuladas
de cada encoder e falha após probe produziram arquivos CPU válidos.

Importação SRT com BOM, CRLF e texto multilinha; estilo em lote com fonte,
tamanho, cor, fundo e posição; undo/redo e pistas bloqueadas. Exportação SRT/VTT
existente reaproveitada. A tela de atalhos foi preservada, ampliada com referência
às combinações adicionais e testada com remapeamento por eventos reais.

A configuração da marca também gera SVG/PNG/ICO e cabeçalho Windows, corrigindo
o ícone e metadados nativos que ainda exibiam TGI. A última execução de
`tool/test_editor.ps1 -Integration -Build`, depois dessa correção, concluiu:

- `flutter pub get`: exit 0.
- `flutter analyze --no-pub`: exit 0, sem problemas (6,0 s).
- `flutter test --no-pub`: exit 0, 160 aprovados e 13 opcionais ignorados.
- Testes com `TGI_RUN_FFMPEG_INTEGRATION_TESTS=true`: exit 0, 173 aprovados,
  sem falhas/ignorados. O render real registrou CPU e NVIDIA NVENC nesta máquina.
- `flutter build windows --release --no-pub`: exit 0, 110,4 s; avisos CMake do
  plugin media_kit continuam presentes.
- 64 arquivos do build copiados para `aplicativo/` e comparados por SHA-256,
  sem divergências. ProductName/FileDescription/CompanyName do executável lidos
  e confirmados como Frame Studio. Versão de pacote mantida em 0.2.0+2.
- Todos os scripts PowerShell passaram pelo parser, inclusive o gerador da marca.

Logs finais: `.work/etapa9-final-branded-checks-build.log`. A opção somente áudio
é transitória e não adiciona campos ao projeto; testes confirmam leitura e
round-trip do v14. Detalhes de uso e limites: docs/EXTRAS.md.

## CI remoto executado

O [workflow da etapa 7](https://github.com/Losfodabr12/tgi-video-editor/actions/runs/39405929902)
terminou com **success** em windows-latest, Flutter 3.44.4: setup das ferramentas,
pub get, analyze, testes padrão, integração e build. Esse run corresponde ao
commit `4ab5d0b`, anterior às etapas 8/9; não é apresentado como validação remota
dessas alterações posteriores. O status do commit mais recente fica em
[Actions](https://github.com/Losfodabr12/tgi-video-editor/actions/workflows/ci.yml).

## Limites e trabalho não realizado

- A revisão de paridade documenta aproximações; não há garantia de pixels
  idênticos entre Flutter/media_kit e todos os filtros FFmpeg.
- Dissolves respeitam o modelo global v14. Não foram criados transições por
  par/pista com novo schema nem handles externos ao trim; bordas são repetidas.
- Controlador e tela foram divididos por responsabilidades, mas ainda concentram
  fluxos de orquestração. Não houve reescrita total da arquitetura ou mudança
  de framework de estado.
- Não há quota automática para todos os caches; o benchmark usa uma fonte
  sintética de 5 s e uma medição por operação. Não é benchmark de FPS da UI.
- Só áudio usa WAV PCM. SRT transporta texto/tempo, não o estilo visual do projeto.
- Não se validou hardware Intel QSV ou AMD AMF real. Seus caminhos de falha e
  fallback foram simulados; o render CPU de fallback foi executado de verdade.
- Não foi publicada nova release binária no GitHub. O código está na branch
  de trabalho e o executável local foi atualizado; a release v0.1.0 é histórica.

## Sessão manual ainda necessária na janela nativa

Não foi executada uma sessão audiovisual manual nesta tarefa. Ainda é preciso
conferir reprodução/seek e sincronismo percebido, dissolve com efeitos/camadas,
qualidade das bordas de chroma/máscaras, diálogos e escalas de tela, captura de
atalhos, fluxo de importação SRT/estilo e destinos de exportação. Também faltam
edição prolongada/4K com mídia de câmera, CPU/GPU/RAM em uso real, exportações
longas por fabricante de GPU, transcrição de voz completa com Whisper e uma
sessão com o adaptador de rede desligado. Build/testes não substituem esses usos.


## Etapa 10 — Visual

Concluída antes de iniciar a etapa 11. Tokens únicos em
`source/lib/app/theme/design_tokens.dart`: superfícies `#101216`, `#20242B`,
`#343B46`, destaque `#82D9B0`, espaçamento em múltiplos de 4 e raios 2/4/6.
Interface com Lato regular/bold incluída no pacote (OFL), Material Icons,
`VisualDensity.compact`, bordas finas e sem sombras/gradientes decorativos.
As fontes e efeitos escolhidos para o conteúdo do vídeo foram preservados.

Timeline com cores por tipo, thumbnails, waveform, régua e playhead sem blur.
O snapping exibe uma borda e a indicação SNAP no ponto correspondente.
Os divisores existentes foram preservados e ganharam identificação para testes;
o arraste dos três divisores e a restauração após fechar/reabrir o editor foram
executados com gravação real em um arquivo de preferências isolado. Nenhuma
alteração no formato v14: dimensões ficam em `editor_layout.json`.

Foram adicionados cinco goldens headless: editor vazio, propriedades de texto,
exportação, atalhos e timeline com snapping ativo. O teste da timeline espera
as imagens decodificarem, fornece samples determinísticos de áudio, arrasta um
clipe e verifica o encaixe real em 4 s. O bootstrap dos testes carrega os bytes
da fonte usada no app; os testes anteriores continuam sem edição.

Comandos finais executados pelo drive curto do build:

- `flutter analyze --no-pub`: exit 0, sem problemas, 3,6 s.
- `flutter test --no-pub`: exit 0, 167 aprovados / 13 opcionais ignorados, 19 s.
- `flutter test --no-pub test/visual_golden_test.dart --update-goldens`:
  exit 0; referências geradas. A suíte completa acima comparou essas referências
  novamente, sem `--update-goldens`, e passou.
- Logs: `.work/etapa10-analyze.log`, `.work/etapa10-test.log`.

Houve falhas intermediárias de overflow e de altura do transporte; foram
corrigidas no código e a suíte inteira foi repetida. Não se avançou para a
etapa seguinte com falhas. As capturas abaixo foram renderizadas pelos widgets
reais a 1440×900; não são fotos de uma sessão na janela nativa. O texto TGI da
cena é conteúdo do projeto histórico de teste, igual nas duas capturas.

| Antes | Depois |
| --- | --- |
| ![Antes](docs/visual/editor-before.png) | ![Depois](docs/visual/editor-after.png) |

![Timeline após a alteração](source/test/goldens/timeline_snapping.png)

Detalhes e reprodução em [docs/VISUAL.md](docs/VISUAL.md). DPI/monitores,
interação contínua com mouse e reprodução audiovisual ainda exigem a janela
nativa.
