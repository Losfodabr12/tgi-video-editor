part of 'editor_screen.dart';

extension _EditorProjectActions on _EditorScreenState {
  void _markExportRange(bool start) {
    final duration = _controller.project.timelineDuration;
    if (duration <= Duration.zero) return;
    final position = _controller.playheadPosition;
    _setExportSettings(
      FfmpegExportSettings(
        resolution: _exportSettings.resolution,
        framesPerSecond: _exportSettings.framesPerSecond,
        quality: _exportSettings.quality,
        encoder: _exportSettings.encoder,
        rangeStart: start
            ? position
            : _exportSettings.rangeStart ?? Duration.zero,
        rangeEnd: start ? _exportSettings.rangeEnd ?? duration : position,
      ),
    );
  }

  Future<bool> _recordVersion(
    TgiProject project,
    FfmpegExportSettings settings,
    String label,
  ) async {
    if ((_isFlutterTest || Platform.environment.containsKey('FLUTTER_TEST')) &&
        widget.projectHistoryService == null) {
      return false;
    }
    try {
      await _projectHistoryService.record(
        project,
        exportSettings: settings,
        label: label,
      );
      _lastVersionAt = DateTime.now();
      _lastVersionProjectId = project.id;
      return true;
    } catch (_) {
      if (mounted) {
        _showEditorNotification(
          'Não foi possível guardar a versão no histórico. O salvamento do projeto continua disponível.',
          tone: TgiNotificationTone.error,
        );
      }
    }
    return false;
  }

