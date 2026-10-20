import 'package:flutter/material.dart';

import '../../../services/editor_font_service.dart';
import '../../../services/subtitle_service.dart';

class CaptionStyleDialog extends StatefulWidget {
  const CaptionStyleDialog({super.key, this.initial = const CaptionStyle()});
  final CaptionStyle initial;
  @override
  State<CaptionStyleDialog> createState() => _CaptionStyleDialogState();
}

class _CaptionStyleDialogState extends State<CaptionStyleDialog> {
  late String _font = widget.initial.fontFamily;
  late double _size = widget.initial.fontSize.clamp(12, 120);
  late double _y = widget.initial.y.clamp(0, 1);
  late int _color = widget.initial.textColor;
  late int _background = widget.initial.backgroundColor;
  @override
  Widget build(BuildContext context) {
    final fonts = {_font, ...EditorFontService.families}.toList();
    return AlertDialog(
      title: const Text('Estilo de todas as legendas'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                key: const ValueKey('caption_style_font'),
                initialValue: _font,
                decoration: const InputDecoration(labelText: 'Fonte'),
                items: [
                  for (final font in fonts)
                    DropdownMenuItem(value: font, child: Text(font)),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _font = value);
                },
              ),
              Text('Tamanho: ${_size.round()}'),
              Slider(
                key: const ValueKey('caption_style_size'),
                value: _size,
                min: 12,
                max: 120,
                onChanged: (v) => setState(() => _size = v),
              ),
              const Text('Posição vertical'),
              Slider(value: _y, onChanged: (v) => setState(() => _y = v)),
              Wrap(
                spacing: 8,
                children: [
                  for (final color in [
                    0xFFFFFFFF,
                    0xFFFFD166,
                    0xFF000000,
                    0xFF44DDEE,
                    0xFFFF5555,
                  ])
                    IconButton(
                      tooltip: 'Cor ${color.toRadixString(16)}',
                      onPressed: () => setState(() => _color = color),
                      icon: Icon(
                        _color == color ? Icons.check_circle : Icons.circle,
                        color: Color(color),
                      ),
                    ),
                ],
              ),
              SwitchListTile(
                title: const Text('Fundo escuro'),
                value: _background != 0,
                onChanged: (v) =>
                    setState(() => _background = v ? 0x99000000 : 0),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                color: Color(_background),
                child: Text(
                  'Prévia da legenda',
                  style: TextStyle(
                    fontFamily: _font,
                    fontSize: _size.clamp(12, 48),
                    color: Color(_color),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const ValueKey('caption_style_apply'),
          onPressed: () => Navigator.pop(
            context,
            CaptionStyle(
              fontFamily: _font,
              fontSize: _size,
              textColor: _color,
              backgroundColor: _background,
              opacity: widget.initial.opacity,
              x: widget.initial.x,
              y: _y,
            ),
          ),
          child: const Text('Aplicar a todas'),
        ),
      ],
    );
  }
}
