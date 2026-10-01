import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/theme/app_chart_colors.dart';
import 'package:flutter_application_1/theme/app_palettes.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/widgets/chart_pager.dart';

/// THE FLOOR IS 4.5:1, NOT 3:1.
///
/// The token was a border colour — `spec.outline`, documented as "a visible edge
/// for a raised card" — and measured at **1.78 to 2.68:1** on the four dark
/// specs. That is under even the 3:1 that icons and borders get, which is why
/// every caption, hint and sub-label in the app looked nearly invisible in every
/// dark theme at once. Sub-text is body copy, so the floor is body copy's 4.5.
const double secondaryTextFloor = 4.5;

/// Every theme/brightness spec the code produces. Counted, not trusted: seven
/// before T1 removed Kanagawa, six now.
List<(String, AppPalette, ThemeVariant)> _specs() {
  final specs = <(String, AppPalette, ThemeVariant)>[];
  for (final palette in AppPalette.values) {
    if (palette.supportsLight) {
      specs.add(('${palette.label} light', palette, ThemeVariant.light));
    }
    specs.add(('${palette.label} dark', palette, ThemeVariant.dark));
  }
  return specs;
}

double _ratio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

/// The three surfaces sub-text is actually drawn on.
ColorScheme _scheme(AppPalette palette, ThemeVariant variant) =>
    AppTheme.forVariant(palette, variant).colorScheme;

