import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_shaders/flutter_shaders.dart';

/// Chroma distance is evaluated per pixel on the GPU, including neutral keys.
/// Sampling stays on the GPU; it does not read video frames back into Dart.
class ChromaKeyPreview extends StatelessWidget {
  const ChromaKeyPreview({
    required this.color,
    required this.similarity,
    required this.blend,
    required this.child,
    super.key,
  });

  final int color;
  final double similarity;
  final double blend;
  final Widget child;

  @override
  Widget build(BuildContext context) => ShaderBuilder(
    assetKey: 'assets/shaders/chroma_key.frag',
    (context, shader, child) =>
        AnimatedSampler((ui.Image image, Size size, Canvas canvas) {
          shader
            ..setFloat(0, size.width)
            ..setFloat(1, size.height)
            ..setFloat(2, ((color >> 16) & 255) / 255)
            ..setFloat(3, ((color >> 8) & 255) / 255)
            ..setFloat(4, (color & 255) / 255)
            ..setFloat(5, similarity.clamp(0.01, 1.0))
            ..setFloat(6, blend.clamp(0.0, 1.0))
            ..setImageSampler(0, image);
          canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
        }, child: child!),
    child: child,
  );
}
