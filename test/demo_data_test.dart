import 'package:flutter_test/flutter_test.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/providers/transaction_provider.dart';
import 'package:daily_companion/services/demo_data_service.dart';
import 'package:daily_companion/providers/journey_provider.dart';
import 'package:daily_companion/services/storage_service.dart';

import 'visual_smoke_test.dart' show initTestStorage;

/// A record the user made, in every section, to prove the demo clear never
/// touches them.
Future<void> _seedRealData() async {
  final storage = StorageService();

  final checklist = Checklist(name: 'My real pack', description: '');
  await storage.addChecklist(checklist);
  await storage.addChecklistItem(
    ChecklistItem(name: 'My own boots', checklistId: checklist.id),
  );

  final place = Location(
    name: 'My own place',
    latitude: 27.7,
    longitude: 85.3,
    description: '',
  );
  await storage.addLocation(place);
  await storage.addLocationLog(
    LocationLog(locationId: place.id, arrivalTime: DateTime.now()),
  );

  await storage.addJourney(
    Journey(destination: 'My own trip', origin: 'My own home'),
  );
  await storage.addTransaction(
    Expense(
      amount: 42,
      category: ExpenseCategory.food,
      description: 'My own lunch',
    ),
  );
  await storage.addTransaction(
    Income(amount: 900, category: 'salary', description: 'My own pay'),
  );
}

/// Counts for every box, so "back to the pre-seed state" can be asserted
/// exactly rather than by a proxy.
Future<StorageCounts> _counts() => StorageService().getStorageCounts();

