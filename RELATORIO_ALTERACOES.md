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

Os 13 testes históricos opcionais dependem de um dart-define e são ignorados
pelo comando padrão pedido. Os seis novos testes de pixels rodam por padrão.
A etapa 1 teve falhas intermediárias nos testes novos; foram corrigidas e os
dois comandos repetidos antes do commit. Asserções de máscara respeitam o
escurecimento por luminância YUV, que difere do preview RGB.

Ainda requer teste manual: janela nativa, reprodução, GPU, sincronismo
audiovisual percebido e diferenças de rasterização descritas em docs/PARIDADE.md.

## Etapa 3

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
