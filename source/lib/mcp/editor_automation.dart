import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/commands/command_engine.dart';
import '../features/editor/application/editor_controller.dart';
import 'editor_jobs.dart';
import 'editor_mcp_server.dart';
import 'editor_plans.dart';
import 'editor_read_service.dart';
import 'mcp_audit.dart';
import 'mcp_path_policy.dart';
import 'mcp_settings.dart';
import 'mcp_tool_router.dart';

class McpActivity {
  McpActivity(
    this.tool,
    this.label,
    this.before,
    this.after, {
    this.error,
    this.planId,
    this.jobId,
  });
  final String tool, label;
  final int before, after;
  final String? error, planId, jobId;
  final time = DateTime.now();
}

class EditorAutomation extends ChangeNotifier {
  EditorAutomation(
    this.controller, {
    McpSettingsStore? settingsStore,
    McpTokenStore? tokenStore,
    McpAudit? audit,
  }) : settingsStore = settingsStore ?? McpSettingsStore(),
       tokenStore = tokenStore ?? const SecureMcpTokenStore(),
       audit = audit ?? McpAudit() {
    reads = EditorReadService(
      controller,
      jobs: EditorJobs(onChanged: notifyListeners),
      checkMedia: (m) async {
        await policy.trustProject(controller.project);
        return policy.authorizeMedia(m);
      },
    );
    plans = EditorPlans(controller, reads, onChanged: notifyListeners);
    router = McpToolRouter(
      reads,
      plans,
      resolveExport: policy.resolveExport,
      authorizeExport: (project, path) async {
        await policy.trustProject(controller.project);
        await policy.authorizeExport(path);
        await policy.authorizeProject(project);
      },
      onActivity: _activity,
    );
  }
  final EditorController controller;
  final McpSettingsStore settingsStore;
  final McpTokenStore tokenStore;
  final McpAudit audit;
  final policy = McpPathPolicy();
  late final EditorReadService reads;
  late final EditorPlans plans;
  late final McpToolRouter router;
  final List<McpActivity> activities = [];
  McpSettings settings = const McpSettings();
  EditorMcpServer? _server;
  String? _token;
  bool _disposed = false, busy = false;
  int _epoch = 0;
  Future<void>? _shutdown;
  Future<void> shutdown() => _shutdown ??= _shutdownNow();
  Future<void> _shutdownNow() async {
    await stop();
    await reads.dispose();
    await audit.flush();
  }

  String? lastError;
  bool get running => _server?.running ?? false;
  int get connectedClients => _server?.connectedClients ?? 0;
  String get url => 'http://127.0.0.1:${settings.port}/mcp';
  String get codexConfiguration =>
      '[mcp_servers.frame_studio]\nurl = "$url"\nbearer_token_env_var = "FRAME_STUDIO_MCP_TOKEN"\ntool_timeout_sec = 120\n';
  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  Future<void> load() async {
    try {
      settings = await settingsStore.load();
      _applySettings();
    } catch (e) {
      lastError = e.toString();
    }
    notifyListeners();
  }

  void _applySettings() {
    plans.requireApproval = settings.requireApproval;
    policy.exportDirectory = settings.exportDirectory;
  }

  Future<void> configure(McpSettings value) async {
    McpSettings.fromJson(Map<String, dynamic>.from(value.toJson()));
    if (running && value.port != settings.port) {
      throw const CommandError(
        'server_running',
        'Desligue o servidor antes de trocar a porta.',
      );
    }
    await settingsStore.save(value);
    settings = value;
    _applySettings();
    notifyListeners();
    unawaited(
      audit.write({
        'event': 'settings_changed',
        'port': value.port,
        'require_approval': value.requireApproval,
        'export_directory_selected': value.exportDirectory != null,
      }),
    );
  }

  Future<String> tokenForClipboard() async {
    final existing = _token ?? await tokenStore.read();
    if (existing != null && existing.length >= 32) {
      _token = existing;
      return existing;
    }
    final token = randomMcpToken();
    await tokenStore.write(token);
    _token = token;
    return token;
  }

