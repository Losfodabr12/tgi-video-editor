import 'package:flutter/material.dart';

import '../../../../domain/text_style_profile.dart';

/// New caption preset only. Legacy text keeps the original Text widget/style.
class StyledCaptionText extends StatelessWidget {
  const StyledCaptionText(
    this.text, {
    super.key,
    required this.fontSize,
    this.color = const Color(NewTextStyle.textColor),
    this.scale = 1,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final double fontSize, scale;
  final Color color;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: 'Editor UI',
      fontWeight: FontWeight.w700,
      fontSize: fontSize,
      height: 1.08,
    );
    return Stack(
      children: [
        ExcludeSemantics(
          child: Text(
            text,
            textAlign: TextAlign.center,
            maxLines: maxLines,
            overflow: overflow,
            style: style.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeJoin = StrokeJoin.round
                ..strokeWidth = NewTextStyle.outlineWidth * scale * 2
                ..color = Colors.black.withValues(alpha: color.a),
            ),
          ),
        ),
        Text(
          text,
          textAlign: TextAlign.center,
          maxLines: maxLines,
          overflow: overflow,
          style: style.copyWith(
            color: color,
            shadows: [
              Shadow(
                color: const Color(
                  NewTextStyle.shadowColor,
                ).withValues(alpha: (0x73 / 255) * color.a),
                offset: Offset(2 * scale, 2 * scale),
                blurRadius: scale,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
