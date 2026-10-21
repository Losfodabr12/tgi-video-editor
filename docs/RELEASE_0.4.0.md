Frame Studio 0.4.0 (`0.4.0+4`) para Windows x64. Projetos continuam no formato v14.

- MCP local com 33 tools de base e a tool adicional `export_cut_check` (34 no total).
- Remoção de silêncios por remapeamento de todas as camadas, preservando vínculos A/V e sincronia de legendas; um Ctrl+Z desfaz o lote.
- Presets suave/normal/agressivo, proteção de palavras, fragmentos mínimos e preview com métricas.
- Micro-fades de áudio de 8 ms nas emendas e amostras para ouvir antes de aprovar.

Extraia o ZIP inteiro e abra `VideoEditor.exe`. FFmpeg, ffprobe, Whisper Base,
fontes, licenças e bibliotecas nativas acompanham o aplicativo.
Confira o ZIP com `SHA256SUMS.txt`; `BUILD_INFO.json` identifica versão, build,
commit e hashes dos arquivos.

O servidor MCP inicia desligado. Ative em Arquivo → Configurações de IA (MCP),
escolha a pasta de exportação e configure o cliente com o token obrigatório.
Mantenha a aprovação de planos ativa. Instruções e limitações em `docs/MCP.md`
dentro do pacote; novidades em `CHANGELOG.md`.
