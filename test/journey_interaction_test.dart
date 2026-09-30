import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/journey_provider.dart';
import 'package:flutter_application_1/providers/settings_provider.dart';
import 'package:flutter_application_1/providers/transaction_provider.dart';
import 'package:flutter_application_1/screens/journeys/journey_detail_sheets.dart';
import 'package:flutter_application_1/services/storage_service.dart';
import 'package:flutter_application_1/theme/app_theme.dart';

import 'test_viewports.dart';
import 'visual_smoke_test.dart' show initTestStorage;

final _someDay = DateTime(2024, 3, 12);

Future<void> settleUi(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    await initTestStorage();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService().clear();
  });

  group('what happened on a day', () {
    test('journeys are found by start and by end', () async {
      final provider = JourneyProvider();
      final started = Journey(
        destination: 'Pokhara',
        origin: 'Kathmandu',
        startTime: DateTime(2024, 3, 12, 9),
        endTime: DateTime(2024, 3, 15, 18),
      );
      final alsoStarted = Journey(
        destination: 'Chitwan',
        origin: 'Kathmandu',
        startTime: DateTime(2024, 3, 12, 20),
      );
      final elsewhere = Journey(
        destination: 'Dhulikhel',
        origin: 'Kathmandu',
        startTime: DateTime(2024, 3, 20),
      );
      provider.journeys
        ..clear()
        ..addAll([started, alsoStarted, elsewhere]);

      final the12th = DateTime(2024, 3, 12);
      expect(
        provider.journeysStartingOn(the12th).map((j) => j.destination),
        containsAll(['Pokhara', 'Chitwan']),
      );
      expect(
        provider.journeysStartingOn(the12th).map((j) => j.destination),
        isNot(contains('Dhulikhel')),
      );

      expect(
        provider.journeysEndingOn(the12th),
        isEmpty,
        reason: 'a trip that ends on the 15th did not finish on the 12th',
      );
      expect(
        provider.journeysEndingOn(DateTime(2024, 3, 15)).single.destination,
        'Pokhara',
      );

      expect(provider.hasActivityOn(the12th), isTrue);
      expect(provider.hasActivityOn(DateTime(2024, 3, 13)), isFalse);
    });

    test('an open trip is not counted as ending on any day', () async {
      final provider = JourneyProvider();
      final open = Journey(
        destination: 'Pokhara',
        origin: 'Kathmandu',
        startTime: DateTime(2024, 3, 12),
      );
      provider.journeys
        ..clear()
        ..add(open);

      // An endTime of null means "has not finished", not "finished on the day
      // it started".
      expect(provider.journeysEndingOn(DateTime(2024, 3, 12)), isEmpty);
      expect(provider.journeysStartingOn(DateTime(2024, 3, 12)), hasLength(1));
    });

    testWidgets('the sheet lists the day\'s journeys and transactions', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final day = DateTime(2024, 3, 12);
      final journeys = JourneyProvider();
      journeys.journeys.add(
        Journey(destination: 'Pokhara', origin: 'Kathmandu', startTime: day),
      );
      journeys.journeys.add(
        Journey(
          destination: 'Dhulikhel',
          origin: 'Kathmandu',
          startTime: DateTime(2024, 3, 20),
          endTime: day,
        ),
      );

      // Every Hive write runs in real async. A write begun inside the
      // fake-async zone of a testWidgets body never completes and leaves the
      // box write lock held, which deadlocks the file.
      final transactions = TransactionProvider();
      await tester.runAsync(() async {
        await transactions.loadTransactionsForMonth(2024, 3);
        await transactions.addTransaction(
          Expense(
            amount: 150,
            category: ExpenseCategory.food,
            description: 'Groceries',
            date: day,
          ),
        );
      });

      final settings = SettingsProvider();
      await tester.runAsync(() => settings.load());

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<JourneyProvider>.value(value: journeys),
            ChangeNotifierProvider<TransactionProvider>.value(
              value: transactions,
            ),
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Builder(
              builder: (context) => Scaffold(body: DayActivitySheet(day: day)),
            ),
          ),
        ),
      );
      await settleUi(tester);

      expect(find.text('12 March 2024'), findsOneWidget);
      expect(find.text('Started'), findsOneWidget);
      expect(find.text('Pokhara'), findsOneWidget);
      // The trip that finished that day is reported as ended, not started.
      expect(find.text('Ended'), findsOneWidget);
      expect(find.text('Dhulikhel'), findsOneWidget);
      expect(find.text('Transactions (1)'), findsOneWidget);
      expect(find.text('Groceries'), findsOneWidget);
    });

    testWidgets('an empty day says so rather than showing nothing', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final journeys = JourneyProvider();
      final transactions = TransactionProvider();
      final settings = SettingsProvider();
      await tester.runAsync(() => settings.load());

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<JourneyProvider>.value(value: journeys),
            ChangeNotifierProvider<TransactionProvider>.value(
              value: transactions,
            ),
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(body: DayActivitySheet(day: _someDay)),
          ),
        ),
      );
      await settleUi(tester);

      // A blank sheet is indistinguishable from a broken one.
      expect(find.text('Nothing recorded on this day.'), findsOneWidget);
    });
  });

  group('the summary stats open for detail', () {
    testWidgets('Trips lists every trip', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final journeys = JourneyProvider();
      journeys.journeys.addAll([
        Journey(
          destination: 'Pokhara',
          origin: 'Kathmandu',
          startTime: DateTime(2024, 3, 1),
        ),
        Journey(
          destination: 'Chitwan',
          origin: 'Kathmandu',
          startTime: DateTime(2024, 2, 1),
          endTime: DateTime(2024, 2, 4),
          completed: true,
        ),
      ]);

      await tester.pumpWidget(
        ChangeNotifierProvider<JourneyProvider>.value(
          value: journeys,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(
              body: JourneyStatSheet(stat: JourneyStat.trips),
            ),
          ),
        ),
      );
      await settleUi(tester);

      expect(find.text('All trips'), findsOneWidget);
      expect(find.text('2 recorded, newest first'), findsOneWidget);
      expect(find.text('Pokhara'), findsOneWidget);
      expect(find.text('Chitwan'), findsOneWidget);
    });

    testWidgets('Completed lists only finished trips', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final journeys = JourneyProvider();
      journeys.journeys.addAll([
        Journey(
          destination: 'Pokhara',
          origin: 'Kathmandu',
          startTime: DateTime(2024, 3, 1),
        ),
        Journey(
          destination: 'Chitwan',
          origin: 'Kathmandu',
          startTime: DateTime(2024, 2, 1),
          endTime: DateTime(2024, 2, 4),
          completed: true,
        ),
      ]);

      await tester.pumpWidget(
        ChangeNotifierProvider<JourneyProvider>.value(
          value: journeys,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(
              body: JourneyStatSheet(stat: JourneyStat.completed),
            ),
          ),
        ),
      );
      await settleUi(tester);

      expect(find.text('1 of 2 finished'), findsOneWidget);
      expect(find.text('Chitwan'), findsOneWidget);
      expect(
        find.text('Pokhara'),
        findsNothing,
        reason: 'an unfinished trip is not completed',
      );
    });

    testWidgets('Avg. time breaks the average down per trip', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final journeys = JourneyProvider();
      journeys.journeys.addAll([
        Journey(
          destination: 'Pokhara',
          origin: 'Kathmandu',
          startTime: DateTime(2024, 3, 1),
        ),
        Journey(
          destination: 'Chitwan',
          origin: 'Kathmandu',
          startTime: DateTime(2024, 2, 1, 8),
          endTime: DateTime(2024, 2, 1, 20),
          completed: true,
        ),
      ]);

      await tester.pumpWidget(
        ChangeNotifierProvider<JourneyProvider>.value(
          value: journeys,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(
              body: JourneyStatSheet(stat: JourneyStat.averageTime),
            ),
          ),
        ),
      );
      await settleUi(tester);

      expect(find.text('Average trip length'), findsOneWidget);
      expect(find.text('12h 0m'), findsOneWidget);
      // Only the finished trip has a length, so only it is itemised.
      expect(find.text('Chitwan'), findsOneWidget);
      expect(find.text('Pokhara'), findsNothing);
    });

    testWidgets('Packed shows the items per trip', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final journeys = JourneyProvider();
      journeys.journeys.add(
        Journey(
          destination: 'Pokhara',
          origin: 'Kathmandu',
          startTime: DateTime(2024, 3, 1),
          items: ['Boots', 'Jacket', 'Map', 'Torch', 'Rope'],
        ),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<JourneyProvider>.value(
          value: journeys,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(
              body: JourneyStatSheet(stat: JourneyStat.packed),
            ),
          ),
        ),
      );
      await settleUi(tester);

      expect(find.text('Items packed'), findsOneWidget);
      expect(find.text('5 across every trip'), findsOneWidget);
      expect(find.text('Pokhara'), findsOneWidget);
      // Long lists are abbreviated rather than pushing the sheet off screen.
      expect(find.textContaining('+1'), findsOneWidget);
    });

    testWidgets('an average with no finished trips explains itself', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final journeys = JourneyProvider();
      journeys.journeys.add(
        Journey(
          destination: 'Pokhara',
          origin: 'Kathmandu',
          startTime: DateTime(2024, 3, 1),
        ),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<JourneyProvider>.value(
          value: journeys,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(
              body: JourneyStatSheet(stat: JourneyStat.averageTime),
            ),
          ),
        ),
      );
      await settleUi(tester);

      // An unfinished trip has no length, so including it would be a fiction.
      expect(
        find.text('An average needs at least one finished trip.'),
        findsOneWidget,
      );
    });
  });
}
