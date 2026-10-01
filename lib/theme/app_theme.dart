import 'package:flutter/material.dart';

import 'app_palettes.dart';

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

  // Light-mode surface ladder.
  //
  // These exist because Material's container roles are what `Card`, `ListTile`,
  // menus, dialogs, bottom sheets, filled text fields, chips and snack bars all
  // paint themselves with. Leaving them unset made every one of them resolve to
  // the same cream as the page — surfaceContainerLow through surfaceContainerHigh
  // were all #f8f1e5 — so there was no elevation anywhere in light mode and every
  // card vanished into the background. A warm ladder, lightest at the top, gives
  // each component the right tone without any of them being hand-painted.
  static const Color surfaceLowest = Color(0xFFFDF9F2); // raised cards
  static const Color surfaceLow = Color(0xFFF8F1E5); // the page
  static const Color surfaceMid = Color(0xFFF3EADB);
  static const Color surfaceHigh = Color(0xFFEDE2CE);
  static const Color surfaceHighest = Color(0xFFE6DAC3);
  static const Color surfaceRecessed = Color(0xFFEADFCB);
  static const Color outlineSoft = Color(0xFFD8C7A8);

  // Dark-mode tones (near-black warm foundation, solid opaque surfaces)
  static const Color darkBackground = Color(0xFF100D0A); // app background
  static const Color darkSurface = Color(0xFF171310); // content surfaces
  static const Color darkSurfaceHigh = Color(0xFF221C16); // secondary surfaces
  static const Color darkBorder = Color(0xFF2E2720); // subtle opaque borders
  static const Color darkCream = Color(0xFFE8D9C2); // muted primary text
  // Dark ladder, same reason as the light one. These extend the two tones that
  // already existed rather than replacing them, so the surfaces the app already
  // painted keep their colour and Material's own components gain steps.
  static const Color darkSurfaceHigher = Color(0xFF2A231C);
  static const Color darkSurfaceMid = Color(0xFF1C1712);

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

/// Motion durations. Nothing here exceeds 250ms: an app that takes half a
/// second to acknowledge a tap feels slow rather than smooth.
class AppMotion {
  AppMotion._();

  /// Progress bars, check/uncheck, and other small state changes.
  static const Duration fast = Duration(milliseconds: 180);

  /// Sheets and larger reveals.
  static const Duration medium = Duration(milliseconds: 220);
}

/// The three surface tiers the app is allowed to use.
///
/// Every screen previously used `Card(` with the same elevation, radius and
/// border, so a page of grouped content read as a page of identical flat boxes
/// with no hierarchy at all. Three tiers, used deliberately, give each screen
/// a reading order:
///
/// - [flat]   no border, tonal fill — list rows and list sections
/// - [raised] subtle border, tonal fill — grouped content
/// - [accent] primaryContainer fill — the single most important element on the
///   screen
///
/// [accent] is meant to be rare. If most things on a screen are accent, the
/// accent means nothing, which is the flat-everything problem wearing a
/// different hat.
enum AppSurfaceTier { flat, raised, accent }

/// Builds a surface from a tier, resolved against the current [ColorScheme].
///
/// Lives in the theme rather than in each screen so the tiers cannot drift.
class AppSurfaces {
  AppSurfaces._();

  /// Fill and border for a tier.
  ///
  /// Every fill comes out of the ACTIVE scheme's container roles rather than out
  /// of a named TBRN constant, which is what lets one tier work in every
  /// palette. Naming `AppColors.darkSurface` here is why the raised card stayed
  /// TBRN-brown on Kanagawa's ink: the tier was pinned to one palette's step.
  ///
  /// The mapping, stated once, and it is BRIGHTNESS-AWARE:
  ///
  /// - light: [raised] is `surfaceContainerLowest` (a step LIGHTER than the
  ///   page), [flat] is `surfaceContainer` (between the page and a card)
  /// - dark:  [raised] is `surfaceContainerHigh` (a step LIGHTER than the page,
  ///   because on a dark page "raised" means further from the background toward
  ///   the reader, not darker), [flat] is `surfaceContainerHighest`
  ///
  /// Getting this wrong is invisible until a card looks like a hole: a dark
  /// palette whose raised tier is the DEEPEST step reads as a well punched
  /// through the page rather than as something sitting on it.
  static ({Color color, BorderSide border}) specFor(
    AppSurfaceTier tier,
    ColorScheme scheme,
  ) {
    final isDark = scheme.brightness == Brightness.dark;

    return switch (tier) {
      AppSurfaceTier.flat => (
        color: isDark
            ? scheme.surfaceContainerHighest
            : scheme.surfaceContainer,
        border: BorderSide.none,
      ),
      AppSurfaceTier.raised => (
        // One step above the page, with an edge, so a card has a visible
        // boundary.
        color: isDark
            ? scheme.surfaceContainerHigh
            : scheme.surfaceContainerLowest,
        border: BorderSide(color: scheme.outlineVariant),
      ),
      AppSurfaceTier.accent => (
        color: scheme.primaryContainer,
        border: BorderSide.none,
      ),
    };
  }
}

