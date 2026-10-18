# Editor de Video

Projeto Flutter independente derivado do editor TGI 1.4.26+33.
Consulte `../README.md` para baixar o aplicativo, preparar os runtimes locais,
executar e desenvolver.

```powershell
flutter pub get
powershell -ExecutionPolicy Bypass -File tool\build_editor.ps1 -Run
```

Entrada: `lib/main.dart`. Interface: `lib/features/editor/`.
Modelos e servicos compartilhados foram copiados com as dependencias locais.
Este projeto possui identidade Windows e dados locais separados do TGI original.
