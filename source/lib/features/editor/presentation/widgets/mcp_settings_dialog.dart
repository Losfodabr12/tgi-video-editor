import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/commands/editor_command.dart';
import '../../../../mcp/editor_automation.dart';
import '../../../../mcp/editor_plans.dart';
import '../../../../mcp/mcp_settings.dart';
import '../../../../mcp/mcp_import_paths.dart';

class McpSettingsDialog extends StatefulWidget {
  const McpSettingsDialog({
    super.key,
    required this.automation,
    this.pickExportDirectory,
    this.pickImportDirectory,
    this.assetsDirectory,
  });
  final EditorAutomation automation;
  final Future<String?> Function()? pickExportDirectory;
  final Future<String?> Function()? pickImportDirectory;
  final String? assetsDirectory;
  @override
  State<McpSettingsDialog> createState() => _McpSettingsDialogState();
}

class _McpSettingsDialogState extends State<McpSettingsDialog> {
  late final TextEditingController _port;
  String? _error;
  bool _working = false;
  EditorAutomation get a => widget.automation;
  @override
  void initState() {
    super.initState();
    _port = TextEditingController(text: '${a.settings.port}');
  }

  @override
  void dispose() {
    _port.dispose();
    super.dispose();
  }

  Future<void> _perform(Future<void> Function() work) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await work();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is CommandError ? e.message : e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _save({
    bool? approval,
    String? directory,
    List<String>? importDirectories,
  }) async {
    final port = int.tryParse(_port.text);
    if (port == null || port < 1024 || port > 65535) {
      throw const CommandError(
        'invalid_port',
        'Use uma porta de 1024 a 65535.',
      );
    }
    await a.configure(
      McpSettings(
        port: port,
        requireApproval: approval ?? a.settings.requireApproval,
        exportDirectory: directory ?? a.settings.exportDirectory,
        importDirectories: importDirectories ?? a.settings.importDirectories,
      ),
    );
  }

  Future<void> _addImportDirectory(String path) async {
    if (a.settings.importDirectories.contains(path)) return;
    await _save(importDirectories: [...a.settings.importDirectories, path]);
  }

