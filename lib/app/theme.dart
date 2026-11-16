import 'package:flutter/material.dart';

const _seed = Color(0xFF4F46E5); // indigo
const accent = Color(0xFF14B8A6); // teal

/// Colors the Material scheme doesn't cover. Read with `AppColors.of(context)`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.success,
    required this.warning,
    required this.heroGradient,
    required this.onHero,
  });

  final Color success;
  final Color warning;

  /// Background of the Today status card.
  final List<Color> heroGradient;
  final Color onHero;

  /// The alarm screen is always dark, in both themes (matches AlarmActivity.kt).
  static const ringGradient = [Color(0xFF1E1B4B), Color(0xFF0F172A)];

  static AppColors of(BuildContext context) => Theme.of(context).extension<AppColors>()!;

  static const light = AppColors(
    success: Color(0xFF16A34A),
    warning: Color(0xFFD97706),
    heroGradient: [Color(0xFF4F46E5), Color(0xFF0D9488)],
    onHero: Colors.white,
  );

  static const dark = AppColors(
    success: Color(0xFF4ADE80),
    warning: Color(0xFFFBBF24),
    heroGradient: [Color(0xFF3730A3), Color(0xFF115E59)],
    onHero: Colors.white,
  );

  @override
  AppColors copyWith({Color? success, Color? warning, List<Color>? heroGradient, Color? onHero}) =>
      AppColors(
        success: success ?? this.success,
        warning: warning ?? this.warning,
        heroGradient: heroGradient ?? this.heroGradient,
        onHero: onHero ?? this.onHero,
      );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      heroGradient: [
        for (var i = 0; i < heroGradient.length; i++)
          Color.lerp(heroGradient[i], other.heroGradient[i], t)!,
      ],
      onHero: Color.lerp(onHero, other.onHero, t)!,
    );
  }
}

/// Calm Material 3: soft tonal surfaces, generous radius, no shadows.
ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: brightness,
    secondary: dark ? const Color(0xFF5EEAD4) : const Color(0xFF0D9488),
    surface: dark ? const Color(0xFF0F1117) : const Color(0xFFF7F7FB),
  );
  final base = ThemeData(colorScheme: scheme, fontFamily: 'Inter');
  final text = base.textTheme;
  final radius = BorderRadius.circular(24);

  return base.copyWith(
    extensions: [dark ? AppColors.dark : AppColors.light],
    scaffoldBackgroundColor: scheme.surface,
    textTheme: text.copyWith(
      displayLarge: text.displayLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -2),
      displaySmall: text.displaySmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -1),
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.5),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      // Explicit size: base.textTheme has no sizes until MaterialApp localizes
      // it, and this style is used as-is.
      titleTextStyle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
        letterSpacing: -0.5,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: dark ? scheme.surfaceContainer : Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: dark ? 0.25 : 0.5)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 56),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 56),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: const StadiumBorder()),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide(color: scheme.outlineVariant),
      showCheckmark: false,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        selectedBackgroundColor: scheme.primary,
        selectedForegroundColor: scheme.onPrimary,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbIcon: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? const Icon(Icons.check, size: 14) : null,
      ),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 20),
      minVerticalPadding: 12,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? scheme.surfaceContainerLow : Colors.white,
      indicatorColor: scheme.primaryContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      labelTextStyle: WidgetStatePropertyAll(
        text.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(showDragHandle: true),
    dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: radius)),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.4), space: 1),
  );
}
