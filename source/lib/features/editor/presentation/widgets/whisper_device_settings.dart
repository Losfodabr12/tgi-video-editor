import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../services/app_preferences_service.dart';
import '../../../../services/whisper_runtime.dart';

class WhisperDeviceSettings extends StatefulWidget {
  const WhisperDeviceSettings({super.key, this.preferences, this.detect});
  final AppPreferencesService? preferences;
  final Future<List<WhisperGpuDevice>> Function()? detect;
  @override
  State<WhisperDeviceSettings> createState() => _WhisperDeviceSettingsState();
}

class _WhisperDeviceSettingsState extends State<WhisperDeviceSettings> {
  String _choice = 'auto';
  List<WhisperGpuDevice> _devices = const [];
  bool _loading = true;
  String? _error;
  AppPreferencesService get _preferences =>
      widget.preferences ?? AppPreferencesService.instance;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final preferences = await _preferences.load();
    final devices = await (widget.detect ?? WhisperRuntime.refreshDevices)();
    if (!mounted) return;
    setState(() {
      _choice = preferences.whisperDevice;
      _devices = devices;
      _loading = false;
    });
  }

  Future<void> _save() async {
    try {
      final preferences = await _preferences.load();
      await _preferences.save(preferences.copyWith(whisperDevice: _choice));
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = 'Não foi possível salvar: $error');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Configurações de transcrição'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ValueListenableBuilder<String>(
              valueListenable: WhisperRuntime.backend,
              builder: (_, value, child) =>
                  Text('Ativo: ${WhisperRuntime.description}'),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const LinearProgressIndicator()
            else
              DropdownButtonFormField<String>(
                key: ValueKey('whisper-device-$_choice'),
                initialValue: _choice,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Dispositivo para próximas transcrições',
                ),
                items: [
                  const DropdownMenuItem(
                    value: 'auto',
                    child: Text('Automático (prefere GPU dedicada)'),
                  ),
                  const DropdownMenuItem(value: 'cpu', child: Text('CPU')),
                  for (final device in _devices)
                    DropdownMenuItem(
                      value: device.id,
                      child: Text(
                        '${device.name} (${device.discrete ? 'dedicada' : 'integrada'})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (_choice != 'auto' &&
                      _choice != 'cpu' &&
                      !_devices.any((d) => d.id == _choice))
                    DropdownMenuItem(
                      value: _choice,
                      child: const Text('GPU indisponível — fallback CPU'),
                    ),
                ],
                onChanged: (value) => setState(() => _choice = value ?? 'auto'),
              ),
            for (final device in _devices)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Vulkan · ${device.name}: ${(device.freeBytes / 1073741824).toStringAsFixed(1)} GiB livres de ${(device.totalBytes / 1073741824).toStringAsFixed(1)} GiB',
                ),
              ),
            if (!_loading && _devices.isEmpty)
              const Text(
                'Nenhuma GPU Vulkan compatível disponível. A CPU será usada.',
              ),
            if (_error != null) Text(_error!),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: _loading ? null : _save,
        child: const Text('Salvar'),
      ),
    ],
  );
}
