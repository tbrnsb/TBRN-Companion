// Tristate is declared in dart:ui, not the flutter package.
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/checklist_provider.dart';
import 'package:flutter_application_1/providers/journey_provider.dart';
import 'package:flutter_application_1/providers/location_provider.dart';
import 'package:flutter_application_1/providers/settings_provider.dart';
import 'package:flutter_application_1/providers/transaction_provider.dart';
import 'package:flutter_application_1/screens/journeys/journey_detail_screen.dart';
import 'package:flutter_application_1/screens/journeys/trip_summary_screen.dart';
import 'package:flutter_application_1/screens/transactions/add_expense_sheet.dart';
import 'package:flutter_application_1/screens/transactions/transactions_screen.dart';
import 'package:flutter_application_1/screens/journeys/trip_import_sheet.dart';
import 'package:flutter_application_1/services/storage_service.dart';
import 'package:flutter_application_1/services/trip_snapshot.dart';
import 'package:flutter_application_1/theme/app_theme.dart';

import 'test_viewports.dart';
import 'visual_smoke_test.dart' show initTestStorage;

/// The trip the whole suite works with.
///
///   You   taxi 4000 + lunch 1500   = 5500
///   Raj   boat 3000 + dinner 2400  = 5400
///   Sita  groceries 2000 + museum  = 3000
///
/// 13900 across three people, which does not divide, so every assertion here
/// also proves the rounding behaves.
const _people = ['you', 'raj', 'sita'];
const _names = ['You', 'Raj', 'Sita'];

Journey _sharedTrip({String? localParticipantId, List<String>? settled}) {
  return Journey(
    id: 'trip-1',
    origin: 'Kathmandu',
    destination: 'Pokhara',
    startTime: DateTime.now().subtract(const Duration(days: 2)),
    participants: [
      for (var i = 0; i < _people.length; i++)
        TripParticipant(
          id: _people[i],
          name: _names[i],
          createdAt: DateTime(2026, 3, 1),
        ),
    ],
    localParticipantId: localParticipantId,
    settledTransfers: settled,
    tripCode: 'BK4J8Q',
  );
}

/// Expenses that add up to the worked example.
Future<void> _seedWorkingTrip({
  String? localParticipantId,
  List<String>? settled,
}) async {
  final storage = StorageService();
  await storage.addJourney(
    _sharedTrip(localParticipantId: localParticipantId, settled: settled),
  );

  const payments = [
    ('t1', 4000, 'you', 'Taxi'),
    ('t2', 1500, 'you', 'Lunch'),
    ('t3', 3000, 'raj', 'Boat'),
    ('t4', 2400, 'raj', 'Dinner'),
    ('t5', 2000, 'sita', 'Groceries'),
    ('t6', 1000, 'sita', 'Museum'),
  ];
  for (final (id, amount, payer, label) in payments) {
    await storage.addTransaction(
      Expense(
        id: id,
        amount: amount.toDouble(),
        category: ExpenseCategory.travel,
        description: label,
        journeyId: 'trip-1',
        paidByParticipantId: payer,
      ),
    );
  }
}

typedef _Providers = ({
  JourneyProvider journeys,
  TransactionProvider transactions,
  ChecklistProvider checklists,
  LocationProvider locations,
  SettingsProvider settings,
});

/// Loads providers from storage.
///
/// Everything runs inside `tester.runAsync`: Hive does real file IO, which cannot
/// complete in the fake-async zone of a `testWidgets` body, and a write started
/// there never finishes and holds the box lock. Same reason a test cannot tap a
/// save button here — saves are covered at the provider layer instead, and the
/// places that do it are marked.
Future<_Providers> _providers(WidgetTester tester) async {
  final p = (await tester.runAsync(() async {
    final journeys = JourneyProvider();
    final transactions = TransactionProvider();
    final checklists = ChecklistProvider();
    final locations = LocationProvider();
    final settings = SettingsProvider();
    await journeys.initialize();
    await transactions.initialize();
    await checklists.initialize();
    await locations.initialize();
    await settings.load();
    return (
      journeys: journeys,
      transactions: transactions,
      checklists: checklists,
      locations: locations,
      settings: settings,
    );
  }))!;

  // JourneyProvider.initialize starts a 1-minute periodic timer, which fails a
  // test as a pending timer if it is never cancelled.
  addTearDown(p.journeys.dispose);
  addTearDown(p.transactions.dispose);
  addTearDown(p.checklists.dispose);
  addTearDown(p.locations.dispose);
  return p;
}

