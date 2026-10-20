import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../app/theme/design_tokens.dart';
import '../application/editor_controller.dart';

enum EditorShortcutAction {
  undo,
  redo,
  split,
  copy,
  paste,
  duplicate,
  playPause,
  delete,
}

class EditorShortcutInfo {
  const EditorShortcutInfo({
    required this.action,
    required this.label,
    required this.description,
  });

  final EditorShortcutAction action;
  final String label;
  final String description;
}

const editorShortcutInfos = [
  EditorShortcutInfo(
    action: EditorShortcutAction.undo,
    label: 'Desfazer',
    description: 'Volta a última edição.',
  ),
  EditorShortcutInfo(
    action: EditorShortcutAction.redo,
    label: 'Refazer',
    description: 'Reaplica a edição desfeita.',
  ),
  EditorShortcutInfo(
    action: EditorShortcutAction.split,
    label: 'Cortar no playhead',
    description: 'Divide o clipe ativo na posição atual.',
  ),
  EditorShortcutInfo(
    action: EditorShortcutAction.copy,
    label: 'Copiar clipes',
    description: 'Copia a seleção atual.',
  ),
  EditorShortcutInfo(
    action: EditorShortcutAction.paste,
    label: 'Colar clipes',
    description: 'Cola os clipes copiados.',
  ),
  EditorShortcutInfo(
    action: EditorShortcutAction.duplicate,
    label: 'Duplicar clipes',
    description: 'Duplica a seleção atual.',
  ),
  EditorShortcutInfo(
    action: EditorShortcutAction.playPause,
    label: 'Play / pause',
    description: 'Alterna a reprodução da timeline.',
  ),
  EditorShortcutInfo(
    action: EditorShortcutAction.delete,
    label: 'Apagar seleção',
    description: 'Remove os clipes selecionados.',
  ),
];

Map<EditorShortcutAction, SingleActivator> defaultEditorShortcutBindings() {
  return const {
    EditorShortcutAction.undo: SingleActivator(
      LogicalKeyboardKey.keyZ,
      control: true,
    ),
    EditorShortcutAction.redo: SingleActivator(
      LogicalKeyboardKey.keyY,
      control: true,
    ),
    EditorShortcutAction.split: SingleActivator(LogicalKeyboardKey.keyS),
    EditorShortcutAction.copy: SingleActivator(
      LogicalKeyboardKey.keyC,
      control: true,
    ),
    EditorShortcutAction.paste: SingleActivator(
      LogicalKeyboardKey.keyV,
      control: true,
    ),
    EditorShortcutAction.duplicate: SingleActivator(
      LogicalKeyboardKey.keyD,
      control: true,
    ),
    EditorShortcutAction.playPause: SingleActivator(LogicalKeyboardKey.space),
    EditorShortcutAction.delete: SingleActivator(LogicalKeyboardKey.delete),
  };
}

class KeyboardShortcutsDialog extends StatefulWidget {
  const KeyboardShortcutsDialog({super.key, required this.initialBindings});

  final Map<EditorShortcutAction, SingleActivator> initialBindings;

  @override
  State<KeyboardShortcutsDialog> createState() =>
      KeyboardShortcutsDialogState();
}

