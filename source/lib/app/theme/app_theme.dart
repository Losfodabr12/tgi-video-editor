import 'package:flutter/material.dart';

import '../../services/app_preferences_service.dart';
import 'design_tokens.dart';

@immutable
class TgiVisualStyleTheme extends ThemeExtension<TgiVisualStyleTheme> {
  const TgiVisualStyleTheme(this.style);

  final AppVisualStyle style;

  bool get isClean => style == AppVisualStyle.clean;
  bool get isStudio => style == AppVisualStyle.studio;
  bool get isHighContrast => style == AppVisualStyle.highContrast;

  @override
  TgiVisualStyleTheme copyWith({AppVisualStyle? style}) {
    return TgiVisualStyleTheme(style ?? this.style);
  }

  @override
  TgiVisualStyleTheme lerp(covariant TgiVisualStyleTheme? other, double t) {
    return t < 0.5 ? this : (other ?? this);
  }
}

class TgiTheme {
  const TgiTheme._();

  static ThemeData get darkTheme => forStyle(AppVisualStyle.clean);

  static ThemeData forStyle(AppVisualStyle style) {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      fontFamily: TgiTextStyles.family,
    );
    const controlRadius = TgiRadii.sm;
    const primary = TgiColors.primary;

    return base.copyWith(
      extensions: [TgiVisualStyleTheme(style)],
      visualDensity: VisualDensity.compact,
      scaffoldBackgroundColor: TgiColors.background,
      shadowColor: TgiColors.transparent,
      focusColor: primary.withValues(alpha: 0.16),
      hoverColor: primary.withValues(alpha: 0.08),
      highlightColor: primary.withValues(alpha: 0.10),
      disabledColor: TgiColors.textDisabled,
      splashFactory: InkRipple.splashFactory,
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: primary,
        selectionColor: primary.withValues(alpha: 0.24),
        selectionHandleColor: primary,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      colorScheme: ColorScheme.dark(
        primary: primary,
        secondary: primary,
        surface: TgiColors.surface,
        surfaceContainer: TgiColors.surfacePanel,
        surfaceContainerHigh: TgiColors.surfaceRaised,
        error: TgiColors.danger,
        onPrimary: TgiColors.background,
        onSecondary: TgiColors.background,
        onSurface: TgiColors.textPrimary,
        onError: TgiColors.background,
      ),
      cardTheme: CardThemeData(
        color: TgiColors.surfacePanel,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: TgiColors.border),
          borderRadius: BorderRadius.circular(TgiRadii.sm),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: TgiColors.surfacePanel,
        elevation: 0,
        surfaceTintColor: TgiColors.transparent,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: TgiColors.textPrimary,
          fontWeight: FontWeight.w800,
        ),
        contentTextStyle: base.textTheme.bodyMedium?.copyWith(
          color: TgiColors.textSecondary,
          height: 1.4,
        ),
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: TgiColors.borderStrong),
          borderRadius: BorderRadius.circular(TgiRadii.md),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: TgiColors.surfacePanel,
        foregroundColor: TgiColors.textPrimary,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: TgiColors.transparent,
        toolbarHeight: 64,
        titleSpacing: TgiSpacing.lg,
        iconTheme: const IconThemeData(
          color: TgiColors.textSecondary,
          size: TgiIconSizes.lg,
        ),
        actionsIconTheme: const IconThemeData(
          color: TgiColors.textSecondary,
          size: TgiIconSizes.lg,
        ),
        titleTextStyle: base.textTheme.titleMedium?.copyWith(
          color: TgiColors.textPrimary,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        ),
        shape: const Border(bottom: BorderSide(color: TgiColors.borderSubtle)),
      ),
      dividerTheme: const DividerThemeData(
        color: TgiColors.border,
        thickness: 1,
      ),
      textTheme: base.textTheme
          .apply(
            bodyColor: TgiColors.textPrimary,
            displayColor: TgiColors.textPrimary,
          )
          .copyWith(
            bodyMedium: base.textTheme.bodyMedium?.copyWith(
              color: TgiColors.textPrimary,
            ),
            bodySmall: base.textTheme.bodySmall?.copyWith(
              color: TgiColors.textSecondary,
            ),
            titleLarge: base.textTheme.titleLarge?.copyWith(
              color: TgiColors.textPrimary,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
            titleMedium: base.textTheme.titleMedium?.copyWith(
              color: TgiColors.textPrimary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size(44, 32)),
          padding: WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          elevation: const WidgetStatePropertyAll(0),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? TgiColors.textDisabled
                : TgiColors.background,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? TgiColors.surfacePressed
                : states.contains(WidgetState.pressed)
                ? primary.withValues(alpha: 0.78)
                : primary,
          ),
          overlayColor: WidgetStatePropertyAll(
            TgiColors.white.withValues(alpha: 0.08),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(controlRadius),
            ),
          ),
          textStyle: const WidgetStatePropertyAll(TgiTextStyles.control),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: TgiColors.surface,
          foregroundColor: TgiColors.textPrimary,
          disabledBackgroundColor: TgiColors.surfacePressed,
          disabledForegroundColor: TgiColors.textDisabled,
          elevation: 0,
          side: BorderSide(color: TgiColors.borderStrong),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(controlRadius),
          ),
          minimumSize: Size(44, 32),
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          textStyle: TgiTextStyles.control,
          animationDuration: const Duration(milliseconds: 140),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size(44, 32)),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? TgiColors.textDisabled
                : states.contains(WidgetState.hovered)
                ? TgiColors.textPrimary
                : TgiColors.textSecondary,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.pressed)
                ? primary.withValues(alpha: 0.10)
                : states.contains(WidgetState.hovered)
                ? TgiColors.surfaceAlt
                : TgiColors.transparent,
          ),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color:
                  states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.focused)
                  ? primary.withValues(alpha: 0.58)
                  : TgiColors.border,
            ),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(controlRadius),
            ),
          ),
          padding: WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          textStyle: const WidgetStatePropertyAll(TgiTextStyles.control),
          animationDuration: const Duration(milliseconds: 140),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size(40, 32)),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? TgiColors.textDisabled
                : TgiColors.textSecondary,
          ),
          overlayColor: WidgetStatePropertyAll(primary.withValues(alpha: 0.08)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(controlRadius),
            ),
          ),
          textStyle: const WidgetStatePropertyAll(TgiTextStyles.control),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size.square(32)),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? TgiColors.textDisabled
                : states.contains(WidgetState.hovered)
                ? TgiColors.textPrimary
                : TgiColors.textSecondary,
          ),
          overlayColor: WidgetStatePropertyAll(primary.withValues(alpha: 0.10)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(controlRadius),
            ),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: TgiColors.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        labelStyle: const TextStyle(color: TgiColors.textSecondary),
        hintStyle: const TextStyle(color: TgiColors.textMuted),
        helperStyle: const TextStyle(color: TgiColors.textMuted),
        errorStyle: const TextStyle(color: TgiColors.danger),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: const BorderSide(color: TgiColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: const BorderSide(color: TgiColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: const BorderSide(color: TgiColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: const BorderSide(color: TgiColors.danger, width: 1.5),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        inactiveTrackColor: TgiColors.borderStrong,
        thumbColor: primary,
        overlayColor: primary.withValues(alpha: 0.12),
        trackHeight: 4,
        trackShape: const TgiSliderTrackShape(),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        tickMarkShape: SliderTickMarkShape.noTickMark,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: TgiColors.surfaceRaised,
        surfaceTintColor: TgiColors.transparent,
        elevation: 0,
        shadowColor: TgiColors.transparent,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: TgiColors.borderStrong),
          borderRadius: BorderRadius.circular(TgiRadii.lg),
        ),
        textStyle: base.textTheme.bodyMedium?.copyWith(
          color: TgiColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(
            TgiColors.surfaceRaised,
          ),
          surfaceTintColor: const WidgetStatePropertyAll(TgiColors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          side: const WidgetStatePropertyAll(
            BorderSide(color: TgiColors.borderStrong),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(TgiRadii.lg),
            ),
          ),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: base.textTheme.bodyMedium?.copyWith(
          color: TgiColors.textPrimary,
        ),
        menuStyle: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(
            TgiColors.surfaceRaised,
          ),
          surfaceTintColor: const WidgetStatePropertyAll(TgiColors.transparent),
          side: const WidgetStatePropertyAll(
            BorderSide(color: TgiColors.borderStrong),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(TgiRadii.lg),
            ),
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: TgiColors.textMuted,
        indicatorColor: primary,
        dividerColor: TgiColors.border,
        overlayColor: WidgetStatePropertyAll(primary.withValues(alpha: 0.08)),
        labelStyle: const TextStyle(fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: TgiColors.surfacePanel,
        indicatorColor: primary.withValues(alpha: 0.14),
        selectedIconTheme: IconThemeData(color: primary, size: 20),
        unselectedIconTheme: const IconThemeData(
          color: TgiColors.textMuted,
          size: 20,
        ),
        selectedLabelTextStyle: TextStyle(
          color: primary,
          fontWeight: FontWeight.w800,
        ),
        unselectedLabelTextStyle: const TextStyle(
          color: TgiColors.textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: TgiColors.textMuted,
        textColor: TgiColors.textPrimary,
        selectedColor: primary,
        selectedTileColor: primary.withValues(alpha: 0.10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: TgiColors.surface,
        selectedColor: primary.withValues(alpha: 0.16),
        disabledColor: TgiColors.surfacePressed,
        side: const BorderSide(color: TgiColors.borderStrong),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TgiRadii.sm),
        ),
        labelStyle: const TextStyle(
          color: TgiColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primary
              : TgiColors.surface,
        ),
        checkColor: const WidgetStatePropertyAll(TgiColors.background),
        side: const BorderSide(color: TgiColors.borderStrong, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TgiRadii.xs),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primary
              : TgiColors.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primary.withValues(alpha: 0.34)
              : TgiColors.surfacePressed,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(TgiColors.borderStrong),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primary
              : TgiColors.textMuted,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? TgiColors.textPrimary
                : TgiColors.textMuted,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? primary.withValues(alpha: 0.14)
                : TgiColors.surface,
          ),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.selected)
                  ? primary.withValues(alpha: 0.52)
                  : TgiColors.border,
            ),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(controlRadius),
            ),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: TgiColors.surfacePanel,
        indicatorColor: primary.withValues(alpha: 0.14),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? TgiColors.textPrimary
                : TgiColors.textMuted,
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? primary
                : TgiColors.textMuted,
            size: 20,
          ),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        radius: const Radius.circular(TgiRadii.pill),
        thickness: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered) ? 8 : 4,
        ),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.dragged)
              ? TgiColors.accentDim
              : TgiColors.borderStrong,
        ),
        trackColor: WidgetStateProperty.all(
          TgiColors.surfaceRail.withValues(alpha: 0.58),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: TgiColors.surfaceRaised,
          border: Border.all(color: TgiColors.borderStrong),
          borderRadius: BorderRadius.circular(TgiRadii.sm),
        ),
        textStyle: base.textTheme.bodySmall?.copyWith(
          color: TgiColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        waitDuration: const Duration(milliseconds: 450),
        showDuration: const Duration(seconds: 4),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: TgiColors.surfaceRaised,
        elevation: 0,
        contentTextStyle: const TextStyle(
          color: TgiColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        actionTextColor: primary,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: TgiColors.borderStrong),
          borderRadius: BorderRadius.circular(TgiRadii.lg),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: TgiColors.surfacePanel,
        modalBackgroundColor: TgiColors.surfacePanel,
        surfaceTintColor: TgiColors.transparent,
        showDragHandle: true,
        dragHandleColor: TgiColors.borderStrong,
      ),
      iconTheme: const IconThemeData(color: TgiColors.textPrimary),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: TgiColors.border,
        circularTrackColor: TgiColors.border,
      ),
    );
  }
}
