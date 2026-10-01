import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/theme/app_palettes.dart';
import 'package:flutter_application_1/theme/app_theme.dart';

enum Currency { rs, usd, eur }

extension CurrencyX on Currency {
  String get symbol {
    switch (this) {
      case Currency.rs:
        return 'Rs. ';
      case Currency.usd:
        return '\$';
      case Currency.eur:
        return '€ ';
    }
  }

  String get name {
    switch (this) {
      case Currency.rs:
        return 'Rs.';
      case Currency.usd:
        return '\$';
      case Currency.eur:
        return '€';
    }
  }
}

class SettingsProvider extends ChangeNotifier {
  static const _currencyKey = 'currency';
  static const _themeKey = 'theme_mode';
  static const _paletteKey = 'theme_palette';

  Currency _currency = Currency.rs;
  ThemeMode _themeMode = ThemeMode.system;

  /// The palette, separate from [themeMode].
  ///
  /// Two settings, not one, and that is the user's explicit instruction: light /
  /// dark / system stays the top group and its `ThemeMode.system` default must not
  /// change, so a user who has never opened Settings is not forced out of their
  /// way. The palette picks the colours WITHIN whichever mode is in force.
  ///
  /// Defaults to TBRN, so a user who never chooses a palette sees exactly what
  /// they saw before palettes existed.
  AppPalette _palette = AppTheme.defaultPalette;

  Currency get currency => _currency;
  ThemeMode get themeMode => _themeMode;
  AppPalette get palette => _palette;

  /// The light theme for the chosen palette.
  ThemeData get lightTheme => AppTheme.lightFor(_palette);

  /// The dark theme for the chosen palette.
  ThemeData get darkTheme => AppTheme.darkFor(_palette);

  /// Reads persisted settings.
  ///
  /// Callers must await this before the first frame. Firing it off from the
  /// constructor left a window where the app rendered with the default
  /// currency and theme and then snapped to the persisted ones, which showed up
  /// as a launch flash. `main()` awaits it, so no listener is missed.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final currencyIndex = prefs.getInt(_currencyKey) ?? 0;
    final themeIndex = prefs.getInt(_themeKey) ?? 2;
    final paletteIndex = prefs.getInt(_paletteKey) ?? 0;

    _currency =
        Currency.values[currencyIndex.clamp(0, Currency.values.length - 1)];
    _themeMode =
        ThemeMode.values[themeIndex.clamp(0, ThemeMode.values.length - 1)];
    // Clamped rather than trusted. An index written by a future build with more
    // palettes must not crash this one; the last palette the user could have
    // chosen is a far better answer than throwing on launch.
    _palette =
        AppPalette.values[paletteIndex.clamp(0, AppPalette.values.length - 1)];
    notifyListeners();
  }

  Future<void> setCurrency(Currency currency) async {
    _currency = currency;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_currencyKey, currency.index);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, mode.index);
    notifyListeners();
  }

  Future<void> setPalette(AppPalette palette) async {
    if (_palette == palette) return;
    _palette = palette;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_paletteKey, palette.index);
    notifyListeners();
  }
}
