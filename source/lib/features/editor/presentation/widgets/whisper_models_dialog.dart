import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../services/whisper_model_service.dart';
import '../../../../services/whisper_runtime.dart';

class WhisperModelsDialog extends StatefulWidget {
  const WhisperModelsDialog({
    super.key,
    this.service = const WhisperModelService(),
  });
  final WhisperModelService service;
  @override
  State<WhisperModelsDialog> createState() => _WhisperModelsDialogState();
}

class _WhisperModelsDialogState extends State<WhisperModelsDialog> {
  List<InstalledWhisperModel> _installed = [];
  String _recommendation = 'Verificando recursos locais';
  String? _active, _message;
  double _progress = 0;
  WhisperModelDownloadCancellationToken? _cancel;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final models = await widget.service.listInstalledModels();
    final recommendation = await widget.service.machineRecommendation();
    if (!mounted) return;
    setState(() {
      _installed = models;
      _recommendation = '${recommendation.info.name}: ${recommendation.reason}';
    });
  }

  Future<void> _download(WhisperModelInfo info) async {
    final cancel = WhisperModelDownloadCancellationToken();
    setState(() {
      _active = info.name;
      _progress = 0;
      _message = null;
      _cancel = cancel;
    });
    try {
      await widget.service.installModel(
        info,
        userInitiated: true,
        cancellationToken: cancel,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (mounted) {
        setState(() => _message = '${info.name}: SHA-256 verificado.');
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _message = cancel.isCancelled
              ? 'Pausado. O arquivo parcial será retomado no próximo clique.'
              : e.toString(),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _active = null;
          _cancel = null;
        });
        await _refresh();
      }
    }
  }

  Future<void> _remove(WhisperModelInfo info) async {
    await widget.service.removeModel(info.name);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Modelos de transcrição'),
    content: SizedBox(
      width: 650,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_recommendation),
            ValueListenableBuilder<String>(
              valueListenable: WhisperRuntime.backend,
              builder: (_, value, _) => Text('Backend: $value'),
            ),
            const Text(
              'Base continua como padrão. Modelos opcionais, baixados somente ao clicar. Qualidade aguarda medição de WER.',
            ),
            if (_message != null) SelectableText(_message!),
            for (final info in whisperModelCatalog.where(
              (m) => m.name != 'tiny',
            ))
              _row(info),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Fechar'),
      ),
    ],
  );
  Widget _row(WhisperModelInfo info) {
    final found = _installed.where((m) => m.info.name == info.name).firstOrNull;
    return FutureBuilder<String>(
      future: widget.service.pathForModel(info),
      builder: (context, target) {
        final removable =
            found != null &&
            target.hasData &&
            File(found.path).absolute.path == File(target.data!).absolute.path;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${info.name} — ${(info.sizeBytes / 1000000).toStringAsFixed(1)} MB',
                ),
                Text(
                  found == null
                      ? 'Não instalado'
                      : 'Instalado${found.hasExpectedSize ? '' : ' — tamanho inesperado'}',
                ),
                if (_active == info.name) ...[
                  LinearProgressIndicator(value: _progress),
                  Text('${(_progress * 100).toStringAsFixed(1)}%'),
                  TextButton(
                    onPressed: () => _cancel?.cancel(),
                    child: const Text('Pausar'),
                  ),
                ] else
                  Row(
                    children: [
                      if (found == null || !found.hasExpectedSize)
                        TextButton(
                          onPressed: _active == null
                              ? () => _download(info)
                              : null,
                          child: const Text('Baixar / retomar'),
                        ),
                      if (removable)
                        TextButton(
                          onPressed: _active == null
                              ? () => _remove(info)
                              : null,
                          child: const Text('Remover'),
                        ),
                      if (found != null && !removable)
                        const Text('Incluído na instalação'),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
