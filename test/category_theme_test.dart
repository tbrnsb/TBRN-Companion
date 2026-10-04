import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/theme/app_chart_colors.dart';
import 'package:daily_companion/theme/app_palettes.dart';

/// EVERY built-in category has to look right in EVERY palette.
///
/// The registry hexes are TUNED FOR ONE PALETTE. They were fixed against TBRN's
/// cream page, which is why `AppCategoryColour` exists — it re-derives them per
/// surface so they clear 3:1 wherever they land. It was written, tested, and
/// then used in one place out of twenty-nine, so on Gruvbox, Catppuccin and
/// Solitude the raw hex was drawn everywhere anyway: category chips, donut
/// slices, detail headers, budgets, search results. That is what "does not match
/// the theme" means in practice, and no amount of resolver is invisible while
/// nothing calls it.
///
/// This group is the guard: it walks all six specs, and every built-in must come
/// back readable on all three surfaces.
void main() {
  group('every built-in category is themed', () {
    const minimumContrast = 3.0;

    /// The two sets a breakdown can draw together.
    ///
    /// A donut is EITHER spending OR income, and the suggested "Other" types join
    /// the expense side, so that is the partition that has to hold up: resolving
    /// each side alone is what stops a fix on one palette moving a colour onto its
    /// neighbour in the other.
    List<CategoryMeta> expenseSide() => [
      ...CategoryRegistry.expenseCategories(),
      ...CategoryRegistry.suggestedExpenseTypes(),
    ];

    List<CategoryMeta> incomeSide() => CategoryRegistry.incomeCategories();

    for (final spec in [
      AppPalettes.tbrnLight,
      AppPalettes.tbrnDark,
      AppPalettes.catppuccinLatte,
      AppPalettes.catppuccinMocha,
      AppPalettes.solitudeDark,
      AppPalettes.gruvboxDark,
    ]) {
      test(
        'every category clears 3:1 on all three ${spec.palette.name} surfaces',
        () {
          final tooLow = <String>[];
          for (final surface in {
            'page': spec.background,
            'raised': spec.surfaceLow,
            'flat': spec.surfaceHigh,
          }.entries) {
            final resolved = AppCategoryColour.allBuiltInOn(surface.value);
            for (final meta in [...expenseSide(), ...incomeSide()]) {
              final colour = resolved[meta.name];
              if (colour == null) {
                tooLow.add('${meta.name} has no themed colour at all');
                continue;
              }
              final ratio = _contrastRatio(colour, surface.value);
              if (ratio < minimumContrast) {
                tooLow.add(
                  '${meta.name} ${ratio.toStringAsFixed(2)} on ${surface.key}',
                );
              }
            }
          }
          expect(tooLow, isEmpty, reason: tooLow.join('; '));
        },
      );
    }

    test('the themed colour actually DIFFERS from the raw hex on some palette', () {
      // The guard above would pass on a resolver that returned the registry
      // colour unchanged, because TBRN light is what those hexes were tuned for.
      // So assert the resolver MOVES something somewhere — otherwise this whole
      // file could be satisfied by a function that ignores its argument.
      final gruvbox = AppPalettes.gruvboxDark.surfaceHigh;
      final resolved = AppCategoryColour.allBuiltInOn(gruvbox);
      final moved = [
        ...expenseSide(),
        ...incomeSide(),
      ].where((m) => resolved[m.name] != m.color).length;

      expect(
        moved,
        greaterThan(0),
        reason:
            'on a palette the hexes were not tuned for, something has to '
            'change; nothing changing means the resolver is not being used',
      );
    });

    test('theming keeps the categories tellable apart', () {
      // The whole point of moving the SET rather than one colour at a time. If
      // this drops below the threshold the fix has started merging two slices
      // into one, which is worse than the low contrast it was solving.
      for (final spec in [
        AppPalettes.gruvboxDark,
        AppPalettes.catppuccinMocha,
        AppPalettes.solitudeDark,
      ]) {
        for (final surface in [spec.background, spec.surfaceHigh]) {
          final resolved = AppCategoryColour.allBuiltInOn(surface);
          final tooClose = <String>[];
          // ALL of them, not just the expense side. The first version of this
          // test checked expense-side only and passed while `gear` and
          // `freelance` sat 59 apart -- one is an expense category and one is an
          // income category, and both are drawn as chips, swatches and detail
          // headers on the same screens, so they have to be told apart just as
          // much as two that share a donut.
          final side = [...expenseSide(), ...incomeSide()];
          for (var i = 0; i < side.length; i++) {
            for (var j = i + 1; j < side.length; j++) {
              final distance = _colourDistance(
                resolved[side[i].name]!,
                resolved[side[j].name]!,
              );
              if (distance < 150) {
                tooClose.add(
                  '${side[i].name}/${side[j].name} ${distance.toStringAsFixed(0)}',
                );
              }
            }
          }
          expect(
            tooClose,
            isEmpty,
            reason: 'on ${spec.palette.name}: ${tooClose.join('; ')}',
          );
        }
      }
    });

    test('theming never washes a category out to grey', () {
      // Clearing contrast by desaturating is the easy way and the wrong one: a
      // donut of grey slices is worse than one of dim slices.
      for (final spec in [
        AppPalettes.tbrnLight,
        AppPalettes.gruvboxDark,
        AppPalettes.catppuccinLatte,
        AppPalettes.solitudeDark,
      ]) {
        final resolved = AppCategoryColour.allBuiltInOn(spec.background);
        final grey = [...expenseSide(), ...incomeSide()]
            .where(
              (m) => HSVColor.fromColor(resolved[m.name]!).saturation <= 0.05,
            )
            .map((m) => m.name);

        expect(
          grey,
          isEmpty,
          reason:
              'on ${spec.palette.name}, these went grey: ${grey.join(', ')}',
        );
      }
    });

    test('a user-chosen custom colour is left exactly as it was picked', () {
      // The one colour in the app the app has no business restyling.
      const picked = Color(0xFF7C3AED);
      final meta = CategoryRegistry.metaForCustom(
        const CustomCategory(
          name: 'Hobby',
          kind: CategoryKind.expense,
          colorValue: 0xFF7C3AED,
        ),
      );
      expect(meta.color, picked);

      for (final spec in [
        AppPalettes.tbrnLight,
        AppPalettes.gruvboxDark,
        AppPalettes.solitudeDark,
      ]) {
        for (final surface in [spec.background, spec.surfaceHigh]) {
          expect(
            AppCategoryColour.forMeta(meta, surface),
            picked,
            reason:
                'a custom category must not be re-derived per theme; it was '
                'chosen on purpose',
          );
        }
      }
    });

    test('forMeta agrees with allBuiltInOn', () {
      // Two entry points that disagree would be worse than either being absent,
      // because a caller could pick the wrong one and see a different colour from
      // its neighbour on the same screen.
      const surfaces = [
        AppPalettes.gruvboxDark,
        AppPalettes.catppuccinMocha,
        AppPalettes.tbrnLight,
      ];
      for (final spec in surfaces) {
        for (final surface in [spec.background, spec.surfaceHigh]) {
          final batch = AppCategoryColour.allBuiltInOn(surface);
          for (final meta in [...expenseSide(), ...incomeSide()]) {
            expect(
              AppCategoryColour.forMeta(meta, surface),
              batch[meta.name],
              reason: '${meta.name} differs between the single and batch paths',
            );
          }
        }
      }
    });
  });
}

/// WCAG relative luminance, then the ratio.
double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

/// Perceived colour distance, on the SAME measure `design_system_test.dart`
/// already uses.
///
/// The first version of this file invented an HSL distance instead — hue,
/// saturation and lightness weighted by hand — and it reported 175 expense-side
/// pairs as unseparated, including "Travel/Coffee 6". `design_system_test.dart`
/// passes today with the hexes as they are, so that formula was measuring
/// something the app has never claimed: two warm browns at the same lightness but
/// different RGB mixes are genuinely distinguishable on screen, and an HSL hue
/// distance calls them identical. A test for this must use the project's
/// measure or it fails the palette rather than testing it.
///
/// Luma-weighted, because the eye is most sensitive to green and least to blue.
double _colourDistance(Color a, Color b) {
  final dr = (a.r - b.r) * 255;
  final dg = (a.g - b.g) * 255;
  final db = (a.b - b.b) * 255;
  return dr * dr * 0.30 + dg * dg * 0.59 + db * db * 0.11;
}
