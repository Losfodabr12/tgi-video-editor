# Relatório de alterações

A revisão mais recente está em [Ajuste curto](#ajuste-curto--legendas-layout-e-diagnóstico-do-ci),
com os comandos executados e as capturas antes/depois. Os resultados das etapas
anteriores permanecem como histórico, vinculados aos respectivos commits.

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

## Ajuste visual adicional — 20 de outubro de 2026

Alteração preparada como um único commit sobre `54252ac`. O formato v14,
os modelos, os tempos dos clipes e o export permanecem preservados; nenhum
arquivo de domínio ou serviço de persistência foi alterado neste ajuste.

### O que mudou

1. Tokens centralizados com fundo `#0E0F11`, painéis `#15171A`, controles
   `#1C1F23`, hover `#262A30`, bordas `#2A2E34`, texto `#E6E8EB`, secundário
   `#A0A7B1` e destaque `#34C38F`. Clipes foscos de vídeo `#3B5B8C`, áudio
   `#2F7D6B`, texto `#6B5BA8` e efeitos/transições `#A0653B`. Imagens usam
   o azul dos visuais. Saíram o dourado do texto e as bordas bege. A seleção
   mantém a cor do tipo e recebe contorno verde de 2 px, também no preview.
   Toggles ligados usam superfície elevada neutra; ícones auxiliares,
   sliders, waveform e indicadores de ferramentas deixaram de usar verde.
   A seleção por retângulo perdeu o blur e usa contorno de 2 px.
2. Abas da biblioteca passaram de 9 para 12 px. Rótulos secundários,
   controles pequenos, tempos do preview e indicadores de mídia ganharam
   tamanho/contraste. A aba Transições recebeu mais largura. Corte,
   Excluir e Texto usam o mesmo estilo, com rótulos de 13 px.
3. Layout padrão com aproximadamente 45% da altura de trabalho para a
   timeline. O mínimo considera cabeçalho/régua e três trilhas completas;
   testes conferem a principal entre elas em 1440×900 e 1280×720. Em janelas
   muito baixas ou trilhas muito altas ainda é necessário scroll. O resize
   e a persistência das proporções continuam funcionando. Sem seleção, o
   inspetor mostra nome, resolução de saída, fps, duração e número de trilhas.
4. Régua e grade escolhem intervalos pelo zoom, com pelo menos 96 px entre
   rótulos principais, milissegundos em detalhe e horas em projetos longos.
   Geram somente a faixa visível com margem, em vez de todos os rótulos do
   projeto. Teste cobre seis horas em cinco escalas diferentes.
5. Voltar/play/avançar ficam centralizados no preview. Ferramentas ocupam
   um grupo separado à esquerda; velocidade e proxy ficam à direita.
6. Slider logarítmico de zoom entre 0,5% e 3200%, preservando o ponto de
   referência e Ctrl + roda. A linha de instruções I/O saiu da timeline;
   ações e estado do trecho ficam nos tooltips dos ícones de marcar início/fim.
7. A diferença **04:53 / 04:58 era um bug no contador**: a timeline exibia
   `_timelineExtent`, que acrescenta cinco segundos de espaço de edição,
   enquanto o preview exibia `project.timelineDuration`. O contador agora
   recebe a duração real; somente o canvas mantém a folga. Um teste abre
   um projeto de 293 segundos e confere **04:53** no preview, timeline e
   propriedades. Os tempos do projeto e do arquivo exportado não mudaram.

Detalhes: [docs/VISUAL.md](docs/VISUAL.md). Preferências de layout continuam
separadas do projeto, em `editor_layout.json`, versão de layout 3.

### Antes e depois

Mesma cena, 1440×900, escala 1. Capturas reais de widgets headless com a
fonte e os ícones carregados do repositório/SDK. O título TGI é conteúdo
do projeto histórico de teste, mantido para permitir comparação.

| Antes deste ajuste | Depois deste ajuste |
| --- | --- |
| ![Antes](docs/visual/editor-after.png) | ![Depois](docs/visual/editor-refined.png) |

![Régua ampliada, inspetor de projeto e duração 04:53](source/test/goldens/editor_zoomed.png)

### Validação executada neste ajuste

Windows, Flutter **3.44.4** / Dart **3.12.2**, pelo mesmo drive curto usado
no build. Todos os comandos abaixo terminaram com exit 0:

| Comando | Resultado real |
| --- | --- |
| `flutter test --no-pub test/visual_golden_test.dart test/visual_refinement_test.dart --update-goldens` | **13 aprovados**, 8 s; seis imagens golden atualizadas, incluindo a nova régua ampliada |
| `flutter analyze --no-pub` | **Sem problemas**, 12,6 s |
| `flutter test --no-pub` | **178 aprovados / 13 opcionais ignorados**, 27 s; comparação dos goldens executada sem `--update-goldens` |
| `flutter build windows --release --no-pub` | **Build Windows aprovado**, 53,1 s |

Os cinco testes novos de regressão conferem duração real, layout com três
trilhas, centralização, seleção de 2 px no preview/timeline, mudança da
régua pelo slider e temas neutros. O sexto teste novo é o golden do zoom.
Os testes anteriores não foram editados, exceto as referências visuais e
a fixture de goldens que agora inclui uma transição para exibir sua cor.
Os 13 opcionais de integração não foram habilitados nesta execução local;
os testes padrão de pixels FFmpeg foram executados pela suíte completa.

Logs locais: `.work/visual-polish-goldens-final.log`,
`.work/ajuste-visual-analyze.log`, `.work/ajuste-visual-test.log`.
Build em `.work/ajuste-visual-build.log`. O conteúdo de
`source/build/windows/x64/runner/Release` foi copiado para `aplicativo/`:
**66 arquivos conferidos por SHA-256, zero divergências**. O launcher
`INICIAR EDITOR.cmd` usa esse aplicativo atualizado, versão **0.3.0+3**.
SHA-256 do código compilado `data/app.so`:
`49e5041df1e100c14c3c761a6ef7d4c57497df0fea4f62e86b481d5106faf2b3`.
Este é um build local preparado antes do commit; a tag e o ZIP histórico
da release v0.3.0 não foram substituídos. O aplicativo não foi aberto para
teste manual.

Os resultados remotos da release registrados acima pertencem ao commit
`e407885`; não validam automaticamente esta revisão visual. O CI do ajuste
`4cfb586` foi consultado posteriormente pela API e concluiu com
**completed / success**:
[run 39504938174](https://github.com/Losfodabr12/tgi-video-editor/actions/runs/39504938174).
Esse resultado pertence ao ajuste anterior; o novo ajuste curto tem outro run.

Contagem atual, comando `wc -l` executado novamente:

```text
  2267 source/lib/services/ffmpeg_service.dart
  6072 source/lib/features/editor/application/editor_controller.dart
  3698 source/lib/features/editor/presentation/editor_screen.dart
 12037 total
```

### Teste manual pendente deste ajuste

Não foi executada sessão audiovisual na janela nativa. Conferir em uso real
o contraste em outros monitores/DPI, arraste contínuo do slider e divisores,
playback/seek, tooltips I/O e a abertura com proporções de layout já salvas.
O padrão 45% não sobrescreve proporções personalizadas existentes; duplo
clique no divisor restaura o layout padrão. Goldens não validam drivers,
GPU nem sincronismo audiovisual percebido.

## Ajuste curto — legendas, layout e diagnóstico do CI

Um único commit sobre `4cfb586`, mantendo o formato de projeto **v14**.

- Textos novos, legendas rápidas/automáticas e importações SRT usam
  **Lato Bold, branco, contorno preto de 2 px e sombra curta a 45%**.
  No preview, o contorno acompanha o canvas e a sombra tem blur de 1 px
  na referência 720p; no export, o contorno tem 2 px de saída e a sombra
  usa o antialiasing da fonte, sem blur extra. O novo preset `Lato Caption`
  usa o campo `fontFamily` já existente. Defaults de desserialização,
  famílias antigas e seus estilos não foram alterados. A escolha explícita
  de outra fonte/preset continua disponível. Preview e diálogos de estilo
  usam o mesmo widget para esse preset.
- Quatro trilhas de 64 px cabem inteiras no layout padrão em 1440×900.
  Em 1280×720 há scroll vertical com scrollbar fixa na área visível,
  independente do zoom horizontal. O teste rola até o fim, confere o áudio
  inteiro e verifica alinhamento com seu cabeçalho. Há margem inferior de
  12 px. Sem trilhas, a scrollbar não tenta usar um controlador desconectado.
- Preferências de layout anteriores à versão 3, ou com menos de 45% para
  a timeline, são normalizadas para 45% e gravadas como layout v3. Não se
  trata de migração do arquivo de projeto. A altura mínima e a rolagem
  continuam funcionando em janelas menores. Proporções válidas são preservadas.
- Toolbar com divisores de edição / snapping / marcadores / navegação.
  Tooltips e tela de atalhos indicam V/Y/U, N, M, F, L, A, Shift+Delete,
  I/O, setas e Ctrl + roda. Os atalhos funcionam e respeitam campos de
  texto, diálogos e bindings personalizados existentes.
- Menu de qualidade/proxy com texto de 14 px, maior contraste e superfície
  elevada. Alças de texto usam a cor do clipe, clareiam no hover e mantêm
  a área de arraste. As alças de imagem mantêm sua cor anterior.
- Painéis laterais com padrão de **280 px** e mínimos de resize de
  200 px (biblioteca) / 220 px (inspetor), liberando espaço ao preview.
- CI passa a executar `git status --porcelain` e `git diff --stat` em um
  passo com `if: always()` logo após analyze/test/build. Isso permitirá
  identificar os arquivos que causam `workingTreeDirty=true`; a causa
  remota ainda não foi confirmada nesta revisão. Não se declara que o
  novo passo já rodou no GitHub antes do push.

### Capturas desta revisão

Goldens reais, headless, 1440×900. A comparação histórica do ajuste anterior
permanece acima; as imagens abaixo mostram os casos novos desta revisão.

![Quatro trilhas, áudio inteiro e painéis de 280 px](source/test/goldens/editor_four_tracks.png)
![Legenda nova sobre cena clara e escura](source/test/goldens/caption_contrast.png)

### Comandos executados

Windows, Flutter 3.44.4 / Dart 3.12.2, caminho curto `V:\source`:

| Comando | Resultado real |
| --- | --- |
| `flutter test --no-pub test/visual_golden_test.dart --update-goldens` | **10 aprovados**, 8 s; oito goldens, incluindo os dois novos |
| `flutter analyze --no-pub` | **Sem problemas**, exit 0, 3,8 s |
| `flutter test --no-pub` | **187 aprovados / 13 opcionais ignorados**, exit 0, 29 s; goldens comparados sem atualização |
| `flutter build windows --release --no-pub` | **Build Windows aprovado**, exit 0, 119,7 s |

O teste novo de FFmpeg exportou frames sobre fundos branco e preto e contou
pixels de contraste. O round-trip v14 preservou estilos antigos e o novo
preset. A rodada de regressão de layout/transporte teve **23 aprovados**.
Os testes anteriores permaneceram sem edição, exceto fixtures/referências
visuais e os dois casos acrescentados ao arquivo de goldens.

Houve falhas intermediárias: controlador de scrollbar sem trilhas e troca
de árvore durante inserção/undo foram corrigidos; o teste novo também exigiu
ajustes de timestamp e espera de I/O. Hooks nativos ficaram com um drive
temporário antigo após interrupção da rodada; `flutter clean` e `flutter pub get`
regeneraram os caches no mesmo caminho curto antes da repetição aprovada.
Uma captura isolada recebeu o ancestral Material para remover os sublinhados
de debug; os goldens e os dois comandos finais foram repetidos depois disso.

Logs: `.work/ajuste-curto-regressions.log`, `.work/ajuste-curto-goldens.log`,
`.work/ajuste-curto-analyze.log`, `.work/ajuste-curto-test.log`.
Os 13 opcionais de integração não foram habilitados localmente nesta rodada.
Os testes padrão de pixels FFmpeg foram executados.

O build foi copiado para `aplicativo/`: **65 arquivos comparados por SHA-256,
zero divergências**, ProductVersion **0.3.0+3**. O launcher local usa esse
build atualizado. A tag e o ZIP histórico v0.3.0 não foram substituídos.
Os avisos CMake CMP0175 do media_kit continuam presentes, sem impedir o build.
Log: `.work/ajuste-curto-build.log`; conferência da cópia em
`.work/ajuste-curto-local-build.json`. O executável não foi aberto para
sessão manual. `git status --porcelain` e `git diff --stat` também foram
executados localmente depois do build; logs em
`.work/ajuste-curto-status-after-build.log` e `.work/ajuste-curto-diff-after-build.log`.
O estado local incluía as alterações intencionais ainda não commitadas;
isso não identifica a causa do estado sujo no checkout remoto histórico.

`wc -l` foi executado novamente: FFmpeg service **2267**, controlador **6073**,
tela **3747** linhas; **12087** no total. Formato e serviços de persistência
do projeto não foram modificados.

Continua pendente teste audiovisual na janela nativa, contraste em monitores
e DPI diferentes, arraste contínuo de trim/scrollbar e uso com layout real
previamente salvo. Os resultados antigos de CI/release permanecem associados
aos SHAs identificados nas seções históricas.
