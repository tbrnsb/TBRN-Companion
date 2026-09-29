import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/transaction_provider.dart';
import 'package:flutter_application_1/services/demo_data_service.dart';
import 'package:flutter_application_1/services/storage_service.dart';

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
      for (final journey in journeys) {
        expect(journey.items, isNotEmpty);
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

    test('demo spend lands in the current month', () async {
      await DemoDataService.seedAll();

      final now = DateTime.now();
      for (final transaction in await StorageService().getAllTransactions()) {
        expect(transaction.date.year, now.year);
        expect(transaction.date.month, now.month);
      }
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

      final previousCount = (await StorageService().getTransactionsForMonth(
        previousMonth.year,
        previousMonth.month,
      )).length;
      expect(previousCount, 1, reason: 'the record really did move month');

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
