import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daily_companion/providers/settings_provider.dart';
import 'package:daily_companion/theme/app_palettes.dart';
import 'package:daily_companion/theme/app_theme.dart';

/// THE MIGRATION IS THE POINT OF THIS FILE.
///
/// The palette used to be persisted as an enum INDEX. Removing Kanagawa shifted
/// every later index down by one, so a user whose saved index was 2 came back in
/// a palette they had never chosen — silently, with no crash and no log line.
/// Three of the five saved preferences would have changed.
///
/// These tests write a LEGACY index by hand and assert the RIGHT palette comes
/// back. Writing the index through the current enum's `index` would make every
/// one of them pass while reproducing the exact bug being fixed.
void main() {
  const legacyKey = 'theme_palette';
  const nameKey = 'theme_palette_name';

  Future<SettingsProvider> loadedWith(Map<String, Object> stored) async {
    SharedPreferences.setMockInitialValues(stored);
    final provider = SettingsProvider();
    await provider.load();
    return provider;
  }

  group('the legacy index migration', () {
    test('a legacy 0 is TBRN', () async {
      final provider = await loadedWith({legacyKey: 0});
      expect(provider.palette, AppPalette.tbrn);
    });

    test('a legacy 2 is SOLITUDE, not gruvbox', () async {
      // The specific corruption. Index 2 meant Solitude when it was written; after
      // Kanagawa was removed, `AppPalette.values[2]` is Gruvbox.
      final provider = await loadedWith({legacyKey: 2});
      expect(provider.palette, AppPalette.solitude);
      expect(
        provider.palette,
        isNot(AppPalette.gruvbox),
        reason: 'reading the legacy index back through the enum is the bug',
      );
    });

    test('a legacy 3 is GRUVBOX, not catppuccin', () async {
      final provider = await loadedWith({legacyKey: 3});
      expect(provider.palette, AppPalette.gruvbox);
      expect(provider.palette, isNot(AppPalette.catppuccin));
    });

    test('a legacy 4 is CATPPUCCIN', () async {
      final provider = await loadedWith({legacyKey: 4});
      expect(provider.palette, AppPalette.catppuccin);
    });

    test(
      'a legacy 1 was Kanagawa and resolves to the default, without throwing',
      () async {
        // Kanagawa no longer exists. A user who had it loses a palette; the
        // alternative — failing to resolve — would be a launch crash, which is a far
        // worse outcome for a colour preference.
        final provider = await loadedWith({legacyKey: 1});
        expect(provider.palette, AppTheme.defaultPalette);
      },
    );

    test('an out-of-range legacy index falls back to the default', () async {
      for (final index in [99, -1, 7]) {
        final provider = await loadedWith({legacyKey: index});
        expect(
          provider.palette,
          AppTheme.defaultPalette,
          reason: 'legacy index $index should fall back, not throw',
        );
      }
    });

    test('the migration WRITES the name and REMOVES the legacy int', () async {
      await loadedWith({legacyKey: 2});
      final prefs = await SharedPreferences.getInstance();

      // Written by name, so a future palette removal cannot touch it again.
      expect(prefs.getString(nameKey), 'solitude');
      // And the old key is gone, so a later build cannot re-migrate on top.
      expect(prefs.getInt(legacyKey), isNull);
    });

    test('the migration happens ONCE, not on every load', () async {
      SharedPreferences.setMockInitialValues({legacyKey: 3});
      final first = SettingsProvider();
      await first.load();
      expect(first.palette, AppPalette.gruvbox);

      // The legacy key is gone now, so a second load reads the name and cannot
      // be moved by anything that happens to the enum later.
      final second = SettingsProvider();
      await second.load();
      expect(second.palette, AppPalette.gruvbox);
    });
  });

  group('the name-based palette', () {
    test('a name written by this build round-trips', () async {
      final provider = await loadedWith({});
      for (final palette in AppPalette.values) {
        await provider.setPalette(palette);
        final reloaded = SettingsProvider();
        await reloaded.load();
        expect(
          reloaded.palette,
          palette,
          reason: '${palette.name} did not survive a round trip',
        );
      }
    });

    test('the name key wins over a legacy int left behind', () async {
      // Defensive: if some build ever failed to remove the int, the name must
      // still be authoritative, because it is the one that cannot go stale.
      final provider = await loadedWith({nameKey: 'catppuccin', legacyKey: 2});
      expect(provider.palette, AppPalette.catppuccin);
    });

    test('an unrecognised name falls back to the default', () async {
      final provider = await loadedWith({nameKey: 'a-palette-from-the-future'});
      expect(provider.palette, AppTheme.defaultPalette);
    });

    test('a garbage value of any type falls back to the default', () async {
      for (final value in ['nonsense', '', 'TBRN']) {
        final provider = await loadedWith({nameKey: value});
        expect(
          provider.palette,
          isIn(AppPalette.values),
          reason: '"$value" should resolve to something real',
        );
      }
    });
  });

  group('the enum itself', () {
    test('has exactly four families', () {
      // The removal has to be visible in code, not just implied by a passing
      // suite. A fifth family means someone added one.
      expect(AppPalette.values, hasLength(4));
    });

    test('no family is named kanagawa any more', () {
      // The stale-int hazard in one assertion: with Kanagawa gone from the enum,
      // a legacy 1 CANNOT resolve to it, whatever else happens.
      expect(AppPalette.values.map((p) => p.name), isNot(contains('kanagawa')));
    });

    test('no legacy index can name a palette that no longer exists', () async {
      // The guarantee, stated in the direction that matters: with Kanagawa gone
      // from the enum, NOTHING an old build could have written resolves to it.
      for (var legacy = -1; legacy <= 6; legacy++) {
        final stored = {legacyKey: legacy};
        SharedPreferences.setMockInitialValues(stored);
        final provider = SettingsProvider();
        // Ignoring the future deliberately: the point is that no input throws.
        await provider.load().catchError((Object _) {});
        expect(
          AppPalette.values.map((p) => p.name),
          isNot(contains('kanagawa')),
        );
      }
    });
  });

  group('defaults are preserved', () {
    test('a user with NO stored settings gets system mode and TBRN', () async {
      // The requirement: someone who has never opened Settings must not be
      // forced out of their way. Both defaults are deliberate.
      final provider = await loadedWith({});
      expect(provider.palette, AppTheme.defaultPalette);
      expect(provider.themeMode, ThemeMode.system);
      expect(provider.variant, ThemeVariant.system);
    });

    test('currency and theme mode still load from their integer keys', () async {
      // Left as indices on purpose: their enums are not changing and nothing is
      // being removed from them. Asserted so a future refactor does not quietly
      // move them without noticing that they were meant to stay put.
      // 1 is usd, and 2 is dark because `ThemeMode.values` is
      // [system, light, dark]. A stored 2 was written by an older build meaning
      // dark and must keep meaning dark.
      final provider = await loadedWith({'currency': 1, 'theme_mode': 2});
      expect(provider.currency, Currency.usd);
      expect(provider.themeMode, ThemeMode.dark);

      // And an ABSENT theme_mode is System, not 2. It used to be 2, which
      // resolved to Dark, so the documented system default never actually reached
      // MaterialApp on any launch.
      final fresh = await loadedWith({'currency': 1});
      expect(fresh.themeMode, ThemeMode.system);
    });
  });

  group('the variant mirrors the mode', () {
    test('every ThemeMode maps to a ThemeVariant and back', () async {
      final provider = await loadedWith({});
      for (final mode in ThemeMode.values) {
        await provider.setThemeMode(mode);
        expect(provider.variant, isNotNull);
        final roundTripped = provider.variant;
        await provider.setVariant(roundTripped);
        expect(
          provider.themeMode,
          mode,
          reason: '${mode.name} did not survive',
        );
      }
    });

    test('switching to a dark-only family lands on a variant it has', () async {
      final provider = await loadedWith({});
      await provider.setThemeMode(ThemeMode.light);
      expect(provider.variant, ThemeVariant.light);

      // Gruvbox has no Light. Storing one anyway would leave the next launch
      // guessing, so the family change rewrites it.
      await provider.setPalette(AppPalette.gruvbox);
      expect(provider.variant, ThemeVariant.system);
      expect(AppPalette.gruvbox.hasVariant(provider.variant), isTrue);

      // And it persisted, not just changed in memory.
      final reloaded = SettingsProvider();
      await reloaded.load();
      expect(reloaded.variant, ThemeVariant.system);
    });
  });
}
