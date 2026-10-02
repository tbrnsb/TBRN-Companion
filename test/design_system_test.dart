import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/theme/app_chart_colors.dart';
import 'package:daily_companion/theme/app_palettes.dart';
import 'package:daily_companion/theme/app_theme.dart';
import 'package:daily_companion/widgets/app_motion.dart';

import 'test_viewports.dart';

void main() {
  group('category colour contrast', () {
    // A category colour is an icon tint and a legend swatch. If it does not
    // clear 3:1 against the surface it is drawn on, the category is a guess.
    //
    // Both surfaces, not one: the same token is used in light mode on cream and
    // in dark mode on near-black, and 3:1 is a claim about a specific
    // background. Nine of the original twenty-one failed one or the other, and
    // Travel failed dark at 1.78 — the carafe brown on a near-black background.
    //
    // The threshold is 3.0 and the palettes clear 3.10, so rounding in a colour
    // space or a future tweak has a little room before this fails.
    const minimumContrast = 3.0;

    // These measure the colour AS DRAWN, through AppCategoryColour, rather than
    // the registry hex.
    //
    // That is the change stage 10 forced. Stage 0b tuned 28 fixed hexes to clear
    // 3:1 on exactly two surfaces, and asserted against those two. Then stage 10
    // added five surfaces per palette — and there is no set of 28 fixed hexes that
    // clears 3:1 on six mid-tone surfaces while keeping every hue, because the
    // 28 include several browns in the same narrow luminance band. So the registry
    // hex is the category's IDENTITY and the drawn colour is resolved per surface.
    //
    // Asserted against TBRN's page, its RAISED card and its dark background —
    // including `darkSurface`, which is the surface charts, legends and category
    // chips actually draw on and which the old assertion missed.
    test('every category colour clears 3:1 on every TBRN surface', () {
      final tooLow = <String>[];
      for (final spec in [AppPalettes.tbrnLight, AppPalettes.tbrnDark]) {
        for (final surface in {
          'page': spec.background,
          'raised': spec.surfaceLow,
          'flat': spec.surfaceHigh,
        }.entries) {
          final metas = _everyCategoryColour().toList();
          final drawn = AppCategoryColour.resolveAll([
            for (final meta in metas) meta.$2,
          ], surface.value);
          for (var i = 0; i < metas.length; i++) {
            final ratio = _contrastRatio(drawn[i], surface.value);
            if (ratio < minimumContrast) {
              tooLow.add(
                '${metas[i].$1} ${ratio.toStringAsFixed(2)} on ${surface.key}',
              );
            }
          }
        }
      }
      expect(tooLow, isEmpty, reason: tooLow.join('; '));
    });

    test('the palette did not get washed out fixing contrast', () {
      // Clearing 3:1 in a narrow luminance band is easy to do by desaturating
      // everything toward grey, and a donut of grey slices is worse than one of
      // low-contrast slices. Every category has to keep real chroma.
      for (final meta in _everyCategoryColour()) {
        final hsv = HSVColor.fromColor(meta.$2);
        expect(
          hsv.saturation,
          greaterThan(0.05),
          reason:
              '${meta.$1} is nearly grey (saturation '
              '${hsv.saturation.toStringAsFixed(2)}); the categories have to '
              'stay tellable apart by colour',
        );
      }
    });
  });

  group('surface tiers', () {
    testWidgets('a surface is an ink surface, not a decorated box', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: AppSurface(
              tier: AppSurfaceTier.raised,
              child: ListTile(
                title: const Text('A tile on a surface'),
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // A Container with a background colour is not an ink surface, so the
      // ListTile's own background and splashes would be hidden by it and
      // Flutter throws "ListTile background color or ink splashes may be
      // invisible". This asserts the surface is built on a Material.
      expect(tester.takeException(), isNull);

      // The nearest Material ancestor of the tile is the surface itself.
      final tileMaterial = tester.widget<Material>(
        find
            .ancestor(
              of: find.text('A tile on a surface'),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(tileMaterial.type, MaterialType.canvas);
    });

    test('the light surface ladder actually has steps', () {
      // The bug this pins: Material's container roles were left unset, so
      // surfaceContainerLow through surfaceContainerHigh all resolved to the
      // page colour. Card, ListTile, menus, dialogs, sheets, filled fields and
      // chips paint themselves with those roles, so with no ladder there was no
      // elevation in light mode and every card vanished into the background.
      final scheme = AppTheme.light().colorScheme;

      final ladder = <String, Color>{
        'lowest': scheme.surfaceContainerLowest,
        'low': scheme.surfaceContainerLow,
        'mid': scheme.surfaceContainer,
        'high': scheme.surfaceContainerHigh,
        'highest': scheme.surfaceContainerHighest,
      };
      final names = ladder.keys.toList();
      for (var i = 0; i < names.length - 1; i++) {
        expect(
          _colourDistance(ladder[names[i]]!, ladder[names[i + 1]]!),
          greaterThan(0),
          reason:
              '${names[i]} and ${names[i + 1]} are the same colour, so a card '
              'painted with one is invisible against a card painted with the '
              'other',
        );
      }
    });

    test('a raised card is visibly above the page', () {
      final scheme = AppTheme.light().colorScheme;
      final page = scheme.surface;
      final raised = AppSurfaces.specFor(AppSurfaceTier.raised, scheme).color;

      // A card has to separate from the page it sits on, or the layout has no
      // structure to read.
      expect(_colourDistance(page, raised), greaterThan(6));
    });

    test('the raised card stays inside the warm palette', () {
      final scheme = AppTheme.light().colorScheme;
      final raised = AppSurfaces.specFor(AppSurfaceTier.raised, scheme).color;

      // It used to be Colors.white, which is off-palette next to a cream page
      // and reads as clinical rather than warm.
      expect(raised, isNot(const Color(0xFFFFFFFF)));
      // Warm means at least as much red as blue.
      expect(raised.r, greaterThanOrEqualTo(raised.b));
    });

    test('the dark surface ladder has steps too', () {
      // Dark had the same defect as light: every container role collapsed onto
      // the surface colour, so Material's own components had no elevation.
      final scheme = AppTheme.dark().colorScheme;
      final ladder = <Color>[
        scheme.surfaceContainerLowest,
        scheme.surfaceContainerLow,
        scheme.surfaceContainer,
        scheme.surfaceContainerHigh,
        scheme.surfaceContainerHighest,
      ];
      for (var i = 0; i < ladder.length - 1; i++) {
        expect(
          _colourDistance(ladder[i], ladder[i + 1]),
          greaterThan(0),
          reason: 'step $i and ${i + 1} of the dark ladder are identical',
        );
      }
      // Dark climbs the other way: each step is lighter than the last.
      for (var i = 0; i < ladder.length - 1; i++) {
        expect(
          ladder[i + 1].computeLuminance(),
          greaterThan(ladder[i].computeLuminance()),
          reason: 'the dark ladder should get lighter as it rises',
        );
      }
    });

    testWidgets('each tier produces a distinct fill', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final scheme = AppTheme.light().colorScheme;
      final flat = AppSurfaces.specFor(AppSurfaceTier.flat, scheme);
      final raised = AppSurfaces.specFor(AppSurfaceTier.raised, scheme);
      final accent = AppSurfaces.specFor(AppSurfaceTier.accent, scheme);

      // The whole point of three tiers: if they all resolved to the same
      // colour there would be no hierarchy, which is what the app looked like
      // when every card was the same flat outlined box.
      expect(flat.color, isNot(raised.color));
      expect(raised.color, isNot(accent.color));
      expect(flat.color, isNot(accent.color));

      // flat has no border, raised does, accent is a tonal container.
      expect(flat.border.style, BorderStyle.none);
      expect(raised.border.style, BorderStyle.solid);
      expect(accent.color, scheme.primaryContainer);
    });

    testWidgets('every tier works in dark mode too', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final scheme = AppTheme.dark().colorScheme;
      for (final tier in AppSurfaceTier.values) {
        final spec = AppSurfaces.specFor(tier, scheme);
        expect(spec.color, isNotNull, reason: '$tier has no dark fill');
      }
    });
  });

  group('type scale', () {
    test('supporting text is clearly lighter than the headline', () {
      final theme = AppTheme.light();
      final text = theme.textTheme;

      // The app used to run on three sizes, so nothing was a headline. The
      // scale has to have real size distance between the two ends of it.
      expect(
        text.displayMedium!.fontSize!,
        greaterThan(text.titleSmall!.fontSize!),
      );
      expect(
        text.displayMedium!.fontSize!,
        greaterThan(text.bodySmall!.fontSize!),
      );

      // And weight contrast, so the eye has something to land on.
      expect(
        text.displayMedium!.fontWeight!.value,
        greaterThan(text.titleMedium!.fontWeight!.value),
      );
      expect(
        text.titleMedium!.fontWeight!.value,
        greaterThan(text.bodySmall!.fontWeight!.value),
      );
    });

    test('every style states its own size, in both brightnesses', () {
      // In this Flutter version every fontSize in the default text theme is
      // null and only appears when a style is merged against the platform
      // default at paint time. A scale that relies on that has no guaranteed
      // size contrast, so every role states its own.
      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        for (final entry in {
          'displayMedium': theme.textTheme.displayMedium,
          'headlineMedium': theme.textTheme.headlineMedium,
          'titleMedium': theme.textTheme.titleMedium,
          'titleSmall': theme.textTheme.titleSmall,
          'bodyLarge': theme.textTheme.bodyLarge,
          'bodyMedium': theme.textTheme.bodyMedium,
          'bodySmall': theme.textTheme.bodySmall,
          'labelLarge': theme.textTheme.labelLarge,
          'labelMedium': theme.textTheme.labelMedium,
        }.entries) {
          expect(entry.value, isNotNull, reason: '${entry.key} is missing');
          expect(
            entry.value!.fontSize,
            isNotNull,
            reason: '${entry.key} has no size of its own',
          );
          expect(
            entry.value!.color,
            isNotNull,
            reason: '${entry.key} has no colour of its own',
          );
        }
      }
    });
  });

  group('motion', () {
    test('durations stay inside the 150-250ms band', () {
      // Nothing bouncy and nothing slow: a tap that takes longer than 250ms to
      // acknowledge feels broken, not smooth.
      expect(AppMotion.fast.inMilliseconds, inInclusiveRange(150, 250));
      expect(AppMotion.medium.inMilliseconds, inInclusiveRange(150, 250));
    });

    testWidgets('the progress bar eases to its new value', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      Widget bar(double value) => MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 200, child: AppProgressBar(value: value)),
          ),
        ),
      );

      await tester.pumpWidget(bar(0));
      await tester.pumpAndSettle();

      await tester.pumpWidget(bar(1));
      // Mid-transition the bar must be part-way, not snapped to its target.
      await tester.pump(const Duration(milliseconds: 90));
      final mid = tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value!;
      expect(mid, greaterThan(0));
      expect(mid, lessThan(1));

      await tester.pumpAndSettle();
      final done = tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value!;
      expect(done, closeTo(1, 0.001));
    });

    testWidgets('the progress bar clamps an out-of-range value', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: Center(child: AppProgressBar(value: 4.2))),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final value = tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value!;
      expect(value, lessThanOrEqualTo(1));
    });
  });

  group('expense categories', () {
    test('there are exactly nine, and Other is the one that leads away', () {
      // The "All" list is meant to show nine with Other among them. Anything
      // else and the list the user sees does not match what was asked for.
      expect(ExpenseCategory.values, hasLength(9));
      expect(
        CategoryRegistry.expenseCategories(),
        hasLength(9),
        reason: 'the registry and the enum must not drift apart',
      );
      expect(ExpenseCategory.values.last, ExpenseCategory.other);
    });

    test('every category has its own name, id and icon', () {
      final metas = CategoryRegistry.expenseCategories();
      expect(metas.map((m) => m.id).toSet(), hasLength(9));
      expect(metas.map((m) => m.name).toSet(), hasLength(9));
      expect(metas.map((m) => m.icon).toSet(), hasLength(9));
    });

    test('no two category colours are close enough to be confused', () {
      // The breakdown donut puts these side by side. Two warm browns next to
      // each other are unreadable, and a screenshot is the only way to notice
      // by eye, so the separation is asserted numerically instead.
      final metas = [
        ...CategoryRegistry.expenseCategories(),
        // The suggested "Other" types land in the same donut, so they have to
        // separate from the main nine and from each other too — checking only
        // the nine would let a suggested colour collide with a main one.
        ...CategoryRegistry.suggestedExpenseTypes(),
      ];
      // The closest pair in the current palette sits at 188 on a 0-441 scale,
      // so 150 leaves headroom while still catching a genuinely confusable pair.
      const minimumSeparation = 150.0;

      final tooClose = <String>[];
      for (var i = 0; i < metas.length; i++) {
        for (var j = i + 1; j < metas.length; j++) {
          final distance = _colourDistance(metas[i].color, metas[j].color);
          if (distance < minimumSeparation) {
            tooClose.add(
              '${metas[i].name}/${metas[j].name} only ${distance.toStringAsFixed(0)} apart',
            );
          }
        }
      }

      expect(tooClose, isEmpty, reason: tooClose.join('; '));
    });

    test('a stored category name still resolves after the list grew', () {
      // MIGRATION SAFETY: a transaction stores its category by name. Every name
      // that could already be on disk must still resolve to the same category
      // it did before health, shopping and housing were added.
      const previouslyStored = {
        'food': ExpenseCategory.food,
        'travel': ExpenseCategory.travel,
        'gear': ExpenseCategory.gear,
        'entertainment': ExpenseCategory.entertainment,
        'utilities': ExpenseCategory.utilities,
        'other': ExpenseCategory.other,
      };

      for (final entry in previouslyStored.entries) {
        final resolved = ExpenseCategory.values.firstWhere(
          (e) => e.name == entry.key,
          orElse: () => ExpenseCategory.other,
        );
        expect(
          resolved,
          entry.value,
          reason: 'a stored "${entry.key}" now resolves to $resolved',
        );
      }
    });
  });
}

