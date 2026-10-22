# Runtimes distribuídos

## FFmpeg

`tool/setup_tools.ps1` baixa **Gyan Windows x64 static essentials 8.1.2**:
[ffmpeg-8.1.2-essentials_build.zip](https://github.com/GyanD/codexffmpeg/releases/download/8.1.2/ffmpeg-8.1.2-essentials_build.zip).
SHA-256 do ZIP: `db580001caa24ac104c8cb856cd113a87b0a443f7bdf47d8c12b1d740584a2ec`.
Não usa a URL mutável de "latest".

`ffmpeg -version` executado localmente identificou
`8.1.2-essentials_build-www.gyan.dev`, GCC 16.1.0, com `--enable-gpl`,
`--enable-version3`, `--enable-static`, libx264 e libx265. O `LICENSE` incluído
é a GNU GPL versão 3; `ffmpeg -L` informa GPL versão 3 ou posterior.
Este binário é **GPL-3.0-or-later**, não a variante LGPL mínima do FFmpeg.
[Documentação do distribuidor](https://www.gyan.dev/ffmpeg/builds/#about-these-builds).

O pacote preserva `ffmpeg/LICENSE` e o README do build. O README identifica
o [código-fonte FFmpeg do build, commit 38b88335f9](https://github.com/FFmpeg/FFmpeg/commit/38b88335f9).
Configuração e bibliotecas estão no README do distribuidor e em `ffmpeg -buildconf`.
As licenças dos componentes são independentes da identidade do editor.

## Whisper, fontes e componentes Flutter

- Whisper.cpp CPU/Vulkan x64 **b5454**, ZIP verificado por SHA-256
  `6ba69e3482d7826214f90a6a9c84ca07782aec1e1d0c6a7c30c994fd5d816ccb`;
  [fonte e licença MIT](https://github.com/ggml-org/whisper.cpp/tree/b5454).
  O pacote preserva `whisper/LICENSE`.
- Modelo Base `ggml-base.bin`, revisão Hugging Face
  `5359861c739e955e79d9a303bcbc70fb988958b1`, SHA-256
  `60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe`.
  [Whisper e seus pesos, licença MIT](https://github.com/openai/whisper/blob/main/LICENSE).
- Fontes de títulos e Lato da interface: arquivos OFL em
  `data/flutter_assets/assets/fonts/`. Ícones Material Icons e dependências
  Flutter: avisos agregados em `data/flutter_assets/NOTICES.Z`.
- Microsoft Visual C++ Runtime: DLLs app-local copiadas do Windows do runner;
  [informações de distribuição da Microsoft](https://learn.microsoft.com/en-us/cpp/windows/redistributing-visual-cpp-files).
- Os demais componentes nativos, incluindo media_kit/libmpv e plugins Windows,
  acompanham o build Flutter; seus avisos constam do pacote e das dependências.

O download prepara o ambiente de desenvolvimento/CI. A execução do ZIP completo
utiliza os runtimes e o modelo já incluídos e não necessita desses downloads.


## Vulkan e validação — SPDX e links

| Componente | SPDX | Links |
|---|---|---|
| whisper.cpp / ggml b5454, CPU e Vulkan | MIT | [Fonte](https://github.com/ggml-org/whisper.cpp/tree/b5454), [licença](https://github.com/ggml-org/whisper.cpp/blob/b5454/LICENSE) |
| Vulkan-Headers 1.4.357.0 | Apache-2.0 OR MIT | [Fonte](https://github.com/KhronosGroup/Vulkan-Headers/tree/vulkan-sdk-1.4.357.0), [licenças](https://github.com/KhronosGroup/Vulkan-Headers/blob/vulkan-sdk-1.4.357.0/LICENSE.md) |
| SPIRV-Headers 1.4.357.0 | MIT | [Fonte](https://github.com/KhronosGroup/SPIRV-Headers/tree/vulkan-sdk-1.4.357.0), [licenças](https://github.com/KhronosGroup/SPIRV-Headers/blob/vulkan-sdk-1.4.357.0/LICENSE) |
| shaderc/glslc, compilação | Apache-2.0 | [Fonte](https://github.com/google/shaderc), [licença](https://github.com/google/shaderc/blob/main/LICENSE) |
| psutil, medições locais | BSD-3-Clause | [Fonte](https://github.com/giampaolo/psutil), [licença](https://github.com/giampaolo/psutil/blob/master/LICENSE) |
| Flutter / integration_test | BSD-3-Clause | [Fonte](https://github.com/flutter/flutter/tree/3.44.4), [licença](https://github.com/flutter/flutter/blob/3.44.4/LICENSE) |
