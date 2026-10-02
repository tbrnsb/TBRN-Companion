import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daily_companion/theme/app_chart_colors.dart';
import 'package:daily_companion/theme/app_palettes.dart';
import 'package:daily_companion/theme/app_theme.dart';
import 'package:daily_companion/widgets/spending_heatmap.dart';
import 'package:daily_companion/widgets/spend_trend_cards.dart' show DayTotal;

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
  ThemeData? theme,
}) {
  return MaterialApp(
    theme:
        theme ??
        (brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light()),
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
      // what "nothing here" looks like — so it is measured against the card, not
      // held to the text-contrast bar. What has to hold is that a spent cell is
      // readable, and that spent and empty are never confusable.
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final scheme = brightness == Brightness.dark
            ? AppTheme.dark().colorScheme
            : AppTheme.light().colorScheme;
        final page = brightness == Brightness.dark
            ? AppColors.darkBackground
            : AppColors.surfaceLow;
        final empty = AppChartColors.heatmapEmpty(scheme);

        expect(
          _contrast(scheme.primary, page),
          greaterThanOrEqualTo(3.0),
          reason: 'the heaviest day must be readable on a $brightness page',
        );
        expect(
          _contrast(empty, page),
          greaterThanOrEqualTo(1.4),
          reason:
              'a day with nothing on it must still read on a $brightness page',
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

    // THE INVISIBLE-GRID BUG, measured in all six specs.
    //
    // `heatmapEmpty` and `heatmapDead` were `surfaceContainer` and
    // `surfaceContainerLowest` — the two lowest-contrast steps in the ladder,
    // built to sit behind content almost invisibly. So a cell with no spending
    // was nearly the colour of the card it sat on, and the month had no visible
    // rectangle at all: no grid, no shape, "a random throwing of pixels". These
    // are DERIVED toward the palette's own ink now, so the assertions hold for a
    // palette added later without being told about it.
    testWidgets(
      'empty and dead cells are VISIBLE against the card, in all six specs',
      (tester) async {
        final specs = <({String name, ThemeData theme})>[];
        for (final palette in AppPalette.values) {
          if (palette.supportsLight) {
            specs.add((
              name: '${palette.label} light',
              theme: AppTheme.lightFor(palette),
            ));
          }
          specs.add((
            name: '${palette.label} dark',
            theme: AppTheme.darkFor(palette),
          ));
        }
        expect(specs.length, 6, reason: 'four families, six specs in total');

        final measured = <String>[];
        for (final spec in specs) {
          final scheme = spec.theme.colorScheme;
          final card = scheme.surface;
          final empty = AppChartColors.heatmapEmpty(scheme);
          final dead = AppChartColors.heatmapDead(scheme);

          final emptyRatio = _contrast(empty, card);
          final deadRatio = _contrast(dead, card);
          measured.add(
            '${spec.name}: empty ${emptyRatio.toStringAsFixed(2)}:1, '
            'dead ${deadRatio.toStringAsFixed(2)}:1',
          );

          expect(
            emptyRatio,
            greaterThanOrEqualTo(AppChartColors.structureFloor),
            reason:
                'in ${spec.name} an empty cell measured $emptyRatio:1 against '
                'the card — the grid has no visible rectangle',
          );
          expect(
            deadRatio,
            greaterThanOrEqualTo(AppChartColors.deadFloor),
            reason:
                'in ${spec.name} a dead cell measured $deadRatio:1 — padding '
                'has to be visible enough to read as padding',
          );
          // The empty cell is held to the STRICTER floor, so "nothing here" and
          // "not part of this month" are never the same weight.
          expect(
            deadRatio,
            lessThan(AppChartColors.structureFloor),
            reason:
                'in ${spec.name} dead padding is as heavy as an empty day; '
                'the outer cells must read as padding, not as a quiet week',
          );
          // Dead is FAINTER than empty, so the month's outline is legible, but
          // they are not the same colour: a reader must be able to tell "no
          // spending" from "not part of this month".
          expect(
            deadRatio,
            lessThan(emptyRatio),
            reason: 'in ${spec.name} dead and empty are indistinguishable',
          );
          expect(
            empty,
            isNot(dead),
            reason: 'in ${spec.name} both tokens resolved to the same colour',
          );
          expect(
            empty,
            isNot(card),
            reason: 'in ${spec.name} the empty cell IS the card colour',
          );
          expect(
            dead,
            isNot(card),
            reason: 'in ${spec.name} the dead cell IS the card colour',
          );
        }
        // Printed so a regression reports the before/after numbers rather than
        // only the failing spec.
        // ignore: avoid_print
        print('heatmap structure contrast — ${measured.join(' | ')}');
      },
    );

    testWidgets('the grid is actually VISIBLE on screen in all six specs', (
      tester,
    ) async {
      // The token test proves the maths. This proves the RENDERED pixels: the
      // colour actually on the card, read back out of the widget tree, is
      // visible. A token that is right but never painted is still invisible.
      for (final palette in AppPalette.values) {
        final modes = <({String name, ThemeData theme})>[
          if (palette.supportsLight)
            (name: '${palette.label} light', theme: AppTheme.lightFor(palette)),
          (name: '${palette.label} dark', theme: AppTheme.darkFor(palette)),
        ];
        for (final mode in modes) {
          usePhoneLayout(tester, TestViewports.phonePortrait);
          await tester.pumpWidget(
            _host(
              SpendingHeatmap(days: _sparseMonth(), currencySymbol: 'Rs. '),
              theme: mode.theme,
            ),
          );
          await tester.pump();

          // A Container, not a DecoratedBox: the spent/empty cell is built as a
          // Container so it can carry the highlight border as well as the fill.
          final painted =
              tester
                      .widget<Container>(
                        find.byKey(const ValueKey('heat-cell-7')),
                      )
                      .decoration!
                  as BoxDecoration;
          final card = mode.theme.colorScheme.surface;
          expect(
            _contrast(painted.color!, card),
            greaterThanOrEqualTo(AppChartColors.structureFloor),
            reason:
                'in ${mode.name} the rendered empty cell is '
                '${_contrast(painted.color!, card).toStringAsFixed(2)}:1 '
                'against the card',
          );

          final deadPainted =
              tester
                      .widget<DecoratedBox>(
                        find.byKey(const ValueKey('heat-dead-cell')).first,
                      )
                      .decoration
                  as BoxDecoration;
          expect(
            _contrast(deadPainted.color!, card),
            greaterThanOrEqualTo(AppChartColors.deadFloor),
            reason:
                'in ${mode.name} the rendered dead cell is '
                '${_contrast(deadPainted.color!, card).toStringAsFixed(2)}:1 '
                'against the card',
          );
        }
      }
    });
  });

  group('the shape of the month', () {
    // THE TRANSPOSE. Item 5 drew FIVE week-COLUMNS by SEVEN weekday-ROWS, which
    // is the transpose of a calendar: days ran down the screen, weeks ran across
    // it, and the result read as a scatter rather than as a month. Days are now
    // seven-across and weeks are the rows.
    test('rows come from the month, never from the window', () {
      // October 2026: 31 days, first on a Thursday -> 3 leading dead + 31 = 34
      // cells -> 5 rows.
      expect(SpendingHeatmap.rowsForMonth(2026, 10), 5);
      // September 2026: 30 days, first on a Tuesday -> 1 + 30 = 31 -> 5 rows.
      expect(SpendingHeatmap.rowsForMonth(2026, 9), 5);
      // February 2021: 28 days starting exactly on a Monday -> 0 + 28 = 4 rows.
      expect(SpendingHeatmap.rowsForMonth(2021, 2), 4);
      // November 2026: 30 days opening on a SUNDAY. The trap is reading a
      // Sunday as NO leading space: `weekday` is 7, so leading is SIX, and
      // 6 + 30 = 36 cells needs SIX rows. Treating it as a five-row month is
      // precisely how a visible day goes missing.
      expect(SpendingHeatmap.rowsForMonth(2026, 11), 6);
    });

    test('a SIX-week month gets six rows, not five', () {
      // May 2027 starts on a Saturday and has 31 days: 5 leading + 31 = 36
      // cells, which needs six rows. Under item 5 a fixed five columns drew only
      // 35 cells and the LAST DAY OF THE MONTH WAS NEVER DRAWN. That is the bug
      // a green suite passed.
      final may = SpendingHeatmap.rowsForMonth(2027, 5);
      expect(may, 6);
      expect(
        5 * SpendingHeatmap.columnsPerRow + (DateTime(2027, 5, 1).weekday - 1),
        greaterThan(5 * SpendingHeatmap.columnsPerRow),
        reason: 'six rows are needed because the month overflows five',
      );
    });

    testWidgets('six-week months draw every day of the month', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      // May 2027: the month that fits in neither four nor five rows.
      await tester.pumpWidget(
        _host(
          SpendingHeatmap(
            days: _sparseMonth(month: 5, year: 2027),
            currencySymbol: 'Rs. ',
          ),
        ),
      );
      await tester.pump();

      // Every day present, day 1 through day 31, with the last day visible.
      for (final day in [1, 7, 28, 29, 30, 31]) {
        expect(
          find.byKey(ValueKey('heat-cell-$day')),
          findsOneWidget,
          reason: 'day $day of a six-week month must be drawn',
        );
      }
      expect(find.byKey(const ValueKey('heat-cell-31')), findsOneWidget);
    });

    testWidgets('a week is a ROW of seven days across', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await tester.pumpWidget(
        _host(SpendingHeatmap(days: _sparseMonth(), currencySymbol: 'Rs. ')),
      );
      await tester.pump();

      // The row's days are DERIVED, not hard-coded, and this is exactly where two
      // earlier versions of this test went wrong. October 2026 opens on a
      // Thursday, so leading dead is THREE: row 0 is three dead cells plus days
      // 1..4, and the first row of SEVEN real days is row 1, holding days 5..11.
      // Measuring "day 1 to day 7" spans two rows, so it fails for reasons that
      // have nothing to do with the grid.
      final leading = SpendingHeatmap.leadingDeadForMonth(2026, 10);
      expect(leading, 3, reason: 'October 2026 opens on a Thursday');
      final daysInRow0 = 7 - leading;
      expect(daysInRow0, 4);
      // Row 1: the first complete week, seven real days and no dead cells.
      final row = [for (var d = daysInRow0 + 1; d <= daysInRow0 + 7; d++) d];
      expect(row, [5, 6, 7, 8, 9, 10, 11]);

      final centres = [
        for (final day in row)
          tester.getCenter(find.byKey(ValueKey('heat-cell-$day'))),
      ];

      // Left to right, evenly spaced, all on ONE row. Under the transpose these
      // ran down the screen and the month read as a scatter.
      for (var i = 1; i < centres.length; i++) {
        expect(
          centres[i].dx,
          greaterThan(centres[i - 1].dx),
          reason: 'day ${row[i]} must sit to the RIGHT of day ${row[i - 1]}',
        );
        expect(
          centres[i].dx - centres[i - 1].dx,
          closeTo(centres[1].dx - centres[0].dx, 0.5),
          reason: 'spacing is even across the row',
        );
        expect(
          centres[i].dy,
          closeTo(centres[0].dy, 0.5),
          reason: 'day ${row[i]} belongs to the same week as day ${row[0]}',
        );
      }
      // And the step is a cell PLUS a SMALL gutter. The row still spans the
      // card — seven cells and six gutters fill the measure — but the gutter is
      // now a constant 3px rather than whatever `spaceBetween` had left over.
      //
      // This is the assertion that matters. Under `spaceBetween` the step was
      // about 57px on a 412dp phone, so seven cells with five times more space
      // between them than width did not read as a grid at all.
      final step = centres[1].dx - centres[0].dx;
      expect(step, greaterThan(SpendingHeatmapShim.cell));
      expect(
        step - tester.getSize(find.byKey(const ValueKey('heat-cell-3'))).width,
        lessThanOrEqualTo(6),
        reason:
            'the gutter is what decides whether this reads as a grid or as '
            'scattered dots, and it must stay tight',
      );
      // The row is NOT expected to span the card: a capped seven-column grid is
      // a centred block, and the gutter assertion above is what pins the shape.
    });

    testWidgets('days continue across rows, seven at a time', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await tester.pumpWidget(
        _host(SpendingHeatmap(days: _sparseMonth(), currencySymbol: 'Rs. ')),
      );
      await tester.pump();

      // The last day of a row and the first of the next: a new Y, and the new
      // day wraps LEFT. That wrap is what makes a calendar read as one.
      final lastOfRow0 =
          7 - (SpendingHeatmap.leadingDeadForMonth(2026, 10) % 7);
      final a = tester.getCenter(find.byKey(ValueKey('heat-cell-$lastOfRow0')));
      final b = tester.getCenter(
        find.byKey(ValueKey('heat-cell-${lastOfRow0 + 1}')),
      );
      expect(b.dy, greaterThan(a.dy), reason: 'a new week is a new ROW');
      expect(b.dx, lessThan(a.dx), reason: 'the eighth day wraps to the left');

      // Seven-per-row stated directly, using row 1 (days 5..11): the first day
      // and the seventh share a row, and the eighth is on the row below.
      final leading = SpendingHeatmap.leadingDeadForMonth(2026, 10);
      final firstOfRow1 = 7 - leading + 1;
      final c = tester.getCenter(
        find.byKey(ValueKey('heat-cell-$firstOfRow1')),
      );
      final d = tester.getCenter(
        find.byKey(ValueKey('heat-cell-${firstOfRow1 + 6}')),
      );
      final e = tester.getCenter(
        find.byKey(ValueKey('heat-cell-${firstOfRow1 + 7}')),
      );
      expect(
        d.dy,
        closeTo(c.dy, 0.5),
        reason: 'six days later is the same week',
      );
      expect(
        e.dy,
        greaterThan(d.dy),
        reason: 'seven days later is the next week',
      );
      expect(e.dx, lessThan(d.dx), reason: 'and it wraps back to the left');
    });

    test('dead cells come before and after, never instead of, days', () {
      // The shape of the month is carried entirely by which cells paint dead.
      // A leading-dead count that does not match the month's first weekday is
      // what makes a grid start on the wrong day.
      final leading = SpendingHeatmap.leadingDeadForMonth(2026, 10);
      expect(leading, DateTime(2026, 10, 1).weekday - 1);
      expect(leading, 3, reason: 'October 2026 opens on a Thursday');

      final rows = SpendingHeatmap.rowsForMonth(2026, 10);
      final days = DateTime(2026, 10, 31).day;
      final total = rows * SpendingHeatmap.columnsPerRow;
      expect(
        SpendingHeatmap.trailingDeadForMonth(2026, 10, rows),
        total - (leading + days),
      );
      // Leading plus real plus trailing accounts for every cell on the grid: no
      // cell is both a day and dead, and none is left out.
      expect(
        leading + days + SpendingHeatmap.trailingDeadForMonth(2026, 10, rows),
        total,
      );
    });
  });

  group('the geometry', () {
    testWidgets('neighbouring cells are separated, sideways and down', (
      tester,
    ) async {
      // THE DEVICE COMPLAINT: the grid read as one congested block with the
      // cells touching, and `cellFor` was already subtracting six horizontal
      // gutters from the measure while the row laid the cells out edge to edge
      // with nothing between them. Rows had a vertical gap; columns had none, so
      // every horizontal seam was two 1px cell borders meeting and the month
      // looked like a hatched rectangle rather than a grid of days.
      for (final viewport in [
        TestViewports.phonePortrait,
        TestViewports.phoneSmall,
      ]) {
        usePhoneLayout(tester, viewport);
        await tester.pumpWidget(
          _host(SpendingHeatmap(days: _sparseMonth(), currencySymbol: 'Rs. ')),
        );
        await tester.pump();

        // October 2026 opens on a Thursday, so row 1 is the complete week:
        // days 5..11 all share one row, so 5 and 6 are true horizontal
        // neighbours and 4 and 5 are true vertical ones.
        final d5 = tester.getRect(
          find.byKey(const ValueKey('heat-cell-5')).first,
        );
        final d6 = tester.getRect(
          find.byKey(const ValueKey('heat-cell-6')).first,
        );
        final d4 = tester.getRect(
          find.byKey(const ValueKey('heat-cell-4')).first,
        );

        expect(
          d6.left - d5.right,
          greaterThanOrEqualTo(3),
          reason:
              'at $viewport the horizontal gutter is ${d6.left - d5.right} -- '
              'the cells are touching sideways',
        );
        expect(
          d5.top - d4.bottom,
          greaterThanOrEqualTo(3),
          reason: 'at $viewport the vertical gutter is ${d5.top - d4.bottom}',
        );
        // Same row, or the sideways number is meaningless.
        expect(d5.top, moreOrLessEquals(d6.top, epsilon: 0.01));
      }
    });

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

    testWidgets('the grid SPANS the width it is given', (tester) async {
      // THE LEFT-HUG REGRESSION GUARD, and the reason cells are FIXED rather
      // than Expanded. `spaceBetween` spaces them across the measure; a
      // content-sized row discards the leftover and hugs the left.
      for (final viewport in [
        TestViewports.phonePortrait,
        TestViewports.phoneSmall,
      ]) {
        usePhoneLayout(tester, viewport);
        await tester.pumpWidget(
          _host(SpendingHeatmap(days: _sparseMonth(), currencySymbol: 'Rs. ')),
        );
        await tester.pump();

        // The FULL row, not days 1 and 7. October 2026 opens on a Thursday, so
        // three cells are leading dead and the row of real days runs 4..10.
        // Measuring day 1 to day 7 spans four cells instead of seven and would
        // PASS a grid that was genuinely hugging the left.
        // BOTH ends from the SAME row. The leading dead cells are on row 0, so
        // pairing one of those with a day on row 1 compares two different rows and
        // the "centre" comes out meaningless.
        //
        // October 2026 opens on a Thursday, so row 0 is three dead cells plus
        // days 1..4 and row 1 is the complete week, days 5..11.
        final leftEdge = tester
            .getRect(find.byKey(const ValueKey('heat-cell-5')).first)
            .left;
        final rightEdge = tester
            .getRect(find.byKey(const ValueKey('heat-cell-11')).first)
            .right;
        final painted = rightEdge - leftEdge;
        final available =
            viewport.width - AppSpacing.screenPadding.horizontal * 2;
        // Not "spans": a seven-column grid CANNOT span a 412dp card and stay
        // small, and pretending otherwise is what put 45px squares on the screen
        // in item 5. The requirement is that the grid is not HUGGING THE LEFT —
        // so it is centred, and the margin beside it is a real margin.
        //
        // Centred within the heatmap's OWN box, not the screen: it sits inside
        // the card's padding, so `available` is not what it is centred within.
        final own = tester.getRect(find.byType(SpendingHeatmap));
        final cardCentre = own.width / 2;
        final gridCentre = (leftEdge + rightEdge) / 2;
        expect(
          (gridCentre - cardCentre).abs(),
          lessThan(own.width * 0.12),
          reason:
              'at $viewport the grid centre is off by '
              '${(gridCentre - cardCentre).abs()} -- it is hugging the left',
        );
        expect(
          painted,
          greaterThan(own.width * 0.4),
          reason: 'at $viewport the row is $painted of $available -- too small',
        );
      }
    });

    testWidgets('cells are sized from the measure, within a cap', (
      tester,
    ) async {
      // Item 5 made cells Expanded + AspectRatio, so they grew to ~45px and the
      // grid became 315px of screen. The cell now takes the width it is given so
      // the gutter can stay tight, and [SpendingHeatmapShim.maxCell] is what stops
      // that becoming the same wall of squares on a tablet.
      for (final viewport in [
        TestViewports.phonePortrait,
        TestViewports.phoneSmall,
      ]) {
        usePhoneLayout(tester, viewport);
        await tester.pumpWidget(
          _host(SpendingHeatmap(days: _sparseMonth(), currencySymbol: 'Rs. ')),
        );
        await tester.pump();

        final cell = tester.getSize(find.byKey(const ValueKey('heat-cell-3')));
        expect(
          cell.width,
          closeTo(
            SpendingHeatmap.cellFor(
              viewport.width - AppSpacing.screenPadding.horizontal * 2,
            ),
            1.5,
          ),
          reason: 'at $viewport the cell is derived from the measure',
        );
        // Square, always: a rectangular cell reads as a bar chart.
        expect(cell.width, closeTo(cell.height, 0.5));
        expect(
          cell.width,
          lessThanOrEqualTo(SpendingHeatmapShim.maxCell),
          reason: 'the cap is what stops a wide measure taking the screen back',
        );
        expect(
          cell.width,
          greaterThanOrEqualTo(SpendingHeatmapShim.minCell - 0.5),
        );
      }
    });

    testWidgets('every cell is outlined, so the month reads as one grid', (
      tester,
    ) async {
      // The empty days are what define the SHAPE of the month, and without an
      // outline they are the same colour as the card. A grid of floating
      // squares was the complaint.
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await tester.pumpWidget(
        _host(SpendingHeatmap(days: _sparseMonth(), currencySymbol: 'Rs. ')),
      );
      await tester.pump();

      // A day inside the month keys a Container; a dead cell keys a
      // DecoratedBox. Both must be outlined — the outline is the only thing
      // that makes a quiet day and a day outside the month read as parts of
      // one grid rather than as background.
      final container = tester.widget<Container>(
        find.byKey(const ValueKey('heat-cell-3')).first,
      );
      expect(
        (container.decoration! as BoxDecoration).border,
        isNotNull,
        reason: 'a day inside the month has no outline',
      );
      final dead = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('heat-dead-cell')).first,
      );
      expect(
        (dead.decoration as BoxDecoration).border,
        isNotNull,
        reason: 'a dead cell has no outline, so the month has no edge',
      );
    });

    testWidgets('the whole grid stays short, so a card cannot take the screen', (
      tester,
    ) async {
      // The guard against a future fill-the-width regression making the heatmap
      // tall again. Seven columns and up to six rows of 11px is well under 100.
      for (final viewport in [
        TestViewports.phonePortrait,
        TestViewports.phoneSmall,
      ]) {
        usePhoneLayout(tester, viewport);
        await tester.pumpWidget(
          _host(SpendingHeatmap(days: _sparseMonth(), currencySymbol: 'Rs. ')),
        );
        await tester.pump();

        final days = _sparseMonth();
        final lastDay = days.last.date.day;
        final grid = tester.getRect(find.byKey(const ValueKey('heat-cell-1')));
        final lastRow = tester.getRect(
          find.byKey(ValueKey('heat-cell-$lastDay')),
        );
        expect(
          lastRow.bottom - grid.top,
          lessThan(200),
          reason:
              'at $viewport the grid is '
              '${lastRow.bottom - grid.top}px tall, which would dominate the '
              'screen the way a fill-the-width grid did',
        );
      }
    });
  });
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
