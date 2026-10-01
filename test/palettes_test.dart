import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/theme/app_chart_colors.dart';
import 'package:flutter_application_1/theme/app_palettes.dart';
import 'package:flutter_application_1/theme/app_theme.dart';

/// Every palette in every mode it can actually produce.
List<({String name, ThemeData theme})> _matrix() {
  final result = <({String name, ThemeData theme})>[];
  for (final palette in AppPalette.values) {
    if (palette.supportsLight) {
      result.add((
        name: '${palette.label} light',
        theme: AppTheme.lightFor(palette),
      ));
    }
    result.add((
      name: '${palette.label} dark',
      theme: AppTheme.darkFor(palette),
    ));
  }
  return result;
}

Iterable<(String, Color)> _colours() sync* {
  for (final meta in CategoryRegistry.expenseCategories()) {
    yield (meta.id, meta.color);
  }
  for (final meta in CategoryRegistry.suggestedExpenseTypes()) {
    yield (meta.id, meta.color);
  }
  for (final meta in CategoryRegistry.incomeCategories()) {
    yield (meta.id, meta.color);
  }
  yield ('custom', CategoryRegistry.metaFor(ExpenseCategory.other).color);
}

List<Color> _paletteHexes() => [for (final c in _colours()) c.$2];

/// Weighted RGB distance, SQUARED. The threshold is 150, which is ~12.25 in
/// ordinary distance terms — see the note on the function in
/// `design_system_test.dart`.
double _distance(Color a, Color b) {
  final dr = (a.r - b.r) * 255;
  final dg = (a.g - b.g) * 255;
  final db = (a.b - b.b) * 255;
  return dr * dr * 0.30 + dg * dg * 0.59 + db * db * 0.11;
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('the palette table', () {
    test('every palette builds a light and a dark theme', () {
      for (final palette in AppPalette.values) {
        expect(AppTheme.lightFor(palette), isA<ThemeData>());
        expect(AppTheme.darkFor(palette), isA<ThemeData>());
      }
    });

    test('only TBRN and Catppuccin have a light mode', () {
      expect(AppPalette.tbrn.supportsLight, isTrue);
      expect(AppPalette.catppuccin.supportsLight, isTrue);
      expect(AppPalette.kanagawa.supportsLight, isFalse);
      expect(AppPalette.solitude.supportsLight, isFalse);
      expect(AppPalette.gruvbox.supportsLight, isFalse);
    });

    test('a dark-only palette asked for light falls back to dark', () {
      // Reachable only from a stored preference the Settings screen does not
      // offer. A coherent dark screen beats a cream one in Kanagawa colours.
      expect(
        AppTheme.lightFor(AppPalette.kanagawa).colorScheme.brightness,
        Brightness.dark,
      );
    });

    test('TBRN is first, so the default index is TBRN', () {
      expect(AppPalette.values.first, AppPalette.tbrn);
      expect(AppTheme.defaultPalette, AppPalette.tbrn);
    });
  });

  group('every palette has its own six-level ladder', () {
    // THE POINT OF THE STAGE. Material's container roles are what Card, ListTile,
    // menus, dialogs, sheets, filled fields, chips and snack bars paint themselves
    // with, so six levels that all resolve to the page colour means no elevation
    // anywhere. That is the bug `90a480a` fixed for TBRN, and four new palettes
    // would inherit it without this.
    test('no level repeats another', () {
      for (final entry in _matrix()) {
        final scheme = entry.theme.colorScheme;
        final ladder = <String, Color>{
          'lowest': scheme.surfaceContainerLowest,
          'low': scheme.surfaceContainerLow,
          'mid': scheme.surfaceContainer,
          'high': scheme.surfaceContainerHigh,
          'highest': scheme.surfaceContainerHighest,
        };
        final seen = <int, String>{};
        for (final entry2 in ladder.entries) {
          expect(
            seen.containsKey(entry2.value.toARGB32()),
            isFalse,
            reason:
                '${entry.name}: ${entry2.key} is the same colour as '
                '${seen[entry2.value.toARGB32()]}',
          );
          seen[entry2.value.toARGB32()] = entry2.key;
        }
      }
    });

    test('consecutive levels are far enough apart to see', () {
      for (final entry in _matrix()) {
        final scheme = entry.theme.colorScheme;
        final ladder = [
          scheme.surfaceContainerLowest,
          scheme.surfaceContainerLow,
          scheme.surfaceContainer,
          scheme.surfaceContainerHigh,
          scheme.surfaceContainerHighest,
        ];
        for (var i = 0; i < ladder.length - 1; i++) {
          expect(
            _distance(ladder[i], ladder[i + 1]),
            greaterThan(2.0),
            reason: '${entry.name}: levels $i and ${i + 1} are too close',
          );
        }
      }
    });
  });

  group('the three surface tiers', () {
    test('flat, raised and accent are three different surfaces', () {
      for (final entry in _matrix()) {
        final scheme = entry.theme.colorScheme;
        final flat = AppSurfaces.specFor(AppSurfaceTier.flat, scheme).color;
        final raised = AppSurfaces.specFor(AppSurfaceTier.raised, scheme).color;
        final accent = AppSurfaces.specFor(AppSurfaceTier.accent, scheme).color;
        expect(flat, isNot(raised), reason: '${entry.name}: flat == raised');
        expect(
          raised,
          isNot(accent),
          reason: '${entry.name}: raised == accent',
        );
        expect(flat, isNot(accent), reason: '${entry.name}: flat == accent');
      }
    });

    test('a raised card separates from the page it sits on', () {
      for (final entry in _matrix()) {
        final scheme = entry.theme.colorScheme;
        expect(
          _distance(
            scheme.surface,
            AppSurfaces.specFor(AppSurfaceTier.raised, scheme).color,
          ),
          greaterThan(6.0),
          reason: '${entry.name}: a raised card has no edge against the page',
        );
      }
    });

    test('the tiers resolve from the scheme, not from a named TBRN tone', () {
      // The specific defect: `specFor` returned `AppColors.darkSurface`, so a Card
      // stayed TBRN-brown on Kanagawa's ink whichever theme was active.
      final tbrn = AppSurfaces.specFor(
        AppSurfaceTier.raised,
        AppTheme.dark().colorScheme,
      ).color;
      final kanagawa = AppSurfaces.specFor(
        AppSurfaceTier.raised,
        AppTheme.darkFor(AppPalette.kanagawa).colorScheme,
      ).color;
      expect(tbrn, isNot(kanagawa));
    });
  });

  group('category colours clear 3:1 on every surface they are drawn on', () {
    // THE OTHER HALF OF THE STAGE. Stage 0b tuned 28 fixed hexes against exactly
    // two surfaces and asserted against those two. Stage 10 added five surfaces
    // per palette and the fixed hexes do not clear 3:1 on them — Travel measures
    // 2.20 against Gruvbox's flat row, Snacks 1.86. There is no set of 28 fixed
    // hexes that clears 3:1 on six mid-tone surfaces while keeping every hue, so
    // the registry hex is the category's IDENTITY and the drawn colour is
    // resolved per surface.
    //
    // Asserted as a MEASURED ratio, never as a hex value.
    test('every category on every surface, in every palette', () {
      final bases = _paletteHexes();
      final tooLow = <String>[];

      for (final entry in _matrix()) {
        for (final surface in AppCategorySurfaces.forScheme(
          entry.theme.colorScheme,
        )) {
          final drawn = AppCategoryColour.resolveAll(bases, surface.$2);
          for (var i = 0; i < drawn.length; i++) {
            final ratio = _contrast(drawn[i], surface.$2);
            if (ratio < AppCategoryColour.minimumContrast) {
              tooLow.add(
                '${entry.name} / ${surface.$1}: ${_colours().elementAt(i).$1} '
                '${ratio.toStringAsFixed(2)}',
              );
            }
          }
        }
      }
      expect(tooLow, isEmpty, reason: tooLow.join('; '));
    });

    test('a palette that wholly passes is not touched at all', () {
      // The whole set moves together or not at all, so the question that matters
      // is "does anything fail here". Where nothing does, the canonical hexes are
      // exactly what a user sees and nothing shifts.
      final bases = _paletteHexes();
      for (final entry in _matrix()) {
        for (final surface in AppCategorySurfaces.forScheme(
          entry.theme.colorScheme,
        )) {
          final allPass = bases.every(
            (b) =>
                _contrast(b, surface.$2) >= AppCategoryColour.minimumContrast,
          );
          if (!allPass) continue;
          final drawn = AppCategoryColour.resolveAll(bases, surface.$2);
          for (var i = 0; i < drawn.length; i++) {
            expect(
              drawn[i].toARGB32(),
              bases[i].toARGB32(),
              reason:
                  '${entry.name} / ${surface.$1} passes outright, so '
                  '${_colours().elementAt(i).$1} must not move',
            );
          }
        }
      }
    });

    test('the whole set moves together, so separation is preserved', () {
      // Moving only the failing members moved them ONTO the passing ones and
      // produced a donut of identical browns. One offset for the whole palette is
      // what makes pairwise distances survive resolution exactly.
      final bases = _paletteHexes();
      for (final entry in _matrix()) {
        for (final surface in AppCategorySurfaces.forScheme(
          entry.theme.colorScheme,
        )) {
          final drawn = AppCategoryColour.resolveAll(bases, surface.$2);
          // Compared as a SPREAD rather than as a set of exact values: HSL
          // lightness does not round-trip perfectly through a colour, so the
          // measured offsets differ by hundredths. What matters is that they are
          // all the SAME offset to within rounding.
          final offsets = [
            for (var i = 0; i < drawn.length; i++)
              HSLColor.fromColor(drawn[i]).lightness -
                  HSLColor.fromColor(bases[i]).lightness,
          ];
          final spread = offsets.reduce(_max) - offsets.reduce(_min);
          expect(
            spread,
            lessThan(0.01),
            reason:
                '${entry.name} / ${surface.$1}: the palette was split into '
                'shifts spanning $spread, which is how colours converge',
          );
        }
      }
    });

    test('resolution preserves hue and saturation exactly', () {
      // A resolver that also nudged saturation, or drifted hue, would pass every
      // contrast check and quietly change what colour a category IS.
      final bases = _paletteHexes();
      for (final entry in _matrix()) {
        for (final surface in AppCategorySurfaces.forScheme(
          entry.theme.colorScheme,
        )) {
          final drawn = AppCategoryColour.resolveAll(bases, surface.$2);
          for (var i = 0; i < drawn.length; i++) {
            final before = HSLColor.fromColor(bases[i]);
            final after = HSLColor.fromColor(drawn[i]);
            // A lightness move in HSL shifts the apparent hue slightly, more so as
            // saturation falls, so the tolerance widens for the least saturated.
            final tolerance = before.saturation < 0.3 ? 6.0 : 3.0;
            final hueDelta = (before.hue - after.hue).abs();
            expect(
              hueDelta < tolerance || hueDelta > 360 - tolerance,
              isTrue,
              reason:
                  '${entry.name}: ${_colours().elementAt(i).$1} moved hue '
                  'by $hueDelta°',
            );
            // A lightness move in HSL perturbs the stored saturation a little on
            // the round trip. The tolerance is tight enough to catch a resolver
            // that was deliberately desaturating, which is the thing that matters.
            expect(
              (before.saturation - after.saturation).abs(),
              lessThan(0.05),
              reason:
                  '${entry.name}: ${_colours().elementAt(i).$1} lost '
                  'saturation',
            );
          }
        }
      }
    });

    test('resolution does not wash the palette out', () {
      // Clearing 3:1 by desaturating is easy and a donut of grey slices is worse
      // than one of low-contrast slices.
      final bases = _paletteHexes();
      for (final entry in _matrix()) {
        for (final surface in AppCategorySurfaces.forScheme(
          entry.theme.colorScheme,
        )) {
          final drawn = AppCategoryColour.resolveAll(bases, surface.$2);
          for (var i = 0; i < drawn.length; i++) {
            expect(
              HSLColor.fromColor(drawn[i]).saturation,
              greaterThan(0.05),
              reason: '${entry.name}: ${_colours().elementAt(i).$1} went grey',
            );
          }
        }
      }
    });

    test('a resolved colour is never the surface itself', () {
      final bases = _paletteHexes();
      for (final entry in _matrix()) {
        for (final surface in AppCategorySurfaces.forScheme(
          entry.theme.colorScheme,
        )) {
          for (final colour in AppCategoryColour.resolveAll(
            bases,
            surface.$2,
          )) {
            expect(colour.toARGB32(), isNot(surface.$2.toARGB32()));
          }
        }
      }
    });
  });

  group('the heatmap ramp slots', () {
    test('the ramp is one hue in several separable steps', () {
      for (final entry in _matrix()) {
        final ramp = AppChartColors.spendRamp(entry.theme.colorScheme);
        expect(ramp.length, greaterThanOrEqualTo(4));

        for (var i = 0; i < ramp.length - 1; i++) {
          expect(
            _distance(ramp[i], ramp[i + 1]),
            greaterThan(150),
            reason:
                '${entry.name}: ramp steps $i and ${i + 1} are too close '
                'to tell apart on a 15-pixel cell',
          );
        }

        final hues = [
          for (final c in ramp)
            HSLColor.fromColor(c).hue < 0
                ? HSLColor.fromColor(c).hue + 360
                : HSLColor.fromColor(c).hue,
        ];
        final spread = (hues.reduce(_max) - hues.reduce(_min)).abs();
        expect(
          spread,
          lessThan(40),
          reason:
              '${entry.name}: the ramp spans $spread° of hue, so it reads as '
              'several categories rather than one scale',
        );
      }
    });

    test('the faintest step is clearly distinct from the empty cell', () {
      // The failure item 5d names: at low alpha the faint end sat near the empty
      // cell's surface, so a lightly-spent day looked like nothing happened.
      for (final entry in _matrix()) {
        final scheme = entry.theme.colorScheme;
        final faintest = AppChartColors.spendRamp(scheme).first;
        final empty = AppChartColors.heatmapEmpty(scheme);
        expect(
          _distance(faintest, empty),
          greaterThan(150),
          reason:
              '${entry.name}: the faintest spend step is only '
              '${_contrast(faintest, empty).toStringAsFixed(2)}:1 against the '
              'empty cell, so a lightly-spent day reads as a blank one',
        );
      }
    });

    test('the dead cell is distinct from the empty cell', () {
      // Otherwise the padding around a month reads as a quiet week.
      for (final entry in _matrix()) {
        final scheme = entry.theme.colorScheme;
        expect(
          _distance(
            AppChartColors.heatmapDead(scheme),
            AppChartColors.heatmapEmpty(scheme),
          ),
          greaterThan(0),
          reason:
              '${entry.name}: dead cells and empty days are the same colour',
        );
      }
    });

    test('every SPENT step clears 3:1 on the card it is drawn on', () {
      // Step 0 is deliberately excluded: zero intensity IS the empty cell, by
      // design, and the empty cell is a surface rather than a mark.
      for (final entry in _matrix()) {
        final scheme = entry.theme.colorScheme;
        final length = AppChartColors.rampLength(scheme);
        for (var i = 0; i < length; i++) {
          final step = AppChartColors.spendStep(scheme, (i + 0.5) / length);
          expect(
            _contrast(step, scheme.surface),
            greaterThanOrEqualTo(AppCategoryColour.minimumContrast),
            reason: '${entry.name}: spend step $i is invisible on the card',
          );
        }
      }
    });

    test('the ramp is monotonic — more spend is always a further step', () {
      // One sample per band: two intensities inside the same band resolve to the
      // same step by construction, so asking them to differ would test the
      // quantisation rather than the ramp.
      for (final entry in _matrix()) {
        final scheme = entry.theme.colorScheme;
        final length = AppChartColors.rampLength(scheme);
        var previous = AppChartColors.spendStep(scheme, 0.01);
        for (var band = 1; band < length; band++) {
          final current = AppChartColors.spendStep(
            scheme,
            (band + 0.5) / length,
          );
          expect(
            _distance(previous, current),
            greaterThan(0),
            reason:
                '${entry.name}: band $band is the same colour as band '
                '${band - 1}, so a day that spends twice as much looks the same',
          );
          previous = current;
        }
      }
    });

    test('zero intensity is the empty cell, not the ramp', () {
      for (final entry in _matrix()) {
        final scheme = entry.theme.colorScheme;
        expect(
          AppChartColors.spendStep(scheme, 0),
          AppChartColors.heatmapEmpty(scheme),
        );
      }
    });
  });
}

double _max(double a, double b) => a > b ? a : b;
double _min(double a, double b) => a < b ? a : b;
