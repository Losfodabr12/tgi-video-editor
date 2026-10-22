# Changelog

## Em desenvolvimento — 22/10/2026

- Whisper b5454 com Vulkan no ZIP, verificação dos sete binários e recuperação automática para CPU.
- Seleção persistida de GPU, prioridade para dedicada e backend/dispositivo efetivos na UI e no MCP.
- Novas transcrições usam Turbo com VRAM suficiente, ou Small na CPU; escolha manual e projetos existentes preservados em v14.
- Validação nativa de UI e HTTP MCP, com três execuções por fluxo GPU, CPU forçada e DLL Vulkan ausente; tempos e picos de memória em docs/TRANSCRICAO.md.
- Correções de layout no diálogo de modelos e indicador de dispositivo; avisos Vulkan incluídos no pacote e metadados SPDX atualizados.

## 0.4.0 — 21/10/2026

- MCP local com 33 tools de base e `export_cut_check` adicional (34 tools expostas), aprovação de planos e autenticação por token.
- `remove_silences` por remapeamento de tempo em todas as camadas, com vínculos A/V, legendas, keyframes e marcadores; um Ctrl+Z desfaz a transação.
- Modos suave, normal e agressivo, com fusão de fragmentos curtos e preview detalhado.
- Micro-fades de áudio nas emendas, padrão de 8 ms, respeitados pelo export FFmpeg.
- Proteção de palavras temporizadas com margem de 50 ms; aviso quando não disponível.

Aplicativo `0.4.0+4`; formato de projeto v14 preservado.
