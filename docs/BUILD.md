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

## Pacote e release

Após o build, `tool/package_windows.ps1` gera em `dist/` o ZIP Windows x64,
`SHA256SUMS.txt` e uma cópia do relatório. Inclui runtimes, modelo Base,
licenças, DLLs do build e Microsoft CRT app-local. Recusa build cuja versão
do executável não corresponda ao pubspec. `.downloads` e caches de preview
não entram no pacote. O CI publica esses arquivos como artefato por 14 dias.

`release.yml` usa o mesmo workflow de CI, com todos os checks, ao receber uma
tag `v*`. A tag precisa corresponder ao pubspec. Se o build e o upload passam,
publica o ZIP, checksum e relatório em GitHub Releases com `GITHUB_TOKEN` e
`contents: write` restrito ao job de publicação. Exemplo para esta versão:

```powershell
git tag -a v0.3.0 -m "Frame Studio 0.3.0"
git push origin v0.3.0
```

Checkout 7.0.1, cache 6.1.0, upload-artifact 7.0.2 e download-artifact 8.0.2
usam Node 24, conferido nos respectivos `action.yml` pela API do GitHub.
O cache interno de `subosito/flutter-action@v2` também usa cache v5 / Node 24.

O relatório remoto é gerado **depois** de analyze/test/integração/build pelo
`tool/write_ci_report.ps1`, com o SHA e o URL do run efetivamente executado.
Ele acompanha o artefato e a release. O documento versionado aponta para essa
evidência gerada, evitando um commit adicional apenas para registrar o próprio
resultado do CI (que mudaria novamente o SHA a validar). O estado final do
workflow é conferido na API antes da entrega.

Nome, marca e cores ficam em `source/lib/app/app_identity.dart`. O gerador
`tool/generate_branding.ps1` produz os ícones e `windows/runner/app_branding.h`;
os scripts de build/teste o executam automaticamente. Os arquivos gerados
também são versionados para permitir compilação direta pelo Flutter.
