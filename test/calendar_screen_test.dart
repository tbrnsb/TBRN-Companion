import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/checklist_provider.dart';
import 'package:flutter_application_1/providers/journey_provider.dart';
import 'package:flutter_application_1/providers/location_provider.dart';
import 'package:flutter_application_1/providers/settings_provider.dart';
import 'package:flutter_application_1/providers/transaction_provider.dart';
import 'package:flutter_application_1/screens/calendar_screen.dart';
import 'package:flutter_application_1/screens/checklists/checklists_screen.dart';
import 'package:flutter_application_1/screens/journeys/journeys_screen.dart';
import 'package:flutter_application_1/screens/locations/locations_screen.dart';
import 'package:flutter_application_1/screens/transactions/transactions_screen.dart';
import 'package:flutter_application_1/services/storage_service.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/utils/date_window.dart';
import 'package:flutter_application_1/widgets/app_calendar.dart';
import 'package:flutter_application_1/widgets/app_gear.dart';
import 'package:flutter_application_1/widgets/app_search.dart';
import 'package:flutter_application_1/widgets/chart_pager.dart';

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

      expect(transactions.currentMonth?.year, past.year);
      expect(transactions.currentMonth?.month, past.month);
      expect(transactions.selectedDay?.day, past.day);
    });
  });

  group('the chart pager has no hole in it', () {
    testWidgets('the pager is as tall as its tallest page, not a constant', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      // A short page and a tall page. If the pager reserved a fixed height the
      // box would be far taller than the tallest page, which is exactly the
      // hole that used to sit under every chart.
      final tall = SizedBox(
        height: 320,
        child: ColoredBox(color: const Color(0xFF123456), child: Text('tall')),
      );
      final short = SizedBox(
        height: 90,
        child: ColoredBox(color: const Color(0xFF654321), child: Text('short')),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ChartPager(
                pages: [tall, short],
                labels: const ['Tall', 'Short'],
              ),
            ),
          ),
        ),
      );
      await settleUi(tester);

      final height = tester.getSize(find.byType(ChartPager)).height;
      // The tallest page, plus the indicator row beneath it. Generously bounded
      // on both sides so this asserts the SHAPE, not a magic number.
      expect(height, greaterThan(320));
      expect(height, lessThan(420));
    });

    testWidgets('no fixed height constant survives', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final short = SizedBox(
        height: 90,
        child: ColoredBox(color: const Color(0xFF654321), child: Text('a')),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ChartPager(pages: [short, short, short]),
            ),
          ),
        ),
      );
      await settleUi(tester);

      // The old 640 reserve made this 640 for ninety pixels of chart.
      expect(tester.getSize(find.byType(ChartPager)).height, lessThan(200));
    });

    testWidgets('the height does not change when the page changes', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final tall = SizedBox(
        height: 300,
        child: ColoredBox(color: const Color(0xFF123456), child: Text('t')),
      );
      final short = SizedBox(
        height: 100,
        child: ColoredBox(color: const Color(0xFF654321), child: Text('s')),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ChartPager(pages: [tall, short]),
            ),
          ),
        ),
      );
      await settleUi(tester);

      final before = tester.getSize(find.byType(ChartPager)).height;
      await tester.tap(find.byKey(const ValueKey('chart-dot-1')));
      await settleUi(tester);
      final after = tester.getSize(find.byType(ChartPager)).height;

      // One height for every page: nothing moves under the user's finger.
      expect(after, moreOrLessEquals(before, epsilon: 0.5));
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