class KeyboardShortcutsDialogState extends State<KeyboardShortcutsDialog> {
  late Map<EditorShortcutAction, SingleActivator> _bindings = {
    ...widget.initialBindings,
  };
  String? _errorText;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Configurações de teclas'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Clique em Alterar e pressione a nova combinação de teclas.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: TgiSpacing.md),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: editorShortcutInfos.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: TgiSpacing.sm),
                itemBuilder: (context, index) {
                  final info = editorShortcutInfos[index];
                  return _KeyboardShortcutRow(
                    info: info,
                    activator: _bindings[info.action]!,
                    onChange: () => _captureShortcut(info),
                    onReset: () => _resetShortcut(info.action),
                  );
                },
              ),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: TgiSpacing.md),
              Text(
                _errorText!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: TgiColors.danger),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _resetAllShortcuts,
          child: const Text('Restaurar padrão'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_bindings),
          child: const Text('Aplicar'),
        ),
      ],
    );
  }

  Future<void> _captureShortcut(EditorShortcutInfo info) async {
    final activator = await showDialog<SingleActivator>(
      context: context,
      builder: (context) => _ShortcutCaptureDialog(actionLabel: info.label),
    );
    if (activator == null || !mounted) {
      return;
    }

    final conflictingAction = _conflictingAction(info.action, activator);
    if (conflictingAction != null) {
      setState(() {
        _errorText =
            'Atalho já usado por ${shortcutInfoFor(conflictingAction).label}.';
      });
      return;
    }

    setState(() {
      _errorText = null;
      _bindings = {..._bindings, info.action: activator};
    });
  }

  void _resetShortcut(EditorShortcutAction action) {
    setState(() {
      _errorText = null;
      _bindings = {
        ..._bindings,
        action: defaultEditorShortcutBindings()[action]!,
      };
    });
  }

  void _resetAllShortcuts() {
    setState(() {
      _errorText = null;
      _bindings = defaultEditorShortcutBindings();
    });
  }

  EditorShortcutAction? _conflictingAction(
    EditorShortcutAction action,
    SingleActivator activator,
  ) {
    for (final entry in _bindings.entries) {
      if (entry.key == action) {
        continue;
      }
      if (_sameShortcutActivator(entry.value, activator)) {
        return entry.key;
      }
    }
    return null;
  }
}

class _KeyboardShortcutRow extends StatelessWidget {
  const _KeyboardShortcutRow({
    required this.info,
    required this.activator,
    required this.onChange,
    required this.onReset,
  });