/// A surface at one of the three [AppSurfaceTier]s.
///
/// Built on [Material] rather than a decorated [Container] on purpose. A
/// Container paints a background but is not an ink surface, so a [ListTile] or
/// any other widget that paints its own background would hide the surface's
/// fill and Flutter asserts that its ink splashes are invisible. Material
/// carries the fill, the border and the ink in one place, which is what `Card`
/// was doing.
class AppSurface extends StatelessWidget {
  const AppSurface({
    super.key,
    required this.tier,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.margin,
    this.color,
    this.clipBehavior = Clip.none,
  });

  final AppSurfaceTier tier;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  /// Overrides the tier's fill.
  ///
  /// Only for a card that has to carry its own semantic colour, such as a
  /// context or warning card. Prefer choosing a tier: the point of the tiers is
  /// that a screen cannot quietly invent a fourth one.
  final Color? color;

  /// Clips the child to the surface's radius. Needed when the child paints
  /// past its own bounds, such as an [ExpansionTile]'s revealed content.
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spec = AppSurfaces.specFor(tier, theme.colorScheme);

    // The outer Container carries the margin only. A Container with no colour
    // and no decoration is a pass-through, so the Material below is still the
    // nearest ink surface.
    return Container(
      margin: margin,
      child: Material(
        type: MaterialType.canvas,
        color: color ?? spec.color,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.mediumRadius,
          side: spec.border,
        ),
        clipBehavior: clipBehavior,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
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

  /// The default palette. Unchanged behaviour for a user who never opens
  /// Settings, which is the requirement: the setting that decides a palette
  /// defaults to what the app looked like before palettes existed.
  static const AppPalette defaultPalette = AppPalette.tbrn;

  /// The TBRN light theme, unchanged from before palettes existed.
  static ThemeData light() => _for(AppPalette.tbrn, Brightness.light);

  /// The TBRN dark theme, unchanged from before palettes existed.
  static ThemeData dark() => _for(AppPalette.tbrn, Brightness.dark);

  /// The light theme for [palette].
  ///
  /// A dark-only palette has no light form, so this falls back to the dark one
  /// rather than inventing a light version. The Settings screen does not offer
  /// the combination in the first place — see [AppPaletteX.supportsLight] — so
  /// reaching this means a stored preference from a future palette, and a
  /// coherent dark screen is the better failure than a cream one in Kanagawa
  /// colours.
  static ThemeData lightFor(AppPalette palette) {
    if (AppPalettes.lightFor(palette) != null) {
      return _for(palette, Brightness.light);
    }
    return darkFor(palette);
  }

  /// The dark theme for [palette]. Every palette has one.
  static ThemeData darkFor(AppPalette palette) =>
      _for(palette, Brightness.dark);

  /// Builds the theme for a palette and a brightness.
  ///
  /// One builder for all ten combinations, because the parts that differ between
  /// them are exactly the palette's own tokens and the brightness — and a
  /// per-palette `ThemeData` would have ten copies of the 120 lines of component
  /// themes below, which is ten places for them to drift.
  static ThemeData _for(AppPalette palette, Brightness brightness) {
    final spec = brightness == Brightness.dark
        ? AppPalettes.darkFor(palette)
        : (AppPalettes.lightFor(palette) ?? AppPalettes.darkFor(palette));
    final scheme = _schemeFor(spec, brightness);
    return _base(scheme, scaffold: spec.background, palette: palette);
  }

  /// The [ColorScheme] for a palette's tokens.
  ///
  /// The container roles are the whole point of this method. Leaving them unset
  /// collapses `surfaceContainerLow` through `surfaceContainerHigh` onto the page
  /// colour, and those are the roles `Card`, `ListTile`, menus, dialogs, sheets,
  /// filled text fields, chips and snack bars paint themselves with — so with no
  /// ladder there is no elevation anywhere and every card vanishes. That is the
  /// bug `90a480a` fixed for TBRN; filling these in per palette is what keeps
  /// four new palettes from inheriting it.
  static ColorScheme _schemeFor(AppPaletteSpec spec, Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    // In light mode the primary is the palette's own strong colour and the
    // foreground on it is near-white. In dark mode that inverts: the primary is
    // the PALE tone and its foreground is the palette's darkest, or a saturated
    // mid-tone with pale text on it.
    final primary = isDark
        ? spec.outline == spec.onSurface
              ? spec.primary
              : _paleFor(spec)
        : spec.primary;
    final onPrimary = isDark ? spec.background : const Color(0xFFFDF9F2);

    return ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: spec.container,
      onPrimaryContainer: isDark ? spec.primary : spec.onSurface,
      secondary: spec.secondary,
      onSecondary: isDark ? spec.background : const Color(0xFFFDF9F2),
      secondaryContainer: spec.surfaceHighest,
      onSecondaryContainer: spec.onSurface,
      tertiary: spec.secondary,
      onTertiary: isDark ? spec.background : const Color(0xFFFDF9F2),
      tertiaryContainer: spec.surfaceHigh,
      onTertiaryContainer: spec.onSurface,
      error: spec.error,
      onError: isDark ? spec.background : const Color(0xFFFDF9F2),
      surface: spec.surfaceLow,
      onSurface: spec.onSurface,
      surfaceDim: spec.surfaceRecessed,
      surfaceBright: spec.surfaceLowest,
      surfaceContainerLowest: spec.surfaceLowest,
      surfaceContainerLow: spec.surfaceLow,
      surfaceContainer: spec.surfaceMid,
      surfaceContainerHigh: spec.surfaceHigh,
      surfaceContainerHighest: spec.surfaceHighest,
      onSurfaceVariant: isDark ? spec.outline : spec.secondary,
      outline: spec.outline,
      outlineVariant: spec.outlineSoft,
      shadow: const Color(0xFF000000),
      inverseSurface: spec.onSurface,
      onInverseSurface: spec.background,
      inversePrimary: spec.primary,
    );
  }

