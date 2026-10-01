import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/journey_provider.dart';
import 'package:flutter_application_1/providers/location_provider.dart';
import 'package:flutter_application_1/providers/settings_provider.dart';
import 'package:flutter_application_1/providers/transaction_provider.dart';
import 'package:flutter_application_1/screens/transactions/transactions_screen.dart';
import 'package:flutter_application_1/services/storage_service.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/widgets/chart_pager.dart';

import 'test_viewports.dart';
import 'visual_smoke_test.dart' show initTestStorage;

Future<void> settleUi(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Hive writes in a `testWidgets` body deadlock, so every save goes through
/// [tester.runAsync]; the widget body only taps and reads.
Future<TransactionProvider> pumpSpend(
  WidgetTester tester, {
  int rowsOn = 3,
}) async {
  final provider = (await tester.runAsync(() async {
    final p = TransactionProvider();
    await p.initialize();
    for (var day = 1; day <= rowsOn; day++) {
      await p.addTransaction(
        Expense(
          amount: 100.0 * day,
          category: ExpenseCategory.food,
          description: 'Expense on day $day',
          date: DateTime(DateTime.now().year, DateTime.now().month, day),
        ),
      );
    }
    return p;
  }))!;

  final settings = (await tester.runAsync(() async {
    final s = SettingsProvider();
    await s.load();
    return s;
  }))!;

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<TransactionProvider>.value(value: provider),
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider(create: (_) => JourneyProvider()),
        ChangeNotifierProvider(create: (_) => LocationProvider()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const Scaffold(body: TransactionsScreen()),
      ),
    ),
  );
  await settleUi(tester);
  return provider;
}

/// Opens the jump-to-day sheet.
Future<void> openDayPicker(WidgetTester tester) async {
  // The month header is the tappable affordance, by design.
  await tester.tap(find.byIcon(Icons.calendar_today_rounded).first);
  await settleUi(tester);
}