  final EditorShortcutInfo info;
  final SingleActivator activator;
  final VoidCallback onChange;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TgiColors.surface.withValues(alpha: 0.78),
        border: Border.all(color: TgiColors.borderSubtle),
        borderRadius: BorderRadius.circular(TgiRadii.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(TgiSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    info.description,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: TgiSpacing.md),
            _ShortcutKeyChip(label: shortcutLabel(activator)),
            const SizedBox(width: TgiSpacing.sm),
            TextButton(onPressed: onChange, child: const Text('Alterar')),
            IconButton(
              tooltip: 'Restaurar padrão',
              onPressed: onReset,
              icon: const Icon(Icons.restart_alt, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutKeyChip extends StatelessWidget {
  const _ShortcutKeyChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TgiColors.surfacePressed,
        border: Border.all(color: TgiColors.accentMuted),
        borderRadius: BorderRadius.circular(TgiRadii.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TgiSpacing.sm,
          vertical: TgiSpacing.xs,
        ),
        child: TgiAccentText(
          label,
          style:
              Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w900) ??
              const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _ShortcutCaptureDialog extends StatefulWidget {
  const _ShortcutCaptureDialog({required this.actionLabel});

  final String actionLabel;

  @override
  State<_ShortcutCaptureDialog> createState() => _ShortcutCaptureDialogState();
}

class _ShortcutCaptureDialogState extends State<_ShortcutCaptureDialog> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Novo atalho: ${widget.actionLabel}'),
      content: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: TgiColors.surface,
            border: Border.all(color: TgiColors.accentMuted),
            borderRadius: BorderRadius.circular(TgiRadii.lg),
          ),
          child: const Padding(
            padding: EdgeInsets.all(TgiSpacing.xxl),
            child: Text(
              'Pressione uma tecla ou combinação agora.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return;
    }
    final trigger = event.logicalKey;
    if (_isModifierKey(trigger)) {
      return;
    }
    Navigator.of(context).pop(
      SingleActivator(
        trigger,
        control: HardwareKeyboard.instance.isControlPressed,
        shift: HardwareKeyboard.instance.isShiftPressed,
        alt: HardwareKeyboard.instance.isAltPressed,
        meta: HardwareKeyboard.instance.isMetaPressed,
      ),
    );
  }
}

EditorShortcutInfo shortcutInfoFor(EditorShortcutAction action) {
  return editorShortcutInfos.firstWhere((info) => info.action == action);
}

bool _sameShortcutActivator(SingleActivator a, SingleActivator b) {
  return a.trigger == b.trigger &&
      a.control == b.control &&
      a.shift == b.shift &&
      a.alt == b.alt &&
      a.meta == b.meta;
}

bool eventMatchesShortcut(KeyEvent event, SingleActivator activator) {
  return event.logicalKey == activator.trigger &&
      HardwareKeyboard.instance.isControlPressed == activator.control &&
      HardwareKeyboard.instance.isShiftPressed == activator.shift &&
      HardwareKeyboard.instance.isAltPressed == activator.alt &&
      HardwareKeyboard.instance.isMetaPressed == activator.meta;
}

bool _isModifierKey(LogicalKeyboardKey key) {
  return key == LogicalKeyboardKey.controlLeft ||
      key == LogicalKeyboardKey.controlRight ||
      key == LogicalKeyboardKey.shiftLeft ||
      key == LogicalKeyboardKey.shiftRight ||
      key == LogicalKeyboardKey.altLeft ||
      key == LogicalKeyboardKey.altRight ||
      key == LogicalKeyboardKey.metaLeft ||
      key == LogicalKeyboardKey.metaRight;
}

String shortcutLabel(SingleActivator activator) {
  final parts = <String>[
    if (activator.control) 'Ctrl',
    if (activator.shift) 'Shift',
    if (activator.alt) 'Alt',
    if (activator.meta) 'Meta',
    _keyLabel(activator.trigger),
  ];
  return parts.join(' + ');
}

String _keyLabel(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.space) return 'Space';
  if (key == LogicalKeyboardKey.delete) return 'Delete';
  if (key == LogicalKeyboardKey.backspace) return 'Backspace';
  if (key == LogicalKeyboardKey.escape) return 'Esc';
  if (key.keyLabel.trim().isNotEmpty) return key.keyLabel.toUpperCase();
  return key.debugName ?? key.keyId.toRadixString(16).toUpperCase();
}

class EditorKeyboardDispatcher {
  const EditorKeyboardDispatcher({
    required this.context,
    required this.controller,
    required this.shortcutsAllowed,
    required this.bindings,
    required this.callbackFor,
    required this.save,
    required this.load,
    required this.redo,
    required this.delete,
    required this.markRange,
    required this.framesPerSecond,
  });
  final BuildContext context;
  final EditorController controller;
  final bool shortcutsAllowed;
  final Map<EditorShortcutAction, SingleActivator> bindings;
  final VoidCallback Function(EditorShortcutAction action) callbackFor;
  final Future<void> Function() save, load;
  final VoidCallback redo, delete;
  final void Function(bool start) markRange;
  final int framesPerSecond;
  bool handle(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return false;
    }
    if (ModalRoute.of(context)?.isCurrent != true) {
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    final command = keyboard.isControlPressed || keyboard.isMetaPressed;
    final saveShortcut =
        command &&
        !keyboard.isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyS;
    if (!shortcutsAllowed) {
      if (saveShortcut &&
          !bindings.values.any(
            (binding) => eventMatchesShortcut(event, binding),
          )) {
        unawaited(save());
        return true;
      }
      return false;
    }

    for (final entry in bindings.entries) {
      if (!eventMatchesShortcut(event, entry.value)) {
        continue;
      }
      callbackFor(entry.key).call();
      return true;
    }
    if (saveShortcut) {
      unawaited(save());
      return true;
    }
    if (command &&
        event.logicalKey == LogicalKeyboardKey.keyZ &&
        keyboard.isShiftPressed) {
      redo();
      return true;
    }
    if (command && event.logicalKey == LogicalKeyboardKey.keyO) {
      unawaited(load());
      return true;
    }
    if (!command &&
        !keyboard.isAltPressed &&
        (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
            event.logicalKey == LogicalKeyboardKey.arrowRight)) {
      final frame = Duration(microseconds: (1000000 / framesPerSecond).round());
      controller.setTimelinePlaybackActive(false);
      controller.setPlayheadPosition(
        controller.playheadPosition +
            (event.logicalKey == LogicalKeyboardKey.arrowLeft ? -frame : frame),
      );
      return true;
    }
    if (!keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed) {
      if (event.logicalKey == LogicalKeyboardKey.keyI) {
        markRange(true);
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyO) {
        markRange(false);
        return true;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      delete();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      controller.setCutMode(false);
      return true;
    }
    return false;
  }
}
