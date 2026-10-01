import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Which palette the app is wearing.
///
/// [tbrn] stays first and stays the default. A user's stored index into this list
/// must keep meaning the same thing, so values are only ever appended.
enum AppPalette { tbrn, kanagawa, solitude, gruvbox, catppuccin }

extension AppPaletteX on AppPalette {
  String get label => switch (this) {
    AppPalette.tbrn => 'TBRN',
    AppPalette.kanagawa => 'Kanagawa',
    AppPalette.solitude => 'Solitude',
    AppPalette.gruvbox => 'Gruvbox',
    AppPalette.catppuccin => 'Catppuccin',
  };

  String get description => switch (this) {
    AppPalette.tbrn => 'Cream and carafe',
    AppPalette.kanagawa => 'Ink, indigo and gold',
    AppPalette.solitude => 'Cold grey, almost black',
    AppPalette.gruvbox => 'Warm earth and amber',
    AppPalette.catppuccin => 'Pastel, blue and mint',
  };

  /// Whether this palette has a light mode at all.
  ///
  /// Kanagawa, Solitude and Gruvbox are DARK ONLY, and saying so is not a detail
  /// — asking a user to choose "Solitude + light" when no such thing exists
  /// produces a screen that is neither palette nor the app they know.
  bool get supportsLight => switch (this) {
    AppPalette.tbrn => true,
    AppPalette.catppuccin => true,
    AppPalette.kanagawa || AppPalette.solitude || AppPalette.gruvbox => false,
  };

  /// The brightness actually used for a dark theme request.
  Brightness get darkBrightness => Brightness.dark;
}

/// The tokens a theme needs beyond the ladder.
///
/// A palette is not a hue swap. Material's container roles are what `Card`,
/// `ListTile`, menus, dialogs, sheets, filled text fields, chips and snack bars
/// paint themselves with, so leaving them unset collapses every one of them onto
/// the page colour and there is no elevation anywhere — which is the bug
/// `90a480a` fixed for TBRN and which every new palette would otherwise inherit.
/// So each palette states all six levels, its own outline, and its own mapping
/// for the three [AppSurfaceTier]s.
@immutable
class AppPaletteSpec {
  const AppPaletteSpec({
    required this.palette,
    required this.background,
    required this.container,
    required this.outline,
    required this.primary,
    required this.secondary,
    required this.onSurface,
    required this.surfaceLowest,
    required this.surfaceLow,
    required this.surfaceMid,
    required this.surfaceHigh,
    required this.surfaceHighest,
    required this.surfaceRecessed,
    required this.outlineSoft,
    required this.error,
    required this.success,
    required this.warning,
  });

  final AppPalette palette;

  /// The scaffold, one step above the page in the ladder's terms.
  final Color background;

  /// `primaryContainer` — the one accent surface per screen.
  final Color container;

  /// A visible edge for a raised card.
  final Color outline;

  final Color primary;
  final Color secondary;

  /// The ink on [background].
  final Color onSurface;

  /// The six-level ladder, lightest first.
  ///
  /// Ordered, and every level is a DIFFERENT colour: a ladder where two levels
  /// coincide is the original bug in a new palette, and it is invisible until a
  /// user sees a card that has no edge.
  final Color surfaceLowest;
  final Color surfaceLow;
  final Color surfaceMid;
  final Color surfaceHigh;
  final Color surfaceHighest;
  final Color surfaceRecessed;

  /// A softer border than [outline].
  final Color outlineSoft;

  final Color error;
  final Color success;
  final Color warning;

  /// The full ladder as a list, in Material's own order.
  List<Color> get ladder => [
    surfaceLowest,
    surfaceLow,
    surfaceMid,
    surfaceHigh,
    surfaceHighest,
    surfaceRecessed,
  ];
}

/// Every palette's tokens, in one table.
///
/// One class per palette rather than one class with a colour argument, because
/// the ladder is the thing that has to be right and a parameterised builder is
/// how six levels quietly get derived from one hue again.
class AppPalettes {
  AppPalettes._();

  static const AppPaletteSpec tbrnLight = AppPaletteSpec(
    palette: AppPalette.tbrn,
    background: Color(0xFFF8F1E5),
    container: Color(0xFFE7D6BC),
    outline: Color(0xFFA8907D),
    primary: Color(0xFF4B392F),
    secondary: Color(0xFF6B5646),
    onSurface: Color(0xFF2B2722),
    surfaceLowest: Color(0xFFFDF9F2),
    surfaceLow: Color(0xFFF8F1E5),
    surfaceMid: Color(0xFFF3EADB),
    surfaceHigh: Color(0xFFEDE2CE),
    surfaceHighest: Color(0xFFE6DAC3),
    surfaceRecessed: Color(0xFFEADFCB),
    outlineSoft: Color(0xFFD8C7A8),
    error: Color(0xFF9E4A38),
    success: Color(0xFF5C7A52),
    warning: Color(0xFFB07A2E),
  );

  static const AppPaletteSpec tbrnDark = AppPaletteSpec(
    palette: AppPalette.tbrn,
    background: Color(0xFF100D0A),
    container: Color(0xFF4B392F),
    outline: Color(0xFF6B5646),
    primary: Color(0xFFE8D9C2),
    secondary: Color(0xFFA8907D),
    onSurface: Color(0xFFE8D9C2),
    surfaceLowest: Color(0xFF100D0A),
    surfaceLow: Color(0xFF171310),
    surfaceMid: Color(0xFF1C1712),
    surfaceHigh: Color(0xFF221C16),
    surfaceHighest: Color(0xFF2A231C),
    surfaceRecessed: Color(0xFF16120F),
    outlineSoft: Color(0xFF2E2720),
    error: Color(0xFFD08A76),
    success: Color(0xFF7FA372),
    warning: Color(0xFFD9A05B),
  );

