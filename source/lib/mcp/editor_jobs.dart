import 'dart:async';
import '../core/commands/editor_command.dart';

class EditorJobContext {
  bool cancelled = false;
  double progress = 0;
  String message = '';
  FutureOr<void> Function()? onCancel;
  void check() {
    if (cancelled) {
      throw const CommandError('cancelled', 'Job cancelado.');
    }
  }

  void update(double value, [String text = '']) {
    if (!cancelled) {
      progress = value.clamp(0, 1);
      message = text;
    }
  }
}

class EditorJob {
  EditorJob(this.id, this.kind, this.revision, this.projectId);
  final String id, kind, projectId;
  final int revision;
  final context = EditorJobContext();
  String status = 'queued';
  Object? result;
  Map<String, Object?>? error;
  bool get finished => ['completed', 'failed', 'cancelled'].contains(status);
  Map<String, Object?> toJson() => {
    'job_id': id,
    'kind': kind,
    'project_id': projectId,
    'base_revision': revision,
    'status': status,
    'progress': context.progress,
    'message': context.message,
    if (result != null) 'result': result,
    if (error != null) 'error': error,
  };
}

/// Native work is queued to bound CPU/memory and isolate cancellation ownership.
class EditorJobs {
  EditorJobs({this.onChanged});
  final void Function()? onChanged;
  final Map<String, EditorJob> _jobs = {};
  Future<void> _tail = Future.value();
  bool _closed = false;
  int _counter = 0;
  Iterable<EditorJob> get all => _jobs.values;
  EditorJob get(String id) =>
      _jobs[id] ??
      (throw CommandError('job_not_found', 'Job desconhecido.', {
        'valid_job_ids': _jobs.keys.toList(),
      }));
  EditorJob start(
    String kind,
    int revision,
    String projectId,
    Future<Object?> Function(EditorJobContext) run,
  ) {
    if (_closed) {
      throw const CommandError('server_stopped', 'Serviço de jobs encerrado.');
    }
    if (_jobs.values.where((j) => !j.finished).length >= 8) {
      throw const CommandError(
        'job_limit',
        'Aguarde ou cancele jobs pendentes.',
        {'maximum_pending': 8},
      );
    }
    while (_jobs.length >= 50 && _jobs.values.any((j) => j.finished)) {
      _jobs.remove(_jobs.values.firstWhere((j) => j.finished).id);
    }
    final job = EditorJob('job_${++_counter}', kind, revision, projectId);
    _jobs[job.id] = job;
    _tail = _tail.then((_) async {
      if (job.context.cancelled) {
        return;
      }
      job.status = 'running';
      onChanged?.call();
      try {
        final result = await run(job.context);
        job.context.check();
        job.result = result;
        job.status = 'completed';
        job.context.progress = 1;
      } catch (e) {
        if (job.context.cancelled) {
          job.status = 'cancelled';
        } else {
          job.status = 'failed';
          job.error =
              (e is CommandError
                      ? e
                      : CommandError('analysis_failed', e.toString()))
                  .toJson();
        }
      } finally {
        job.context.onCancel = null;
        onChanged?.call();
      }
    });
    onChanged?.call();
    return job;
  }

  Future<void> cancel(String id) async {
    final job = get(id);
    if (job.finished) {
      return;
    }
    job.context.cancelled = true;
    job.status = 'cancelled';
    job.result = null;
    await job.context.onCancel?.call();
    onChanged?.call();
  }

  Future<void> cancelAll() async {
    for (final job in _jobs.values.toList()) {
      await cancel(job.id);
    }
  }

  Future<void> close() async {
    _closed = true;
    await cancelAll();
  }
}
