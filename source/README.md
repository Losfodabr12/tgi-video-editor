# TGI Video Editor — Flutter

Versão local 0.2.0+2. Entrada: `lib/main.dart`. Interface e estado:
`lib/features/editor/`. Regras da timeline: `lib/domain/models/project_timeline.dart`.
Formato de projeto 14, com migração de versões anteriores.

Consulte [as instruções de execução](../README.md) e o
[registro de implementação e testes](../REFORMULACAO.md).

```powershell
flutter pub get
powershell -ExecutionPolicy Bypass -File tool\build_editor.ps1 -Run
```

O script sem `-Run` compila e atualiza `../aplicativo`, usando uma unidade
temporária para evitar o limite de caminhos de plugins nativos no Windows.
