import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daily_companion/theme/app_theme.dart';
import 'package:daily_companion/widgets/widgets.dart';

import 'test_viewports.dart';

Future<void> settleUi(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// A month of days, one of them busy, so the heatmap is not the empty-cell case.
List<DayTotal> _month({int year = 2026, int month = 8}) {
  final last = DateTime(year, month + 1, 0).day;
  return [
    for (var d = 1; d <= last; d++)
      DayTotal(
        date: DateTime(year, month, d),
        income: 0,
        expenses: d == 4 ? 2400 : 0,
      ),
  ];
}

/// The four real pages, at their real intrinsic sizes.
List<Widget> _realPages() => [
  SpendingHeatmap(days: _month(), currencySymbol: 'Rs. '),
  DailyTotalsChart(days: _month(), currencySymbol: 'Rs. '),
  CumulativeBalanceChart(days: _month(), currencySymbol: 'Rs. '),
  WeeklyTotalsChart(days: _month(), currencySymbol: 'Rs. '),
];

void main() {
  group('the pager box is big enough for its pages', () {
    // The guard that replaces the measurement machinery.
    //
    // [ChartPager.pageHeight] is a constant, so the only thing stopping a chart
    // from growing into it and being CLIPPED is this test. A constant that is
    // wrong is a bug; a constant with a test that notices is a number.
    for (final viewport in [
      TestViewports.phonePortrait,
      TestViewports.phoneSmall,
    ]) {
      testWidgets('no page overflows at $viewport', (tester) async {
        usePhoneLayout(tester, viewport);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: ChartPager(
                  pages: _realPages(),
                  labels: const ['Heatmap', 'Daily', 'Balance', 'Weekly'],
                ),
              ),
            ),
          ),
        );
        await settleUi(tester);

        // Every page visited, because a page that only renders once you swipe to
        // it is exactly the one that gets clipped without anybody noticing.
        for (var page = 0; page < 4; page++) {
          await tester.tap(find.byKey(ValueKey('chart-dot-$page')));
          await settleUi(tester);
          expect(
            tester.takeException(),
            isNull,
            reason: 'chart page ${page + 1} overflows at $viewport',
          );
        }
      });
    }

    testWidgets('the four real pages fit the box side by side', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ChartPager(
                pages: _realPages(),
                labels: const ['Heatmap', 'Daily', 'Balance', 'Weekly'],
              ),
            ),
          ),
        ),
      );
      await settleUi(tester);

      expect(tester.takeException(), isNull);
    });

    testWidgets('the box is not a hole again', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      // 640 reserved for charts needing ~270 is the bug this replaced, and it is
      // one number away from coming back.
      expect(ChartPager.pageHeight, lessThan(320));
    });
  });
}
