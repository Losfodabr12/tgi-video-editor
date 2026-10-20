import 'package:flutter/material.dart';

import 'design_tokens.dart';

class TgiDecorations {
  const TgiDecorations._();

  static BoxDecoration panel({
    Color color = TgiColors.surfacePanel,
    Color borderColor = TgiColors.border,
    double radius = TgiRadii.md,
  }) {
    return BoxDecoration(
      color: color,
      border: Border.all(color: borderColor),
      borderRadius: BorderRadius.circular(radius),
    );
  }

  static BoxDecoration glowingPanel({
    Color color = TgiColors.surfacePanel,
    double radius = TgiRadii.md,
  }) {
    return BoxDecoration(
      color: color,
      border: Border.all(color: TgiColors.border),
      borderRadius: BorderRadius.circular(radius),
    );
  }

  static BoxDecoration appHeader() {
    return BoxDecoration(
      color: TgiColors.surfaceRail,
      border: Border.all(color: TgiColors.borderStrong),
      borderRadius: BorderRadius.circular(TgiRadii.xs),
    );
  }

  static BoxDecoration toolRail() {
    return BoxDecoration(
      color: TgiColors.surfaceRail,
      border: Border.all(color: TgiColors.borderStrong),
      borderRadius: BorderRadius.circular(TgiRadii.md),
    );
  }

  static BoxDecoration controlCluster() {
    return BoxDecoration(
      color: TgiColors.surface.withValues(alpha: 0.88),
      border: Border.all(color: TgiColors.borderStrong),
      borderRadius: BorderRadius.circular(TgiRadii.md),
    );
  }

  static BoxDecoration activeControl({
    double radius = TgiRadii.md,
    Color color = TgiColors.surfaceHover,
  }) {
    return BoxDecoration(
      color: color,
      border: Border.all(color: TgiColors.border),
      borderRadius: BorderRadius.circular(radius),
    );
  }

  static List<BoxShadow> get activeGlow => const [];
}