  void _copied(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([a, a.controller]),
    builder: (context, _) => DefaultTabController(
      length: 2,
      child: AlertDialog(
        title: Row(
          children: [
            const Expanded(child: Text('IA e automação (MCP)')),
            IconButton(
              tooltip: 'Fechar',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        content: SizedBox(
          width: 760,
          height: math.min(
            620,
            math.max(260, MediaQuery.sizeOf(context).height - 180),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const TabBar(
                tabs: [
                  Tab(text: 'Configurações'),
                  Tab(text: 'Atividade da IA'),
                ],
              ),
              if (_error != null ||
                  a.lastError != null ||
                  a.audit.lastError != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    _error ?? a.lastError ?? a.audit.lastError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Expanded(child: TabBarView(children: [_settings(), _activity()])),
            ],
          ),
        ),
      ),
    ),
  );
  Widget _settings() => ListView(
    key: const ValueKey('mcp_settings_list'),
    padding: const EdgeInsets.symmetric(vertical: 12),
    children: [
      SwitchListTile(
        key: const ValueKey('mcp_enabled'),
        title: const Text('Servidor MCP local'),
        subtitle: Text(
          a.running
              ? (a.connectedClients > 0
                    ? 'IA conectada · ${a.connectedClients} cliente(s)'
                    : 'Ligado · aguardando IA')
              : 'Desligado · inicia sempre desligado',
        ),
        value: a.running,
        onChanged: _working || a.busy
            ? null
            : (enabled) => _perform(() async {
                if (enabled) {
                  await _save();
                  await a.start();
                  if (a.lastError != null) {
                    throw CommandError('server_start_failed', a.lastError!);
                  }
                } else {
                  await a.stop();
                }
              }),
      ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            SizedBox(
              width: 160,
              child: TextField(
                key: const ValueKey('mcp_port'),
                controller: _port,
                enabled: !a.running && !_working,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Porta',
                  helperText: '127.0.0.1 apenas',
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(child: SelectableText(a.url)),
          ],
        ),
      ),
      SwitchListTile(
        key: const ValueKey('mcp_approval'),
        title: const Text('Aprovar plano antes de aplicar'),
        subtitle: const Text(
          'A IA prepara o plano; você revisa e aplica na aba Atividade.',
        ),
        value: a.settings.requireApproval,
        onChanged: _working
            ? null
            : (value) => _perform(() => _save(approval: value)),
      ),
      ListTile(
        title: const Text('Pasta de exportação da IA'),
        subtitle: Text(a.settings.exportDirectory ?? 'Nenhuma pasta escolhida'),
        trailing: TextButton(
          onPressed: _working
              ? null
              : () => _perform(() async {
                  final path =
                      await (widget.pickExportDirectory?.call() ??
                          FilePicker.getDirectoryPath(
                            dialogTitle: 'Pasta de exportação da IA',
                          ));
                  if (path != null) {
                    await _save(directory: path);
                  }
                }),
          child: const Text('Escolher pasta'),
        ),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          'Exportações usam nomes .mp4/.wav dentro desta pasta e não sobrescrevem arquivos.',
        ),
      ),
      const Divider(),
      const ListTile(
        title: Text('Pastas autorizadas para importar pela IA'),
        subtitle: Text('Somente arquivos destas pastas podem ser importados.'),
      ),
      if (a.settings.importDirectories.isEmpty)
        const ListTile(title: Text('Nenhuma pasta autorizada')),
      for (final path in a.settings.importDirectories)
        ListTile(
          title: Text(path),
          trailing: IconButton(
            tooltip: 'Remover autorização',
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: _working
                ? null
                : () => _perform(
                    () => _save(
                      importDirectories: a.settings.importDirectories
                          .where((p) => p != path)
                          .toList(),
                    ),
                  ),
          ),
        ),
      Wrap(
        spacing: 8,
        children: [
          TextButton(
            key: const ValueKey('mcp_add_import_directory'),
            onPressed: _working
                ? null
                : () => _perform(() async {
                    final path =
                        await (widget.pickImportDirectory?.call() ??
                            FilePicker.getDirectoryPath(
                              dialogTitle:
                                  'Autorizar pasta de importação da IA',
                            ));
                    if (path != null) await _addImportDirectory(path);
                  }),
            child: const Text('Adicionar pasta'),
          ),
          TextButton(
            key: const ValueKey('mcp_add_assets_directory'),
            onPressed: _working
                ? null
                : () => _perform(() async {
                    final profile =
                        Platform.environment['USERPROFILE'] ??
                        Platform.environment['HOME'];
                    final path =
                        widget.assetsDirectory ??
                        (profile == null
                            ? throw const CommandError(
                                'path_not_allowed',
                                'Desktop indisponível.',
                              )
                            : '$profile${Platform.pathSeparator}Desktop${Platform.pathSeparator}FrameStudio_Assets');
                    await McpImportPaths.directory(Directory(path).parent.path);
                    await Directory(path).create();
                    await _addImportDirectory(path);
                  }),
            child: const Text('Adicionar Desktop\\FrameStudio_Assets'),
          ),
        ],
      ),
      const Divider(),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            key: const ValueKey('mcp_copy_codex'),
            icon: const Icon(Icons.content_copy),
            label: const Text('Copiar configuração do Codex'),
            onPressed: () => _perform(() async {
              await Clipboard.setData(
                ClipboardData(text: a.codexConfiguration),
              );
              _copied(
                'TOML copiado. Defina FRAME_STUDIO_MCP_TOKEN no ambiente do Codex.',
              );
            }),
          ),
          OutlinedButton(
            onPressed: _working
                ? null
                : () => _perform(() async {
                    await Clipboard.setData(
                      ClipboardData(text: await a.tokenForClipboard()),
                    );
                    _copied(
                      'Token copiado. Guarde-o na variável FRAME_STUDIO_MCP_TOKEN.',
                    );
                  }),
            child: const Text('Copiar token'),
          ),
          OutlinedButton(
            onPressed: _working
                ? null
                : () => _perform(() async {
                    await a.rotateToken();
                    _copied(
                      'Token rotacionado. Reconecte a IA com o novo token.',
                    );
                  }),
            child: const Text('Rotacionar token'),
          ),
          OutlinedButton(
            onPressed: _working || a.running
                ? null
                : () => _perform(() => _save()),
            child: const Text('Salvar configurações'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        key: const ValueKey('mcp_emergency_stop'),
        style: FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
        onPressed: () => _perform(a.stop),
        icon: const Icon(Icons.stop_circle_outlined),
        label: const Text('Desligar IA agora'),
      ),
      const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Text(
          'O token é obrigatório e fica no armazenamento seguro do sistema. Rotacionar desconecta os clientes.',
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: SelectableText(
          'Auditoria: ${a.audit.path}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ],
  );
  Widget _activity() {
    final plans = a.plans.all.toList().reversed.toList(),
        jobs = a.reads.jobs.all.toList().reversed.toList();
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        if (plans.isEmpty && jobs.isEmpty && a.activities.isEmpty)
          const ListTile(title: Text('Nenhuma atividade da IA nesta sessão.')),
        for (final plan in plans)
          Card(
            child: ListTile(
              title: Text(plan.label),
              subtitle: Text(
                '${plan.commands.length} comando(s) · revisão ${plan.revision} · ${plan.applied
                    ? 'aplicado'
                    : plan.revision != a.controller.projectRevision
                    ? 'revisão antiga'
                    : 'aguardando revisão'}',
              ),
              trailing: TextButton(
                onPressed: () => _review(plan),
                child: const Text('Revisar plano'),
              ),
            ),
          ),
        for (final job in jobs)
          ListTile(
            title: Text('${job.kind} · ${job.id}'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${job.status} · ${(job.context.progress * 100).round()}% ${job.context.message}',
                ),
                if (!job.finished)
                  LinearProgressIndicator(value: job.context.progress),
                if (job.error != null) Text('${job.error!['message']}'),
              ],
            ),
            trailing: job.finished
                ? null
                : TextButton(
                    onPressed: () =>
                        _perform(() => a.reads.jobs.cancel(job.id)),
                    child: const Text('Cancelar'),
                  ),
          ),
        for (final item in a.activities)
          ListTile(
            dense: true,
            leading: Icon(
              item.error == null
                  ? Icons.smart_toy_outlined
                  : Icons.error_outline,
            ),
            title: Text(item.label),
            subtitle: Text(
              '${item.time.hour.toString().padLeft(2, '0')}:${item.time.minute.toString().padLeft(2, '0')} · ${item.tool} · revisão ${item.before} → ${item.after}${item.error == null ? '' : ' · ${item.error}'}',
            ),
            trailing: a.canUndo(item)
                ? TextButton(
                    onPressed: () => _perform(() async {
                      a.undo(item);
                    }),
                    child: const Text('Desfazer'),
                  )
                : null,
          ),
      ],
    );
  }

