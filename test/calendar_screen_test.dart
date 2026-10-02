import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/providers/checklist_provider.dart';
import 'package:daily_companion/providers/journey_provider.dart';
import 'package:daily_companion/providers/location_provider.dart';
import 'package:daily_companion/providers/settings_provider.dart';
import 'package:daily_companion/providers/transaction_provider.dart';
import 'package:daily_companion/screens/calendar_screen.dart';
import 'package:daily_companion/screens/checklists/checklists_screen.dart';
import 'package:daily_companion/screens/journeys/journeys_screen.dart';
import 'package:daily_companion/screens/locations/locations_screen.dart';
import 'package:daily_companion/screens/transactions/transactions_screen.dart';
import 'package:daily_companion/services/storage_service.dart';
import 'package:daily_companion/theme/app_theme.dart';
import 'package:daily_companion/utils/date_window.dart';
import 'package:daily_companion/widgets/app_calendar.dart';
import 'package:daily_companion/widgets/app_gear.dart';
import 'package:daily_companion/widgets/app_search.dart';

import 'test_viewports.dart';
import 'visual_smoke_test.dart' show initTestStorage;

/// Pumps long enough for a post-frame measurement and any provider load.
Future<void> settleUi(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<TransactionProvider> _transactions(WidgetTester tester) async {
  return (await tester.runAsync(() async {
    final provider = TransactionProvider();
    await provider.initialize();
    return provider;
  }))!;
}

Future<JourneyProvider> _journeys(WidgetTester tester) async {
  return (await tester.runAsync(() async {
    final provider = JourneyProvider();
    await provider.initialize();
    return provider;
  }))!;
}

Widget _app({
  required TransactionProvider transactions,
  required JourneyProvider journeys,
  Widget? home,
}) {
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
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: home ?? const TransactionsScreen(),
    ),
  );
}

/// A day last month, so a test can assert the picker reaches BACKWARD.
DateTime _lastMonth() {
  final now = DateTime.now();
  return DateTime(now.year, now.month - 1, 15);
}

