import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daily_companion/providers/journey_provider.dart';
import 'package:daily_companion/providers/location_provider.dart';
import 'package:daily_companion/providers/settings_provider.dart';
import 'package:daily_companion/providers/transaction_provider.dart';
import 'package:daily_companion/screens/transactions/transactions_screen.dart';
import 'package:daily_companion/services/storage_service.dart';
import 'package:daily_companion/theme/app_theme.dart';
import 'package:daily_companion/utils/date_window.dart';

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

  group('the day picker reaches the whole window', () {
    // REVERSAL, deliberately. This group used to assert the opposite: that the
    // picker was scoped to the month on screen so it could not double as a
    // second route to changing the month. That was a tidy rule and it made the
    // thing unusable — "jump to the 12th", with the 12th in another month, had
    // no answer, and the build before this drew chevrons in the sheet that did
    // nothing at all. The picker now spans [AppDateWindow] and its own header
    // pages months.
    testWidgets('it is reachable from any month, and spans the window', (
      tester,
    ) async {
      // Paging back must not take the day picker away with it: choosing a day in
      // an old month is a normal thing to do, and the affordance has to survive
      // the bounds.
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await pumpTransactions(tester);

      await tester.tap(find.byKey(const ValueKey('month-previous')));
      await settleUi(tester);
      await tester.tap(find.byKey(const ValueKey('month-previous')));
      await settleUi(tester);

      // The month header is the affordance, and paging back has not taken it
      // away.
      await tester.tap(find.byIcon(Icons.calendar_today_rounded).first);
      await settleUi(tester);
      expect(find.text('Jump to a day'), findsOne);

      final picker = tester.widget<CalendarDatePicker>(
        find.byKey(const ValueKey('day-picker-calendar')),
      );

      // Relationships rather than equality against a separately captured `now`:
      // testWidgets runs on a faked clock, so the assertion would end up about
      // the clock instead of about the picker.
      expect(
        picker.firstDate,
        AppDateWindow.monthFloor(picker.lastDate),
        reason: 'the range starts exactly on the shared floor',
      );
      expect(
        picker.firstDate.isBefore(
          DateTime(picker.lastDate.year, picker.lastDate.month, 1),
        ),
        isTrue,
        reason:
            'a range inside one month cannot reach a day in another, which is '
            'the bug this reversed',
      );

      // Choosing a day HOLDS it and narrows nothing, so the "whole month" way
      // back is still absent -- there is no filter to undo yet. Applying it is
      // the second act, and only then does the way back appear.
      await tester.tap(find.text('15').first);
      await settleUi(tester);
      expect(
        find.byKey(const ValueKey('day-picker-whole-month')),
        findsNothing,
        reason: 'a merely CHOSEN day has not narrowed the view yet',
      );

      await tester.tap(find.byKey(const ValueKey('day-picker-apply')));
      await settleUi(tester);

      await tester.tap(find.byIcon(Icons.calendar_today_rounded).first);
      await settleUi(tester);
      expect(find.byKey(const ValueKey('day-picker-whole-month')), findsOne);
    });
  });
}
