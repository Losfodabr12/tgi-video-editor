# Análise rápida para revisão externa — 20/10/2026

Estado revisado: TGI Video Editor **0.2.0+2**, projeto Windows em Flutter,
derivado do TGI 1.4.26+33. Esta publicação inclui a reformulação que estava
somente na cópia local. A release executável `v0.1.0` continua sendo a base
anterior; para revisar o código atual, use a branch `main`.

## Resultado desta revisão

- `flutter analyze --no-pub`: **sem problemas**.
- `flutter test --no-pub --dart-define=TGI_RUN_FFMPEG_INTEGRATION_TESTS=true --reporter expanded`:
  **145 testes aprovados**, sem falhas ou testes ignorados.
- `git diff --check`: sem erros de whitespace.
- Busca por padrões comuns de credenciais nos arquivos preparados: nenhum
  candidato encontrado. Binários, caches, dados locais e `.work/` são ignorados.
- Não foi feita nova compilação nem sessão manual na janela nativa nesta revisão.
  Os resultados de build e revisão gráfica de 18/10 estão em `REFORMULACAO.md`.

A leitura rápida e os testes não revelaram uma regressão bloqueadora. Isso não
substitui auditoria completa nem valida o desempenho de projetos reais extensos.

## Mapa para a outra IA

| Área | Arquivos de entrada |
| --- | --- |
| Inicialização e recuperação | `source/lib/main.dart`, `source/lib/app/app.dart` |
| Modelo e operações da timeline | `source/lib/domain/models/project.dart`, `project_timeline.dart`, `track.dart` |
| Estado, histórico e edição | `source/lib/features/editor/application/editor_controller.dart`, `editor_controller_timeline.dart` |
| Workspace, timeline e preview | `source/lib/features/editor/presentation/editor_desktop_workspace.dart`, `widgets/timeline_panel.dart`, `widgets/video_preview_stage.dart` |
| Exportação e composição | `source/lib/services/ffmpeg_service.dart`, `ffmpeg_service_segments.dart` |
| Persistência e migração | `source/lib/services/project_io_service.dart`, `project_file_storage.dart` |
| Regressões | `source/test/` — 13 arquivos de testes |

A timeline usa snapshots de projeto, undo/redo e operações transacionais.
`TrackKind` separa pistas visuais e sonoras; vídeo, imagem e texto podem ocupar
a mesma pista visual. O formato salvo é **14**, com migração dos anteriores.

## Prioridades de revisão

1. **Preview e arquivo exportado.** O preview usa Flutter/media_kit e a
   exportação usa FFmpeg. Conferir ordem de camadas, transparência, keyframes,
   fades, máscaras, chroma e sincronismo. Os testes exercitam composição real,
   mas não provam equivalência de todos os filtros. As transições existentes
   são efeitos globais; não há um novo motor A/B de cross-dissolve.
2. **Uso nativo e desempenho.** A revisão anterior registrou capturas nativas
   em branco. Falta validar visualmente reprodução, GPU e sessões prolongadas.
   O benchmark do índice de clipes não mede FPS, memória ou edição 4K.
3. **Integrações e planos herdados.** O app entra direto no editor, mas mantém
   serviços de autenticação/downloads do TGI. A exportação 4K continua dependendo
   de `hasPaidPlan`, e a configuração de autenticação de produção aponta para
   `https://tgiapp.pages.dev`. Avaliar o fluxo pretendido para o app independente
   antes de mudar regras de produto.
4. **Manutenção e regressões.** `editor_controller.dart` tem 6.268 linhas,
   `ffmpeg_service.dart` 5.633 e `editor_screen.dart` 3.808. A separação já começou,
   mas ainda há concentração de responsabilidades. Não existe workflow de CI
   em `.github/workflows/`; as verificações desta publicação foram locais.
5. **Persistência e vínculos.** Aprofundar migração dos formatos 1–13, operações
   envolvendo pistas bloqueadas, grupos vinculados, colisões e undo/redo.
   A exportação recusa vídeos antigos sobrepostos na mesma pista; é necessário
   movê-los para camadas diferentes. Há testes para vários desses cenários.

Os itens acima distinguem limites observados e áreas que merecem investigação;
não são uma lista de cinco defeitos reproduzidos.

## Reproduzir as verificações

Ambiente usado: Windows, Flutter 3.44.4 / Dart 3.12.2. FFmpeg e ffprobe precisam
estar em `source/tools/ffmpeg/bin/`; os runtimes estão no pacote da release
inicial e não são versionados. Consulte `README.md` para Whisper e compilação.

```powershell
cd source
flutter pub get
flutter analyze --no-pub
flutter test --no-pub --dart-define=TGI_RUN_FFMPEG_INTEGRATION_TESTS=true --reporter expanded
```

Nesta máquina, a primeira tentativa de testes falhou antes de executar a suíte
por um cache de hooks nativos referenciando a unidade temporária `V:`, já
desmontada pelo script de build. Remapear temporariamente a raiz do projeto
para `V:` permitiu executar os 145 testes; a unidade foi liberada ao terminar.
O script de build limpa e recria caches sob esse caminho curto. Se alternar
para outro caminho e encontrar a mesma falha, regenere os caches no diretório
de trabalho com `flutter clean` e `flutter pub get` antes de repetir os testes.

Logs desta execução: `.work/review-2026-10-20-tests.log`, somente local.
Detalhes da reformulação, cenários cobertos e limitações: `REFORMULACAO.md`.