  Future<void> start() async {
    if (running || busy || _disposed) {
      return;
    }
    final epoch = ++_epoch;
    busy = true;
    lastError = null;
    notifyListeners();
    try {
      final token = await tokenForClipboard();
      await policy.trustProject(controller.project);
      if (epoch != _epoch || _disposed) {
        return;
      }
      final server = EditorMcpServer(
        router,
        token: token,
        port: settings.port,
        onChanged: notifyListeners,
        onSecurityEvent: (reason) => unawaited(
          audit.write({'event': 'http_rejected', 'reason': reason}),
        ),
      );
      _server = server;
      await server.start();
      if (epoch != _epoch || _disposed) {
        await server.stop();
        return;
      }
      unawaited(
        audit.write({
          'event': 'server_started',
          'port': settings.port,
          'project_id': controller.project.id,
        }),
      );
    } catch (e) {
      lastError = e.toString();
      _server = null;
    } finally {
      if (epoch == _epoch) {
        busy = false;
      }
      notifyListeners();
    }
  }

  Future<void> stop() async {
    final hadWork =
        running ||
        busy ||
        plans.all.isNotEmpty ||
        reads.jobs.all.any((j) => !j.finished);
    ++_epoch;
    busy = false;
    final server = _server;
    _server = null;
    plans.clear();
    notifyListeners();
    await server?.stop();
    await reads.cancelAll();
    if (hadWork) {
      unawaited(
        audit.write({
          'event': 'server_stopped',
          'revision': controller.projectRevision,
        }),
      );
    }
    notifyListeners();
  }

  Future<void> rotateToken() async {
    final restart = running;
    await stop();
    final token = randomMcpToken();
    await tokenStore.write(token);
    _token = token;
    unawaited(audit.write({'event': 'token_rotated'}));
    if (restart) {
      await start();
    }
    notifyListeners();
  }

  void _activity(
    String tool,
    Map<String, Object?> args,
    Map<String, Object?> result,
    int before,
    int after,
  ) {
    final error = result['error'] as Map?;
    final label = result['label'] as String? ?? 'IA: $tool';
    final activity = McpActivity(
      tool,
      label,
      before,
      after,
      error: error?['code'] as String?,
      planId: result['plan_id'] as String?,
      jobId: result['job_id'] as String?,
    );
    activities.insert(0, activity);
    if (activities.length > 100) {
      activities.removeLast();
    }
    unawaited(
      audit.write({
        'event': 'tool_call',
        'tool': tool,
        'argument_fields': args.keys.toList(),
        'clip_id': args['clip_id'],
        'media_id': args['media_id'],
        'revision_before': before,
        'revision_after': after,
        'result': error == null ? 'ok' : 'error',
        'error_code': error?['code'],
        'plan_id': activity.planId,
        'job_id': activity.jobId,
        'command_count': result['command_count'],
      }),
    );
    notifyListeners();
  }

  bool canUndo(McpActivity activity) =>
      activity.after > activity.before &&
      activity.after == controller.projectRevision &&
      controller.canUndo &&
      activity.label == controller.undoLabel;
  void undo(McpActivity activity) {
    if (!canUndo(activity)) {
      throw const CommandError(
        'history_changed',
        'Somente a última transação ainda no topo pode ser desfeita aqui. Use Ctrl+Z para navegar no histórico.',
      );
    }
    final before = controller.projectRevision;
    final result = controller.executeCommands(
      [EditorCommand('undo', {})],
      baseRevision: before,
      label: 'IA: desfazer ${activity.tool}',
    );
    _activity('undo (app)', {}, result, before, controller.projectRevision);
  }

  void approveAndApply(String id) {
    plans.approve(id);
    final before = controller.projectRevision;
    final result = plans.apply(id, baseRevision: before);
    _activity(
      'apply_plan (app)',
      {'plan_id': id},
      result,
      before,
      controller.projectRevision,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(shutdown());
    super.dispose();
  }
}