void main() {
  setUpAll(() async {
    await initTestStorage();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService().clear();
  });

  group('the calendar is global, like the gear', () {
    testWidgets('every tab offers it beside settings', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      final transactions = await _transactions(tester);
      final journeys = await _journeys(tester);

      for (final screen in <Widget>[
        const TransactionsScreen(),
        const JourneysScreen(),
        const ChecklistsScreen(),
        const LocationsScreen(),
      ]) {
        await tester.pumpWidget(
          _app(transactions: transactions, journeys: journeys, home: screen),
        );
        await settleUi(tester);

        expect(
          find.byKey(AppCalendarButton.buttonKey),
          findsOneWidget,
          reason: '$screen has no calendar button',
        );
        expect(
          find.byKey(AppGearButton.buttonKey),
          findsOneWidget,
          reason: '$screen lost its settings button',
        );
      }
    });

    testWidgets('the order is search, calendar, settings', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      final transactions = await _transactions(tester);
      final journeys = await _journeys(tester);

      await tester.pumpWidget(
        _app(transactions: transactions, journeys: journeys),
      );
      await settleUi(tester);

      // Read the real x positions rather than trusting the source order, so a
      // reorder cannot pass by accident.
      final search = tester.getCenter(find.byKey(AppSearchButton.buttonKey));
      final calendar = tester.getCenter(
        find.byKey(AppCalendarButton.buttonKey),
      );
      final settings = tester.getCenter(find.byKey(AppGearButton.buttonKey));

      expect(search.dx, lessThan(calendar.dx));
      expect(calendar.dx, lessThan(settings.dx));
    });

    testWidgets('it opens the calendar', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      final transactions = await _transactions(tester);
      final journeys = await _journeys(tester);

      await tester.pumpWidget(
        _app(transactions: transactions, journeys: journeys),
      );
      await settleUi(tester);

      await tester.tap(find.byKey(AppCalendarButton.buttonKey));
      await settleUi(tester);

      expect(find.byType(CalendarScreen), findsOneWidget);
      expect(find.byKey(CalendarScreen.monthLabelKey), findsOneWidget);
    });
  });

  group('the calendar grid', () {
    testWidgets('shows the month and lays out at 360dp', (tester) async {
      usePhoneLayout(tester, TestViewports.phoneSmall);
      final transactions = await _transactions(tester);
      final journeys = await _journeys(tester);

      await tester.pumpWidget(
        _app(
          transactions: transactions,
          journeys: journeys,
          home: const CalendarScreen(),
        ),
      );
      await settleUi(tester);

      // Derived from the clock, not a literal: a hardcoded month name passes for
      // a month and then fails at midnight on the 1st, which trains you to
      // ignore the failure.
      final month = DateFormat.yMMMM().format(DateTime.now());
      expect(find.text(month), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the journey list belongs to the month on the grid', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      final transactions = await _transactions(tester);
      final journeys = await _journeys(tester);

      // A journey that started in a DIFFERENT month. It must not appear under
      // the current month's calendar: "August 18" listed beneath an October grid
      // is not information.
      final longAgo = DateTime(DateTime.now().year, DateTime.now().month - 3);
      journeys.journeys.add(
        Journey(
          destination: 'Old trip',
          origin: 'Kathmandu',
          startTime: longAgo,
          endTime: longAgo.add(const Duration(days: 2)),
        ),
      );

      await tester.pumpWidget(
        _app(
          transactions: transactions,
          journeys: journeys,
          home: const CalendarScreen(),
        ),
      );
      await settleUi(tester);

      expect(find.text('Old trip'), findsNothing);
      expect(find.text(DateFormat.yMMMMd().format(longAgo)), findsNothing);
    });

    testWidgets('cannot page past the current month', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      final transactions = await _transactions(tester);
      final journeys = await _journeys(tester);

      await tester.pumpWidget(
        _app(
          transactions: transactions,
          journeys: journeys,
          home: const CalendarScreen(),
        ),
      );
      await settleUi(tester);

      final forward = tester.widget<IconButton>(
        find.byKey(CalendarScreen.nextMonthKey),
      );
      // On the current month there is nothing after it, and a LIVE chevron
      // there is the dead-button bug this replaced.
      expect(forward.onPressed, isNull);
    });

    testWidgets('can page back, and the label follows', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      final transactions = await _transactions(tester);
      final journeys = await _journeys(tester);

      await tester.pumpWidget(
        _app(
          transactions: transactions,
          journeys: journeys,
          home: const CalendarScreen(),
        ),
      );
      await settleUi(tester);

      await tester.tap(find.byKey(CalendarScreen.prevMonthKey));
      await settleUi(tester);

      final expected = DateFormat.yMMMM().format(_lastMonth());
      expect(find.text(expected), findsOneWidget);
    });
  });

  group('the day picker reaches the past', () {
    /// Opens "Jump to a day" from the month card, with one expense present so
    /// the month summary card is on screen at all.
    Future<void> openPicker(
      WidgetTester tester,
      TransactionProvider transactions,
      JourneyProvider journeys,
    ) async {
      await tester.runAsync(
        () => transactions.addTransaction(
          Expense(
            amount: 120,
            category: ExpenseCategory.food,
            description: 'Lunch',
            date: DateTime.now(),
          ),
        ),
      );

      await tester.pumpWidget(
        _app(transactions: transactions, journeys: journeys),
      );
      await settleUi(tester);

      await tester.tap(find.byIcon(Icons.calendar_today_rounded).first);
      await settleUi(tester);
    }

    testWidgets('its range spans the whole window, so it can reach the past', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      final transactions = await _transactions(tester);
      final journeys = await _journeys(tester);

      await openPicker(tester, transactions, journeys);

      final picker = tester.widget<CalendarDatePicker>(
        find.byKey(const ValueKey('day-picker-calendar')),
      );

      // Relationships, not equality against a separately captured `now`:
      // testWidgets runs on a faked clock, so two DateTime.now() calls in one
      // test are not guaranteed to agree and the assertion would be about the
      // clock rather than about the picker.
      expect(
        picker.firstDate,
        AppDateWindow.monthFloor(picker.lastDate),
        reason: 'the range must start exactly on the shared floor',
      );
      expect(picker.lastDate.day, DateTime.now().day);
      expect(picker.lastDate.isAfter(DateTime.now()), isFalse);

      // THE fix. Scoping the range to the month on screen is what made a day in
      // another month unreachable; the picker drives its own chevrons from this
      // range, so the range IS the behaviour. A one-month range cannot render a
      // chevron that moves.
      expect(
        picker.firstDate.isBefore(
          DateTime(picker.lastDate.year, picker.lastDate.month, 1),
        ),
        isTrue,
      );
    });

    testWidgets('one row of month navigation, not two', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      final transactions = await _transactions(tester);
      final journeys = await _journeys(tester);

      await openPicker(tester, transactions, journeys);

      // The first version added its own chevron row above the picker and left
      // the built-in one below, so the device showed two month navigators and
      // only one of them worked.
      expect(find.byType(CalendarDatePicker), findsOneWidget);
      expect(
        find.byKey(const ValueKey('day-picker-prev-month')),
        findsNothing,
        reason: 'the added chevron row is what created the duplicate',
      );
      expect(
        find.byKey(const ValueKey('day-picker-next-month')),
        findsNothing,
        reason: 'the added chevron row is what created the duplicate',
      );
    });

    testWidgets('it says a day HAS transactions, not HAVE', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      final transactions = await _transactions(tester);
      final journeys = await _journeys(tester);

      await openPicker(tester, transactions, journeys);

      expect(find.textContaining('1 day has transactions'), findsOneWidget);
      expect(find.textContaining('1 day have transactions'), findsNothing);
    });

    testWidgets('whole month is offered once a day is selected', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      final transactions = await _transactions(tester);
      final journeys = await _journeys(tester);

      await tester.runAsync(
        () => transactions.addTransaction(
          Expense(
            amount: 120,
            category: ExpenseCategory.food,
            description: 'Lunch',
            date: DateTime.now(),
          ),
        ),
      );
      await tester.pumpWidget(
        _app(transactions: transactions, journeys: journeys),
      );
      await settleUi(tester);

      // With nothing narrowed there is nothing to escape from, so the control is
      // absent rather than inert.
      await tester.tap(find.byIcon(Icons.calendar_today_rounded).first);
      await settleUi(tester);
      expect(
        find.byKey(const ValueKey('day-picker-whole-month')),
        findsNothing,
      );
      await tester.tapAt(const Offset(20, 20));
      await settleUi(tester);

      // Narrow to a day, and the way back appears.
      transactions.setSelectedDay(DateTime.now());
      await settleUi(tester);
      await tester.tap(find.byIcon(Icons.calendar_today_rounded).first);
      await settleUi(tester);

      expect(
        find.byKey(const ValueKey('day-picker-whole-month')),
        findsOneWidget,
      );
    });
    testWidgets('picking a past day loads ITS month and narrows to it', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      final transactions = await _transactions(tester);
      final journeys = await _journeys(tester);

      // A known past day, inside the window the picker offers.
      final now = DateTime.now();
      final past = DateTime(
        now.year,
        now.month,
        1,
      ).subtract(const Duration(days: 20));
      await tester.runAsync(
        () => transactions.addTransaction(
          Expense(
            amount: 120,
            category: ExpenseCategory.food,
            description: 'Lunch',
            date: DateTime.now(),
          ),
        ),
      );

      await tester.pumpWidget(
        _app(transactions: transactions, journeys: journeys),
      );
      await settleUi(tester);
      await tester.tap(find.byIcon(Icons.calendar_today_rounded).first);
      await settleUi(tester);

      // The picker can now OFFER a day outside the loaded month...
      final picker = tester.widget<CalendarDatePicker>(
        find.byKey(const ValueKey('day-picker-calendar')),
      );
      expect(picker.firstDate.isBefore(past), isTrue);

      // ...so selecting one has to load that month. It did not: the day was
      // offered, tapped, and dropped, because setSelectedDay refuses a day whose
      // month it has not read. The tap did nothing and looked broken.
      //
      // Invoked through the callback rather than by tapping the day text:
      // CalendarDatePicker lays its grid out itself, and in a widget test a tap
      // at a day's centre reliably lands on a neighbouring cell. The callback is
      // the same path a real tap takes; the hit test is the part being unreliable,
      // not the behaviour under test.
      picker.onDateChanged(past);
      await settleUi(tester);

      // SELECTING DOES NOT CLOSE. It used to: `onDateChanged` popped the sheet,
      // so one tap on a grid of thirty cells both chose a day and dismissed the
      // thing you choose it in, and a stray tap silently narrowed the month.
      expect(
        find.byKey(const ValueKey('day-picker-apply')),
        findsOneWidget,
        reason: 'the sheet closed on selection',
      );
      // The button says WHICH day it will apply, so the held value is never a
      // secret and a mis-tap is visible before it costs anything.
      expect(find.textContaining('Show'), findsOneWidget);

      // Now commit it.
      await tester.tap(find.byKey(const ValueKey('day-picker-apply')));
      await settleUi(tester);

      expect(transactions.currentMonth?.year, past.year);
      expect(transactions.currentMonth?.month, past.month);
      expect(transactions.selectedDay?.day, past.day);
    });
  });

  group('choosing a day does not LEAVE', () {
    // THE DEVICE REPORT: "clicking on a day on calendar shouldnt immediately
    // close the calendar section". It did, on both surfaces: a tap loaded the
    // month, narrowed the ledger and popped, all in one gesture. A month grid is
    // thirty targets, and one stray touch silently ended the screen you were
    // browsing. Choosing is now one act and committing is a second, named one.
    testWidgets('a tap holds the day, and the sheet stays open', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      final transactions = await _transactions(tester);
      final journeys = await _journeys(tester);

      await tester.pumpWidget(
        _app(transactions: transactions, journeys: journeys),
      );
      await settleUi(tester);
      await tester.tap(find.byIcon(Icons.calendar_today_rounded).first);
      await settleUi(tester);

      final picker = tester.widget<CalendarDatePicker>(
        find.byKey(const ValueKey('day-picker-calendar')),
      );
      final past = DateTime.now().subtract(const Duration(days: 9));

      picker.onDateChanged(past);
      await settleUi(tester);

      // Still here.
      expect(
        find.byKey(const ValueKey('day-picker-calendar')),
        findsOneWidget,
        reason: 'the sheet closed just from choosing a day',
      );
      // It says which day it will apply, so the held value is never a secret and
      // a mis-tap is visible before it costs anything.
      final apply = tester.widget<FilledButton>(
        find.byKey(const ValueKey('day-picker-apply')),
      );
      expect(apply.onPressed, isNotNull);
      expect(find.textContaining('Show'), findsOneWidget);

      // Choosing a DIFFERENT day replaces the held one rather than stacking.
      picker.onDateChanged(past.subtract(const Duration(days: 3)));
      await settleUi(tester);
      expect(find.textContaining('Show'), findsOneWidget);

      // Committing is what closes it.
      await tester.tap(find.byKey(const ValueKey('day-picker-apply')));
      await settleUi(tester);
      expect(
        find.byKey(const ValueKey('day-picker-calendar')),
        findsNothing,
        reason: 'applying the day did not close the sheet',
      );
    });

    testWidgets('the Calendar screen holds a tapped day behind an Open button', (
      tester,
    ) async {
      // A TALL viewport so the whole month is laid out at once. A `ListView`
      // builds only what is near the viewport, and the grid is far enough down
      // that at phone height the day cells are simply not in the tree -- a test
      // that scrolled to them would be testing the scroll.
      usePhoneLayout(tester, const Size(412, 2600));
      final transactions = await _transactions(tester);
      final journeys = await _journeys(tester);

      // The full-screen Calendar itself. On Transactions the calendar button
      // opens the day-picker SHEET, which is a different screen and is covered
      // by the test above.
      await tester.pumpWidget(
        _app(
          transactions: transactions,
          journeys: journeys,
          home: const CalendarScreen(),
        ),
      );
      await settleUi(tester);

      // No day held yet, so there is nothing to open.
      expect(
        find.byKey(const ValueKey('calendar-open-selected-day')),
        findsNothing,
      );

      await tester.tap(find.byKey(CalendarScreen.dayKey(2)));
      await settleUi(tester);

      // Still on the calendar, with the day named and a way out that is explicit.
      expect(
        find.byKey(const ValueKey('calendar-open-selected-day')),
        findsOneWidget,
      );
      expect(find.textContaining('selected'), findsOneWidget);
    });
  });

  group('the bounds are shared with the pickers', () {
    test('the calendar window is the same one the record window uses', () {
      final now = DateTime.now();
      // If these two ever disagree, a calendar can offer a month whose days no
      // picker would accept.
      expect(AppDateWindow.monthCeiling(now), DateTime(now.year, now.month, 1));
      expect(
        AppDateWindow.monthFloor(now),
        DateTime(now.year - AppDateWindow.yearsBack, now.month, 1),
      );
    });
  });
}