Widget _app(_Providers p, Widget home) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<JourneyProvider>.value(value: p.journeys),
      ChangeNotifierProvider<TransactionProvider>.value(value: p.transactions),
      ChangeNotifierProvider<ChecklistProvider>.value(value: p.checklists),
      ChangeNotifierProvider<LocationProvider>.value(value: p.locations),
      ChangeNotifierProvider<SettingsProvider>.value(value: p.settings),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: home,
    ),
  );
}

/// A deliberately TALL viewport at the width of the phone being tested.
///
/// A lazy ListView disposes rows scrolled past, so a test that only scrolls
/// downwards can never find a disposed row again and reports a FALSE PASS. These
/// tests assert on content near the bottom of long screens, so the viewport is
/// made tall enough to lay all of it out. Narrowing is what the overflow check
/// needs; height buys reachability.
const _tallPhone = Size(360, 2800);
const _tallPortrait = Size(412, 2800);

Future<void> _settle(WidgetTester tester) async {
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
  });

  group('the shared section on journey detail', () {
    testWidgets('shows the roster, the totals and the way into the summary', (
      tester,
    ) async {
      usePhoneLayout(tester, _tallPhone);

      await tester.runAsync(() async {
        await StorageService().clear();
        await _seedWorkingTrip(localParticipantId: 'you');
      });
      final p = await _providers(tester);

      await tester.pumpWidget(
        _app(p, JourneyDetailScreen(journey: _sharedTrip())),
      );
      await _settle(tester);

      expect(find.text('Shared'), findsOneWidget);
      expect(find.text('3 people'), findsOneWidget);
      // Who-am-I, and the answer is already given.
      expect(find.text('Which one are you?'), findsOneWidget);
      // The trip code, prominent.
      expect(find.text('BK4J8Q'), findsOneWidget);
      // Per-person totals, with "paid" and "share" spelled out.
      expect(find.textContaining('paid Rs. 5,500'), findsOneWidget);
      expect(find.textContaining('share Rs. 4,633.34'), findsOneWidget);
      expect(find.byKey(const ValueKey('open-trip-summary')), findsOneWidget);
    });

    testWidgets('a solo trip shows no shared section at all', (tester) async {
      usePhoneLayout(tester, _tallPortrait);

      await tester.runAsync(() async {
        await StorageService().clear();
        await StorageService().addJourney(
          Journey(
            id: 'solo',
            origin: 'a',
            destination: 'b',
            startTime: DateTime.now().subtract(const Duration(days: 1)),
          ),
        );
      });
      final p = await _providers(tester);
      final solo = (await tester.runAsync(
        () => StorageService().getJourney('solo'),
      ))!;

      await tester.pumpWidget(_app(p, JourneyDetailScreen(journey: solo)));
      await _settle(tester);

      expect(find.text('Shared'), findsNothing);
      expect(find.text('Which one are you?'), findsNothing);
    });

    testWidgets('the current answer is marked on the right chip', (
      tester,
    ) async {
      usePhoneLayout(tester, _tallPhone);

      await tester.runAsync(() async {
        await StorageService().clear();
        await _seedWorkingTrip(localParticipantId: 'raj');
      });
      final p = await _providers(tester);

      await tester.pumpWidget(
        _app(p, JourneyDetailScreen(journey: _sharedTrip())),
      );
      await _settle(tester);

      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('who-am-i-raj')))
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('who-am-i-you')))
            .flagsCollection
            .isSelected,
        Tristate.isFalse,
      );
      // And the roster says so too, so the answer is visible without reading
      // chip selection.
      expect(find.text('You (you)'), findsNothing);
      expect(find.text('Raj (you)'), findsNothing);
    });
  });

  group('shared-trip writes, at the provider layer', () {
    // These three are here rather than as widget tests on purpose: a Hive write
    // started inside a testWidgets body deadlocks — it never completes and holds
    // the box lock — so a save button cannot be tapped. The widgets that call
    // these are covered above for what they show; what they SAVE is covered
    // here. A comment at each widget explains the same thing.
    test('choosing who you are persists, and is changeable', () async {
      await StorageService().clear();
      await _seedWorkingTrip();

      final journeys = JourneyProvider();
      await journeys.initialize();
      addTearDown(journeys.dispose);

      await journeys.setLocalParticipant('trip-1', 'raj');
      expect(
        (await StorageService().getJourney('trip-1'))!.localParticipantId,
        'raj',
      );

      // Changeable, because people get their own phone or correct a mistake.
      await journeys.setLocalParticipant('trip-1', 'sita');
      expect(
        (await StorageService().getJourney('trip-1'))!.localParticipantId,
        'sita',
      );

      // And clearable.
      await journeys.setLocalParticipant('trip-1', null);
      expect(
        (await StorageService().getJourney('trip-1'))!.localParticipantId,
        isNull,
      );
    });

    test('adding someone by name persists and appears on the roster', () async {
      await StorageService().clear();
      await _seedWorkingTrip();

      final journeys = JourneyProvider();
      await journeys.initialize();
      addTearDown(journeys.dispose);

      final added = await journeys.addParticipant('trip-1', 'Bikash');
      expect(added, isNotNull);

      final stored = await StorageService().getJourney('trip-1');
      expect(stored!.participants.map((e) => e.name), [
        'You',
        'Raj',
        'Sita',
        'Bikash',
      ]);
      expect(stored.isShared, isTrue);
    });

    test('a blank name adds nobody', () async {
      await StorageService().clear();
      await _seedWorkingTrip();

      final journeys = JourneyProvider();
      await journeys.initialize();
      addTearDown(journeys.dispose);

      expect(await journeys.addParticipant('trip-1', '   '), isNull);
      expect(
        (await StorageService().getJourney('trip-1'))!.participants,
        hasLength(3),
      );
    });

    test('two people with the same name are two people', () async {
      // A trip can have two Rajs. Silently merging them would hand one of them
      // the other's money, so the app does not try to be clever about names.
      await StorageService().clear();
      await _seedWorkingTrip();

      final journeys = JourneyProvider();
      await journeys.initialize();
      addTearDown(journeys.dispose);

      final first = await journeys.addParticipant('trip-1', 'Raj');
      final second = await journeys.addParticipant('trip-1', 'Raj');
      expect(first!.id, isNot(second!.id));
      expect(
        (await StorageService().getJourney('trip-1'))!.participants,
        hasLength(5),
        reason: 'two extra Rajs on top of the three already on the trip',
      );
    });

    test('the trip code is generated once and then left alone', () async {
      await StorageService().clear();
      await _seedWorkingTrip();

      final journeys = JourneyProvider();
      await journeys.initialize();
      addTearDown(journeys.dispose);

      // The seeded trip already has one.
      expect(await journeys.ensureTripCode('trip-1'), 'BK4J8Q');
      expect((await StorageService().getJourney('trip-1'))!.tripCode, 'BK4J8Q');
    });

    test('an expense saved for the user is attributed to them', () async {
      // The provider-level half of the add-expense "Paid by" field: what the
      // sheet passes down is what lands.
      await StorageService().clear();
      await _seedWorkingTrip(localParticipantId: 'you');

      final transactions = TransactionProvider();
      await transactions.initialize();
      addTearDown(transactions.dispose);

      expect(
        await transactions.addTransaction(
          Expense(
            id: 'new-1',
            amount: 250,
            category: ExpenseCategory.food,
            description: 'Tea',
            journeyId: 'trip-1',
            paidByParticipantId: 'you',
          ),
        ),
        isTrue,
      );

      final stored = await StorageService().getTransactionsByJourney('trip-1');
      expect(
        stored.firstWhere((e) => e.id == 'new-1').paidByParticipantId,
        'you',
      );
    });
  });

  group('the trip summary', () {
    Future<void> open(WidgetTester tester, _Providers p) async {
      await tester.pumpWidget(
        _app(p, const TripSummaryScreen(journeyId: 'trip-1')),
      );
      await _settle(tester);
    }

    testWidgets('the headline says the total, the people and the count', (
      tester,
    ) async {
      usePhoneLayout(tester, _tallPhone);

      await tester.runAsync(() async {
        await StorageService().clear();
        await _seedWorkingTrip(localParticipantId: 'you');
      });
      final p = await _providers(tester);
      await open(tester, p);

      expect(find.text('Rs. 13,900'), findsOneWidget);
      expect(find.text('spent · 3 people'), findsOneWidget);
    });

    testWidgets('two transfers, and both are readable', (tester) async {
      usePhoneLayout(tester, _tallPhone);

      await tester.runAsync(() async {
        await StorageService().clear();
        await _seedWorkingTrip(localParticipantId: 'you');
      });
      final p = await _providers(tester);
      await open(tester, p);

      expect(find.text('Sita pays You'), findsOneWidget);
      expect(find.text('Sita pays Raj'), findsOneWidget);
      expect(find.text('Rs. 866.66'), findsOneWidget);
      expect(find.text('Rs. 766.67'), findsOneWidget);
      expect(find.text('2 payments'), findsOneWidget);
    });

    testWidgets('the settlement is explained in prose, not just listed', (
      tester,
    ) async {
      usePhoneLayout(tester, _tallPhone);

      await tester.runAsync(() async {
        await StorageService().clear();
        await _seedWorkingTrip(localParticipantId: 'you');
      });
      final p = await _providers(tester);
      await open(tester, p);

      // A sentence a person could read out to the table.
      expect(
        find.textContaining('You are owed Rs. 866.66 in total'),
        findsOneWidget,
      );
      expect(
        find.textContaining('2 payments settle everything'),
        findsOneWidget,
      );
    });

    testWidgets('before who-am-I is answered it says so, not a wrong number', (
      tester,
    ) async {
      usePhoneLayout(tester, _tallPhone);

      await tester.runAsync(() async {
        await StorageService().clear();
        await _seedWorkingTrip();
      });
      final p = await _providers(tester);
      await open(tester, p);

      expect(
        find.textContaining('Tell the app which one you are'),
        findsOneWidget,
      );
      expect(find.textContaining('You are owed'), findsNothing);
    });

    testWidgets('a trip where everyone is even says so and lists nothing', (
      tester,
    ) async {
      usePhoneLayout(tester, _tallPhone);

      await tester.runAsync(() async {
        await StorageService().clear();
        await StorageService().addJourney(
          _sharedTrip(localParticipantId: 'you'),
        );
        for (final (id, payer) in [('a', 'you'), ('b', 'raj'), ('c', 'sita')]) {
          await StorageService().addTransaction(
            Expense(
              id: id,
              amount: 100,
              category: ExpenseCategory.food,
              description: 'x',
              journeyId: 'trip-1',
              paidByParticipantId: payer,
            ),
          );
        }
      });
      final p = await _providers(tester);
      await open(tester, p);

      expect(
        find.text('Everyone is even. Nothing left to pay.'),
        findsOneWidget,
      );
      expect(find.byType(Checkbox), findsNothing);
      expect(find.textContaining('settle everything'), findsNothing);
      expect(find.text('Nothing to settle'), findsOneWidget);
    });
  });

  group('ticking a transfer', () {
    // The taps here are covered at the provider layer, not by tapping widgets:
    // a Hive write started inside a testWidgets body deadlocks — it never
    // completes and holds the box lock — so no save can be driven from a tap.
    // What this group proves is that the summary SHOWS the state correctly once
    // the ticks exist.
    testWidgets('ticked payments render as ticked', (tester) async {
      usePhoneLayout(tester, _tallPhone);

      await tester.runAsync(() async {
        await StorageService().clear();
        await _seedWorkingTrip(
          localParticipantId: 'sita',
          settled: const ['sita>you:86666'],
        );
      });
      final p = await _providers(tester);

      await tester.pumpWidget(
        _app(p, const TripSummaryScreen(journeyId: 'trip-1')),
      );
      await _settle(tester);

      final ticked = tester.widget<Checkbox>(
        find.byKey(const ValueKey('transfer-tick-sita>you:86666')),
      );
      final unticked = tester.widget<Checkbox>(
        find.byKey(const ValueKey('transfer-tick-sita>raj:76667')),
      );
      expect(ticked.value, isTrue);
      expect(unticked.value, isFalse);
    });

    testWidgets('an already-settled trip still shows every row', (
      tester,
    ) async {
      usePhoneLayout(tester, _tallPhone);

      await tester.runAsync(() async {
        await StorageService().clear();
        await _seedWorkingTrip(
          localParticipantId: 'sita',
          settled: const ['sita>you:86666', 'sita>raj:76667'],
        );
      });
      final p = await _providers(tester);

      await tester.pumpWidget(
        _app(p, const TripSummaryScreen(journeyId: 'trip-1')),
      );
      await _settle(tester);

      // The rows stay visible and ticked — hiding them would make "Reopen"
      // meaningless — and the button offers to undo rather than to settle.
      expect(find.byType(Checkbox), findsNWidgets(2));
      expect(find.text('Sita pays You'), findsOneWidget);
      expect(find.text('Sita pays Raj'), findsOneWidget);
      expect(find.text('Reopen'), findsOneWidget);
    });
  });

  group('ticking a payment, at the provider layer', () {
    // THE REGRESSION GUARD.
    //
    // A reimbursement is money coming back for money already spent. If ticking a
    // settled payment also wrote an Income transaction, income would be inflated
    // by a transfer that never happened, the balance would be wrong, and every
    // chart and every budget would inherit it — while the original expense STILL
    // counted in full, so the amount would be double. Nothing else in the suite
    // would catch that.
    test('records the key and writes NO transaction', () async {
      await StorageService().clear();
      await _seedWorkingTrip(localParticipantId: 'sita');

      final journeys = JourneyProvider();
      await journeys.initialize();
      addTearDown(journeys.dispose);

      final before = await StorageService().getAllTransactions();
      expect(before, hasLength(6));

      final settlement = await journeys.tripSettlement('trip-1');
      expect(settlement.transfers, hasLength(2));
      final key = settlement.transfers.first.key;

      await journeys.toggleTransferSettled('trip-1', key);

      expect((await StorageService().getJourney('trip-1'))!.settledTransfers, [
        key,
      ]);

      final after = await StorageService().getAllTransactions();
      expect(
        after,
        hasLength(6),
        reason: 'a tick must not write a transaction',
      );
      expect(after.whereType<Income>(), isEmpty);

      // And the expense is still counted in full: nothing was written off.
      final recomputed = await journeys.tripSettlement('trip-1');
      expect(recomputed.total, 13900);
      expect(recomputed.balances.length, 3);
    });

    test('the same key twice is a tick and then an untick', () async {
      await StorageService().clear();
      await _seedWorkingTrip(localParticipantId: 'sita');

      final journeys = JourneyProvider();
      await journeys.initialize();
      addTearDown(journeys.dispose);

      final key = (await journeys.tripSettlement('trip-1')).transfers.first.key;

      await journeys.toggleTransferSettled('trip-1', key);
      expect(
        journeys.isTransferSettled(
          (await StorageService().getJourney('trip-1'))!,
          key,
        ),
        isTrue,
      );

      await journeys.toggleTransferSettled('trip-1', key);
      expect(
        (await StorageService().getJourney('trip-1'))!.settledTransfers,
        isEmpty,
      );
    });

    test('ticks survive a recompute of the settlement', () async {
      // The whole reason a tick is a KEY rather than a row: the settlement is
      // recomputed from the expenses every time the screen opens.
      await StorageService().clear();
      await _seedWorkingTrip(localParticipantId: 'sita');

      final journeys = JourneyProvider();
      await journeys.initialize();
      addTearDown(journeys.dispose);

      final before = await journeys.tripSettlement('trip-1');
      await journeys.toggleTransferSettled(
        'trip-1',
        before.transfers.first.key,
      );

      final after = await journeys.tripSettlement('trip-1');
      expect(
        after.transfers.map((t) => t.key),
        before.transfers.map((t) => t.key),
        reason: 'an unchanged trip settles to exactly the same keys',
      );

      // Adding an expense changes the amounts, so an old key stops matching —
      // which is honest: that payment's amount has genuinely changed.
      await StorageService().addTransaction(
        Expense(
          id: 'extra',
          amount: 500,
          category: ExpenseCategory.food,
          description: 'Snacks',
          journeyId: 'trip-1',
          paidByParticipantId: 'sita',
        ),
      );
      final changed = await journeys.tripSettlement('trip-1');
      expect(
        changed.transfers.map((t) => t.key),
        isNot(before.transfers.map((t) => t.key)),
      );
    });

    test('"we\'re even" records every key and writes no transaction', () async {
      await StorageService().clear();
      await _seedWorkingTrip(localParticipantId: 'sita');

      final journeys = JourneyProvider();
      await journeys.initialize();
      addTearDown(journeys.dispose);

      await journeys.markWholeTripSettled('trip-1');

      final journey = await StorageService().getJourney('trip-1');
      final settlement = await journeys.tripSettlement('trip-1');
      expect(
        journey!.settledTransfers.toSet(),
        settlement.transfers.map((t) => t.key).toSet(),
      );
      expect(await StorageService().getAllTransactions(), hasLength(6));
    });

    test('"we\'re even" twice does not duplicate the keys', () async {
      await StorageService().clear();
      await _seedWorkingTrip(localParticipantId: 'sita');

      final journeys = JourneyProvider();
      await journeys.initialize();
      addTearDown(journeys.dispose);

      await journeys.markWholeTripSettled('trip-1');
      await journeys.markWholeTripSettled('trip-1');

      expect(
        (await StorageService().getJourney('trip-1'))!.settledTransfers,
        hasLength(2),
      );
    });

    test('reopening puts everything back outstanding', () async {
      await StorageService().clear();
      await _seedWorkingTrip(localParticipantId: 'sita');

      final journeys = JourneyProvider();
      await journeys.initialize();
      addTearDown(journeys.dispose);

      await journeys.markWholeTripSettled('trip-1');
      await journeys.clearSettledTransfers('trip-1');

      final journey = await StorageService().getJourney('trip-1');
      expect(journey!.settledTransfers, isEmpty);
      expect(await journeys.outstandingAcrossTrips(), hasLength(1));
    });

    test('a settled trip stops showing on the Transactions card', () async {
      await StorageService().clear();
      await _seedWorkingTrip(localParticipantId: 'sita');

      final journeys = JourneyProvider();
      await journeys.initialize();
      addTearDown(journeys.dispose);

      expect(await journeys.outstandingAcrossTrips(), hasLength(1));
      await journeys.markWholeTripSettled('trip-1');
      expect(await journeys.outstandingAcrossTrips(), isEmpty);
    });

    test('one person paid everything: they are owed the whole trip', () async {
      await StorageService().clear();
      await StorageService().addJourney(_sharedTrip(localParticipantId: 'you'));
      await StorageService().addTransaction(
        Expense(
          id: 'all',
          amount: 900,
          category: ExpenseCategory.travel,
          description: 'Everything',
          journeyId: 'trip-1',
          paidByParticipantId: 'you',
        ),
      );

      final journeys = JourneyProvider();
      await journeys.initialize();
      addTearDown(journeys.dispose);

      final outstanding = await journeys.outstandingAcrossTrips();
      expect(outstanding, hasLength(1));
      expect(outstanding.single.localIsOwed, isTrue);
      expect(outstanding.single.localNet, 600);
      expect(outstanding.single.remainingTransfers, hasLength(2));
    });
  });

  group('the Transactions card', () {
    testWidgets('appears when a shared trip still owes money', (tester) async {
      usePhoneLayout(tester, _tallPortrait);

      await tester.runAsync(() async {
        await StorageService().clear();
        await _seedWorkingTrip(localParticipantId: 'sita');
      });
      final p = await _providers(tester);

      await tester.pumpWidget(_app(p, const TransactionsScreen()));
      await _settle(tester);

      expect(find.byKey(const ValueKey('outstanding-trip-1')), findsOneWidget);
      expect(find.textContaining('you owe Rs.'), findsOneWidget);
      expect(find.textContaining('2 payments left'), findsOneWidget);
    });

    testWidgets('says what you are owed, not what you owe', (tester) async {
      usePhoneLayout(tester, _tallPortrait);

      await tester.runAsync(() async {
        await StorageService().clear();
        await _seedWorkingTrip(localParticipantId: 'you');
      });
      final p = await _providers(tester);

      await tester.pumpWidget(_app(p, const TransactionsScreen()));
      await _settle(tester);

      expect(find.textContaining('you get Rs. 866.66 back'), findsOneWidget);
    });

    testWidgets('is hidden entirely when nothing is outstanding', (
      tester,
    ) async {
      // A card that always reads "everyone is even" is noise, and a permanently
      // visible one trains the eye to skip it.
      usePhoneLayout(tester, _tallPortrait);

      await tester.runAsync(() async {
        await StorageService().clear();
        await _seedWorkingTrip(localParticipantId: 'sita');
      });
      final p = await _providers(tester);

      await tester.pumpWidget(_app(p, const TransactionsScreen()));
      await _settle(tester);
      expect(find.byKey(const ValueKey('outstanding-trip-1')), findsOneWidget);

      await tester.runAsync(() => p.journeys.markWholeTripSettled('trip-1'));
      await tester.pumpWidget(_app(p, const TransactionsScreen()));
      await _settle(tester);

      expect(find.byKey(const ValueKey('outstanding-trip-1')), findsNothing);
    });

    testWidgets('a personal trip never produces one', (tester) async {
      usePhoneLayout(tester, _tallPortrait);

      await tester.runAsync(() async {
        await StorageService().clear();
        await StorageService().addJourney(
          Journey(id: 'solo', origin: 'a', destination: 'b'),
        );
        await StorageService().addTransaction(
          Expense(
            id: 'x',
            amount: 100,
            category: ExpenseCategory.food,
            description: 'tea',
            journeyId: 'solo',
          ),
        );
      });
      final p = await _providers(tester);

      await tester.pumpWidget(_app(p, const TransactionsScreen()));
      await _settle(tester);

      expect(find.textContaining('payments left'), findsNothing);
    });
  });

  group('the add-expense sheet on a shared trip', () {
    Future<void> openSheet(WidgetTester tester, _Providers p) async {
      await tester.pumpWidget(
        _app(
          p,
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () =>
                      AddExpenseSheet.show(context, initialJourneyId: 'trip-1'),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
      await tester.tap(find.text('open'));
      await _settle(tester);
    }

    testWidgets('offers "Paid by" and starts on you', (tester) async {
      usePhoneLayout(tester, _tallPortrait);

      await tester.runAsync(() async {
        await StorageService().clear();
        await _seedWorkingTrip(localParticipantId: 'you');
      });
      final p = await _providers(tester);

      await openSheet(tester, p);

      expect(find.text('Paid by'), findsOneWidget);
      expect(find.text('You (you)'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('paid-by-you')))
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
    });

    testWidgets('another person can be chosen', (tester) async {
      usePhoneLayout(tester, _tallPortrait);

      await tester.runAsync(() async {
        await StorageService().clear();
        await _seedWorkingTrip(localParticipantId: 'you');
      });
      final p = await _providers(tester);

      await openSheet(tester, p);

      await tester.tap(find.byKey(const ValueKey('paid-by-raj')));
      await _settle(tester);

      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('paid-by-raj')))
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('paid-by-you')))
            .flagsCollection
            .isSelected,
        Tristate.isFalse,
      );
    });

    testWidgets('a personal trip does not ask at all', (tester) async {
      usePhoneLayout(tester, _tallPortrait);

      await tester.runAsync(() async {
        await StorageService().clear();
        await StorageService().addJourney(
          Journey(
            id: 'solo',
            origin: 'a',
            destination: 'b',
            startTime: DateTime.now().subtract(const Duration(days: 1)),
          ),
        );
      });
      final p = await _providers(tester);

      await tester.pumpWidget(
        _app(
          p,
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () =>
                      AddExpenseSheet.show(context, initialJourneyId: 'solo'),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
      await tester.tap(find.text('open'));
      await _settle(tester);

      expect(find.text('Paid by'), findsNothing);
    });
  });

  group('the import flow', () {
    TripSnapshot snapshotFromRaj() {
      return TripSnapshot.fromJourney(
        journey: _sharedTrip(),
        expenses: [
          Expense(
            id: 'r1',
            amount: 4000,
            category: ExpenseCategory.travel,
            description: 'Taxi',
            journeyId: 'trip-1',
            paidByParticipantId: 'raj',
          ),
          Expense(
            id: 'r2',
            amount: 3000,
            category: ExpenseCategory.food,
            description: 'Dinner',
            journeyId: 'trip-1',
            paidByParticipantId: 'raj',
          ),
        ],
        exportedBy: 'Raj',
      );
    }

    Future<void> preview(
      WidgetTester tester,
      TripSnapshot snapshot,
      _Providers providers,
    ) async {
      await tester.pumpWidget(
        _app(
          providers,
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showTripImportPreview(context, snapshot),
                  child: const Text('preview'),
                ),
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
      await tester.tap(find.text('preview'));
      await _settle(tester);
    }

    testWidgets('previews the whole file before anything is written', (
      tester,
    ) async {
      usePhoneLayout(tester, _tallPortrait);

      await tester.runAsync(() async {
        await StorageService().clear();
        await _seedWorkingTrip(localParticipantId: 'you');
      });
      final p = await _providers(tester);

      await preview(tester, snapshotFromRaj(), p);

      // Trip name, who sent it, how many people, how many expenses, the total.
      expect(find.text('Check before importing'), findsOneWidget);
      expect(find.text('Pokhara'), findsOneWidget);
      expect(find.text('Raj'), findsWidgets);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Rs. 7,000'), findsOneWidget);
      expect(find.textContaining('Nothing has been added yet'), findsOneWidget);

      // And nothing has been written.
      expect(
        await tester.runAsync(() => StorageService().getAllTransactions()),
        hasLength(6),
      );
    });

    testWidgets('cannot be confirmed until you say who you are', (
      tester,
    ) async {
      usePhoneLayout(tester, _tallPortrait);

      await tester.runAsync(() async {
        await StorageService().clear();
        await _seedWorkingTrip(localParticipantId: 'you');
      });
      final p = await _providers(tester);

      await preview(tester, snapshotFromRaj(), p);

      // The question is asked, and the button is dead until it is answered.
      // There is no safe default: guessing would put a confident wrong number
      // on screen, which is the one answer this flow must never give.
      expect(find.text('Which one are you?'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('import-confirm')),
      );
      expect(button.onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('import-who-sita')));
      await _settle(tester);

      final after = tester.widget<FilledButton>(
        find.byKey(const ValueKey('import-confirm')),
      );
      expect(after.onPressed, isNotNull);

      // The file records who PAID, not who is reading — and the local trip
      // already had an answer, which import must not overwrite.
      expect(
        (await tester.runAsync(() => StorageService().getJourney('trip-1')))!
            .localParticipantId,
        'you',
      );
    });

    testWidgets('cancelling writes nothing at all', (tester) async {
      usePhoneLayout(tester, _tallPortrait);

      await tester.runAsync(() async {
        await StorageService().clear();
        await _seedWorkingTrip(localParticipantId: 'you');
      });
      final p = await _providers(tester);

      await preview(tester, snapshotFromRaj(), p);
      await tester.tap(find.text('Cancel'));
      await _settle(tester);

      expect(find.text('Check before importing'), findsNothing);
      expect(
        await tester.runAsync(() => StorageService().getAllTransactions()),
        hasLength(6),
      );
    });

    testWidgets('says what it will and will not do before importing', (
      tester,
    ) async {
      usePhoneLayout(tester, _tallPortrait);

      await tester.runAsync(() async {
        await StorageService().clear();
        await _seedWorkingTrip(localParticipantId: 'you');
      });
      final p = await _providers(tester);

      await preview(tester, snapshotFromRaj(), p);

      expect(find.textContaining('Importing only adds'), findsOneWidget);
      expect(find.textContaining('anything you deleted'), findsOneWidget);
    });
  });

  group('at 360dp, the tightest phone', () {
    testWidgets('the shared section fits without overflowing', (tester) async {
      usePhoneLayout(
        tester,
        _tallPhone,
        because: 'four names plus three amounts is the widest this screen gets',
      );

      await tester.runAsync(() async {
        await StorageService().clear();
        await _seedWorkingTrip(localParticipantId: 'you');
      });
      final p = await _providers(tester);

      await tester.pumpWidget(
        _app(p, JourneyDetailScreen(journey: _sharedTrip())),
      );
      await _settle(tester);

      expect(find.byKey(const ValueKey('open-trip-summary')), findsOneWidget);
    });

    testWidgets('the summary fits without overflowing', (tester) async {
      usePhoneLayout(tester, _tallPhone);

      await tester.runAsync(() async {
        await StorageService().clear();
        await _seedWorkingTrip(localParticipantId: 'you');
      });
      final p = await _providers(tester);

      await tester.pumpWidget(
        _app(p, const TripSummaryScreen(journeyId: 'trip-1')),
      );
      await _settle(tester);

      expect(find.text('Sita pays You'), findsOneWidget);
    });

    testWidgets('four people on the summary fits too', (tester) async {
      usePhoneLayout(tester, _tallPhone);

      await tester.runAsync(() async {
        await StorageService().clear();
        await _seedWorkingTrip(localParticipantId: 'you');
      });
      final p = await _providers(tester);

      // A fourth person who has paid nothing. They still owe their share, so
      // they turn what was two payments into three — the widest this screen
      // gets.
      await tester.runAsync(
        () => p.journeys.addParticipant('trip-1', 'Bikash'),
      );

      await tester.pumpWidget(
        _app(p, const TripSummaryScreen(journeyId: 'trip-1')),
      );
      await _settle(tester);

      expect(find.byType(Checkbox), findsNWidgets(3));
    });

    testWidgets('the Transactions card fits', (tester) async {
      usePhoneLayout(tester, _tallPhone);

      await tester.runAsync(() async {
        await StorageService().clear();
        await _seedWorkingTrip(localParticipantId: 'sita');
      });
      final p = await _providers(tester);

      await tester.pumpWidget(_app(p, const TransactionsScreen()));
      await _settle(tester);

      expect(find.byKey(const ValueKey('outstanding-trip-1')), findsOneWidget);
    });

    testWidgets('the add-expense payer row fits', (tester) async {
      usePhoneLayout(tester, _tallPhone);

      await tester.runAsync(() async {
        await StorageService().clear();
        await _seedWorkingTrip(localParticipantId: 'you');
      });
      final p = await _providers(tester);

      await tester.pumpWidget(
        _app(
          p,
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () =>
                      AddExpenseSheet.show(context, initialJourneyId: 'trip-1'),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
      await tester.tap(find.text('open'));
      await _settle(tester);

      expect(find.byKey(const ValueKey('paid-by-you')), findsOneWidget);
    });
  });
}