  /// The dark-mode primary: the palette's own primary, lifted if it is too dark
  /// to read on a near-black page.
  ///
  /// Kanagawa's and Catppuccin's primaries are already pale and are used as they
  /// are. Gruvbox's amber and Solitude's grey both sit below 3:1 against their
  /// own backgrounds, so each is mixed toward its own text colour until it
  /// clears the threshold — computed rather than hand-picked so a palette edit
  /// cannot silently take the app back under 3:1.
  static Color _paleFor(AppPaletteSpec spec) {
    final background = spec.background;
    if (_relativeLuminance(spec.primary) / _relativeLuminance(background) >=
        3.0 / _contrastDenominator(background)) {
      return spec.primary;
    }
    var candidate = spec.primary;
    for (var i = 0; i < 12; i++) {
      candidate = Color.lerp(candidate, spec.onSurface, 0.12)!;
      final ratio =
          _relativeLuminance(candidate) / _contrastDenominator(background);
      if (ratio >= 3.0) return candidate;
    }
    return spec.onSurface;
  }

  static double _contrastDenominator(Color background) =>
      _relativeLuminance(background) > 0.0
      ? _relativeLuminance(background)
      : 1.0;

  static double _relativeLuminance(Color c) {
    double channel(double v) =>
        v <= 0.03928 ? v / 12.92 : _pow((v + 0.055) / 1.055, 2.4);
    return 0.2126 * channel(c.r) +
        0.7152 * channel(c.g) +
        0.0722 * channel(c.b);
  }

  static double _pow(double base, double exponent) {
    // ln then exp, so this needs no dart:math import in a theme file.
    if (base <= 0) return 0;
    return _exp(exponent * _ln(base));
  }

