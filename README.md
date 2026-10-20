# Frame Studio

Editor de vídeo offline para Windows em Flutter, derivado do editor TGI.
Pacote **0.2.0+2**, projetos **v14**, código atual na branch `main`.
Para revisar esta implementação, comece pelo
[relatório das etapas e resultados reais](RELATORIO_ALTERACOES.md).

[Paridade](docs/PARIDADE.md) · [Build e CI](docs/BUILD.md) ·
[Migração](docs/MIGRACAO.md) · [Desempenho medido](docs/DESEMPENHO.md) ·
[Presets, legendas e atalhos](docs/EXTRAS.md).

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
- Dissolve A/B com xfade/acrossfade, preservando a duração da timeline.
- Presets YouTube/4K/9:16/1:1/WAV, GPU automática e fallback CPU.
- Importação/exportação SRT e edição do estilo das legendas.
- Caches persistentes de proxies, miniaturas e waveform.

## Desenvolver no Windows

Ambiente usado: Flutter 3.44.4 / Dart 3.12.2, Git e Visual Studio com C++ desktop.
Trabalhe em `source`. FFmpeg e Whisper precisam estar em:

```text
source/tools/ffmpeg/bin/ffmpeg.exe
source/tools/ffmpeg/bin/ffprobe.exe
source/tools/whisper/bin/whisper-cli.exe
source/tools/whisper/models/ggml-base.bin
```

Na raiz, `tool/setup_tools.ps1` prepara os runtimes e o modelo Base, com
SHA-256 conferido. Também é possível copiar uma instalação existente.

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

Verificação final das etapas: análise sem problemas, **160 testes padrão
aprovados / 13 opcionais ignorados** e **173 aprovados com integração habilitada**.
Logs, builds e resultado do CI estão no [relatório](RELATORIO_ALTERACOES.md).
Não foi declarada aprovação visual da janela nativa, GPU ou sincronismo percebido.

## Estrutura e dados

`source/lib/domain/` contém projeto, pistas, clipes e operações transacionais;
`source/lib/features/editor/` contém controlador e interface;
`source/lib/services/` contém importação, arquivos, áudio e exportação;
`source/test/` contém as regressões. Configurações e rascunhos ficam em
`%LOCALAPPDATA%\TGI_VIDEO_EDITOR`, separados do projeto TGI original.

Os estúdios completos de áudio/imagem, site e servidor do TGI não fazem parte
desta cópia. Integrações TGI estão isoladas sob `EDITOR_STANDALONE=false`;
o padrão independente dispensa conta, plano e rede durante a edição.
Componentes de terceiros mantêm suas licenças e avisos.
