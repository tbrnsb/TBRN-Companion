import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daily_companion/theme/app_palettes.dart';
import 'package:daily_companion/utils/format.dart';
import 'package:daily_companion/utils/number_style.dart';
import 'package:daily_companion/theme/app_theme.dart';

/// A currency the app can display amounts in.
///
/// STORED BY NAME, never by index. An earlier build persisted an enum INDEX, and
/// growing this list is exactly the case that breaks: inserting GBP at index 2
/// would silently turn every saved US Dollar into Pounds, with no crash and
/// nothing to notice. [name] is the persisted value and the list may grow in any
/// order.
///
/// ORDER IS THE DISPLAY ORDER and nothing more. [rs] leads because this is a
/// Nepali app and the rupee is what nearly everybody here wants; the rest follow
/// the order they were asked for.
enum Currency { rs, usd, gbp, jpy, eur, cny, cad, aud, inr }

extension CurrencyX on Currency {
  /// The glyph placed BEFORE the amount, including its trailing space.
  ///
  /// A SPACE, not none, because every one of these is a word-shaped mark rather
  /// than a mathematical operator: "Rs. 1,200" and "$1,200" both read, while
  /// "€1,200" runs the glyph into the digits. Yen and rupee are the two that
  /// look like operators and still want the gap, because the amounts they
  /// precede are usually long.
  ///
  /// [yenRenminbi] rather than a bare yen sign for China: ￥ and ¥ are different
  /// characters, and a Chinese amount written with the Japanese glyph is wrong in
  /// a way a user reads immediately even if they cannot say why.
  String get symbol => switch (this) {
    Currency.rs => 'Rs. ',
    Currency.usd => '\$',
    Currency.gbp => '£',
    Currency.jpy => '¥',
    Currency.eur => '€ ',
    Currency.cny => 'CN¥',
    Currency.cad => 'C\$',
    Currency.aud => 'A\$',
    Currency.inr => '₹',
  };

  /// The short label shown in the picker.
  ///
  /// [symbol] for the marks that ARE the label, and a code for the two that are
  /// not: "C$" and "A$" are how Canadians and Australians write their own
  /// currencies at home, but in a list next to a bare "$" they are ambiguous, so
  /// the picker shows the ISO code and the amounts show the mark.
  String get name => switch (this) {
    Currency.rs => 'Rs.',
    Currency.usd => '\$',
    Currency.gbp => '£',
    Currency.jpy => '¥',
    Currency.eur => '€',
    Currency.cny => 'CN¥',
    Currency.cad => 'CAD',
    Currency.aud => 'AUD',
    Currency.inr => '₹',
  };

  /// The full name, for the picker's supporting line.
  String get title => switch (this) {
    Currency.rs => 'Nepalese Rupee',
    Currency.usd => 'US Dollar',
    Currency.gbp => 'Pound Sterling',
    Currency.jpy => 'Japanese Yen',
    Currency.eur => 'Euro',
    Currency.cny => 'Chinese Yuan',
    Currency.cad => 'Canadian Dollar',
    Currency.aud => 'Australian Dollar',
    Currency.inr => 'Indian Rupee',
  };

  /// The ISO code, which is what [name] falls back to and what makes the
  /// persisted value readable rather than opaque.
  String get code => switch (this) {
    Currency.rs => 'NPR',
    Currency.usd => 'USD',
    Currency.gbp => 'GBP',
    Currency.jpy => 'JPY',
    Currency.eur => 'EUR',
    Currency.cny => 'CNY',
    Currency.cad => 'CAD',
    Currency.aud => 'AUD',
    Currency.inr => 'INR',
  };
}

class SettingsProvider extends ChangeNotifier {
  /// The currency, stored BY NAME under this key.
  ///
  /// See [Currency]: the list is about to grow, and an index would silently
  /// re-point every saved user's money at a different currency.
  static const _currencyNameKey = 'currency_name';