  Future<void> _review(EditorPlan plan) async {
    final summary = plan.toJson();
    await showDialog<void>(
      context: context,
      builder: (context) => AnimatedBuilder(
        animation: a,
        builder: (context, _) => AlertDialog(
          title: Text(plan.label),
          content: SizedBox(
            width: 720,
            height: math.min(450, MediaQuery.sizeOf(context).height * 0.55),
            child: SingleChildScrollView(
              child: SelectableText(
                const JsonEncoder.withIndent('  ').convert({
                  'base_revision': plan.revision,
                  if (summary['cut_summary'] != null)
                    'cut_summary': summary['cut_summary'],
                  if (summary['word_protection'] != null)
                    'word_protection': summary['word_protection'],
                  if (summary['warnings'] != null)
                    'warnings': summary['warnings'],
                  'before': summary['before'],
                  'after': summary['after'],
                  if (plan.exportSettings != null)
                    'export_resolution': plan.exportSettings!.resolution.id,
                  'commands': plan.commands.map((c) => c.toJson()).toList(),
                  'changes': summary['changes'],
                  'change_count': summary['change_count'],
                  'changes_truncated': summary['changes_truncated'],
                }),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
            FilledButton(
              key: const ValueKey('mcp_approve_apply'),
              onPressed:
                  plan.applied || plan.revision != a.controller.projectRevision
                  ? null
                  : () {
                      try {
                        a.approveAndApply(plan.id);
                        Navigator.pop(context);
                      } catch (e) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(e.toString())));
                      }
                    },
              child: const Text('Aprovar e aplicar'),
            ),
          ],
        ),
      ),
    );
  }
}