void main() {
  setUpAll(() async {
    await initTestStorage();
  });

  setUp(() async {
    await StorageService().clear();
  });

  group('demo identity', () {
    test('every seeded id is recognisable as demo data', () {
      expect(DemoDataService.isDemoId('demo-abc'), isTrue);
      expect(DemoDataService.isDemoId('a1b2c3'), isFalse);
      expect(DemoDataService.isDemoId(null), isFalse);
      expect(DemoDataService.newId(), startsWith(DemoDataService.idPrefix));
    });
  });

  group('seeding covers the whole app', () {
    test('one action adds records to all four sections', () async {
      await DemoDataService.seedAll();

      final storage = StorageService();
      expect(await storage.getAllChecklists(), isNotEmpty);
      expect(await storage.getAllJourneys(), isNotEmpty);
      expect(await storage.getAllLocations(), isNotEmpty);

      final transactions = await storage.getAllTransactions();
      expect(transactions, isNotEmpty);
      expect(transactions.whereType<Income>(), isNotEmpty);
      expect(transactions.whereType<Expense>(), isNotEmpty);
      expect(
        transactions.whereType<Expense>().map((e) => e.category).toSet().length,
        greaterThanOrEqualTo(4),
        reason: 'the charts need several categories to be worth looking at',
      );
    });

    test('one checklist is partially checked', () async {
      await DemoDataService.seedAll();

      final checklists = await StorageService().getAllChecklists();
      final partiallyChecked = checklists.where(
        (c) =>
            c.items.any((i) => i.isChecked) && c.items.any((i) => !i.isChecked),
      );

      expect(
        partiallyChecked,
        isNotEmpty,
        reason:
            'a fully packed or fully empty list shows nothing about progress',
      );
    });

    test('there is both an active and a completed journey', () async {
      await DemoDataService.seedAll();

      final journeys = await StorageService().getAllJourneys();
      expect(journeys.where((j) => j.completed), hasLength(1));
      expect(journeys.where((j) => !j.completed), isNotEmpty);
    });

    test('every journey carries something to pack', () async {
      await DemoDataService.seedAll();

      for (final journey in await StorageService().getAllJourneys()) {
        expect(
          journey.items,
          isNotEmpty,
          reason: '${journey.destination} arrived with an empty list',
        );
      }
    });

    test('every place has coordinates', () async {
      await DemoDataService.seedAll();

      final locations = await StorageService().getAllLocations();
      expect(locations.length, greaterThanOrEqualTo(2));
      for (final location in locations) {
        expect(location.latitude, isNot(0));
        expect(location.longitude, isNot(0));
      }
    });

    test('every seeded record is labelled in the UI', () async {
      await DemoDataService.seedAll();

      final storage = StorageService();
      for (final checklist in await storage.getAllChecklists()) {
        expect(checklist.name, startsWith(DemoDataService.label));
      }
      for (final location in await storage.getAllLocations()) {
        expect(location.name, startsWith(DemoDataService.label));
      }
      for (final journey in await storage.getAllJourneys()) {
        expect(journey.destination, startsWith(DemoDataService.label));
      }
      for (final transaction in await storage.getAllTransactions()) {
        expect(transaction.description, startsWith(DemoDataService.label));
      }
    });

    test('demo spend spans the current month and the two before it', () async {
      // Month navigation used to be empty everywhere except the month you
      // happened to open the app in, so you could not see what moving between
      // months looks like.
      await DemoDataService.seedAll();

      final now = DateTime.now();
      final months = <int, int>{};
      for (final transaction in await StorageService().getAllTransactions()) {
        final offset =
            (now.year - transaction.date.year) * 12 +
            (now.month - transaction.date.month);
        // A demo record in the future would be a bug: it would show up in no
        // month the user can currently reach.
        expect(
          offset,
          inInclusiveRange(0, 2),
          reason: '${transaction.description} landed $offset months out',
        );
        months[offset] = (months[offset] ?? 0) + 1;
      }

      expect(
        months[0],
        isNotNull,
        reason: 'the current month must have spend in it',
      );
      expect(months[1], isNotNull, reason: 'last month must not be empty');
      expect(
        months[2],
        isNotNull,
        reason: 'the month before must not be empty',
      );
    });

    test('seeding twice does not disturb the first batch', () async {
      await DemoDataService.seedAll();
      final first = await _counts();
      await DemoDataService.seedAll();
      final second = await _counts();

      // Ids are unique per record, so a second seed is simply more demo data.
      // This is asserted so the behaviour is deliberate rather than surprising.
      expect(second.transactions, first.transactions * 2);
      expect(second.journeys, first.journeys * 2);
    });
  });

  group('the demo includes a shared trip with something owed', () {
    // The settlement feature existed with demo data that had no participants
    // at all, so it was invisible unless you added three people by hand. This
    // is what makes TripOutstandingCard appear and the summary show transfers.
    test('one demo trip is shared and owes someone money', () async {
      await DemoDataService.seedAll();

      final journeys = JourneyProvider();
      await journeys.initialize();
      addTearDown(journeys.dispose);

      final shared = (await StorageService().getAllJourneys())
          .where((j) => j.participants.length >= 2)
          .toList();
      expect(shared, hasLength(1), reason: 'no shared trip was seeded');

      final trip = shared.single;
      expect(trip.participants, hasLength(3));
      expect(trip.localParticipantId, isNotNull);
      expect(trip.isShared, isTrue);

      // The README's worked example, exactly.
      final settlement = await journeys.tripSettlement(trip.id);
      expect(settlement.total, 13900);
      expect(settlement.transfers, hasLength(2));
      expect(settlement.transfers.map((t) => '${t.fromName}->${t.toName}'), [
        'Sita->You',
        'Sita->Raj',
      ]);
    });

    test('the shared trip shows on Transactions as outstanding', () async {
      await DemoDataService.seedAll();

      final journeys = JourneyProvider();
      await journeys.initialize();
      addTearDown(journeys.dispose);

      final outstanding = await journeys.outstandingAcrossTrips();
      expect(outstanding, hasLength(1));
      // The demo's local participant is "You", who fronted 5500 of 13900 and is
      // therefore owed. Sita is the one who owes, and the card is about the
      // person holding the phone.
      expect(outstanding.single.localIsOwed, isTrue);
      expect(outstanding.single.remainingTransfers, hasLength(2));
    });

    test(
      'every shared trip expense names a payer who is on the trip',
      () async {
        await DemoDataService.seedAll();

        final journeys = await StorageService().getAllJourneys();
        final shared = journeys.firstWhere((j) => j.participants.length >= 2);
        final roster = shared.participants.map((p) => p.id).toSet();

        for (final transaction
            in await StorageService().getTransactionsByJourney(shared.id)) {
          if (transaction is! Expense) continue;
          expect(
            roster.contains(transaction.paidByParticipantId),
            isTrue,
            reason:
                '${transaction.description} has payer '
                '${transaction.paidByParticipantId}, who is not on the trip',
          );
        }
      },
    );

    test('the shared trip survives a full clear', () async {
      await DemoDataService.seedAll();
      final seeded = await StorageService().getAllJourneys();
      final shared = seeded.firstWhere((j) => j.participants.length >= 2);

      await DemoDataService.clearAll();

      // The participants live inside the journey record, so deleting the
      // journey has to take them with it — an orphan would keep a name and an
      // id the user could never reach again.
      expect(await StorageService().getAllJourneys(), isEmpty);
      expect(
        await StorageService().getTransactionsByJourney(shared.id),
        isEmpty,
        reason: "the shared trip's expenses outlived it",
      );
    });
  });

  group('clearing is reversible and safe', () {
    test('clearing returns every box to its pre-seed state', () async {
      await _seedRealData();
      final before = await _counts();

      await DemoDataService.seedAll();
      final seeded = await _counts();
      expect(
        seeded.total,
        greaterThan(before.total),
        reason: 'the seed must actually have added something',
      );

      final removed = await DemoDataService.clearAll();

      expect(removed, seeded.total - before.total);
      final after = await _counts();
      expect(after.checklists, before.checklists);
      expect(after.checklistItems, before.checklistItems);
      expect(after.locations, before.locations);
      expect(after.locationLogs, before.locationLogs);
      expect(after.transactions, before.transactions);
      expect(after.journeys, before.journeys);
      expect(after.total, before.total);
    });

    test('the user\'s own records survive untouched', () async {
      await _seedRealData();
      await DemoDataService.seedAll();

      final realChecklistId = (await StorageService().getAllChecklists())
          .firstWhere((c) => c.name == 'My real pack')
          .id;
      final realLocationId = (await StorageService().getAllLocations())
          .firstWhere((l) => l.name == 'My own place')
          .id;
      final realJourneyId = (await StorageService().getAllJourneys())
          .firstWhere((j) => j.destination == 'My own trip')
          .id;

      await DemoDataService.clearAll();

      final storage = StorageService();

      final checklist = await storage.getChecklist(realChecklistId);
      expect(checklist, isNotNull);
      expect(checklist!.name, 'My real pack');
      expect(checklist.items.map((i) => i.name), [
        'My own boots',
      ], reason: 'a real item must not be removed with a demo checklist');

      final location = await storage.getLocation(realLocationId);
      expect(location, isNotNull);
      expect(
        await storage.getLocationLogs(realLocationId),
        hasLength(1),
        reason: 'a real location log must survive',
      );

      final journeys = await storage.getAllJourneys();
      expect(journeys, hasLength(1));
      expect(journeys.single.id, realJourneyId);

      final transactions = await storage.getAllTransactions();
      expect(transactions, hasLength(2));
      for (final transaction in transactions) {
        expect(
          DemoDataService.isDemoId(transaction.id),
          isFalse,
          reason: 'a demo transaction survived the clear',
        );
        expect(transaction.description, startsWith('My own'));
      }
    });

    test(
      'a record whose text says "Demo" but whose id does not is kept',
      () async {
        // The clear matches on the id prefix precisely so it cannot catch a
        // user's own record that happens to be called "Demo".
        await StorageService().addChecklist(
          Checklist(name: 'Demo of my own', description: 'not app demo data'),
        );
        await DemoDataService.seedAll();

        await DemoDataService.clearAll();

        final checklists = await StorageService().getAllChecklists();
        expect(checklists.map((c) => c.name), ['Demo of my own']);
      },
    );

    test('clearing works across months, not just the loaded one', () async {
      await DemoDataService.seedAll();

      // Move one demo transaction to a previous month, as an edit would.
      final all = await StorageService().getAllTransactions();
      final victim = all.first;
      final previousMonth = DateTime(
        DateTime.now().year,
        DateTime.now().month - 1,
        15,
      );
      if (victim is Expense) {
        await StorageService().updateTransaction(
          victim.copyWith(date: previousMonth),
        );
      } else {
        await StorageService().updateTransaction(
          (victim as Income).copyWith(date: previousMonth),
        );
      }

      // The seed spans several months now, so this is about the one record, not
      // about the month being empty.
      final inMonth = await StorageService().getTransactionsForMonth(
        previousMonth.year,
        previousMonth.month,
      );
      expect(
        inMonth.any((t) => t.id == victim.id),
        isTrue,
        reason: 'the record really did move month',
      );

      await DemoDataService.clearAll();

      // The old code only ever looked at the loaded month, so a demo record
      // that had been re-dated into another month stayed on disk forever.
      final after = await StorageService().getTransactionsForMonth(
        previousMonth.year,
        previousMonth.month,
      );
      expect(after, isEmpty);
      expect(await StorageService().getAllTransactions(), isEmpty);
    });

    test('clearing twice is harmless', () async {
      await DemoDataService.seedAll();
      final first = await DemoDataService.clearAll();
      final second = await DemoDataService.clearAll();

      expect(first, greaterThan(0));
      expect(second, 0);
    });

    test('the provider delegates to the same reversible behaviour', () async {
      final provider = TransactionProvider();
      await provider.initialize();

      await provider.addDemoData();
      await provider.goToCurrentMonth();
      expect(
        provider.transactions.where((t) => DemoDataService.isDemoId(t.id)),
        isNotEmpty,
      );

      await provider.clearDemoData();
      await provider.goToCurrentMonth();
      expect(
        provider.transactions.where((t) => DemoDataService.isDemoId(t.id)),
        isEmpty,
      );
    });

    test(
      'clearing never removes a real transaction in the loaded month',
      () async {
        // The old implementation deleted every transaction in the loaded month,
        // which is how a user's own records were at risk.
        final provider = TransactionProvider();
        await provider.initialize();
        await provider.addTransaction(
          Expense(
            amount: 15,
            category: ExpenseCategory.food,
            description: 'Real coffee',
          ),
        );
        await provider.addDemoData();
        await provider.goToCurrentMonth();

        expect(provider.transactions.length, greaterThan(1));

        await provider.clearDemoData();
        await provider.goToCurrentMonth();

        expect(provider.transactions.map((t) => t.description), [
          'Real coffee',
        ]);
      },
    );
  });
}
