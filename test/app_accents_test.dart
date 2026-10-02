import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daily_companion/theme/app_accents.dart';
import 'package:daily_companion/theme/app_palettes.dart';
import 'package:daily_companion/theme/app_theme.dart';

/// WCAG contrast between two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

Future<AppAccents> _accentsIn(WidgetTester tester, AppPalette palette) async {
  late AppAccents found;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkFor(palette),
      home: Builder(
        builder: (context) {
          found = AppAccents.of(context);
          return const SizedBox();
        },
      ),
    ),
  );
  return found;
}

void main() {
  group('Gruvbox carries a second accent, and it is the one that was asked for', () {
    // THE POINT OF THE WHOLE THING. A screen with one accent has no hierarchy:
    // on the device the Active Journey card had its heading, chips, reminders
    // and call to action all in the same amber, which is why it read as a flat
    // block in every theme.
    test('the two accents are declared, and are different colours', () {
      final spec = AppPalettes.gruvboxDark;
      expect(spec.accentWarm, isNotNull);
      expect(spec.accentCool, isNotNull);
      expect(spec.accentWarm, isNot(spec.accentCool));
      expect(spec.accentWarm, isNot(spec.primary));
      expect(spec.accentCool, isNot(spec.primary));
    });

    test('they are the hexes that were asked for', () {
      // Written as the hexes, not as a description of them. A "warm accent" that
      // drifted a little each time a palette was tidied up would still satisfy
      // every other test in this file.
      expect(AppPalettes.gruvboxDark.accentWarm, const Color(0xFFDE741D));
      expect(AppPalettes.gruvboxDark.accentCool, const Color(0xFF779488));
    });

    test('both are legible on the card they will be drawn on', () {
      // Asserted as a MEASURED ratio, never as "it looks fine". 3:1 is the
      // non-text floor, and an accent used on a chip or a marker is non-text.
      const floor = 3.0;
      final scheme = AppTheme.darkFor(AppPalette.gruvbox).colorScheme;
      final card = scheme.surface;
      for (final entry in {
        'warm': AppPalettes.gruvboxDark.accentWarm!,
        'cool': AppPalettes.gruvboxDark.accentCool!,
      }.entries) {
        expect(
          _contrast(entry.value, card),
          greaterThanOrEqualTo(floor),
          reason:
              'the ${entry.key} accent ${entry.value} does not clear 3:1 '
              'on the card $card',
        );
      }
    });

    test('the warm and cool accents are actually different hues', () {
      // Two greys, or two near-identical browns, would satisfy "not equal" and
      // still leave the card with one apparent colour. Their hues have to be
      // far enough apart to read as two.
      final warm = HSLColor.fromColor(AppPalettes.gruvboxDark.accentWarm!);
      final cool = HSLColor.fromColor(AppPalettes.gruvboxDark.accentCool!);
      final apart = (warm.hue - cool.hue).abs();
      expect(
        apart > 0.15 || (1 - apart) > 0.15,
        isTrue,
        reason:
            'the two accents sit at hues $warm and $cool -- close enough that '
            'the card would still read as one colour',
      );
    });
  });

  group('a family with one hue keeps exactly the one it had', () {
    for (final palette in [
      AppPalette.tbrn,
      AppPalette.catppuccin,
      AppPalette.solitude,
    ]) {
      testWidgets('$palette falls back to primary and secondary', (
        tester,
      ) async {
        final accents = await _accentsIn(tester, palette);
        final scheme = AppTheme.darkFor(palette).colorScheme;
        expect(accents.warm, scheme.primary);
        expect(accents.cool, scheme.secondary);
      });
    }
  });

  group('reading an accent never fails', () {
    testWidgets('a theme with no extension falls back rather than throwing', (
      tester,
    ) async {
      // Extensions are opt-in, so a bare ThemeData -- a one-off MaterialApp in a
      // test, or a widget preview -- has none installed. Asking for an accent
      // there used to be a null dereference in whatever was being tested.
      late AppAccents found;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              found = AppAccents.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(found, isA<AppAccents>());
    });

    testWidgets('Gruvbox resolves through the extension', (tester) async {
      final accents = await _accentsIn(tester, AppPalette.gruvbox);
      expect(accents.warm, const Color(0xFFDE741D));
      expect(accents.cool, const Color(0xFF779488));
    });
  });

  group('a role names what an accent is for, not which colour it is', () {
    test('the roles return the two accents', () {
      const accents = AppAccents(
        warm: Color(0xFFDE741D),
        cool: Color(0xFF779488),
      );
      expect(accents.forRole(AppAccentRole.emphasis), accents.warm);
      expect(accents.forRole(AppAccentRole.supporting), accents.cool);
    });
  });

  group('the Gruvbox spec is the published palette, not an approximation', () {
    test('the tokens that have published names use them', () {
      final named = AppPalettes.gruvboxNamed;
      final spec = AppPalettes.gruvboxDark;
      expect(spec.background, named['background']);
      expect(spec.container, named['selection']);
      expect(spec.outline, named['muted']);
      expect(spec.primary, named['yellow']);
      expect(spec.secondary, named['cyan']);
      expect(spec.onSurface, named['foreground']);
      expect(spec.surfaceLowest, named['dark_background']);
      expect(spec.surfaceRecessed, named['darker_background']);
      expect(spec.surfaceHigh, named['lighter_background']);
      expect(spec.error, named['red']);
    });

    test('the ladder is six DIFFERENT colours', () {
      // Two levels coinciding is invisible until a user sees a card with no
      // edge, which is the original bug in a new palette.
      final ladder = AppPalettes.gruvboxDark.ladder;
      expect(ladder.toSet().length, ladder.length);
    });
  });
}
