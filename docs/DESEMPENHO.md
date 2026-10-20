# Desempenho medido

Execução em **20/10/2026, 10:14:30 UTC**, Windows 11 Pro build 26200,
AMD Ryzen 5 5500, 12 processadores lógicos, Flutter 3.44.4 / Dart 3.12.2.
FFmpeg 8.1.2. Resultado bruto: [performance-results.json](performance-results.json).

O benchmark realmente gerou, decodificou e exportou mídia. A fonte é sintética:
`testsrc2` 1920×1080, 30 fps, 5 segundos, H.264/AAC com tom de 440 Hz.
Não é uma medição de edição prolongada com vídeos de câmera nem de FPS da UI.
Cada operação foi medida **uma vez** por Stopwatch; carga da máquina e cache
do sistema operacional influenciam. A geração da fonte não entra na tabela.
As medições de metadados incluem ffprobe e verificação de ferramentas.

| Operação executada | Tempo (ms) |
| --- | ---: |
| Metadados + thumbnail, cache ausente | 292,312 |
| Metadados + thumbnail, nova instância lendo disco | 183,263 |
| Waveform, extração por FFmpeg | 158,261 |
| Waveform, nova instância lendo disco | 9,332 |
| Construção do proxy | 435,509 |
| Proxy já concluído em disco | 1,349 |
| Decodificação completa da fonte | 279,571 |
| Decodificação completa do proxy | 176,971 |
| Exportação completa em 720p, CPU | 1002,469 |

Fonte: 11.360.001 bytes. Proxy: 966.192 bytes. Os contadores confirmaram um
hit de thumbnail e um hit de waveform em instâncias novas, sem usar o cache
em memória da instância anterior. Não se mediram NVENC, QSV ou AMF aqui.

## Implementação

- Proxies persistem em `cache/proxies`, com publicação atômica após conclusão,
  30 fps e escala dentro de 960×540, preservando proporção e dimensões pares.
  Um teste exporta proxy vertical e confere proporção e pixels sem barras.
- Thumbnails JPEG de 320 px e waveforms JSON persistem em `cache`, dentro do
  diretório local do aplicativo. Corrupção de JPEG/JSON provoca regeneração.
- A chave SHA-256 usa caminho, tamanho, data de modificação e versão/parâmetros
  do processamento. Não é um hash integral do conteúdo da mídia. Alterar o
  arquivo mantendo exatamente tamanho e mtime não é detectado por essa chave.
- Cache indisponível não deve impedir waveform/importação. Os arquivos originais
  são usados na exportação; o proxy é destinado ao preview.
- Não há quota automática para todos os caches. Podem ser removidos com o
  editor fechado; a mídia original e os projetos ficam fora desses caches.

Testes cobrem reabertura, parâmetros, modificação de fonte, corrupção, proxy
vertical, reaproveitamento e ausência de arquivos temporários publicados.

## Reproduzir

Após setup das ferramentas, em um caminho curto com `source` como diretório:

```powershell
flutter test --no-pub tool/benchmark_editor.dart --reporter expanded
```

O helper `Invoke-EditorShortPath` em `tool/editor_paths.ps1` prepara esse caminho.
O benchmark grava `.work/performance-results.json` e preserva os artefatos da
execução em `.work/performance/`. O teste está fora de `test/` e não roda na suíte
padrão. Não se extrapolam esses tempos para 4K, GPU, RAM ou fluidez nativa.