  Future<void> _showProjectTools() async {
    if (_projectToolBusy) return;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Projeto e modelos'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final item in const [
                  (
                    'history',
                    Icons.history,
                    'Histórico de versões',
                    'Restaurar uma edição anterior',
                  ),
                  (
                    'checkpoint',
                    Icons.bookmark_add_outlined,
                    'Guardar versão agora',
                    'Criar um ponto de retorno',
                  ),
                  (
                    'collect',
                    Icons.folder_copy_outlined,
                    'Reunir projeto e mídias',
                    'Criar uma pasta para transportar ou arquivar',
                  ),
                  (
                    'presets',
                    Icons.style_outlined,
                    'Modelos pessoais',
                    'Salvar e aplicar texto, cor e animação',
                  ),
                  (
                    'captions',
                    Icons.subtitles_outlined,
                    'Usar textos como legendas',
                    'Incluir os textos selecionados no SRT/VTT',
                  ),
                ])
                  ListTile(
                    leading: Icon(item.$2),
                    title: Text(item.$3),
                    subtitle: Text(item.$4),
                    onTap: () => Navigator.of(ctx).pop(item.$1),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'history':
        await _showProjectHistory();
      case 'checkpoint':
        final saved = await _recordVersion(
          _controller.project,
          _exportSettings,
          'Ponto de retorno',
        );
        if (mounted && saved) {
          _showEditorNotification('Versão guardada no histórico.');
        }
      case 'collect':
        await _collectProject();
      case 'presets':
        await _showPersonalPresets();
      case 'captions':
        _controller.registerSelectedTextClipsAsCaptions();
    }
    _restoreEditorShortcutFocus();
  }

  Future<void> _showProjectHistory() async {
    try {
      final sessionRevision = _projectSessionRevision;
      final entries = await _projectHistoryService.list(_controller.project.id);
      if (!mounted || sessionRevision != _projectSessionRevision) return;
      final chosen = await showDialog<ProjectHistoryEntry>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Histórico de versões'),
          content: SizedBox(
            width: 560,
            height: 360,
            child: entries.isEmpty
                ? const Center(
                    child: Text(
                      'Nenhuma versão guardada.\nSalve o projeto ou use “Guardar versão agora”.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (ctx, index) {
                      final entry = entries[index];
                      final time = entry.savedAt.toLocal();
                      String two(int value) => value.toString().padLeft(2, '0');
                      return ListTile(
                        leading: const Icon(Icons.restore),
                        title: Text(
                          '${two(time.day)}/${two(time.month)}/${time.year}  ${two(time.hour)}:${two(time.minute)}:${two(time.second)}',
                        ),
                        subtitle: Text('${entry.label} · ${entry.projectName}'),
                        trailing: const Text('Restaurar'),
                        onTap: () => Navigator.of(ctx).pop(entry),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Fechar'),
            ),
          ],
        ),
      );
      if (chosen == null ||
          !mounted ||
          sessionRevision != _projectSessionRevision) {
        return;
      }
      if (!await _confirmDiscardUnsavedChanges() || !mounted) return;
      // Read before mutating editor state and keep the current version too.
      final restored = await _projectHistoryService.restore(chosen);
      await _recordVersion(
        _controller.project,
        _exportSettings,
        'Antes de restaurar',
      );
      if (!mounted || sessionRevision != _projectSessionRevision) return;
      _projectSessionRevision++;
      _controller.loadProjectFromData(restored);
      _refreshEditor(() {
        _exportSettings = restored.exportSettings ?? _exportSettings;
        _recoveredDraftPending = true;
      });
      _scheduleProjectAutosave(force: true);
      _showEditorNotification(
        'Versão restaurada. Salve para atualizar o arquivo do projeto.',
      );
      if (restored.missingMediaItems.isNotEmpty) {
        await _promptRelinkMissingMedia(restored.missingMediaItems);
      }
    } catch (error) {
      if (mounted) {
        _showEditorNotification(
          error.toString(),
          tone: TgiNotificationTone.error,
        );
      }
    }
  }

  Future<void> _collectProject() async {
    final folder = await FilePicker.getDirectoryPath(
      dialogTitle: 'Escolha onde reunir o projeto',
    );
    if (folder == null || !mounted) return;
    final project = _controller.project;
    final settings = _exportSettings;
    _refreshEditor(() => _projectToolBusy = true);
    _showEditorNotification(
      'Reunindo o projeto e as mídias…',
      duration: const Duration(seconds: 5),
    );
    try {
      final path = await ProjectCollectionService().collect(
        project,
        folder,
        exportSettings: settings,
      );
      if (!mounted) return;
      _showEditorNotification(
        'Projeto reunido: $path',
        duration: const Duration(seconds: 10),
      );
      await _revealExportedFile(path);
    } catch (error) {
      if (mounted) {
        _showEditorNotification(
          error.toString(),
          tone: TgiNotificationTone.error,
        );
      }
    } finally {
      _refreshEditor(() => _projectToolBusy = false);
    }
  }

  Future<void> _showPersonalPresets() async {
    try {
      var entries = await _editorPresetService.list();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, update) {
            final clip = _controller.selectedTimelineClip;
            return AlertDialog(
              title: const Text('Modelos pessoais'),
              content: SizedBox(
                width: 520,
                height: 400,
                child: Column(
                  children: [
                    Text(
                      clip == null
                          ? 'Selecione um clipe para salvar ou aplicar um modelo.'
                          : 'O modelo preserva o conteúdo, os cortes e a posição do clipe.',
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final kind in EditorPresetKind.values)
                          OutlinedButton(
                            onPressed:
                                clip == null ||
                                    !EditorPresetService.accepts(kind, clip)
                                ? null
                                : () async {
                                    final nameController =
                                        TextEditingController();
                                    final name = await showDialog<String>(
                                      context: ctx,
                                      builder: (nameContext) => AlertDialog(
                                        title: Text(
                                          'Salvar ${kind.label.toLowerCase()}',
                                        ),
                                        content: TextField(
                                          controller: nameController,
                                          autofocus: true,
                                          decoration: const InputDecoration(
                                            labelText: 'Nome do modelo',
                                          ),
                                          onSubmitted: (value) => Navigator.of(
                                            nameContext,
                                          ).pop(value),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(nameContext).pop(),
                                            child: const Text('Cancelar'),
                                          ),
                                          FilledButton(
                                            onPressed: () => Navigator.of(
                                              nameContext,
                                            ).pop(nameController.text),
                                            child: const Text('Salvar'),
                                          ),
                                        ],
                                      ),
                                    );
                                    // The route keeps its text field alive during its exit animation.
                                    Future<void>.delayed(
                                      const Duration(seconds: 1),
                                      nameController.dispose,
                                    );
                                    if (name == null ||
                                        name.trim().isEmpty ||
                                        !mounted ||
                                        !ctx.mounted) {
                                      return;
                                    }
                                    try {
                                      await _editorPresetService.save(
                                        EditorPresetService.capture(
                                          name,
                                          kind,
                                          clip,
                                        ),
                                      );
                                      entries = await _editorPresetService
                                          .list();
                                      if (ctx.mounted) update(() {});
                                    } catch (error) {
                                      if (mounted) {
                                        _showEditorNotification(
                                          error.toString(),
                                          tone: TgiNotificationTone.error,
                                        );
                                      }
                                    }
                                  },
                            child: Text('Salvar ${kind.label.toLowerCase()}'),
                          ),
                      ],
                    ),
                    const Divider(),
                    Expanded(
                      child: entries.isEmpty
                          ? const Center(
                              child: Text('Seus modelos aparecerão aqui.'),
                            )
                          : ListView(
                              children: [
                                for (final preset in entries)
                                  ListTile(
                                    title: Text(preset.name),
                                    subtitle: Text(preset.kind.label),
                                    enabled:
                                        clip != null &&
                                        EditorPresetService.accepts(
                                          preset.kind,
                                          clip,
                                        ),
                                    onTap: () {
                                      _controller.applyPersonalPreset(preset);
                                      Navigator.of(ctx).pop();
                                    },
                                    trailing: IconButton(
                                      tooltip: 'Excluir modelo',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () async {
                                        try {
                                          await _editorPresetService.remove(
                                            preset.id,
                                          );
                                          entries = await _editorPresetService
                                              .list();
                                          if (ctx.mounted) update(() {});
                                        } catch (error) {
                                          if (mounted) {
                                            _showEditorNotification(
                                              error.toString(),
                                              tone: TgiNotificationTone.error,
                                            );
                                          }
                                        }
                                      },
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Fechar'),
                ),
              ],
            );
          },
        ),
      );
    } catch (error) {
      if (mounted) {
        _showEditorNotification(
          error.toString(),
          tone: TgiNotificationTone.error,
        );
      }
    }
  }
}
