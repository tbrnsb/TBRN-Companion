import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  Currency _currency = Currency.rs;
  ThemeMode _themeMode = ThemeMode.system;

  Currency get currency => _currency;
  ThemeMode get themeMode => _themeMode;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final currencyIndex = prefs.getInt(_currencyKey) ?? 0;
    final themeIndex = prefs.getInt(_themeKey) ?? 2;

    _currency =
        Currency.values[currencyIndex.clamp(0, Currency.values.length - 1)];
    _themeMode =
        ThemeMode.values[themeIndex.clamp(0, ThemeMode.values.length - 1)];
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
}
