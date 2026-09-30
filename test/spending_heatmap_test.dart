import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/widgets/spending_heatmap.dart';
import 'package:flutter_application_1/widgets/spend_trend_cards.dart'
    show DayTotal;

import 'test_viewports.dart';

/// A month with spend on a handful of days and nothing on the rest.
///
/// Sparse on purpose: a heatmap whose every cell is filled proves nothing about
/// whether the empty ones are distinguishable, and that is the whole question.
List<DayTotal> _sparseMonth({int month = 10, int year = 2026}) {
  final daysInMonth = DateTime(year, month + 1, 0).day;
  return [
    for (var day = 1; day <= daysInMonth; day++)
      DayTotal(
        date: DateTime(year, month, day),
        income: day == 1 ? 4000 : 0,
        // Three busy days, a few small ones, the rest nothing.
        expenses: switch (day) {
          3 => 4200,
          11 => 1500,
          19 => 900,
          5 => 150,
          24 => 60,
          _ => 0,
        },
      ),
  ];
}

Widget _host(
  SpendingHeatmap child, {
  Brightness brightness = Brightness.light,
}) {
  return MaterialApp(
    theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
    home: Scaffold(
      body: ListView(padding: AppSpacing.screenPadding, children: [child]),
    ),
  );
}

void main() {
  group('the heatmap', () {
    testWidgets('draws a cell for every day of the month', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      await tester.pumpWidget(
        _host(SpendingHeatmap(days: _sparseMonth(), currencySymbol: 'Rs. ')),
      );
      await tester.pump();

      // Counted by key, not by tooltip message: a day with no spending has a
      // different message, so counting messages counts only the busy days.
      for (var day = 1; day <= 31; day++) {
        expect(
          find.byKey(ValueKey('heat-cell-$day')),
          findsOneWidget,
          reason: 'day $day has no cell',
        );
      }
    });

    testWidgets('says which day was heaviest', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      await tester.pumpWidget(
        _host(SpendingHeatmap(days: _sparseMonth(), currencySymbol: 'Rs. ')),
      );
      await tester.pump();

      // A grid cannot show this without a caption, and it is the single most
      // useful fact in it.
      expect(find.textContaining('Heaviest day Rs. 4,200'), findsOneWidget);
      expect(find.textContaining('total'), findsOneWidget);
    });

    testWidgets(
      'a month with no spending says so rather than shading nothing',
      (tester) async {
        usePhoneLayout(tester, TestViewports.phonePortrait);

        await tester.pumpWidget(
          _host(
            SpendingHeatmap(
              days: [
                for (var day = 1; day <= 28; day++)
                  DayTotal(
                    date: DateTime(2026, 10, day),
                    income: 0,
                    expenses: 0,
                  ),
              ],
              currencySymbol: 'Rs. ',
            ),
          ),
        );
        await tester.pump();

        expect(find.text('Nothing spent this month'), findsOneWidget);
      },
    );

    testWidgets('an empty month renders nothing at all', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      await tester.pumpWidget(
        _host(const SpendingHeatmap(days: [], currencySymbol: 'Rs. ')),
      );
      await tester.pump();

      // Shrinks to nothing rather than drawing an empty month.
      expect(find.textContaining('Heaviest day'), findsNothing);
      expect(find.byKey(const ValueKey('heat-cell-1')), findsNothing);
    });

    testWidgets('a filtered day is outlined on its cell', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      await tester.pumpWidget(
        _host(
          SpendingHeatmap(
            days: _sparseMonth(),
            currencySymbol: 'Rs. ',
            highlightedDate: DateTime(2026, 10, 11),
          ),
        ),
      );
      await tester.pump();

      // The tooltip for that day exists, and the outline is on the cell the
      // grid put it in.
      expect(find.byTooltip(RegExp(r'^Day 11 ·')), findsOneWidget);
    });
  });

  group('every viewport', () {
    for (final size in [
      TestViewports.phonePortrait,
      TestViewports.phoneSmall,
      TestViewports.phoneLandscape,
      TestViewports.oversized,
    ]) {
      testWidgets('fits at ${size.width.toInt()}x${size.height.toInt()}', (
        tester,
      ) async {
        usePhoneLayout(tester, size);

        await tester.pumpWidget(
          _host(SpendingHeatmap(days: _sparseMonth(), currencySymbol: 'Rs. ')),
        );
        await tester.pump();

        expect(find.byKey(const ValueKey('heat-cell-15')), findsOneWidget);
      });
    }
  });

  group('in both brightnesses', () {
    testWidgets('the shading differs, so the grid still reads on dark', (
      tester,
    ) async {
      // Colours come from the theme's own container and primary roles rather
      // than from literals, so a palette added later cannot leave this grid
      // invisible without a test noticing.
      final schemeLight = AppTheme.light().colorScheme;
      final schemeDark = AppTheme.dark().colorScheme;

      expect(
        schemeLight.primaryContainer,
        isNot(schemeDark.primaryContainer),
        reason: 'if the two matched, one of them would be unreadable',
      );

      await tester.pumpWidget(
        _host(
          SpendingHeatmap(days: _sparseMonth(), currencySymbol: 'Rs. '),
          brightness: Brightness.dark,
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('heat-cell-15')), findsOneWidget);
    });

    testWidgets('a SPENT cell is readable and distinct from an empty one', (
      tester,
    ) async {
      // Not every cell needs 3:1. An EMPTY cell is meant to recede — that is
      // what "nothing here" looks like — so it is measured against the page,
      // not held to the text-contrast bar. What has to hold is that a spent
      // cell is readable, and that spent and empty are never confusable.
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final scheme = brightness == Brightness.dark
            ? AppTheme.dark().colorScheme
            : AppTheme.light().colorScheme;
        final page = brightness == Brightness.dark
            ? AppColors.darkBackground
            : AppColors.surfaceLow;
        final empty = scheme.surfaceContainerHighest;

        expect(
          _contrast(scheme.primary, page),
          greaterThanOrEqualTo(3.0),
          reason: 'the heaviest day must be readable on a $brightness page',
        );
        // The faint end of the ramp: primary at its lowest alpha, composited
        // over the page. This was primaryContainer, which is the same warm
        // parchment as the light page and measured 1.27:1 — a lightly-spent day
        // was invisible in light mode.
        final faintest = _over(scheme.primary.withValues(alpha: 0.22), page);
        expect(
          _contrast(faintest, page),
          greaterThanOrEqualTo(1.4),
          reason:
              'a lightly-spent day must still be visible on a $brightness page',
        );
        expect(
          _contrast(scheme.primary, empty),
          greaterThanOrEqualTo(1.5),
          reason:
              'the busiest and the emptiest day have to be tellable apart on a '
              '$brightness page',
        );
      }
    });
  });

  group('the geometry', () {
    testWidgets('cells are square and the same size', (tester) async {
      usePhoneLayout(tester, TestViewports.phoneSmall);

      await tester.pumpWidget(
        _host(SpendingHeatmap(days: _sparseMonth(), currencySymbol: 'Rs. ')),
      );
      await tester.pump();

      // Every real cell is the same square; a ragged grid reads as a mistake.
      final first = tester.getRect(find.byKey(const ValueKey('heat-cell-3')));
      expect(first.width, moreOrLessEquals(first.height, epsilon: 0.01));

      final second = tester.getRect(find.byKey(const ValueKey('heat-cell-4')));
      expect(second.width, moreOrLessEquals(first.width, epsilon: 0.01));
    });

    testWidgets('the grid uses the width it is given', (tester) async {
      usePhoneLayout(tester, TestViewports.phoneSmall);

      await tester.pumpWidget(
        _host(SpendingHeatmap(days: _sparseMonth(), currencySymbol: 'Rs. ')),
      );
      await tester.pump();

      // Capped on a wide window, and shrunk rather than overflowing a very
      // narrow one. The cap means the grid never grows past a comfortable cell,
      // so an unusually narrow measure is the only case that scales down.
      expect(SpendingHeatmap.cellFor(2000, 5), SpendingHeatmap.maxCell);
      expect(SpendingHeatmap.cellFor(90, 5), lessThan(SpendingHeatmap.maxCell));
      for (final width in [40.0, 60.0, 90.0, 360.0, 412.0, 1400.0]) {
        expect(
          SpendingHeatmap.cellFor(width, 5),
          greaterThan(0),
          reason: 'a cell size of zero at $width would collapse the grid',
        );
      }
    });
  });
}

/// [over] laid on [background], the way the framework composites it.
Color _over(Color over, Color background) {
  return Color.alphaBlend(over, background);
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
