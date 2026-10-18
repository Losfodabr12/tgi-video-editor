# Editor de Vídeo

Editor de vídeo para Windows construído com Flutter, separado do editor TGI
1.4.26+33 como base para um aplicativo independente.

## Baixar o aplicativo

Baixe o arquivo **Editor-de-Video-Windows-v0.1.0.zip** na
[release v0.1.0](https://github.com/Losfodabr12/tgi-video-editor/releases/tag/v0.1.0),
extraia a pasta inteira e abra **VideoEditor.exe**.
O pacote inclui FFmpeg, ffprobe, Whisper Base, fontes e bibliotecas nativas.

## Recursos

- Timeline com múltiplas trilhas de vídeo, áudio, imagem e texto.
- Cortes, ajustes de duração, transições, efeitos e chroma key.
- Preview, legendas automáticas locais e exportação por FFmpeg.
- Fontes incluídas, histórico de versões e modelos de projeto.
- Recuperação de rascunhos e configurações próprias do aplicativo.

## Desenvolver no Windows

Requisitos: Flutter 3.44.4 / Dart 3.12.2 ou uma versão compatível, Git e
Visual Studio com as ferramentas de desenvolvimento desktop em C++.

```powershell
git clone https://github.com/Losfodabr12/tgi-video-editor.git
cd tgi-video-editor
```

Os executáveis do FFmpeg e o modelo Whisper são distribuídos na release.
Antes de compilar, extraia o ZIP do aplicativo e copie suas pastas **ffmpeg** e
**whisper** para **source/tools**, mantendo os arquivos existentes. O resultado
deve incluir:

```text
source/tools/ffmpeg/bin/ffmpeg.exe
source/tools/ffmpeg/bin/ffprobe.exe
source/tools/whisper/bin/whisper-cli.exe
source/tools/whisper/models/ggml-base.bin
```

Para executar durante o desenvolvimento:

```powershell
cd source
powershell -ExecutionPolicy Bypass -File tool\build_editor.ps1 -Run
```

Para gerar a versão de distribuição:

```powershell
powershell -ExecutionPolicy Bypass -File tool\build_editor.ps1
```

O script usa temporariamente uma unidade livre para evitar o limite de caminhos
dos plugins nativos no Windows. O resultado fica em **aplicativo/**, fora do Git.

## Estrutura

```text
source/lib/main.dart           Inicialização do aplicativo
source/lib/app/                Aplicativo e tema
source/lib/features/editor/    Interface e controlador do editor
source/lib/domain/             Modelos de projeto e timeline
source/lib/services/           Exportação, arquivos, áudio e bibliotecas
source/assets/                 Fontes, shaders e recursos visuais
source/third_party/            Dependência local do FFmpeg Kit
source/windows/               Projeto nativo Windows
source/test/                  Testes do editor
source/tool/                  Compilação e empacotamento
```

## Verificação

A base foi validada com análise estática sem problemas, **96 testes aprovados**
e build Windows release. Sete testes de integração ficaram desativados pela
configuração padrão. Os comandos para repetir análise e testes em `source` são:

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
```

## Estado desta base

Esta versão abre diretamente no editor e mantém seus dados em
`%LOCALAPPDATA%\TGI_VIDEO_EDITOR`. Os estúdios completos de áudio e imagem,
o site e o servidor do TGI não fazem parte deste projeto.

A marca visual e as regras de recursos gratuitos/pagos do editor de origem
foram preservadas. O diálogo de downloads opcionais ainda contém integrações
com serviços TGI. São pontos disponíveis para adaptação no novo aplicativo.

Os componentes de terceiros acompanham suas respectivas licenças e avisos nas
pastas correspondentes do código e do pacote de distribuição.