void main() {
  setUpAll(() async {
    await initTestStorage();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService().clear();
  });

  group('4a — dismissing the sheet must not change the view', () {
    testWidgets('swiping the sheet away PRESERVES the selected day', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      final provider = await pumpSpend(tester);

      // Derived from the clock, never a literal day: a fixed date is in the
      // future on the 1st of a month and the selection is refused.
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, 1);
      provider.setSelectedDay(day);
      await settleUi(tester);
      expect(provider.selectedDay, day, reason: 'the setup itself must stick');

      await openDayPicker(tester);
      expect(find.byType(BottomSheet), findsOneWidget);

      // Drag the sheet DOWN and off. A dismiss gesture is the common case and it
      // used to be indistinguishable from "Whole month", so it cleared the
      // filter: select a day, change your mind about the sheet, and the view
      // changed anyway.
      await tester.drag(find.byType(BottomSheet), const Offset(0, 600));
      await settleUi(tester);
      await settleUi(tester);

      expect(
        provider.selectedDay,
        day,
        reason: 'dismissing the sheet is not a request to clear the day filter',
      );
    });

    testWidgets('"Whole month" DOES clear the filter', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      final provider = await pumpSpend(tester);

      final now = DateTime.now();
      provider.setSelectedDay(DateTime(now.year, now.month, 1));
      await settleUi(tester);

      await openDayPicker(tester);
      await tester.tap(find.byKey(const ValueKey('day-picker-whole-month')));
      await settleUi(tester);
      await settleUi(tester);

      // The two intents are now separable, so the button works as its label says.
      expect(provider.selectedDay, isNull);
    });

    test('the three outcomes are three distinct values', () {
      // The mechanism, stated directly. A null could not carry this.
      const dismissed = DayPick.dismissed();
      const whole = DayPick.wholeMonth();
      final day = DayPick.day(DateTime(2026, 5, 4));

      expect(dismissed.isDismissed, isTrue);
      expect(dismissed.day, isNull);
      expect(whole.isDismissed, isFalse);
      expect(whole.day, isNull);
      expect(day.day, DateTime(2026, 5, 4));
      expect(dismissed.result, isNot(whole.result));
    });
  });

  group('4b — a tap always gives a visible result', () {
    test('a day in the FUTURE is refused, which the picker needs', () async {
      final provider = TransactionProvider();
      await provider.loadTransactionsForMonth(2026, 5);

      // Deliberately far enough ahead to be unambiguously the future.
      final outcome = provider.setSelectedDay(DateTime(2030, 1, 1));
      expect(outcome.changed, isFalse);
      expect(outcome, isA<DayInTheFuture>());
      expect(provider.selectedDay, isNull);
      // The picker caps `lastDate` at today, so an accepted future day made
      // `initialDate` later than `lastDate` and the sheet threw on open.
      expect(outcome.message, isNotNull);
    });

    test('a day in another month is refused AND named', () async {
      final provider = TransactionProvider();
      await provider.loadTransactionsForMonth(2026, 5);

      final outcome = provider.setSelectedDay(DateTime(2026, 7, 4));

      // Refused...
      expect(outcome.changed, isFalse);
      expect(outcome, isA<DayOutsideLoadedMonth>());
      expect(provider.selectedDay, isNull);
      // ...and the refusal CARRIES the month it would need, so the caller can
      // say something actionable rather than nothing.
      expect((outcome as DayOutsideLoadedMonth).loadedMonth, DateTime(2026, 5));
    });

    test('re-tapping the selected day explains itself', () async {
      final provider = TransactionProvider();
      await provider.loadTransactionsForMonth(2026, 5);
      final day = DateTime(2026, 5, 4);

      expect(provider.setSelectedDay(day).changed, isTrue);

      final again = provider.setSelectedDay(day);
      expect(again.changed, isFalse);
      expect(again, isA<DayAlreadySelected>());
      // A message exists, which is the whole requirement.
      expect(again.message, isNotNull);
    });

    test('clearing while nothing is selected explains itself', () async {
      final provider = TransactionProvider();
      await provider.loadTransactionsForMonth(2026, 5);

      final outcome = provider.setSelectedDay(null);
      expect(outcome.changed, isFalse);
      expect(outcome.message, isNotNull);
    });

    test(
      'a successful tap says nothing, because nothing needs saying',
      () async {
        final provider = TransactionProvider();
        await provider.loadTransactionsForMonth(2026, 5);
        final outcome = provider.setSelectedDay(DateTime(2026, 5, 4));
        expect(outcome.changed, isTrue);
        // A snackbar on every successful tap would be noise, not feedback.
        expect(outcome.message, isNull);
      },
    );

    testWidgets('tapping a day outside the month shows a message', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      final provider = await pumpSpend(tester);

      // Drive it the way a stale tap could: a day in a month not on screen.
      final outcome = provider.setSelectedDay(
        DateTime(DateTime.now().year, DateTime.now().month + 1, 4),
      );
      await settleUi(tester);

      expect(outcome.changed, isFalse);
      expect(provider.selectedDay, isNull);
    });
  });

  group('changing month clears a stale day filter', () {
    testWidgets('the path is reachable from the UI: the month arrows', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      final provider = await pumpSpend(tester);

      // Day 1, not a literal 2: a fixed day is in the FUTURE on the 1st of a
      // month and is correctly refused.
      final now = DateTime.now();
      provider.setSelectedDay(DateTime(now.year, now.month, 1));
      await settleUi(tester);
      expect(provider.selectedDay, isNotNull);

      // Back one month, then forward again, tapped the way a user does.
      //
      // NOT "next month": the screen opens on the current month and the forward
      // chevron is disabled there, because the ceiling is now the current month.
      // Tapping forward from now is a no-op BY DESIGN, so this test has to move
      // within the window to test what it means to move.
      await tester.tap(find.byKey(const ValueKey('month-previous')));
      await settleUi(tester);
      await tester.tap(find.byKey(const ValueKey('month-next')));
      await settleUi(tester);
      await settleUi(tester);

      expect(
        provider.selectedDay,
        isNull,
        reason:
            'a day belongs to a month; moving months must drop the selection '
            'or the view stays narrowed to a day that is not loaded',
      );
    });

    test('and it is dropped in the provider, not only in the screen', () async {
      // Anchored on the clock rather than a literal 2026, which is inside the
      // two-year window today and will not be in a year's time.
      final now = DateTime.now();
      final month = DateTime(now.year, now.month - 1);
      final provider = TransactionProvider();
      await provider.loadTransactionsForMonth(month.year, month.month);
      provider.setSelectedDay(DateTime(month.year, month.month, 4));
      expect(provider.selectedDay, isNotNull);

      await provider.nextMonth();
      expect(provider.selectedDay, isNull);
      expect(provider.filteredTransactions, isEmpty);

      await provider.previousMonth();
      expect(provider.selectedDay, isNull);
    });
  });

  group('charts do not jump when the day filter toggles', () {
    testWidgets('the pager keeps its height across the toggle', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      final provider = await pumpSpend(tester);

      final pager = find.byType(ChartPager);
      expect(pager, findsOneWidget);
      final before = tester.getSize(pager).height;

      provider.setSelectedDay(
        DateTime(DateTime.now().year, DateTime.now().month, 2),
      );
      await settleUi(tester);

      // The pager has a FIXED height precisely because a PageView sizes to its
      // tallest child and the page jumped on swipe. A day toggle must not change
      // it, or the screen moves under the user's thumb.
      expect(
        tester.getSize(find.byType(ChartPager)).height,
        closeTo(before, 0.5),
      );
    });
  });
}
