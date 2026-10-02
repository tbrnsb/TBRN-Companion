import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daily_companion/theme/app_theme.dart';
import 'package:daily_companion/widgets/chart_pager.dart';
import 'package:daily_companion/widgets/spend_trend_cards.dart';
import 'package:daily_companion/widgets/spending_heatmap.dart';

import 'test_viewports.dart';

Future<void> settleUi(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

List<DayTotal> _busyMonth() => [
  for (var d = 1; d <= 28; d++)
    DayTotal(
      date: DateTime(2026, 8, d),
      income: d == 1 ? 5000 : 0,
      expenses: d % 3 == 0 ? 300 : 0,
    ),
];

/// The titles the user says the plots run into.
const _titles = {1: 'In and out, by day', 3: 'By week'};

void main() {
  group('a chart plot never runs into the text above it', () {
    // THE DEVICE REPORT: "the 2nd and 4th charts are still overlapping the
    // above text like 'In and out, by day'". Those are the two pages with the
    // most prose above the plot, which is the tell: a fixed-height plot does not
    // care how tall the text under it becomes, so a larger system font, or a
    // title that wraps, pushes the page past the pager's box and the plot is
    // painted over the heading.
    for (final page in [1, 3]) {
      for (final scale in [1.0, 1.3, 1.5, 2.0]) {
        for (final viewport in [
          TestViewports.phonePortrait,
          TestViewports.phoneSmall,
        ]) {
          testWidgets('page ${page + 1} at text scale $scale on $viewport', (
            tester,
          ) async {
            usePhoneLayout(tester, viewport);

            await tester.pumpWidget(
              MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: MaterialApp(
                  theme: AppTheme.dark(),
                  home: Scaffold(
                    body: SingleChildScrollView(
                      child: ChartPager(
                        labels: const ['Heatmap', 'Daily', 'Balance', 'Weekly'],
                        pages: [
                          SpendingHeatmap(
                            days: _busyMonth(),
                            currencySymbol: 'Rs. ',
                          ),
                          DailyTotalsChart(
                            days: _busyMonth(),
                            currencySymbol: 'Rs. ',
                          ),
                          CumulativeBalanceChart(
                            days: _busyMonth(),
                            currencySymbol: 'Rs. ',
                          ),
                          WeeklyTotalsChart(
                            days: _busyMonth(),
                            currencySymbol: 'Rs. ',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
            await settleUi(tester);
            await tester.tap(find.byKey(ValueKey('chart-dot-$page')));
            await settleUi(tester);

            expect(
              tester.takeException(),
              isNull,
              reason: 'page ${page + 1} overflows at scale $scale',
            );

            final title = find.text(_titles[page]!);
            expect(title, findsOneWidget);
            final titleRect = tester.getRect(title);
            final plot = tester.getRect(
              page == 1 ? find.byType(BarChart) : find.byType(BarChart),
            );

            expect(
              plot.top >= titleRect.bottom,
              isTrue,
              reason:
                  'page ${page + 1} at scale $scale on $viewport: the plot '
                  'starts at ${plot.top} and the title ends at '
                  '${titleRect.bottom} -- they overlap',
            );
          });
        }
      }
    }
  });
}
