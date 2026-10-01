import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/providers/journey_provider.dart';
import 'package:flutter_application_1/providers/location_provider.dart';
import 'package:flutter_application_1/providers/settings_provider.dart';
import 'package:flutter_application_1/providers/transaction_provider.dart';
import 'package:flutter_application_1/screens/transactions/transactions_screen.dart';
import 'package:flutter_application_1/services/storage_service.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/utils/date_window.dart';

import 'test_viewports.dart';
import 'visual_smoke_test.dart' show initTestStorage;

Future<void> settleUi(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<TransactionProvider> pumpTransactions(WidgetTester tester) async {
  final provider = (await tester.runAsync(() async {
    final p = TransactionProvider();
    await p.initialize();
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

/// A provider off-test, for the assertions that are about state rather than
/// about widgets. Hive writes deadlock inside a widget body, so this is always
/// reached through `runAsync`.
Future<TransactionProvider> makeProvider() async {
  final provider = TransactionProvider();
  await provider.initialize();
  return provider;
}

bool _isDisabled(WidgetTester tester, String key) {
  final button = tester.widget<IconButton>(find.byKey(ValueKey(key)));
  return button.onPressed == null;
}

void main() {
  setUpAll(() async {
    await initTestStorage();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService().clear();
  });

  group('the date window', () {
    test('the month floor is two years back, floored to the month', () {
      // The pickers and the month chevrons share this floor, so a user cannot
      // page back to a month they then cannot record anything in.
      expect(
        AppDateWindow.monthFloor(DateTime(2026, 10, 17)),
        DateTime(2024, 10),
      );
      expect(
        AppDateWindow.monthFloor(DateTime(2026, 1, 31)),
        DateTime(2024, 1),
      );
    });

    test('the month ceiling is the CURRENT month, not a day ahead', () {
      expect(
        AppDateWindow.monthCeiling(DateTime(2026, 10, 17)),
        DateTime(2026, 10),
      );
    });

    test('a trip may start in the future; a record may not', () {
      final now = DateTime(2026, 10, 17);
      expect(AppDateWindow.tripLast(now).isAfter(now), isTrue);
      expect(AppDateWindow.recordLast(now), DateTime(2026, 10, 17));
      // Both reach back the same two years.
      expect(AppDateWindow.tripFirst(now), DateTime(2024));
      expect(AppDateWindow.recordFirst(now), DateTime(2024));
    });

    test('clamping leaves a month inside the range alone', () {
      final now = DateTime(2026, 10, 17);
      expect(
        AppDateWindow.clampMonth(DateTime(2026, 3), now),
        DateTime(2026, 3),
      );
      expect(
        AppDateWindow.clampMonth(DateTime(1990, 5), now),
        DateTime(2024, 10),
      );
      expect(
        AppDateWindow.clampMonth(DateTime(2046, 9), now),
        DateTime(2026, 10),
        reason: 'September 2046 is clamped to now rather than loaded',
      );
    });
  });

  group('month navigation is bounded', () {
    test('the ceiling is the current month', () async {
      final now = DateTime.now();
      final provider = await makeProvider();
      expect(provider.latestMonth, DateTime(now.year, now.month));
      // And nothing is navigable past it.
      expect(provider.canGoToNextMonth, isFalse, reason: 'it opens on now');
      expect(provider.canGoToPreviousMonth, isTrue);
    });

    test('nextMonth at the ceiling is a no-op, not an error', () async {
      final provider = await makeProvider();
      final before = provider.currentMonth;
      await provider.nextMonth();
      expect(
        provider.currentMonth,
        before,
        reason: 'pressing a disabled chevron leaves the user where they were',
      );
    });

    test('walking forward stops at the ceiling', () async {
      final provider = await makeProvider();
      await provider.previousMonth();
      await provider.previousMonth();
      for (var i = 0; i < 12; i++) {
        await provider.nextMonth();
      }
      expect(provider.currentMonth!.year, DateTime.now().year);
      expect(provider.currentMonth!.month, DateTime.now().month);
    });

    testWidgets('next stops at the current month and says so', (tester) async {
      // SEPTEMBER 2046 WAS AN UNBOUNDED CHEVRON, NOT BAD FORMATTING. The month
      // label formats correctly for any month; what let the calendar reach 2046
      // was `nextMonth` having no wall, so holding the chevron walked forward
      // forever into empty months whose totals read as zero.
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await pumpTransactions(tester);

      // Walk back one month, so there IS somewhere to go forward to, then
      // forward as far as the control allows.
      await tester.tap(find.byKey(const ValueKey('month-previous')));
      await settleUi(tester);
      expect(_isDisabled(tester, 'month-previous'), isFalse);
      expect(_isDisabled(tester, 'month-next'), isFalse);

      for (var i = 0; i < 6; i++) {
        if (_isDisabled(tester, 'month-next')) break;
        await tester.tap(find.byKey(const ValueKey('month-next')));
        await settleUi(tester);
      }

      // Bounded: the forward chevron is now disabled and the header is this
      // month. It is NOT September 2046, and no amount of tapping gets there.
      expect(_isDisabled(tester, 'month-next'), isTrue);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('month-label'))).data,
        DateFormat.yMMMM().format(DateTime.now()),
        reason: 'the header must name the current month, not a distant one',
      );
      // Named in the test as well, because September 2046 is the exact thing
      // this change exists to stop.
      expect(find.textContaining('2046'), findsNothing);
    });

    testWidgets('previous stops two years back and says so', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await pumpTransactions(tester);

      // 40 taps is far more than the 24 months in the window, so a control that
      // silently kept going would be obvious.
      for (var i = 0; i < 40; i++) {
        if (_isDisabled(tester, 'month-previous')) break;
        await tester.tap(find.byKey(const ValueKey('month-previous')));
        await settleUi(tester);
      }

      expect(_isDisabled(tester, 'month-previous'), isTrue);
      final floor = AppDateWindow.monthFloor(DateTime.now());
      expect(floor.year, DateTime.now().year - 2);

      // The provider agrees, so the chevron and the state cannot disagree.
      final provider = await makeProvider();
      for (var i = 0; i < 40; i++) {
        await provider.previousMonth();
      }
      expect(provider.currentMonth, AppDateWindow.monthFloor(DateTime.now()));
    });

    testWidgets('a disabled chevron explains itself in its tooltip', (
      tester,
    ) async {
      // "Nothing happened" is not an acceptable answer for a tap. The chevron is
      // still THERE, disabled, with a tooltip that names the boundary.
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await pumpTransactions(tester);

      await tester.tap(find.byKey(const ValueKey('month-next')));
      await settleUi(tester);

      final button = tester.widget<IconButton>(
        find.byKey(const ValueKey('month-next')),
      );
      expect(button.onPressed, isNull);
      expect(button.tooltip, 'Latest month');
      // Present, not hidden: a missing chevron would leave a gap that reads as a
      // layout mistake rather than as a boundary.
      expect(find.byKey(const ValueKey('month-next')), findsOne);
    });
  });

  group('the day picker is not a month picker', () {
    testWidgets('it is still reachable, from any month', (tester) async {
      // Paging back must not take the day picker away with it: choosing a day in
      // an old month is a normal thing to do, and the affordance has to survive
      // the new bounds.
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await pumpTransactions(tester);

      await tester.tap(find.byKey(const ValueKey('month-previous')));
      await settleUi(tester);
      await tester.tap(find.byKey(const ValueKey('month-previous')));
      await settleUi(tester);

      // The month header is the affordance, by design, and paging back has not
      // taken it away.
      await tester.tap(find.byIcon(Icons.calendar_today_rounded).first);
      await settleUi(tester);
      expect(find.text('Jump to a day'), findsOne);

      // It offers days of THAT month. Two months back from now, the last day on
      // offer is the last day of THAT month — so the picker is month-scoped and
      // cannot be a second route to changing the month.
      final browsed =
          AppDateWindow.monthFloor(
            DateTime.now(),
          ).isBefore(DateTime(DateTime.now().year, DateTime.now().month - 2, 1))
          ? DateTime(DateTime.now().year, DateTime.now().month - 2, 1)
          : DateTime(DateTime.now().year, DateTime.now().month, 1);
      final lastDayOfBrowsed = DateTime(browsed.year, browsed.month + 1, 0).day;
      expect(
        find.text('$lastDayOfBrowsed'),
        findsWidgets,
        reason:
            'the picker must offer day $lastDayOfBrowsed of the month on '
            'screen',
      );

      // Selecting a day narrows the view, and THEN the sheet offers a way back to
      // the whole month. Both are day controls: nothing here changes the month.
      await tester.tap(find.text('$lastDayOfBrowsed').first);
      await settleUi(tester);
      expect(
        find.byKey(const ValueKey('day-picker-whole-month')),
        findsNothing,
      );
      await tester.tap(find.byIcon(Icons.calendar_today_rounded).first);
      await settleUi(tester);
      expect(find.byKey(const ValueKey('day-picker-whole-month')), findsOne);
    });
  });
}