  /// Where the currency USED to be stored, as an enum index.
  ///
  /// Read once, for a migration, then left alone. Not deleted: a downgrade would
  /// find it, and it costs nothing to keep.
  static const _legacyCurrencyIndexKey = 'currency';
  static const _themeKey = 'theme_mode';

  /// The palette, stored BY NAME.
  ///
  /// It used to be stored as an enum INDEX, which is the whole reason this class
  /// carries a migration table. An index is positional: remove Kanagawa and
  /// everything after it shifts down, so a user whose saved index was 2 came back
  /// in Gruvbox, one whose index was 3 came back in Catppuccin, and none of it
  /// threw or logged. The app just came up in a palette nobody chose.
  /// The number shape, stored BY NAME (see [NumberStyle] and [Currency] for why
  /// an index is not safe here).
  static const _numberStyleKey = 'number_style';

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

  /// The number shape the user chose. See [AppFormat.numberStyle] for why the
  /// value is also held statically.
  NumberStyle _numberStyle = NumberStyle.commaDot;

  NumberStyle get numberStyle => _numberStyle;
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
    // Not a stored-index fallback of 0: 0 was `rs` under the old enum AND is
    // `rs` under the new one, so the first entry is the same either way and the
    // index is only consulted when a real legacy value is present.
    final legacyCurrencyIndex = prefs.getInt(_legacyCurrencyIndexKey);
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

    _currency = _readCurrency(prefs, legacyCurrencyIndex);
    _numberStyle = _readNumberStyle(prefs);
    // Pushed into the formatter HERE, once, rather than at each call site.
    AppFormat.setNumberStyle(_numberStyle);
    // ThemeMode is STILL stored as an index, deliberately. Its enum is not
    // changing, nothing is being removed from it, and rewriting working
    // persistence for no benefit is scope this was not asked for. Currency and
    // the palette were different because THEIR enums did change.
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

  /// The persisted currency, by name, with the old index honoured once.
  ///
  /// An unrecognised name falls back to the rupee rather than throwing: a
  /// corrupt or hand-edited value should cost a user their currency preference,
  /// not the ability to open the app.
  static Currency _readCurrency(SharedPreferences prefs, int? legacyIndex) {
    final stored = prefs.getString(_currencyNameKey);
    if (stored != null) {
      for (final currency in Currency.values) {
        if (currency.code == stored) return currency;
      }
    }
    // A legacy index is only meaningful against the OLD three-value enum, whose
    // order was [rs, usd, eur] -- and those three are the first, second and
    // fifth values now. Read against the CURRENT list it would turn a saved
    // Euro into Pounds, so the old meaning is stated here rather than inferred.
    if (legacyIndex != null && legacyIndex >= 0 && legacyIndex < 3) {
      return switch (legacyIndex) {
        0 => Currency.rs,
        1 => Currency.usd,
        _ => Currency.eur,
      };
    }
    return Currency.rs;
  }

  /// The persisted number shape, by name, defaulting when absent or unreadable.
  static NumberStyle _readNumberStyle(SharedPreferences prefs) {
    final stored = prefs.getString(_numberStyleKey);
    if (stored == null) return NumberStyle.commaDot;
    for (final style in NumberStyle.values) {
      if (style.name == stored) return style;
    }
    // A corrupt value costs a preference, not the ability to open the app.
    return NumberStyle.commaDot;
  }

  /// Chooses the number shape.
  Future<void> setNumberStyle(NumberStyle style) async {
    if (style == _numberStyle) return;
    _numberStyle = style;
    AppFormat.setNumberStyle(style);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_numberStyleKey, style.name);
    notifyListeners();
  }

  Future<void> setCurrency(Currency currency) async {
    _currency = currency;
    final prefs = await SharedPreferences.getInstance();
    // BY NAME, and the legacy index is REMOVED rather than left behind. Leaving
    // it means a user who somehow ended up holding both has two sources of truth
    // for one setting, and the one that wins is whichever is read first.
    await prefs.setString(_currencyNameKey, currency.code);
    await prefs.remove(_legacyCurrencyIndexKey);
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
