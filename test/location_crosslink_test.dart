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
import 'package:daily_companion/screens/locations/location_detail_screen.dart';
import 'package:daily_companion/services/storage_service.dart';
import 'package:daily_companion/screens/journeys/journey_detail_screen.dart';
import 'package:daily_companion/screens/transactions/expense_detail_screen.dart';
import 'package:daily_companion/theme/app_theme.dart';
import 'package:daily_companion/widgets/transaction_location_block.dart';

import 'visual_smoke_test.dart' show initTestStorage;
import 'test_viewports.dart';

/// The links between a transaction, the place it happened at, and the trip it
/// was on — plus what a saved place can tell you about itself.
void main() {
  setUpAll(() async {
    await initTestStorage();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService().clear();
  });

  Location place({String id = 'home', String name = 'Home'}) => Location(
    id: id,
    name: name,
    latitude: 27.7100,
    longitude: 85.3000,
    description: 'Where I live',
    icon: 'home',
  );

  Journey trip({String id = 'trip-1', String to = 'Pokhara'}) => Journey(
    id: id,
    destination: to,
    origin: 'Kathmandu',
    startTime: DateTime(2026, 10, 1),
  );

  /// The block on its own, which is how both detail screens actually use it.
  ///
  /// Locations and journeys go in through STORAGE and the providers' own
  /// `initialize`, not through a hand-filled list. A test that sets the provider's
  /// state itself is testing a registry it filled by hand — the wiring between
  /// what was written and what gets drawn is the part that actually breaks.
  Future<void> pumpBlock(
    WidgetTester tester,
    Transaction transaction, {
    List<Location> locations = const [],
    List<Journey> journeys = const [],
  }) async {
    final locationProvider = (await tester.runAsync(() async {
      final storage = StorageService();
      for (final location in locations) {
        await storage.addLocation(location);
      }
      final provider = LocationProvider();
      await provider.initialize();
      return provider;
    }))!;

    final journeyProvider = (await tester.runAsync(() async {
      final storage = StorageService();
      for (final journey in journeys) {
        await storage.addJourney(journey);
      }
      final provider = JourneyProvider();
      // initialize() starts a periodic reminder timer, which fails a widget test
      // for a pending timer. Loading is what this test needs.
      await provider.loadJourneys();
      addTearDown(provider.dispose);
      return provider;
    }))!;

    final transactionProvider = (await tester.runAsync(() async {
      final p = TransactionProvider();
      await p.initialize();
      return p;
    }))!;

    final settings = (await tester.runAsync(() async {
      final s = SettingsProvider();
      await s.load();
      return s;
    }))!;

    // The full set, because tapping a place navigates to LocationDetailScreen,
    // which reads the transaction, settings and journey providers. Asserting on a
    // screen that cannot open is not the same as asserting that it does.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LocationProvider>.value(
            value: locationProvider,
          ),
          ChangeNotifierProvider<JourneyProvider>.value(value: journeyProvider),
          ChangeNotifierProvider<TransactionProvider>.value(
            value: transactionProvider,
          ),
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          // JourneyDetailScreen reads the checklist provider too — a trip's
          // packing list is part of it.
          ChangeNotifierProvider(create: (_) => ChecklistProvider()),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TransactionLocationBlock(transaction: transaction),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('a transaction points at where it happened', () {
    testWidgets('the place name is tappable and opens the place', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final expense = Expense(
        amount: 500,
        category: ExpenseCategory.food,
        description: 'Dinner',
        locationId: 'home',
        latitude: 27.7100,
        longitude: 85.3000,
        locationCapturedAt: DateTime(2026, 10, 4, 20, 15),
        date: DateTime(2026, 10, 4),
      );
      await pumpBlock(tester, expense, locations: [place()]);

      expect(find.text('Home'), findsOneWidget);

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();

      // The place's OWN screen, with its counts and history.
      expect(find.byType(LocationDetailScreen), findsOneWidget);
      expect(find.text('Transactions'), findsOneWidget);
    });

    testWidgets('INCOME gets the identical place link', (tester) async {
      // The gap: income recorded no location, so it had no place row to tap at
      // all. Both directions now go through this one widget.
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final income = Income(
        amount: 5000,
        category: 'salary',
        description: 'Payday',
        locationId: 'home',
        latitude: 27.7100,
        longitude: 85.3000,
        locationCapturedAt: DateTime(2026, 10, 4, 9),
        date: DateTime(2026, 10, 4),
      );
      await pumpBlock(tester, income, locations: [place()]);

      expect(find.text('Home'), findsOneWidget);
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.byType(LocationDetailScreen), findsOneWidget);
    });

    testWidgets('a journey tag opens the journey', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final expense = Expense(
        amount: 1200,
        category: ExpenseCategory.travel,
        description: 'Bus',
        journeyId: 'trip-1',
        date: DateTime(2026, 10, 4),
      );

      await pumpBlock(tester, expense, journeys: [trip()]);

      await tester.tap(find.text('Pokhara'));
      await tester.pumpAndSettle();

      // The journey's own screen. Asserted on the TYPE rather than its text,
      // because what a journey screen leads with is its business, not this
      // link's — the claim under test is that the tap arrives.
      expect(find.byType(JourneyDetailScreen), findsOneWidget);
    });

    testWidgets('a dangling journey id shows nothing rather than a blank', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      // A trip deleted after the expense was logged. An empty "Journey" row
      // would be worse than none.
      final expense = Expense(
        amount: 100,
        category: ExpenseCategory.food,
        description: 'Old trip expense',
        journeyId: 'deleted-trip',
        date: DateTime(2026, 10, 4),
      );
      await pumpBlock(tester, expense);

      expect(find.text('Journey'), findsNothing);
    });
  });

  group('a saved place answers for itself', () {
    /// The place screen with [transactions] already linked to it.
    Future<void> pumpPlace(
      WidgetTester tester,
      Location location,
      List<Transaction> transactions,
    ) async {
      final provider = (await tester.runAsync(() async {
        final p = TransactionProvider();
        await p.initialize();
        for (final t in transactions) {
          await p.addTransaction(t);
        }
        return p;
      }))!;

      final settings = (await tester.runAsync(() async {
        final s = SettingsProvider();
        await s.load();
        return s;
      }))!;

      final locations = (await tester.runAsync(() async {
        await StorageService().addLocation(location);
        final l = LocationProvider();
        await l.initialize();
        return l;
      }))!;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TransactionProvider>.value(value: provider),
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
            ChangeNotifierProvider<LocationProvider>.value(value: locations),
            ChangeNotifierProvider(create: (_) => JourneyProvider()),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: LocationDetailScreen(location: location),
          ),
        ),
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Expense spend(double amount, String what, {int day = 1}) => Expense(
      amount: amount,
      category: ExpenseCategory.food,
      description: what,
      locationId: 'home',
      latitude: 27.7100,
      longitude: 85.3000,
      date: DateTime(2026, 10, day),
    );

    testWidgets('it counts the transactions and totals the money', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      await pumpPlace(tester, place(), [
        spend(500, 'Dinner', day: 1),
        spend(250, 'Lunch', day: 2),
        spend(1200, 'Groceries', day: 3),
      ]);

      // The answer to "is this place worth keeping", which was impossible to get
      // before this screen existed.
      expect(find.text('3'), findsWidgets);
      expect(find.text('Spent here'), findsOneWidget);
      // Twice on purpose: once as the headline total and once as the single
      // category row beneath it. One match would mean the other is missing.
      expect(find.textContaining('1950'), findsNWidgets(2));
    });

    testWidgets('it lists the history, most recent first', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      await pumpPlace(tester, place(), [
        spend(500, 'Dinner', day: 1),
        spend(250, 'Lunch', day: 3),
      ]);

      expect(find.text('Lunch'), findsOneWidget);
      expect(find.text('Dinner'), findsOneWidget);
      // Newest at the top of a list.
      final lunchY = tester.getTopLeft(find.text('Lunch')).dy;
      final dinnerY = tester.getTopLeft(find.text('Dinner')).dy;
      expect(lunchY, lessThan(dinnerY));
    });

    testWidgets('it breaks the place down by category', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      await pumpPlace(tester, place(), [
        spend(500, 'Dinner', day: 1),
        Expense(
          amount: 300,
          category: ExpenseCategory.travel,
          description: 'Rickshaw',
          locationId: 'home',
          date: DateTime(2026, 10, 2),
        ),
      ]);

      expect(find.text('Breakdown'), findsOneWidget);
      expect(find.text('Food'), findsOneWidget);
    });

    testWidgets('income at the place is counted too', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      await pumpPlace(tester, place(), [
        Income(
          amount: 5000,
          category: 'salary',
          description: 'Payday',
          locationId: 'home',
          date: DateTime(2026, 10, 1),
        ),
      ]);

      expect(find.text('Received here'), findsOneWidget);
      // Three times: the "Received here" stat, the category row in the
      // breakdown, and the transaction itself in the history. All three are the
      // same fact shown at three levels of detail.
      expect(find.textContaining('5000'), findsNWidgets(3));
    });

    testWidgets('a place with nothing on it says so and explains the radius', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      await pumpPlace(tester, place(), const []);

      expect(find.text('Nothing recorded yet'), findsOneWidget);
      // The radius is stated, because it is the rule the place applies to every
      // future transaction.
      expect(find.textContaining('50 m'), findsWidgets);
    });

    testWidgets('a transaction in the history opens it', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      await pumpPlace(tester, place(), [spend(500, 'Dinner')]);

      await tester.tap(find.text('Dinner'));
      await tester.pumpAndSettle();

      expect(find.byType(ExpenseDetailScreen), findsOneWidget);
    });
  });
}