  static double _ln(double x) {
    // Natural log via a series around 1, then a few squarings. Only ever called
    // with values in (0, 2], where the series converges quickly.
    if (x <= 0) return double.negativeInfinity;
    var exponent = 0;
    var value = x;
    while (value > 2) {
      value /= 2;
      exponent++;
    }
    while (value < 1) {
      value *= 2;
      exponent--;
    }
    final z = (value - 1) / (value + 1);
    final z2 = z * z;
    var sum = 0.0;
    var term = z;
    for (var k = 1; k <= 21; k += 2) {
      sum += term / k;
      term *= z2;
    }
    return 2 * sum + exponent * 0.6931471805599453;
  }

  static double _exp(double x) {
    if (x > 3) return _exp(x / 2) * _exp(x / 2);
    var term = 1.0;
    var sum = 1.0;
    for (var i = 1; i <= 18; i++) {
      term *= x / i;
      sum += term;
    }
    return sum;
  }

  static ThemeData _base(
    ColorScheme scheme, {
    required Color scaffold,
    required AppPalette palette,
  }) {
    final isDark = scheme.brightness == Brightness.dark;
    final textTheme = _typeScale(scheme);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      textTheme: textTheme,
      // Checkboxes are one of the app's main "something just changed" signals.
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : Colors.transparent,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        linearMinHeight: AppSpacing.xxs,
      ),
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
        // One step above the page, from the scheme rather than a named TBRN
        // tone. A literal here is why a Card stayed cream on Kanagawa's ink.
        color: isDark
            ? scheme.surfaceContainerLow
            : scheme.surfaceContainerLowest,
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
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
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
    );
  }

  /// The app's type scale.
  ///
  /// Before this the app referenced only titleSmall, titleMedium and bodySmall,
  /// so every screen read at the same weight and there was no entry point — the
  /// eye had nothing to land on. This keeps those three for supporting text and
  /// adds a real jump at the top, so each screen has exactly one number allowed
  /// to be large.
  ///
  /// The sizes are the Material 3 values, so nothing on screen shifts; what is
  /// new is that they are stated here rather than resolved at paint time. That
  /// matters: in this Flutter version every `fontSize` in the default text
  /// theme is null and the sizes only appear when a style is merged against the
  /// platform default, so a scale built on `ThemeData().textTheme` has no
  /// guaranteed size contrast at all — only the weights below.
  static TextTheme _typeScale(ColorScheme scheme) {
    TextStyle style(
      String role,
      double size, {
      FontWeight weight = FontWeight.w400,
      Color? color,
    }) {
      return TextStyle(
        fontSize: size,
        fontWeight: weight,
        color: color ?? scheme.onSurface,
      );
    }

    return TextTheme(
      // The one number that matters on a screen.
      displayLarge: style('displayLarge', 57, weight: FontWeight.w800),
      displayMedium: style('displayMedium', 45, weight: FontWeight.w800),
      displaySmall: style('displaySmall', 36, weight: FontWeight.w700),
      // Section and screen titles: clearly above body, clearly below the
      // headline number.
      headlineLarge: style('headlineLarge', 32, weight: FontWeight.w700),
      headlineMedium: style('headlineMedium', 28, weight: FontWeight.w700),
      headlineSmall: style('headlineSmall', 24, weight: FontWeight.w600),
      titleLarge: style('titleLarge', 22, weight: FontWeight.w700),
      // Supporting titles. w600 rather than w700 so they do not compete with
      // the headline they sit under.
      titleMedium: style('titleMedium', 16, weight: FontWeight.w600),
      titleSmall: style('titleSmall', 14, weight: FontWeight.w600),
      bodyLarge: style('bodyLarge', 16),
      bodyMedium: style('bodyMedium', 14),
      // Supporting and secondary text sits back in the colour as well as down
      // in size, which is what keeps a screen from reading as one flat block.
      bodySmall: style('bodySmall', 12, color: scheme.onSurfaceVariant),
      labelLarge: style('labelLarge', 14, weight: FontWeight.w600),
      labelMedium: style(
        'labelMedium',
        12,
        weight: FontWeight.w500,
        color: scheme.onSurfaceVariant,
      ),
      labelSmall: style('labelSmall', 11, color: scheme.onSurfaceVariant),
    );
  }
}
