# Relatório de alterações

O texto completo, incluindo os resultados remotos da release 0.3.0, está
disponível neste arquivo do repositório público. Não é necessário baixar
um asset de release para lê-lo. Os registros abaixo identificam o SHA que
foi executado; esta publicação posterior serve para facilitar a revisão.

Execução por etapas na ordem solicitada (a lista recebida não contém etapa 2).
Formato de projeto preservado em v14. Resultados locais e remotos são identificados em cada seção. Logs locais
completos ficam em `.work/`, ignorada pelo Git.

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
- A etapa 11 acrescenta publicação Windows por tag; o resultado executado fica
  na seção da etapa 11 e no relatório que acompanha o artefato/release.

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


## Etapa 11 — Release 0.3.0

Versão do pacote elevada para **0.3.0+3**; versão do projeto permanece **14**.
CI Windows / Flutter 3.44.4 agora empacota o build e publica ZIP, SHA256SUMS e
relatório como artefato. `release.yml`, disparado por tag `v*`, reutiliza esse
mesmo CI e publica GitHub Release apenas depois do sucesso do build. Tag e
versão do executável/pubspec precisam corresponder. Checkout 7.0.1, cache
6.1.0, upload 7.0.2 e download 8.0.2 usam Node 24; os manifests foram lidos
pela API do GitHub. O cache interno da action Flutter usa cache v5 / Node 24.

Ao sobrescrever projeto migrado, o original fica em `.bak`, sem reserializar
seus bytes. Gravações seguintes preservam esse primeiro backup. A proteção
cobre formatos anteriores, sobreposições de versões iniciais do v14 e grupos
de legendas normalizados, sem novos campos de projeto. Os novos testes
executaram v13/v14, Save As, concorrência, persistência por outra instância e
entrada corrompida; os testes anteriores de falha e rollback também passaram.

`tool/test_editor.ps1 -Integration -Build` executado pelo mesmo caminho curto:

| Comando | Resultado local final |
| --- | --- |
| `flutter pub get` | exit 0 |
| `flutter analyze --no-pub` | exit 0, sem problemas, 5,9 s |
| `flutter test --no-pub` | exit 0, 172 aprovados / 13 opcionais ignorados, 25 s |
| `flutter test --no-pub --dart-define=TGI_RUN_FFMPEG_INTEGRATION_TESTS=true` | exit 0, 185 aprovados / zero ignorados, 30 s |
| `flutter build windows --release --no-pub` | exit 0, 113,4 s |

Log: `.work/etapa11-checks-build.log`. Os avisos CMake CMP0175 do media_kit
continuam presentes; não são avisos de Node 20. Os scripts PowerShell também
passaram pelo parser. A comparação dos goldens é parte das duas suítes acima.

A última repetição ao fim da etapa também passou: analyze sem problemas
(5,1 s) e 172 testes padrão aprovados / 13 opcionais ignorados (27 s).
Logs: `.work/etapa11-final-analyze.log`, `.work/etapa11-final-test.log`.

O ZIP local foi gerado, extraído e seus **91 arquivos** conferidos contra o
manifesto SHA-256. Executável extraído: ProductVersion **0.3.0+3**.
FFmpeg `-version` e Whisper CLI `-h` extraídos executados com exit 0. Isso
verifica inicialização dos runtimes, não transcrição completa de voz.
`aplicativo/` foi atualizado e os mesmos 91 arquivos foram comparados, sem
divergências. ZIP local de conferência: 251.917.295 bytes, SHA-256
`b94863027e3c775085aa6ecc8a72cbd58f55eb20a7bd3ce5f74e5c0037a43b43`.
Esse ZIP foi criado antes do commit da etapa 11; o manifesto registra essa
condição com `workingTreeDirty`. O CI recompila o commit final e gera seu
próprio ZIP/checksum; não se presume igualdade binária entre máquinas.
Log: `.work/etapa11-package.log`.

### FFmpeg baixado e licença

