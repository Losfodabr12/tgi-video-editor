# Exportação, legendas e atalhos

## Presets e áudio

O diálogo de exportação oferece YouTube 1080p, 4K 2160p, vertical 9:16,
quadrado 1:1 e somente áudio WAV. Presets de vídeo escolhem GPU automática;
o campo Processamento permite CPU, NVENC, QSV e AMF. Há probe do encoder e
fallback CPU tanto na indisponibilidade quanto numa falha durante o render.

O preset de áudio escreve PCM estéreo, 48 kHz, sem stream de vídeo. É uma
opção de execução: **não adiciona campo ao formato v14** e volta ao modo
vídeo ao reabrir um projeto. Resolução, qualidade, FPS, encoder e trecho usam
a persistência anterior. Um teste confirma o comportamento com payload v14.

Os testes exportam frames nas dimensões reais dos quatro presets de vídeo,
inclusive 3840×2160; exportam WAV e inspecionam codec, streams e duração.
Falhas simuladas de NVENC/QSV/AMF e falha após probe testam retry por CPU com
arquivo real. A suíte histórica adicional executa CPU/GPU automática e registra
qual encoder foi usado. Simular indisponibilidade não valida hardware QSV/AMF.

## Legendas

Na aba Legendas, **Importar SRT** lê UTF-8 com BOM opcional, LF/CRLF, texto
multilinha e tempos em milissegundos. Um bloco inválido rejeita a importação
inteira. Os tempos originais são preservados, inclusive sobreposições.
**Estilo** edita fonte, tamanho, cor, fundo e posição vertical de todas as
legendas com uma operação de undo. Pistas bloqueadas impedem a alteração.
O inspetor existente continua permitindo editar cada texto individualmente.

Exportar SRT/VTT mantém texto e tempos; SRT não transporta o estilo visual do
projeto. Tags de markup presentes no texto não são interpretadas como estilo
tipográfico pelo novo importador. O estilo usa campos existentes de Clip e
é salvo/reaberto em v14 sem novo schema. Há testes de round-trip, bloqueio,
undo/redo e interação com o diálogo de estilo.

## Atalhos

Exibir → Atalhos abre a tela existente, agora em módulo próprio e com referência
às combinações adicionais de salvar, abrir, refazer, navegar por frame e marcar
trecho. Alterar captura eventos reais, detecta conflitos e permite restaurar
padrões. Mapeamentos personalizados têm prioridade. Um teste remapeia Desfazer
para Ctrl+P através dos eventos de teclado e confirma o resultado do diálogo.

## Identidade

`source/lib/app/app_identity.dart` define nome/nome curto, cores do ícone e
modo independente. `tool/generate_branding.ps1` gera SVG, PNG, ICO e o cabeçalho
nativo a partir desse arquivo; build e teste invocam o gerador. A marca TGI foi
substituída na interface, no ícone e no título/metadados de produto do Windows.
Nomes internos de pacote, `VideoEditor.exe`, diretório de dados e avisos legais
históricos foram preservados. Runtimes de terceiros mantêm suas licenças.

Ainda requer uso manual na janela nativa: escolha de destinos, diálogos com
escala de tela diferente, reprodução do dissolve, qualidade de cor/chroma,
sincronismo e exportações longas em cada GPU.
