import 'dart:async';
import 'dart:io';

/// Ordena o acesso a cada projeto/rascunho, inclusive entre servicos diferentes.
class ProjectFileStorage {
  static final _pending = <String, Future<void>>{};

  static Future<T> _run<T>(
    String path,
    Future<T> Function(File file) operation,
  ) {
    final file = File.fromUri(File(path).absolute.uri.normalizePath());
    final key = Platform.isWindows ? file.path.toLowerCase() : file.path;
    final previous = _pending[key] ?? Future<void>.value();
    final result = previous.then((_) => operation(file));
    // Uma falha continua sendo entregue ao chamador, mas nao trava a fila.
    final completed = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _pending[key] = completed;
    unawaited(
      completed.then((_) {
        if (identical(_pending[key], completed)) _pending.remove(key);
      }),
    );
    return result;
  }

  static Future<void> write(
    String path,
    FutureOr<String> Function() contents,
  ) => _run(path, (file) async {
    final text = await contents();
    await file.parent.create(recursive: true);
    final staging = await file.parent.createTemp('.tgi_project_write_');
    final temporary = File(
      '${staging.path}${Platform.pathSeparator}project.tmp',
    );
    final backup = File('${file.path}.bak');
    try {
      await temporary.writeAsString(text, flush: true);
      if (await file.exists()) {
        await file.copy(backup.path);
      }
      // Substitui somente depois de gravar todo o novo conteudo. Nao apaga
      // primeiro o original: uma falha de escrita nao deve deixar um vazio.
      await temporary.rename(file.path);
      try {
        if (await backup.exists()) await backup.delete();
      } catch (_) {
        // Falhar ao limpar um backup nao transforma uma gravacao em falha.
      }
    } catch (_) {
      try {
        if (!await file.exists() && await backup.exists()) {
          await backup.copy(file.path);
        }
      } catch (_) {
        // Mantem o backup para recuperacao e preserva a falha original.
      }
      rethrow;
    } finally {
      try {
        await staging.delete(recursive: true);
      } catch (_) {
        // Este diretorio temporario pertence apenas a esta gravacao.
      }
    }
  });

  static Future<String> read(String path) => _run(path, (file) async {
    final readable = await file.exists() ? file : File('${file.path}.bak');
    return readable.readAsString();
  });

  static Future<void> delete(String path) => _run(path, (file) async {
    for (final candidate in [
      file,
      File('${file.path}.bak'),
      File('${file.path}.tmp'),
    ]) {
      if (await candidate.exists()) await candidate.delete();
    }
  });
}
