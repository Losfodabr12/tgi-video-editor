# Preparação, testes e build Windows

Na raiz do repositório:

```powershell
powershell -ExecutionPolicy Bypass -File tool/setup_tools.ps1
powershell -ExecutionPolicy Bypass -File tool/test_editor.ps1 -Integration -Build
```

O primeiro comando instala em `source/tools`. Para testar sem alterar runtimes
existentes, use `-ToolsRoot .work/setup-verification`. `-SkipWhisper` prepara
somente FFmpeg/ffprobe. Downloads parciais não são publicados antes da conferência
de SHA-256; executáveis já presentes são reutilizados e executados com `-version`.
O modelo existente também tem o hash conferido. A rede é necessária nesta
preparação, antes do uso offline do editor.

Versões fixadas, com hashes registrados em `tool/setup_tools.ps1`:

- [FFmpeg 8.1.2 essentials, build Gyan](https://github.com/GyanD/codexffmpeg/releases/tag/8.1.2).
- [Whisper.cpp CPU x64 b5454](https://github.com/ggml-org/whisper.cpp/releases/tag/b5454).
- [Whisper Base, revisão fixada](https://huggingface.co/ggerganov/whisper.cpp/tree/5359861c739e955e79d9a303bcbc70fb988958b1).

O script de testes usa a mesma função `Invoke-EditorShortPath` do build, em
`tool/editor_paths.ps1`. Escolhe uma unidade livre, regenera caches absolutos
com `flutter clean` e `flutter pub get`, executa analyze/test e libera a unidade
em `finally`, inclusive após falha. Sem `-Integration`, executa exatamente
`flutter analyze --no-pub` e `flutter test --no-pub`. A opção adicional habilita
os testes históricos de FFmpeg; `-Build` também compila Windows release.

Para atualizar `aplicativo/`, use `source/tool/build_editor.ps1`; `-Run` abre
o editor em desenvolvimento. Os atalhos em `source/tool/` encaminham aos
scripts da raiz. Nenhum instalador ou arquivo pessoal é apagado por esses scripts.

O workflow `.github/workflows/ci.yml` usa `windows-latest`, Flutter **3.44.4**,
instala os runtimes, roda pub get/analyze/test, a integração e o build release.
O relatório principal distingue execuções locais do resultado remoto do CI.

Nome, marca e cores ficam em `source/lib/app/app_identity.dart`. O gerador
`tool/generate_branding.ps1` produz os ícones e `windows/runner/app_branding.h`;
os scripts de build/teste o executam automaticamente. Os arquivos gerados
também são versionados para permitir compilação direta pelo Flutter.