  static const AppPaletteSpec kanagawaDark = AppPaletteSpec(
    palette: AppPalette.kanagawa,
    background: Color(0xFF1F1F28),
    container: Color(0xFF223249),
    outline: Color(0xFF54546D),
    primary: Color(0xFFC0A36E),
    secondary: Color(0xFF6A9589),
    onSurface: Color(0xFFDCD7BA),
    // Dark themes need the ladder ordered DARKEST first, so `surfaceLowest` sits
    // deepest and the steps rise away from the page. Inverting this is what makes
    // a dark card look like a hole rather than a raised surface.
    surfaceLowest: Color(0xFF111116),
    surfaceLow: Color(0xFF17171E),
    surfaceMid: Color(0xFF1F1F28),
    surfaceHigh: Color(0xFF2A3550),
    surfaceHighest: Color(0xFF364460),
    surfaceRecessed: Color(0xFF14141B),
    outlineSoft: Color(0xFF3A3A4F),
    error: Color(0xFFE82424),
    success: Color(0xFF98BB6C),
    warning: Color(0xFFE6C384),
  );

  static const AppPaletteSpec solitudeDark = AppPaletteSpec(
    palette: AppPalette.solitude,
    background: Color(0xFF101315),
    container: Color(0xFF28323B),
    outline: Color(0xFF4B4E55),
    primary: Color(0xFFA8ADB0),
    secondary: Color(0xFF798186),
    onSurface: Color(0xFFCACCCC),
    surfaceLowest: Color(0xFF080A0B),
    surfaceLow: Color(0xFF0C0E10),
    surfaceMid: Color(0xFF101315),
    surfaceHigh: Color(0xFF16191C),
    surfaceHighest: Color(0xFF1E242A),

    surfaceRecessed: Color(0xFF0A0C0D),
    outlineSoft: Color(0xFF2A2F34),
    error: Color(0xFFC8553D),
    success: Color(0xFF7CA08C),
    warning: Color(0xFFC0A16B),
  );

  static const AppPaletteSpec gruvboxDark = AppPaletteSpec(
    palette: AppPalette.gruvbox,
    background: Color(0xFF282828),
    container: Color(0xFF504945),
    outline: Color(0xFF665C54),
    primary: Color(0xFFD8A657),
    secondary: Color(0xFF89B482),
    onSurface: Color(0xFFD4BE98),
    surfaceLowest: Color(0xFF1E1E1E),
    surfaceLow: Color(0xFF232323),
    surfaceMid: Color(0xFF282828),
    surfaceHigh: Color(0xFF3C3836),
    surfaceHighest: Color(0xFF5E564F),
    surfaceRecessed: Color(0xFF1A1A1A),
    outlineSoft: Color(0xFF4A4A4A),
    error: Color(0xFFCC241D),
    success: Color(0xFF98971A),
    warning: Color(0xFFD79921),
  );

  static const AppPaletteSpec catppuccinMocha = AppPaletteSpec(
    palette: AppPalette.catppuccin,
    background: Color(0xFF1E1E2E),
    container: Color(0xFF3B3D52),
    outline: Color(0xFF585B70),
    primary: Color(0xFF89B4FA),
    secondary: Color(0xFF94E2D5),
    onSurface: Color(0xFFCDD6F4),
    surfaceLowest: Color(0xFF161622),
    surfaceLow: Color(0xFF181825),
    surfaceMid: Color(0xFF1E1E2E),
    surfaceHigh: Color(0xFF313244),
    surfaceHighest: Color(0xFF49495E),
    surfaceRecessed: Color(0xFF13131F),
    outlineSoft: Color(0xFF45475A),
    error: Color(0xFFF38BA8),
    success: Color(0xFFA6E3A1),
    warning: Color(0xFFF9E2AF),
  );

  static const AppPaletteSpec catppuccinLatte = AppPaletteSpec(
    palette: AppPalette.catppuccin,
    background: Color(0xFFEFF1F5),
    container: Color(0xFFDCE0E8),
    outline: Color(0xFFACB0BE),
    primary: Color(0xFF1E66F5),
    secondary: Color(0xFF179299),
    onSurface: Color(0xFF4C4F69),
    surfaceLowest: Color(0xFFFFFFFF),
    surfaceLow: Color(0xFFF5F6FA),
    surfaceMid: Color(0xFFEFF1F5),
    surfaceHigh: Color(0xFFE6E9EF),
    surfaceHighest: Color(0xFFDCE0E8),
    surfaceRecessed: Color(0xFFE9EBF1),
    outlineSoft: Color(0xFFCCD0DA),
    error: Color(0xFFD20F39),
    success: Color(0xFF40A02B),
    warning: Color(0xFFDF8E1D),
  );

  /// The light spec for [palette], or null when it has none.
  static AppPaletteSpec? lightFor(AppPalette palette) => switch (palette) {
    AppPalette.tbrn => tbrnLight,
    AppPalette.catppuccin => catppuccinLatte,
    AppPalette.kanagawa || AppPalette.solitude || AppPalette.gruvbox => null,
  };

  /// The dark spec for [palette]. Every palette has one.
  static AppPaletteSpec darkFor(AppPalette palette) => switch (palette) {
    AppPalette.tbrn => tbrnDark,
    AppPalette.kanagawa => kanagawaDark,
    AppPalette.solitude => solitudeDark,
    AppPalette.gruvbox => gruvboxDark,
    AppPalette.catppuccin => catppuccinMocha,
  };
}
