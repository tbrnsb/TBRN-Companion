import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/providers/checklist_provider.dart';
import 'package:daily_companion/providers/journey_provider.dart';
import 'package:daily_companion/providers/location_provider.dart';
import 'package:daily_companion/providers/settings_provider.dart';
import 'package:daily_companion/providers/transaction_provider.dart';
import 'package:daily_companion/screens/transactions/transactions_screen.dart';
import 'package:daily_companion/services/storage_service.dart';
import 'package:daily_companion/theme/app_theme.dart';

import 'visual_smoke_test.dart' show initTestStorage;

Future<void> settleUi(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// A month with a bar on most days, in both directions.
///
/// A seeded month was ten records on one day, and the September month has a
/// few. Between them they cover the case that matters: a plot whose TALLEST bar
/// reaches the top of its own box, which is when an overlap is visible at all.
Future<void> seedAMonth() async {
  final now = DateTime.now();
  final storage = StorageService();
  for (var d = 1; d <= 28; d++) {
    await storage.addTransaction(
      Expense(
        id: 'exp-$d',
        amount: 100.0 + (d * 137) % 900,
        category: ExpenseCategory.values[d % ExpenseCategory.values.length],
        description: 'Spend $d',
        date: DateTime(now.year, now.month, d),
      ),
    );
    if (d % 5 == 0) {
      await storage.addTransaction(
        Income(
          id: 'inc-$d',
          amount: 900.0,
          category: 'freelance',
          description: 'In $d',
          date: DateTime(now.year, now.month, d),
        ),
      );
    }
  }
}

Widget _app(TransactionProvider transactions, JourneyProvider journeys) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<TransactionProvider>.value(value: transactions),
      ChangeNotifierProvider<JourneyProvider>.value(value: journeys),
      ChangeNotifierProvider(create: (_) => LocationProvider()),
      ChangeNotifierProvider(create: (_) => ChecklistProvider()),
      ChangeNotifierProvider(create: (_) => SettingsProvider()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const TransactionsScreen(),
    ),
  );
}

Future<(TransactionProvider, JourneyProvider)> _providers(
  WidgetTester tester,
) async {
  final transactions = (await tester.runAsync(() async {
    final p = TransactionProvider();
    await p.initialize();
    return p;
  }))!;
  final journeys = (await tester.runAsync(() async {
    final p = JourneyProvider();
    await p.initialize();
    return p;
  }))!;
  return (transactions, journeys);
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await initTestStorage();
  });

  group('the breakdown pager clears the FAB', () {
    // THE TEST THAT SHOULD HAVE EXISTED.
    //
    // `countOnTheLeft` was added to SwipePages, tested on SwipePages, and the
    // whole suite was green -- because nothing checked that the screen PASSED
    // it. The device still had "1 of 2 . Spending" under the Add button, which
    // is the exact bug the flag was for. A flag nobody sets is not a fix, so
    // this asserts the call site rather than the capability.
    testWidgets('the count label sits LEFT of the dots on the real screen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 5200);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.runAsync(seedAMonth);
      final (transactions, journeys) = await _providers(tester);

      await tester.pumpWidget(_app(transactions, journeys));
      await settleUi(tester);

      final label = find.byKey(const ValueKey('swipe-indicator-count'));
      final dot = find.byKey(const ValueKey('swipe-dot-0'));

      expect(label, findsOneWidget, reason: 'the breakdown pager is not shown');
      expect(dot, findsOneWidget);
      expect(
        tester.getCenter(dot).dx,
        greaterThan(tester.getCenter(label).dx),
        reason:
            'the count label is to the right of the dots, which is where '
            'the FAB is',
      );
    });
  });

  group('on the real screen, no chart plot reaches its own heading', () {
    // The widget-level version of this test pumps ChartPager inside a
    // SingleChildScrollView and is green at every text scale, at both viewports.
    // The device drew bars through "In and out, by day" anyway. The difference
    // is the screen around it, so this pumps TransactionsScreen itself.
    for (final scale in [1.0, 1.15, 1.3]) {
      testWidgets('no overlap at text scale $scale', (tester) async {
        tester.view.physicalSize = const Size(1080, 5200);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);

        await tester.runAsync(seedAMonth);
        final (transactions, journeys) = await _providers(tester);

        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: _app(transactions, journeys),
          ),
        );
        await settleUi(tester);

        // Page 2 of 4, the one the user named: "In and out, by day".
        await tester.tap(find.byKey(const ValueKey('chart-dot-1')));
        await settleUi(tester);

        final title = find.text('In and out, by day');
        final plot = find.byType(BarChart);
        expect(title, findsOneWidget);
        expect(plot, findsOneWidget);

        final titleRect = tester.getRect(title);
        final plotRect = tester.getRect(plot);
        expect(
          plotRect.top,
          greaterThanOrEqualTo(titleRect.bottom),
          reason:
              'the plot starts at ${plotRect.top} and the heading ends at '
              '${titleRect.bottom} at text scale $scale -- they overlap',
        );
      });
    }
  });
}
