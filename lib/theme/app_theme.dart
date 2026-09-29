import 'package:flutter/material.dart';

/// V2 visual identity for Daily Context Companion.
///
/// Palette:
/// - Cream      #F0E1CA  (warm light surfaces)
/// - Khaki      #A8907D  (muted accents, secondary)
/// - Jet Black  #2B2722  (primary text / dark ink)
/// - Carafe     #4B392F  (primary brand, deep brown)
class AppColors {
  AppColors._();

  static const Color cream = Color(0xFFF0E1CA);
  static const Color khaki = Color(0xFFA8907D);
  static const Color jet = Color(0xFF2B2722);
  static const Color carafe = Color(0xFF4B392F);

  // Derived tones (harmonized with the palette)
  static const Color creamLight = Color(0xFFF8F1E5); // scaffold
  static const Color parchment = Color(0xFFE7D6BC); // container
  static const Color sand = Color(0xFFDDD0B8); // outline-ish
  static const Color mocha = Color(0xFF6B5646); // secondary dark
  static const Color latte = Color(0xFFEFE7DA); // subtle fill

  // Dark-mode tones (near-black warm foundation, solid opaque surfaces)
  static const Color darkBackground = Color(0xFF100D0A); // app background
  static const Color darkSurface = Color(0xFF171310); // content surfaces
  static const Color darkSurfaceHigh = Color(0xFF221C16); // secondary surfaces
  static const Color darkBorder = Color(0xFF2E2720); // subtle opaque borders
  static const Color darkCream = Color(0xFFE8D9C2); // muted primary text

  // Semantic (kept warm/desaturated to fit palette)
  static const Color success = Color(0xFF5C7A52);
  static const Color warning = Color(0xFFB07A2E);
  static const Color error = Color(0xFF9E4A38);
  static const Color info = Color(0xFF6E7F80);
}

/// Spacing scale used across the app.
class AppSpacing {
  AppSpacing._();

  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;

  static const EdgeInsets screenPadding = EdgeInsets.all(md);
}

/// Corner radii used across the app.
class AppRadii {
  AppRadii._();

  static const double small = 10; // controls, chips, small tiles
  static const double medium = 14; // cards, sheets
  static const double large = 18; // emphasis surfaces only

  static final BorderRadius smallRadius = BorderRadius.circular(small);
  static final BorderRadius mediumRadius = BorderRadius.circular(medium);
}

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.carafe,
      onPrimary: AppColors.creamLight,
      primaryContainer: AppColors.parchment,
      onPrimaryContainer: AppColors.jet,
      secondary: AppColors.mocha,
      onSecondary: AppColors.creamLight,
      secondaryContainer: AppColors.latte,
      onSecondaryContainer: AppColors.carafe,
      tertiary: AppColors.khaki,
      onTertiary: AppColors.jet,
      tertiaryContainer: AppColors.cream,
      onTertiaryContainer: AppColors.carafe,
      error: AppColors.error,
      onError: AppColors.creamLight,
      surface: AppColors.creamLight,
      onSurface: AppColors.jet,
      surfaceContainerHighest: AppColors.latte,
      onSurfaceVariant: AppColors.mocha,
      outline: AppColors.khaki,
      outlineVariant: AppColors.sand,
      shadow: AppColors.jet,
      inverseSurface: AppColors.jet,
      onInverseSurface: AppColors.cream,
      inversePrimary: AppColors.cream,
    );

    return _base(scheme, scaffold: AppColors.creamLight);
  }

  static ThemeData dark() {
    final scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.cream,
      onPrimary: AppColors.jet,
      primaryContainer: AppColors.carafe,
      onPrimaryContainer: AppColors.cream,
      secondary: AppColors.khaki,
      onSecondary: AppColors.jet,
      secondaryContainer: AppColors.darkSurfaceHigh,
      onSecondaryContainer: AppColors.darkCream,
      tertiary: AppColors.khaki,
      onTertiary: AppColors.jet,
      tertiaryContainer: AppColors.darkSurfaceHigh,
      onTertiaryContainer: AppColors.darkCream,
      error: const Color(0xFFD08A76),
      onError: AppColors.jet,
      surface: AppColors.darkSurface,
      onSurface: AppColors.cream,
      surfaceContainerHighest: AppColors.darkSurfaceHigh,
      onSurfaceVariant: AppColors.khaki,
      outline: AppColors.mocha,
      outlineVariant: AppColors.darkBorder,
      shadow: Colors.black,
      inverseSurface: AppColors.cream,
      onInverseSurface: AppColors.jet,
      inversePrimary: AppColors.carafe,
    );

    return _base(scheme, scaffold: AppColors.darkBackground);
  }

  static ThemeData _base(ColorScheme scheme, {required Color scaffold}) {
    final isDark = scheme.brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.mediumRadius,
          side: BorderSide(color: scheme.outlineVariant),
        ),
        color: isDark ? AppColors.darkSurface : Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadii.smallRadius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.smallRadius,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.smallRadius,
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.secondaryContainer,
        labelStyle: TextStyle(color: scheme.onSecondaryContainer),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.smallRadius),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: AppRadii.smallRadius),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: AppRadii.smallRadius),
          side: BorderSide(color: scheme.outline),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppRadii.mediumRadius),
        backgroundColor: scheme.surface,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        showDragHandle: true,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.smallRadius),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: isDark ? AppColors.darkBackground : Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: isDark ? AppColors.carafe : scheme.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),
    );
  }
}
