import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/transaction_provider.dart';
import 'package:flutter_application_1/services/csv_export.dart';
import 'package:flutter_application_1/services/storage_service.dart';

import 'visual_smoke_test.dart' show initTestStorage;

void main() {
  setUpAll(() async {
    await initTestStorage();
  });

  setUp(() async {
    await StorageService().clear();
  });

  group('storage counts', () {
    test('reports zero for an empty install', () async {
      final counts = await StorageService().getStorageCounts();

      expect(counts.checklists, 0);
      expect(counts.checklistItems, 0);
      expect(counts.locations, 0);
      expect(counts.locationLogs, 0);
      expect(counts.transactions, 0);
      expect(counts.journeys, 0);
      expect(counts.customCategories, 0);
      expect(counts.total, 0);
      expect(counts.isEmpty, isTrue);
    });

    test('counts every box the wipe would empty', () async {
      final journey = Journey(destination: 'Pokhara', origin: 'Kathmandu');
      await StorageService().addJourney(journey);

      final checklist = Checklist(name: 'Pack', description: '');
      await StorageService().addChecklist(checklist);
      await StorageService().addChecklistItem(
        ChecklistItem(name: 'Boots', checklistId: checklist.id),
      );

      await StorageService().addLocation(
        Location(
          name: 'Phewa',
          latitude: 28.2,
          longitude: 83.9,
          description: '',
        ),
      );
      await StorageService().addLocationLog(
        LocationLog(
          locationId: 'any',
          arrivalTime: DateTime.now(),
        ),
      );
      await StorageService().addTransaction(
        Expense(
          amount: 10,
          category: ExpenseCategory.food,
          description: 'Lunch',
        ),
      );
      await StorageService().addExpenseCategory('Coffee');

      final counts = await StorageService().getStorageCounts();

      expect(counts.checklists, 1);
      expect(counts.checklistItems, 1);
      expect(counts.locations, 1);
      expect(counts.locationLogs, 1);
      expect(counts.transactions, 1);
      expect(counts.journeys, 1);
      expect(counts.customCategories, 1);
      // Seven boxes: checklist, checklist item, location, location log,
      // transaction, journey, custom category.
      expect(counts.total, 7);
      expect(counts.isEmpty, isFalse);
    });

    test('clear() really does empty every box the counts report', () async {
      final checklist = Checklist(name: 'Pack', description: '');
      await StorageService().addChecklist(checklist);
      await StorageService().addChecklistItem(
        ChecklistItem(name: 'Boots', checklistId: checklist.id),
      );
      await StorageService().addJourney(
        Journey(destination: 'Pokhara', origin: 'Kathmandu'),
      );
      await StorageService().addTransaction(
        Expense(
          amount: 10,
          category: ExpenseCategory.food,
          description: 'Lunch',
        ),
      );

      await StorageService().clear();

      final counts = await StorageService().getStorageCounts();
      expect(counts.total, 0);
      // Confirmed through the real getters too, not just the counters.
      expect(await StorageService().getAllChecklists(), isEmpty);
      expect(await StorageService().getAllJourneys(), isEmpty);
      expect(await StorageService().getAllTransactions(), isEmpty);
      expect(await StorageService().getAllLocations(), isEmpty);
    });
  });

  group('CSV export', () {
    test('the file name is the month being exported', () {
      expect(
        CsvExport.fileNameFor(DateTime(2026, 9, 15)),
        'transactions-2026-09.csv',
      );
    });

    test('writes the month\'s transactions to disk', () async {
      final provider = TransactionProvider();
      await provider.initialize();
      await provider.addTransaction(
        Expense(
          amount: 120.50,
          category: ExpenseCategory.food,
          description: 'Lunch',
          date: DateTime.now(),
        ),
      );
      await provider.addTransaction(
        Income(
          amount: 900,
          category: 'salary',
          description: 'Payday',
          date: DateTime.now(),
        ),
      );

      final csv = await provider.exportCurrentMonthCsv();
      final file = await CsvExport.writeCsv(csv, DateTime.now());
      addTearDown(() => file.parent.deleteSync(recursive: true));

      expect(await file.exists(), isTrue);
      final written = await file.readAsString();

      expect(written, startsWith('date,description,amount,category,type'));
      expect(written, contains('Lunch'));
      expect(written, contains('Payday'));
      // Amounts keep two decimals, and the sign is carried by the type column
      // rather than by a leading minus.
      expect(written, contains('120.50'));
      expect(written, contains('900.00'));
      expect(written, contains('expense'));
      expect(written, contains('income'));
    });

    test('quotes descriptions containing a comma', () async {
      final provider = TransactionProvider();
      await provider.initialize();
      await provider.addTransaction(
        Expense(
          amount: 10,
          category: ExpenseCategory.food,
          description: 'Tea, coffee and a bun',
          date: DateTime.now(),
        ),
      );

      final csv = await provider.exportCurrentMonthCsv();
      final file = await CsvExport.writeCsv(csv, DateTime.now());
      addTearDown(() => file.parent.deleteSync(recursive: true));

      expect(await file.readAsString(), contains('"Tea, coffee and a bun"'));
    });

    test('a month with no transactions produces a header-only file', () async {
      final provider = TransactionProvider();
      await provider.initialize();

      final csv = await provider.exportCurrentMonthCsv();
      final file = await CsvExport.writeCsv(csv, DateTime.now());
      addTearDown(() => file.parent.deleteSync(recursive: true));

      final written = await file.readAsString();
      expect(written.trim(), 'date,description,amount,category,type');
    });

    test('quotes are escaped by doubling them', () async {
      final provider = TransactionProvider();
      await provider.initialize();
      await provider.addTransaction(
        Expense(
          amount: 10,
          category: ExpenseCategory.food,
          description: 'The "special" one',
          date: DateTime.now(),
        ),
      );

      final csv = await provider.exportCurrentMonthCsv();
      final file = await CsvExport.writeCsv(csv, DateTime.now());
      addTearDown(() => file.parent.deleteSync(recursive: true));

      expect(await file.readAsString(), contains('"The ""special"" one"'));
    });
  });
}
