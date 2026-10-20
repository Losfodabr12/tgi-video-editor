# Relatório de alterações

Execução por etapas na ordem solicitada (a lista recebida não contém etapa 2).
Formato de projeto preservado em v14. Resultados abaixo são de comandos
executados nesta máquina; logs completos ficam em `.work/`, ignorada pelo Git.

| Etapa | analyze --no-pub | test --no-pub | Resultado |
| --- | --- | --- | --- |
| 1 — Paridade | exit 0, sem problemas | exit 0, 138 aprovados / 13 ignorados | Frames FFmpeg, correção de dessaturação por máscara e docs/PARIDADE.md |
| 3 - Refatoracao | exit 0, sem problemas | exit 0, 141 aprovados / 13 ignorados | Builder puro, executor/parser, historico, legendas, preview e atalhos |

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