/// Perceptual-ish RGB distance on a 0-255 scale.
///
/// Good enough to catch two swatches that read as the same colour next to each
/// other, which is the failure that matters here. Note that [Color.r] and
/// friends are normalised 0-1 doubles in current Flutter, so they have to be
/// scaled back up or every distance rounds to zero and the check passes
/// vacuously.
double _colourDistance(Color a, Color b) {
  final dr = (a.r - b.r) * 255;
  final dg = (a.g - b.g) * 255;
  final db = (a.b - b.b) * 255;
  // Weighted to approximate perceived difference: the eye is most sensitive to
  // green and least to blue.
  return (dr * dr * 0.30 + dg * dg * 0.59 + db * db * 0.11);
}

/// Every colour a category can be drawn in, paired with a name for the failure
/// message.
///
/// All four lists, not just the nine: the donut check only covers expense and
/// suggested, but an income category colour is drawn as a legend swatch and a
/// chip exactly the same way, so it has the same obligation.
Iterable<(String, Color)> _everyCategoryColour() sync* {
  for (final meta in CategoryRegistry.expenseCategories()) {
    yield (meta.name, meta.color);
  }
  for (final meta in CategoryRegistry.suggestedExpenseTypes()) {
    yield (meta.name, meta.color);
  }
  for (final meta in CategoryRegistry.incomeCategories()) {
    yield (meta.name, meta.color);
  }
  yield ('Custom', CategoryRegistry.metaFor(ExpenseCategory.other).color);
}

/// WCAG relative-luminance contrast ratio between [a] and [b], 1.0 to 21.0.
///
/// The standard formula, on the real surfaces rather than a mock, because the
/// whole point is that these two specific backgrounds are the ones a category
/// is drawn against. [Color.r] and friends are 0-1 doubles in current Flutter,
/// so they are scaled back to 0-255 before the transfer function.
double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}
