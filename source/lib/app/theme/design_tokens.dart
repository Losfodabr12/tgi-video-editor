import 'package:flutter/material.dart';

class TgiColors {
  const TgiColors._();

  static const Color backgroundDeep = Color(0xFF0B0C0E);
  static const Color background = Color(0xFF0F1013);
  static const Color surface = Color(0xFF18191D);
  static const Color surfacePanel = Color(0xFF15161A);
  static const Color surfaceAlt = Color(0xFF1D1F24);
  static const Color surfaceRaised = Color(0xFF23252B);
  static const Color surfaceRail = Color(0xFF131418);
  static const Color surfacePressed = Color(0xFF292C33);

  // O fallback e neutro. Cores de identidade vêm do estilo escolhido no tema.
  static Color accent = const Color(0xFFB8B8BE);
  static Color accentSoft = const Color(0xFFD0D0D4);
  static Color accentDim = const Color(0xFF3B3B41);
  static Color accentMuted = const Color(0xFF323238);
  static Color accentCool = const Color(0xFFB8B8BE);
  static Color accentBlue = const Color(0xFFB8B8BE);
  static Color accentGreen = const Color(0xFFB8B8BE);
  static Color accentRose = const Color(0xFFB8B8BE);

  static void applyAccent(Color primary) {
    accent = primary;
    accentSoft = Color.lerp(primary, textPrimary, 0.28)!;
    accentDim = Color.lerp(surfacePressed, primary, 0.34)!;
    accentMuted = Color.lerp(surfacePressed, primary, 0.20)!;
    accentCool = primary;
    accentBlue = primary;
    accentGreen = primary;
    accentRose = primary;
    waveformHigh = primary;
    playheadGlow = primary;
  }

  static const Color textPrimary = Color(0xFFF7F7F8);
  static const Color textMuted = Color(0xFF9699A2);
  static const Color textSecondary = Color(0xFFB8BAC1);
  static const Color textDisabled = Color(0xFF666A73);

  static const Color border = Color(0xFF2B2D33);
  static const Color borderSubtle = Color(0xFF22242A);
  static const Color borderStrong = Color(0xFF3A3D45);

  static const Color timelineLane = Color(0xFF121212);
  static const Color timelineLaneAlt = Color(0xFF101010);
  static const Color timelineGrid = Color(0xFF2A2A2A);
  static const Color waveformLow = Color(0xFF606067);
  static Color waveformHigh = accent;
  static Color playheadGlow = accent;
  static const Color glowBorder = border;
  static const Color glowOuter = transparent;
  static const Color glowSoft = transparent;

  static const Color danger = Color(0xFFFF6178);
  static const Color success = Color(0xFF5ED6A8);
  static const Color warning = Color(0xFFF1C84B);
  static const Color info = Color(0xFF76A9FA);
  static const Color transparent = Color(0x00000000);
  static const Color black = Color(0xFF000000);
  static const Color white = Color(0xFFF4F4F5);
  static const Color scrim = Color(0xD9111113);
  static const Color shadow = Color(0x99000000);
  static const Color shadowSoft = Color(0x66000000);
}

class TgiRadii {
  const TgiRadii._();

  // Desktop criativo usa cantos contidos: a hierarquia vem de contraste,
  // divisores e espacamento, sem transformar cada superficie em um card.
  static const double xs = 2;
  static const double sm = 4;
  static const double md = 6;
  static const double lg = 8;
  static const double xl = 10;
  static const double pill = 999;
}

class TgiSpacing {
  const TgiSpacing._();

  static const double xxs = 4;
  static const double xs = 6;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
}

class TgiIconSizes {
  const TgiIconSizes._();

  static const double sm = 14;
  static const double md = 18;
  static const double lg = 22;
  static const double rail = 24;
}

class TgiTextStyles {
  const TgiTextStyles._();

  static TextStyle display({
    Color color = TgiColors.textPrimary,
    double? fontSize,
    FontWeight fontWeight = FontWeight.w700,
    FontStyle? fontStyle,
    double letterSpacing = 0,
  }) {
    return TextStyle(
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      letterSpacing: letterSpacing,
    );
  }
}

class TgiAccentText extends StatelessWidget {
  const TgiAccentText(
    this.text, {
    required this.style,
    this.maxLines,
    this.overflow,
    super.key,
  });

  final String text;
  final TextStyle style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: maxLines,
      overflow: overflow,
      style: style.copyWith(color: Theme.of(context).colorScheme.primary),
    );
  }
}

class TgiAccentIcon extends StatelessWidget {
  const TgiAccentIcon(this.icon, {this.size, super.key});

  final IconData icon;
  final double? size;

  @override
  Widget build(BuildContext context) {
    return Icon(icon, size: size, color: Theme.of(context).colorScheme.primary);
  }
}

class TgiWorkspaceTitle extends StatelessWidget {
  const TgiWorkspaceTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final largeText = MediaQuery.textScalerOf(context).scale(16) >= 24;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.10),
            border: Border.all(color: primary.withValues(alpha: 0.32)),
            borderRadius: BorderRadius.circular(TgiRadii.md),
          ),
          child: Icon(icon, color: primary, size: TgiIconSizes.md),
        ),
        const SizedBox(width: TgiSpacing.md),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: TgiColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              if (!largeText)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: TgiColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class TgiFramedBox extends StatelessWidget {
  const TgiFramedBox({
    required this.child,
    this.radius = TgiRadii.md,
    this.strokeWidth = 1,
    this.padding,
    this.backgroundColor = TgiColors.surfacePressed,
    this.borderColor = TgiColors.border,
    this.clipBehavior = Clip.antiAlias,
    super.key,
  });

  final Widget child;
  final double radius;
  final double strokeWidth;
  final EdgeInsetsGeometry? padding;
  final Color backgroundColor;
  final Color borderColor;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border.all(color: borderColor, width: strokeWidth),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: clipBehavior,
        child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
      ),
    );
  }
}

class TgiProgressBar extends StatelessWidget {
  const TgiProgressBar({
    required this.value,
    this.height = 4,
    this.backgroundColor = TgiColors.border,
    super.key,
  });

  final double value;
  final double height;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final progress = value.clamp(0.0, 1.0).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(TgiRadii.pill),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 0.0;
          return Stack(
            children: [
              ColoredBox(
                color: backgroundColor,
                child: SizedBox(height: height, width: double.infinity),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                height: height,
                width: width * progress,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          );
        },
      ),
    );
  }
}

class TgiSliderTrackShape extends RoundedRectSliderTrackShape {
  const TgiSliderTrackShape();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    double additionalActiveTrackHeight = 2,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    if (trackRect.isEmpty) {
      return;
    }

    final radius = Radius.circular(trackRect.height / 2);
    final inactivePaint = Paint()
      ..color = sliderTheme.inactiveTrackColor ?? TgiColors.border;
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, radius),
      inactivePaint,
    );

    final activeRect = textDirection == TextDirection.ltr
        ? Rect.fromLTRB(
            trackRect.left,
            trackRect.top,
            thumbCenter.dx.clamp(trackRect.left, trackRect.right).toDouble(),
            trackRect.bottom,
          )
        : Rect.fromLTRB(
            thumbCenter.dx.clamp(trackRect.left, trackRect.right).toDouble(),
            trackRect.top,
            trackRect.right,
            trackRect.bottom,
          );
    if (activeRect.width <= 0) {
      return;
    }
    final activePaint = Paint()..color = TgiColors.accent;
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(activeRect, radius),
      activePaint,
    );
  }
}
