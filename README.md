# TGI Video Editor

Editor desktop para Windows em Flutter, derivado do editor TGI 1.4.26+33.
A versão **0.2.0+2**, na branch `main`, reformula a timeline, a composição de
camadas e o workspace. Para revisão externa, comece pela
[análise rápida de 20/10/2026](ANALISE_RAPIDA.md). Veja também
[a implementação, testes e limites](REFORMULACAO.md).

## Executar

Na cópia de trabalho, abra **INICIAR EDITOR.cmd** ou **aplicativo/VideoEditor.exe**.
Os arquivos de runtime devem acompanhar o executável.

A [release pública v0.1.0](https://github.com/Losfodabr12/tgi-video-editor/releases/tag/v0.1.0)
contém a base anterior. O código da reformulação está na branch `main`; seu
executável foi compilado localmente e não tem nova release publicada.
O pacote inicial inclui FFmpeg, ffprobe, Whisper Base, fontes e bibliotecas nativas.

## Recursos

- Pistas dinâmicas visuais e de áudio, com vídeo/imagem/texto na mesma camada.
- Clipes vinculados, movimento entre pistas, snapping e criação de camada por arraste.
- Trim, cortes, ripple delete, seleção múltipla, copiar/colar, duplicar e undo/redo.
- Biblioteca em abas, prévia central, inspetor contextual e timeline redimensionável.
- Composição de múltiplas camadas no preview e no FFmpeg, com ordem explícita.
- Projetos formato 14, migração dos formatos anteriores e recuperação de rascunhos.
- Ferramentas existentes de cor, chroma, máscaras, animação, áudio e legendas locais.

## Desenvolver no Windows

Ambiente usado: Flutter 3.44.4 / Dart 3.12.2, Git e Visual Studio com C++ desktop.
Trabalhe em `source`. FFmpeg e Whisper precisam estar em:

```text
source/tools/ffmpeg/bin/ffmpeg.exe
source/tools/ffmpeg/bin/ffprobe.exe
source/tools/whisper/bin/whisper-cli.exe
source/tools/whisper/models/ggml-base.bin
```

Para obter os runtimes de uma instalação do pacote inicial, copie suas pastas
`ffmpeg` e `whisper` para `source/tools`, preservando os arquivos já presentes.

```powershell
cd source
flutter pub get
powershell -ExecutionPolicy Bypass -File tool\build_editor.ps1 -Run
```

Para compilar e atualizar `aplicativo/`, execute o mesmo script sem `-Run`.
Ele usa temporariamente uma unidade livre para evitar MAX_PATH nos plugins
nativos do Windows e libera a unidade ao terminar.

## Verificação

```powershell
flutter analyze --no-pub
flutter test --no-pub --dart-define=TGI_RUN_FFMPEG_INTEGRATION_TESTS=true
```

Revalidação em 20/10/2026: **145 testes aprovados, nenhum ignorado** e análise sem
problemas. Release Windows 0.2.0+2 compilada em 18/10/2026. A verificação adicional de
widgets/índice passou em 12 testes. A captura gráfica nativa ficou em branco no
ambiente, inclusive na versão anterior; a aprovação visual nativa permanece
pendente. Os widgets reais foram renderizados e inspecionados nos testes.

## Estrutura e dados

`source/lib/domain/` contém projeto, pistas, clipes e operações transacionais;
`source/lib/features/editor/` contém controlador e interface;
`source/lib/services/` contém importação, arquivos, áudio e exportação;
`source/test/` contém as regressões. Configurações e rascunhos ficam em
`%LOCALAPPDATA%\TGI_VIDEO_EDITOR`, separados do projeto TGI original.

Os estúdios completos de áudio/imagem, site e servidor do TGI não fazem parte
desta cópia. Regras de recursos e integrações opcionais TGI preexistentes foram
preservadas. Componentes de terceiros mantêm suas licenças e avisos.
