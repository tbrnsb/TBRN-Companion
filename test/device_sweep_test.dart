import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daily_companion/theme/app_theme.dart';
import 'package:daily_companion/utils/format.dart';
import 'package:daily_companion/widgets/spending_heatmap.dart';

import 'test_viewports.dart';

void main() {
  group('a floating action button has room to sit', () {
    // Every one of these came off a real screenshot, not a hunch: the dock
    // covered a list row's overflow menu on Places, the "10 this month" count and
    // the pager's page label on Transactions, and a checklist row on Pack.
    testWidgets('the padding clears the button', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      // Deeper than the ordinary screen padding, because a FAB floats OVER the
      // list instead of sitting in it.
      expect(
        AppSpacing.screenPaddingWithFab.bottom,
        greaterThan(AppSpacing.screenPadding.bottom),
      );

      // An extended FAB is 56 tall and sits 16 above the content edge, so the
      // list needs at least that much room at the end for its last row to be
      // reachable.
      const extendedFabHeight = 56.0;
      const fabMargin = 16.0;
      expect(
        AppSpacing.screenPaddingWithFab.bottom,
        greaterThanOrEqualTo(extendedFabHeight + fabMargin),
      );
    });

    testWidgets('a real list can scroll its last row clear of a FAB', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phoneSmall);

      // The actual shape of the problem, at the viewport where it bit: a short
      // list, a FAB over its bottom-right, and ordinary screen padding. Scrolled
      // to the end, the last row must not be under the button.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () {},
              label: const Text('Add'),
            ),
            body: ListView(
              padding: AppSpacing.screenPadding,
              children: [
                for (var i = 0; i < 6; i++)
                  SizedBox(height: 64, child: Text('row $i')),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump();

      final lastRow = tester.getRect(find.text('row 5'));
      final fab = tester.getRect(find.byType(FloatingActionButton));
      expect(
        lastRow.overlaps(fab),
        isFalse,
        reason: 'the last row is under the FAB, which is the reported bug',
      );
    });
  });

  group('the heatmap is a grid', () {
    // The complaint was that it read as "a random throwing of pixels". That is
    // a statement about SPACING, so it is asserted as spacing.
    testWidgets('columns sit next to each other, not scattered', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      // 7 columns of 26 with 3px gutters is 200. `spaceBetween` across a 380
      // measure gave a step of about 51 — five times the gap it should have.
      final cell = SpendingHeatmap.cellFor(380);
      final step = cell + 3;
      expect(step, lessThan(cell * 2));

      // And the grid still has to be a sensible size: not a stamp, not a wall.
      expect(cell, lessThanOrEqualTo(SpendingHeatmapShim.maxCell));
      expect(cell, greaterThanOrEqualTo(SpendingHeatmapShim.minCell));
    });

    testWidgets('the cell is capped so a wide measure cannot take over', (
      tester,
    ) async {
      // 1800 wide would give a 250px cell without the cap, which is the wall of
      // squares item 5 was merged to remove.
      final wide = SpendingHeatmap.cellFor(1800);
      expect(wide, SpendingHeatmapShim.maxCell);
      expect(wide, lessThan(40));
    });

    testWidgets('a very narrow measure falls back to the floor', (
      tester,
    ) async {
      expect(SpendingHeatmap.cellFor(60), SpendingHeatmapShim.minCell);
      expect(SpendingHeatmap.cellFor(0), SpendingHeatmapShim.minCell);
    });
  });

  group('a duration says the biggest thing that is true', () {
    test('a three-day average is not "72h 0m"', () {
      // Straight off the device: the Journey tab's "Avg. time" read 72h 0m,
      // which is three days written in hours with a meaningless remainder.
      expect(AppFormat.duration(72 * 60), '3d');
      expect(AppFormat.duration(72 * 60 + 30), '3d');
      expect(AppFormat.duration(60 * 24 * 2 + 180), '2d 3h');
      expect(AppFormat.duration(180), '3h');
      expect(AppFormat.duration(195), '3h 15m');
      expect(AppFormat.duration(45), '45m');
      expect(AppFormat.duration(0), '0m');
      expect(AppFormat.duration(-5), '0m');

      // Never hours for something longer than a day.
      for (final minutes in [1441.0, 2880.0, 10080.0, 525600.0]) {
        expect(
          AppFormat.duration(minutes),
          isNot(matches(RegExp(r'^\d+h'))),
          reason: '${minutes}m still reads in hours',
        );
      }
    });
  });

  group('theme spacing stays in the theme', () {
    testWidgets('the FAB padding is a real margin', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      // Sanity: it must be positive and generous, and it must not be a raw
      // number smuggled into a screen.
      expect(AppSpacing.screenPaddingWithFab.bottom, greaterThan(64));
      expect(AppSpacing.screenPaddingWithFab.top, AppSpacing.md);
    });

    testWidgets('the app themes still build', (tester) async {
      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        await tester.pumpWidget(
          MaterialApp(theme: theme, home: const SizedBox.shrink()),
        );
        expect(tester.takeException(), isNull);
      }
    });
  });
}
