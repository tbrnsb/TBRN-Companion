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

  /// The palette, stored BY NAME.
  ///
  /// It used to be stored as an enum INDEX, which is the whole reason this class
  /// carries a migration table. An index is positional: remove Kanagawa and
  /// everything after it shifts down, so a user whose saved index was 2 came back
  /// in Gruvbox, one whose index was 3 came back in Catppuccin, and none of it
  /// threw or logged. The app just came up in a palette nobody chose.
  static const _paletteNameKey = 'theme_palette_name';

  /// The pre-name key. Read once, translated, and REMOVED.
  static const _legacyPaletteIndexKey = 'theme_palette';

  /// Legacy index -> the palette that index MEANT at the time it was written.
  ///
  /// LITERAL, and that is the entire point. It is tempting to write this as
  /// `AppPalette.values[index]`, which is precisely the bug restated: the enum
  /// has changed since those indices were written, so recomputing from it
  /// reproduces the original corruption. This table encodes what the indices meant
  /// BEFORE Kanagawa was removed, and it never needs changing again because it
  /// reads nothing from the enum.
  static const Map<int, AppPalette> _legacyPaletteByIndex = {
    0: AppPalette.tbrn,
    // 1 was Kanagawa. It no longer exists, so it maps to the DEFAULT rather than
    // throwing: a user who had it loses a palette, which is a smaller harm than
    // being unable to launch the app.
    1: AppTheme.defaultPalette,
    2: AppPalette.solitude,
    3: AppPalette.gruvbox,
    4: AppPalette.catppuccin,
  };

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

  /// True once [setPalette] has run.
  ///
  /// Exists for one reason: [_readPalette] calls [setPalette] to write the
  /// migrated name, and without this the `if (_palette == palette) return` guard
  /// would skip that write whenever the migrated value happens to equal the
  /// default — which is exactly the Kanagawa case, and exactly the case the
  /// migration exists to resolve.
  bool _migratedPalette = false;

  Currency get currency => _currency;
  ThemeMode get themeMode => _themeMode;
  AppPalette get palette => _palette;

  /// The VARIANT within the chosen family.
  ///
  /// Mirrors [themeMode] exactly, because it is the same fact read through the
  /// two-level model. A palette is not a brightness and a brightness is not a
  /// palette: a family has variants, and this is which one. Kept as a [ThemeMode]
  /// so `MaterialApp.themeMode` is unchanged and its `ThemeMode.system` default
  /// — which a user who never opens Settings must keep — stays exactly where it
  /// was.
  ThemeVariant get variant => switch (_themeMode) {
    ThemeMode.system => ThemeVariant.system,
    ThemeMode.light => ThemeVariant.light,
    ThemeMode.dark => ThemeVariant.dark,
  };

  set variant(ThemeVariant value) => setThemeMode(switch (value) {
    ThemeVariant.system => ThemeMode.system,
    ThemeVariant.light => ThemeMode.light,
    ThemeVariant.dark => ThemeMode.dark,
  });

  /// The light theme for the chosen family.
  ThemeData get lightTheme => AppTheme.forVariant(_palette, ThemeVariant.light);

  /// The dark theme for the chosen family.
  ThemeData get darkTheme => AppTheme.forVariant(_palette, ThemeVariant.dark);

  /// The theme in force, resolving System against the platform.
  ThemeData get activeTheme => switch (_themeMode) {
    ThemeMode.system => AppTheme.forSystem(_palette),
    ThemeMode.light => lightTheme,
    ThemeMode.dark => darkTheme,
  };

  /// Reads persisted settings.
  ///
  /// Callers must await this before the first frame. Firing it off from the
  /// constructor left a window where the app rendered with the default
  /// currency and theme and then snapped to the persisted ones, which showed up
  /// as a launch flash. `main()` awaits it, so no listener is missed.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final currencyIndex = prefs.getInt(_currencyKey) ?? 0;
    // `ThemeMode.system`, NOT the number 2.
    //
    // `ThemeMode.values` is [system, light, dark], so a `?? 2` fallback resolved
    // to DARK — and `load()` runs on every launch, so the documented
    // `ThemeMode.system` default was overwritten before the first frame. The
    // field initialiser said system; the value that actually reached
    // `MaterialApp` did not. Named rather than written as 0 so the intent cannot
    // rot if the enum is ever reordered.
    //
    // A STORED 2 is still honoured as dark: it was written by an older build
    // meaning dark, and this fix is about the absent case only.
    final themeIndex = prefs.getInt(_themeKey) ?? ThemeMode.system.index;

    _currency =
        Currency.values[currencyIndex.clamp(0, Currency.values.length - 1)];
    // Currency and ThemeMode are STILL stored as indices, deliberately. Their
    // enums are not changing, nothing is being removed from them, and rewriting
    // working persistence for no benefit is scope this was not asked for. The
    // palette was different because the palette's enum DID change.
    _themeMode =
        ThemeMode.values[themeIndex.clamp(0, ThemeMode.values.length - 1)];
    _palette = await _readPalette(prefs);
    notifyListeners();
  }

  /// The saved palette, by name; migrated from the legacy index exactly once.
  Future<AppPalette> _readPalette(SharedPreferences prefs) async {
    // The name key FIRST, and it is a DIFFERENT key from the legacy one.
    // `SharedPreferences.getString` on a key holding an int throws, so sharing
    // the key would have turned every returning user's first launch into a
    // crash rather than a silent re-theme.
    final name = prefs.getString(_paletteNameKey);
    if (name != null) {
      // An unrecognised NAME falls back to the default rather than throwing. A
      // future build may write a palette this one has never heard of, and a
      // launch failure over a colour is not an acceptable trade.
      return _paletteByName(name) ?? AppTheme.defaultPalette;
    }

    final legacyIndex = prefs.getInt(_legacyPaletteIndexKey);
    if (legacyIndex == null) return AppTheme.defaultPalette;

    final migrated =
        _legacyPaletteByIndex[legacyIndex] ?? AppTheme.defaultPalette;
    await setPalette(migrated);
    return migrated;
  }

  static AppPalette? _paletteByName(String name) {
    for (final palette in AppPalette.values) {
      if (palette.name == name) return palette;
    }
    return null;
  }

  Future<void> setCurrency(Currency currency) async {
    _currency = currency;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_currencyKey, currency.index);
    notifyListeners();
  }

  /// Chooses a VARIANT of the current family.
  ///
  /// Writes through to [setThemeMode] so there is exactly one persisted fact
  /// about brightness. Two setters writing two keys would let them disagree, and
  /// which one won would depend on read order.
  Future<void> setVariant(ThemeVariant value) => setThemeMode(switch (value) {
    ThemeVariant.system => ThemeMode.system,
    ThemeVariant.light => ThemeMode.light,
    ThemeVariant.dark => ThemeMode.dark,
  });

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, mode.index);
    notifyListeners();
  }

  Future<void> setPalette(AppPalette palette) async {
    if (_palette == palette && _migratedPalette) return;
    _palette = palette;
    _migratedPalette = true;

    // A family change must not leave a variant the new family does not have.
    // Switching to Gruvbox while the app was in Light would otherwise keep a
    // stored "light" that Gruvbox has no answer for, and the next launch would
    // have to guess. System is the safe landing: every family offers it.
    if (!palette.hasVariant(variant)) {
      _themeMode = ThemeMode.system;
      final prefsEarly = await SharedPreferences.getInstance();
      await prefsEarly.setInt(_themeKey, _themeMode.index);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_paletteNameKey, palette.name);
    // Removed once the name is written, so the legacy value cannot be read again
    // by a later build and re-migrated onto top of a newer preference.
    await prefs.remove(_legacyPaletteIndexKey);
    notifyListeners();
  }
}