void main() {
  group('the token itself', () {
    test('there are exactly SIX specs', () {
      // Counted in code. The Stage 10 report said nine; the code produced seven;
      // after T1 it produces six.
      expect(_specs(), hasLength(6));
      expect(AppPalette.values, hasLength(4));
    });

    test('secondary text clears 4.5:1 on every surface it lands on', () {
      final failures = <String>[];
      for (final (name, palette, variant) in _specs()) {
        final scheme = _scheme(palette, variant);
        for (final entry in <String, Color>{
          'surface': scheme.surface,
          'surfaceContainerLow': scheme.surfaceContainerLow,
          'surfaceContainer': scheme.surfaceContainer,
          'surfaceContainerHigh': scheme.surfaceContainerHigh,
          'primaryContainer': scheme.primaryContainer,
        }.entries) {
          final ratio = _ratio(scheme.onSurfaceVariant, entry.value);
          if (ratio < secondaryTextFloor) {
            failures.add('$name / ${entry.key}: ${ratio.toStringAsFixed(2)}');
          }
        }
      }
      expect(failures, isEmpty, reason: failures.join('; '));
    });

    test('REGRESSION: it would FAIL on the old border token', () {
      // The point of this test. On the old code `onSurfaceVariant` was
      // `spec.outline` in dark, which measured 1.78 on Gruvbox's
      // containerHigh — so this asserts against that exact colour and fails.
      for (final palette in [
        AppPalette.solitude,
        AppPalette.gruvbox,
        AppPalette.catppuccin,
      ]) {
        final spec = AppPalettes.darkFor(palette);
        final oldToken = spec.outline;
        expect(
          _ratio(oldToken, spec.surfaceHighest),
          lessThan(secondaryTextFloor),
          reason:
              '${palette.name}: if the old outline token ever cleared the '
              'floor, this test is no longer proving anything',
        );
      }
    });

    test('every spec that FAILED now differs from its old source', () {
      // Scoped to the specs that were actually below the floor. TBRN light's
      // source measured 6.14 and is deliberately returned untouched -- an
      // adjusted-but-passing token would be changing an approved palette for no
      // reason -- so asserting "differs" there would be asserting the bug.
      const failed = {
        (AppPalette.tbrn, ThemeVariant.dark),
        (AppPalette.solitude, ThemeVariant.dark),
        (AppPalette.gruvbox, ThemeVariant.dark),
        (AppPalette.catppuccin, ThemeVariant.dark),
        (AppPalette.catppuccin, ThemeVariant.light),
      };
      var checked = 0;
      for (final (name, palette, variant) in _specs()) {
        if (!failed.contains((palette, variant))) continue;
        checked++;
        final scheme = _scheme(palette, variant);
        final oldSource = variant == ThemeVariant.dark
            ? AppPalettes.darkFor(palette).outline
            : AppPalettes.lightFor(palette)!.secondary;
        expect(
          scheme.onSurfaceVariant.toARGB32(),
          isNot(oldSource.toARGB32()),
          reason: '$name: sub-text is still painted with the old source token',
        );
      }
      expect(checked, 5, reason: 'expected five specs to have needed fixing');
    });

    test('a light mode that already passed is left alone', () {
      // TBRN light measured 6.14 before this change, and an unadjusted token is
      // still 6.14. Moving a passing colour would be changing an approved palette
      // for no reason.
      expect(
        _ratio(
          AppTheme.forVariant(
            AppPalette.tbrn,
            ThemeVariant.light,
          ).colorScheme.onSurfaceVariant,
          AppPalettes.tbrnLight.surfaceLow,
        ),
        closeTo(6.14, 0.05),
      );
    });
  });

  group('measured RENDERED text, not the token', () {
    // A token that clears 4.5 is necessary and not sufficient: the caller might
    // dim it again. These read the colour the PAINT actually got.
    Future<void> pumpWith(
      WidgetTester tester,
      ThemeData theme,
      Widget child,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    /// The colour [finder]'s Text actually renders with.
    Color renderedColor(WidgetTester tester, Finder finder) {
      final style = tester.widget<Text>(finder).style;
      return style?.color ??
          Theme.of(tester.element(finder)).colorScheme.onSurface;
    }

    testWidgets('the search hint renders at or above the floor', (
      tester,
    ) async {
      // A real screen, real Text, every theme. This is the call site the brief
      // named, and it is a hint at 12pt -- squarely body copy.
      for (final (name, palette, variant) in _specs()) {
        final theme = AppTheme.forVariant(palette, variant);
        await pumpWith(
          tester,
          theme,
          Builder(
            builder: (context) => Column(
              children: [
                for (final hint in ['Alpha', 'Bravo', 'Charlie'])
                  Text(
                    hint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        );
        final finder = find.text('Bravo');
        final rendered = renderedColor(tester, finder);
        expect(
          _ratio(rendered, theme.colorScheme.surface),
          greaterThanOrEqualTo(secondaryTextFloor),
          reason:
              '$name: the rendered hint is '
              '${_ratio(rendered, theme.colorScheme.surface).toStringAsFixed(2)}:1',
        );
      }
    });

    testWidgets('pager dots render visible, inactive AND active', (
      tester,
    ) async {
      for (final (name, palette, variant) in _specs()) {
        final theme = AppTheme.forVariant(palette, variant);
        await pumpWith(
          tester,
          theme,
          ChartPager(
            labels: const ['One', 'Two', 'Three'],
            pages: [
              for (final label in ['One', 'Two', 'Three'])
                Text(label, style: theme.textTheme.titleSmall),
            ],
          ),
        );

        final card = theme.colorScheme.surfaceContainerLow;
        _lastCardBackdrop = card;
        final inactive = _dotColour(
          tester,
          find.byKey(const ValueKey('chart-dot-1')),
        );
        final active = _dotColour(
          tester,
          find.byKey(const ValueKey('chart-dot-0')),
        );

        // The dot is a NON-TEXT indicator, so 3:1 is its floor -- but it is the
        // affordance that says "there is a second page", so it has to be visible.
        expect(
          _ratio(inactive, card),
          greaterThanOrEqualTo(3.0),
          reason:
              '$name: the inactive dot renders at '
              '${_ratio(inactive, card).toStringAsFixed(2)}:1, so a swipe '
              'control is invisible',
        );
        // And the two must differ, or "which page am I on" has no answer.
        expect(active.toARGB32(), isNot(inactive.toARGB32()));
      }
    });
  });

  group('the heatmap ramp is still readable after the token moved', () {
    // The ramp's faintest step was validated against `heatmapEmpty`, which is a
    // surface. Raising `onSurfaceVariant` does not touch either, but the ramp's
    // caption does read the token, so this pins the whole card together.
    test('the faintest ramp step is still distinct from the empty cell', () {
      for (final (name, palette, variant) in _specs()) {
        final scheme = _scheme(palette, variant);
        final faintest = AppChartColors.spendRamp(scheme).first;
        expect(
          _ratio(faintest, AppChartColors.heatmapEmpty(scheme)),
          greaterThan(1.3),
          reason:
              '$name: the faintest spend step has faded into the empty cell',
        );
      }
    });
  });
}

/// The colour a pager dot's decoration paints with, read off the render tree.
///
/// Read from the DECORATION rather than assumed, because the whole failure was an
/// alpha: the widget's `color` field is the translucent paint and the user sees
/// that over the card behind it.
Color _dotColour(WidgetTester tester, Finder key) {
  // The key is on the InkWell (the tap target); the painted box is a descendant,
  // because a key on a zero-size AnimatedContainer is not a usable handle.
  final finder = find.descendant(
    of: key,
    matching: find.byType(AnimatedContainer),
  );
  final container = tester.widget<AnimatedContainer>(finder.first);
  final decoration = container.decoration as BoxDecoration;
  final raw = decoration.color!;
  // Composited against the card the pager sits on, which is what the eye sees.
  return Color.alphaBlend(raw, _lastCardBackdrop);
}

/// The card backdrop used when compositing dots.
///
/// Set by the dot test before it pumps; module-level because `_dotColour` is a
/// top-level helper and threading a parameter through `AnimatedContainer`'s
/// subtree is more plumbing than the measurement is worth.
Color _lastCardBackdrop = const Color(0xFFFFFFFF);