Build fixado **8.1.2-essentials_build-www.gyan.dev**, Windows x64 estático,
GCC 16.1.0, [ZIP Gyan 8.1.2](https://github.com/GyanD/codexffmpeg/releases/download/8.1.2/ffmpeg-8.1.2-essentials_build.zip).
SHA-256 do ZIP baixado conferido novamente:
`db580001caa24ac104c8cb856cd113a87b0a443f7bdf47d8c12b1d740584a2ec`.
`ffmpeg -version` e `ffmpeg -L` foram executados; configuração contém
`--enable-gpl --enable-version3 --enable-static`. Licença declarada pelo
executável: **GNU GPL v3 ou posterior**. O pacote preserva LICENSE/README.
Fontes do build: commit FFmpeg `38b88335f9`, indicado no README do distribuidor.
Detalhes e links em [docs/THIRD_PARTY.md](docs/THIRD_PARTY.md).

### Contagem pedida, executada com wc

Comando real (`wc.exe` do Git for Windows):

```text
wc -l source/lib/services/ffmpeg_service.dart source/lib/features/editor/application/editor_controller.dart source/lib/features/editor/presentation/editor_screen.dart
  2267 source/lib/services/ffmpeg_service.dart
  6072 source/lib/features/editor/application/editor_controller.dart
  3689 source/lib/features/editor/presentation/editor_screen.dart
 12028 total
```

Esses números deixam explícito que controlador e tela ainda são grandes,
apesar da extração de módulos nas etapas anteriores. Não se declara uma
reescrita completa deles. Log: `.work/etapa11-wc.log`.

### Evidência remota e entrega

A etapa visual `403aabf` também passou no
[CI remoto](https://github.com/Losfodabr12/tgi-video-editor/actions/runs/39497056306).
O CI gerou **depois dos comandos** uma cópia deste relatório com o SHA exato
e o run executado. O resultado concluído está transcrito integralmente abaixo,
para leitura direta no repositório. Há também cópias no ZIP, no artefato
`frame-studio-windows-x64` e na release.
[Workflow e runs](https://github.com/Losfodabr12/tgi-video-editor/actions/workflows/ci.yml).

<!-- CI_RESULT_START -->
## Resultado remoto do commit da release — conferido após conclusão

Commit **`e407885c086d4d06b49f0925bb14100965f60c44`**, tag **v0.3.0**.
Estado consultado pela API do GitHub depois de ambos os workflows terminarem:

| Execução | Estado remoto final |
| --- | --- |
| [CI da branch main — 39498721935](https://github.com/Losfodabr12/tgi-video-editor/actions/runs/39498721935) | **completed / success** |
| [Release por tag — 39498725045](https://github.com/Losfodabr12/tgi-video-editor/actions/runs/39498725045) | **completed / success**, jobs build e publish aprovados |

Logs remotos lidos: analyze sem problemas (17,3 s no CI main), **172 testes
padrão aprovados / 13 opcionais ignorados**, **185 aprovados com integração**,
build Windows aprovado (168,6 s no CI main), empacotamento e upload aprovados.
A execução da tag registrou os mesmos totais de testes. Busca nos logs dos
dois runs por Node.js 20 / Node20 / node20: **zero ocorrências**. Os avisos
CMake do media_kit continuam presentes. O watcher auxiliar encontrou HTTP 502
nas anotações; a consulta direta posterior e os logs confirmaram sucesso.

Artefato do CI main: `frame-studio-windows-x64`, ID **12299935483**, 299.080.856
bytes, disponível no run. [Release publicada](https://github.com/Losfodabr12/tgi-video-editor/releases/tag/v0.3.0),
sem draft/prerelease. O ZIP da release foi baixado e extraído nesta máquina:

- `FrameStudio-0.3.0-windows-x64.zip`: **299.061.481 bytes**.
- SHA-256: `e5de95a56b701ffde863ad3bda9bc26bb768d712bbe57830a6616f4f8db99be3`,
  igual a SHA256SUMS.txt e ao digest informado pelo GitHub.
- **120 arquivos** conferidos contra o manifesto do ZIP, sem divergências.
- `BUILD_INFO.json` identifica o commit acima; ProductVersion do EXE
  extraído **0.3.0+3**. O manifesto registra `workingTreeDirty=true` após a
  preparação; o diff remoto não foi capturado, portanto não se afirma que
  todos os arquivos gerados pelo build permaneceram iguais ao checkout.
- FFmpeg extraído: **8.1.2-essentials_build-www.gyan.dev**; `-version` e `-L`
  executados com exit 0, GPL v3 ou posterior confirmado no binário.
- Whisper CLI extraído: `-h` executado com exit 0. Não houve transcrição
  completa de voz nem sessão audiovisual manual na janela nativa.

Este resultado pós-CI foi incorporado ao relatório local, ao asset da release
e agora ao texto versionado, a pedido de disponibilizar a leitura sem assets.
As etapas 10 e 11 foram entregues em commits separados; esta publicação
adicional contém documentação. As aprovações acima correspondem ao commit
`e407885`, identificado nos dois runs, e não são apresentadas como resultados
de uma nova execução para este commit posterior de documentação. O relatório
dentro do ZIP registra os checks quando executados e aponta para o mesmo run.

Evidências locais: `.work/final-ci-remote.log`, `.work/final-release-remote.log`,
`.work/final-remote-results.json`, `.work/final-package-results.json`.
<!-- CI_RESULT_END -->

### Teste manual ainda necessário

Não foi executada sessão audiovisual na janela nativa. Continuam pendentes
playback/seek e sincronismo percebido, DPI/monitores, interação contínua com
mouse, exportação longa por fabricante de GPU, transcrição completa de voz e
uso com adaptador de rede desligado. O ZIP conter runtimes locais e CRT não
substitui teste em uma instalação Windows limpa. Goldens são headless.
