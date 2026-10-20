Frame Studio 0.3.0 para Windows x64, com projetos no formato v14.

- Interface compacta com tokens centrais, cores por tipo de clipe, snapping
  visível e painéis com proporções salvas.
- Proxies e caches persistentes, dissolve A/B, presets de exportação,
  GPU com fallback CPU, SRT e edição de estilo de legendas.
- Projetos antigos são migrados em memória; ao sobrescrever, o original é
  preservado em `.bak`, inclusive nas gravações seguintes.
- ZIP com FFmpeg essentials 8.1.2 (GPL v3 ou posterior), Whisper CPU e modelo
  Base, fontes e runtimes. Extraia tudo e abra `VideoEditor.exe`.

O relatório que acompanha o ZIP e o asset `RELATORIO_ALTERACOES.md` registram
o SHA do código e o run dos checks realmente executados. `SHA256SUMS.txt`
permite conferir o ZIP. Goldens headless e testes de FFmpeg não substituem
a avaliação manual de playback, sincronismo, DPI e hardware de cada GPU.

Detalhes: [relatório da implementação](https://github.com/Losfodabr12/tgi-video-editor/blob/main/RELATORIO_ALTERACOES.md)
e [licenças dos runtimes](https://github.com/Losfodabr12/tgi-video-editor/blob/main/docs/THIRD_PARTY.md).
