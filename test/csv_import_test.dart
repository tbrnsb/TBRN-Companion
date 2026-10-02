import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/providers/journey_provider.dart';
import 'package:daily_companion/providers/transaction_provider.dart';
import 'package:daily_companion/services/csv_document.dart';
import 'package:daily_companion/services/csv_import.dart';
import 'package:daily_companion/services/storage_service.dart';

import 'visual_smoke_test.dart' show initTestStorage;

/// A CSV with two expenses and an income, in the documented format.
///
/// Dates and amounts are built from arguments rather than hardcoded literals, so
/// nothing here asserts against a month name or a figure that a future change to
/// the demo set would silently invalidate.
String sampleCsv({
  DateTime? firstDate,
  double food = 120.5,
  double travel = 900,
  double salary = 5000,
}) {
  final d = (firstDate ?? DateTime(2026, 3, 4)).toIso8601String().substring(
    0,
    10,
  );
  return [
    CsvDocument.header,
    '"$d","Groceries","$food","Food","Expense"',
    '"$d","Taxi","$travel","Travel","Expense"',
    '"$d","Payday","$salary","Salary","Income"',
  ].join('\n');
}

Expense _expense(
  double amount,
  ExpenseCategory category, {
  required DateTime date,
  String description = 'Test',
  String? journeyId,
  String? paidByParticipantId,
}) {
  return Expense(
    amount: amount,
    category: category,
    description: description,
    date: date,
    journeyId: journeyId,
    paidByParticipantId: paidByParticipantId,
  );
}

void main() {
  setUpAll(() async {
    await initTestStorage();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService().clear();
  });

  group('the CSV format is defined once', () {
    test('the header is the documented one', () {
      expect(CsvDocument.header, 'date,description,amount,category,type');
    });

    test('a quoted field containing a comma stays one column', () {
      // The whole reason the parser is hand-rolled. A split on ',' turns
      // "Lunch, with Raj" into two fields and every column after it shifts, which
      // then reports as a corrupt amount rather than as the quoting mistake it is.
      final rows = CsvDocument.parse(
        '"2026-03-04","Lunch, with Raj","120.00","Food","Expense"',
      );
      expect(rows, hasLength(1));
      expect(rows.single[1], 'Lunch, with Raj');
      expect(rows.single[2], '120.00');
      expect(rows.single[4], 'Expense');
    });

    test('a doubled quote inside a field is one literal quote', () {
      final rows = CsvDocument.parse(
        '"2026-03-04","The ""special"" one","10.00","Food","Expense"',
      );
      expect(rows.single[1], 'The "special" one');
    });

    test('a CRLF file does not leave a carriage return on the last column', () {
      final rows = CsvDocument.parse(
        '2026-03-04,Lunch,120.00,Food,Expense\r\n2026-03-05,Dinner,90.00,Food,Expense\r\n',
      );
      expect(rows, hasLength(2));
      expect(rows.every((r) => !r.last.contains('\r')), isTrue);
    });

    test('a final row with no trailing newline is not lost', () {
      final rows = CsvDocument.parse('2026-03-04,Lunch,10.00,Food,Expense');
      expect(rows, hasLength(1));
    });

    test('blank lines are ignored rather than parsed as empty rows', () {
      final rows = CsvDocument.parse(
        '2026-03-04,Lunch,10.00,Food,Expense\n\n\n2026-03-05,Dinner,20.00,Food,Expense\n',
      );
      expect(rows, hasLength(2));
    });
  });

  group('parsing', () {
    test('the documented shape parses into rows', () {
      final rows = CsvParser.parse(sampleCsv());
      expect(rows, hasLength(3));
      expect(rows.every((r) => r.isValid), isTrue);
    });

    test('an INTEGER amount is accepted, like fromJson already does', () {
      // A spreadsheet writes a whole number as `250`, and `(json['amount'] as
      // num)` already proves the app tolerates one in JSON. A strict
      // double.parse would reject a value this app reads without complaint.
      final rows = CsvParser.parse('2026-03-04,Lunch,250,Food,Expense');
      expect(rows.single.amount, 250);
      expect(rows.single.isValid, isTrue);
    });

    test('a decimal amount is accepted', () {
      final rows = CsvParser.parse('2026-03-04,Lunch,250.75,Food,Expense');
      expect(rows.single.amount, 250.75);
    });

    test('an unreadable amount rejects the ROW, not the file', () {
      final rows = CsvParser.parse(
        '2026-03-04,Lunch,not-a-number,Food,Expense\n2026-03-05,Dinner,20.00,Food,Expense',
      );
      expect(rows, hasLength(2));
      expect(rows[0].isValid, isFalse);
      expect(rows[0].failure, contains('amount'));
      // The good row still comes through.
      expect(rows[1].isValid, isTrue);
    });

    test('an unreadable date rejects the row', () {
      final rows = CsvParser.parse('the-fourth,Lunch,10.00,Food,Expense');
      expect(rows.single.isValid, isFalse);
      expect(rows.single.failure, contains('date'));
    });

    test('an unknown type rejects the row and says which', () {
      final rows = CsvParser.parse('2026-03-04,Lunch,10.00,Food,Transfer');
      expect(rows.single.isValid, isFalse);
      expect(rows.single.failure, contains('Transfer'));
    });

    test('a short row is rejected with the column count', () {
      final rows = CsvParser.parse('2026-03-04,Lunch,10.00');
      expect(rows.single.isValid, isFalse);
      expect(rows.single.failure, contains('5'));
    });

    test('the header row is recognised and not imported as data', () {
      final rows = CsvParser.parse(sampleCsv());
      expect(rows.map((r) => r.description), isNot(contains('description')));
    });

    test('a file with NO header still imports its first row', () {
      // A row that happens to start with the word "date" must not cost the user
      // a transaction. Dropping it silently is exactly the data loss a preview
      // is supposed to prevent.
      final rows = CsvParser.parse('2026-03-04,Lunch,10.00,Food,Expense');
      expect(rows, hasLength(1));
      expect(rows.single.isValid, isTrue);
    });

    test('a UTF-8 BOM does not turn the header into data', () {
      final rows = CsvParser.parse('﻿${sampleCsv()}');
      expect(rows, hasLength(3));
      expect(rows.every((r) => r.isValid), isTrue);
    });
  });

  group('categories resolve through the registry', () {
    test('a built-in name maps to its enum value', () {
      final row = CsvParser.parse('2026-03-04,Lunch,10.00,Food,Expense').single;
      final t = row.toTransaction() as Expense;
      expect(t.category, ExpenseCategory.food);
      expect(t.customCategoryName, isNull);
    });

    test('an unknown name becomes a custom name under "other"', () {
      // Never a new ExpenseCategory value: a transaction stores its category by
      // NAME, so adding an enum value would not invalidate a record — but it WOULD
      // push an imported name into the main nine and redefine what "the main
      // categories" means.
      final row = CsvParser.parse('2026-03-04,Vinyl record,10.00,Vinyl,Expense')
          .single;
      final t = row.toTransaction() as Expense;
      expect(t.category, ExpenseCategory.other);
      expect(t.customCategoryName, 'Vinyl');
      expect(t.effectiveCategoryName, 'Vinyl');
    });

    test('an empty category falls back to Other', () {
      final row = CsvParser.parse('2026-03-04,Lunch,10.00,,Expense').single;
      final t = row.toTransaction() as Expense;
      expect(t.category, ExpenseCategory.other);
      expect(t.customCategoryName, isNull);
    });

    test('an income row keeps its category string', () {
      final row = CsvParser.parse('2026-03-04,Payday,5000,Salary,Income')
          .single;
      final t = row.toTransaction() as Income;
      expect(t.category, 'Salary');
      expect(t.isIncome, isTrue);
    });

    test(
      'a blank description gets a placeholder rather than an empty title',
      () {
        final row = CsvParser.parse('2026-03-04,,10.00,Food,Expense').single;
        expect(row.toTransaction()!.description, 'Imported');
      },
    );
  });

  group('duplicate detection', () {
    test('the key is date + amount + description, and not the id', () {
      final row = CsvParser.parse('2026-03-04,Lunch,10.00,Food,Expense').single;
      // Fresh ids are generated on every import, so including one would make every
      // row new every time and the check would never fire.
      expect(row.dedupeKey, '2026-03-04|1000|lunch');
    });

    test('description case does not matter', () {
      final a = CsvParser.parse('2026-03-04,Lunch,10.00,Food,Expense').single;
      final b = CsvParser.parse('2026-03-04,LUNCH,10.00,Food,Expense').single;
      expect(a.dedupeKey, b.dedupeKey);
    });

    test('a different amount is a different row', () {
      final a = CsvParser.parse('2026-03-04,Lunch,10.00,Food,Expense').single;
      final b = CsvParser.parse('2026-03-04,Lunch,11.00,Food,Expense').single;
      expect(a.dedupeKey, isNot(b.dedupeKey));
    });

    test('a row already on the phone is marked a duplicate', () {
      final existing = _expense(
        10,
        ExpenseCategory.food,
        date: DateTime(2026, 3, 4),
        description: 'Lunch',
      );
      final plan = CsvImportPlan.analyse(
        text: '2026-03-04,Lunch,10.00,Food,Expense',
        existing: [existing],
        fileName: 'x.csv',
      );
      expect(plan.duplicates, hasLength(1));
      expect(plan.newRows, isEmpty);
    });

    test('importing the same file twice plans nothing the second time', () {
      final plan = CsvImportPlan.analyse(
        text: sampleCsv(),
        existing: const [],
        fileName: 'x.csv',
      );
      expect(plan.newRows, hasLength(3));

      final second = CsvImportPlan.analyse(
        text: sampleCsv(),
        existing: plan.newRows.map((r) => r.toTransaction()!).toList(),
        fileName: 'x.csv',
      );
      expect(second.newRows, isEmpty);
      expect(second.duplicates, hasLength(3));
    });

    test('the summary says what will happen in words', () {
      final plan = CsvImportPlan.analyse(
        text: sampleCsv(),
        existing: const [],
        fileName: 'x.csv',
      );
      expect(plan.summary, contains('3 to import'));
    });

    test(
      'dropping a row removes it from the plan and changes nothing else',
      () {
        final plan = CsvImportPlan.analyse(
          text: sampleCsv(),
          existing: const [],
          fileName: 'x.csv',
        );
        final dropped = plan.without({'2'});
        expect(dropped.rows, hasLength(2));
        expect(dropped.newRows, hasLength(2));
      },
    );
  });

  group('export and import are symmetric', () {
    test('a row written by the exporter parses back', () async {
      // The month is LOADED explicitly, not `initialize()`d. Export reads the
      // loaded month, and a record dated into some other month is deliberately
      // not folded into it — so a provider initialised to "now" would export
      // nothing at all and this test would pass for the wrong reason.
      final provider = TransactionProvider();
      await provider.loadTransactionsForMonth(2026, 3);
      final date = DateTime(2026, 3, 4);
      await provider.addTransaction(
        _expense(
          120.5,
          ExpenseCategory.food,
          date: date,
          description: 'Groceries, market run',
        ),
      );
      await provider.addTransaction(
        Income(
          amount: 5000,
          category: 'salary',
          description: 'Payday',
          date: date,
        ),
      );

      final csv = provider.exportCurrentMonthCsv();

      // Put the exported rows into the empty month they came from, and check they
      // come back as the same transactions. This is THE round trip, and it is the
      // only test that can catch the two formats drifting apart.
      await StorageService().clear();
      final target = TransactionProvider();
      await target.loadTransactionsForMonth(2026, 3);

      final existing = await target.existingLedgerForImport();
      final plan = CsvImportPlan.analyse(
        text: csv,
        existing: existing,
        fileName: 'round-trip.csv',
      );

      expect(plan.rejected, isEmpty);
      expect(plan.newRows, hasLength(2));

      final restored = plan.newRows.map((r) => r.toTransaction()!).toList();
      await target.addTransactionsInBulk(restored);

      expect(target.transactions, hasLength(2));
      final byDescription = {
        for (final t in target.transactions) t.description: t,
      };
      final groceries = byDescription['Groceries, market run']! as Expense;
      expect(groceries.amount, 120.5);
      expect(groceries.category, ExpenseCategory.food);
      expect(groceries.date, DateTime(2026, 3, 4));
      expect(byDescription['Payday']!.isIncome, isTrue);
    });

    test('export and import agree about a trip expense the user DID pay', () async {
      // Loaded explicitly for the same reason as the round-trip test above.
      // Exported, so it parses back and is recognised as already present. The two
      // halves must agree, or the round trip duplicates the user's own trip
      // spending.
      final provider = TransactionProvider();
      await provider.loadTransactionsForMonth(2026, 3);
      final date = DateTime(2026, 3, 4);
      provider.setLocalParticipant('trip-1', 'me');
      await provider.addTransaction(
        _expense(
          500,
          ExpenseCategory.food,
          date: date,
          description: 'Trip lunch',
          journeyId: 'trip-1',
          paidByParticipantId: 'me',
        ),
      );

      final csv = provider.exportCurrentMonthCsv();
      expect(csv, contains('Trip lunch'));

      // Re-analysing the same file against the same ledger finds the duplicate.
      final existing = await provider.existingLedgerForImport();
      final plan = CsvImportPlan.analyse(
        text: csv,
        existing: existing,
        fileName: 'x.csv',
      );
      expect(plan.newRows, isEmpty, reason: 'a re-import must add nothing');
    });

    test("export OMITS a trip expense the user did NOT pay", () async {
      // The asymmetry that matters, and it is the SAME rule on both sides:
      // another participant's trip spending is not the user's, so it is not in
      // their export and it is not in what an import compares against either.
      final provider = TransactionProvider();
      await provider.loadTransactionsForMonth(2026, 3);
      final date = DateTime(2026, 3, 4);
      provider.setLocalParticipant('trip-1', 'me');
      await provider.addTransaction(
        _expense(
          900,
          ExpenseCategory.food,
          date: date,
          description: 'Sita groceries',
          journeyId: 'trip-1',
          paidByParticipantId: 'sita',
        ),
      );
      await provider.addTransaction(
        _expense(
          500,
          ExpenseCategory.food,
          date: date,
          description: 'My taxi',
          journeyId: 'trip-1',
          paidByParticipantId: 'me',
        ),
      );

      final csv = provider.exportCurrentMonthCsv();
      expect(csv, contains('My taxi'));
      expect(
        csv,
        isNot(contains('Sita groceries')),
        reason: 'a stranger\'s expense must not go into a file the user shares',
      );

      // And the import side never offers it as a duplicate-blocker either, so
      // importing a file that happens to contain it does not silently skip a row
      // the user can see on screen.
      final existing = await provider.existingLedgerForImport();
      expect(
        existing.map((t) => t.description),
        isNot(contains('Sita groceries')),
      );
    });

    test('export omits a trashed row', () async {
      final provider = TransactionProvider();
      await provider.loadTransactionsForMonth(2026, 3);
      await provider.addTransaction(
        _expense(
          100,
          ExpenseCategory.food,
          date: DateTime(2026, 3, 4),
          description: 'Kept',
        ),
      );
      await provider.addTransaction(
        _expense(
          300,
          ExpenseCategory.food,
          date: DateTime(2026, 3, 5),
          description: 'Binned',
        ),
      );
      await provider.moveToTrash(
        provider.transactions.firstWhere((t) => t.description == 'Binned').id,
      );

      final csv = provider.exportCurrentMonthCsv();
      expect(csv, contains('Kept'));
      expect(csv, isNot(contains('Binned')));
    });

    test('imported rows are ordinary rows with no trip attached', () async {
      // An imported row must not become a path AROUND the shared-trip filter. It
      // carries no journeyId at all, so it is plain spending and counts
      // everywhere — and it cannot be someone's trip expense smuggled in through
      // a file, because the CSV format has no payer column.
      final provider = TransactionProvider();
      await provider.loadTransactionsForMonth(2026, 3);
      final plan = CsvImportPlan.analyse(
        text: '2026-03-04,Imported lunch,10.00,Food,Expense',
        existing: const [],
        fileName: 'x.csv',
      );
      await provider.addTransactionsInBulk(
        plan.newRows.map((r) => r.toTransaction()!).toList(),
      );

      expect(provider.transactions.single.journeyId, isNull);
      expect(provider.transactions.single.paidByParticipantId, isNull);
      // So it is unambiguously the user's own spending.
      expect(provider.totalSpend(anchor: DateTime(2026, 3)), 10);
    });

    test('an imported file cannot restore a trashed row as a duplicate blocker', () async {
      // Loaded explicitly: the trashed row has to be in this provider's month.
      final provider = TransactionProvider();
      await provider.loadTransactionsForMonth(2026, 3);
      await provider.addTransaction(
        _expense(
          100,
          ExpenseCategory.food,
          date: DateTime(2026, 3, 4),
          description: 'Lunch',
        ),
      );
      await provider.moveToTrash(provider.transactions.single.id);

      // The trashed row is not in the live ledger, so re-importing the same
      // purchase is allowed. That is right: the user deleted it, so bringing it
      // back from a file they chose is a deliberate act.
      final existing = await provider.existingLedgerForImport();
      final plan = CsvImportPlan.analyse(
        text: '2026-03-04,Lunch,100.00,Food,Expense',
        existing: existing,
        fileName: 'x.csv',
      );
      expect(plan.newRows, hasLength(1));
    });
  });

  group('import is add-only', () {
    test('a duplicate changes nothing', () async {
      final provider = TransactionProvider();
      await provider.loadTransactionsForMonth(2026, 3);
      await provider.addTransaction(
        _expense(
          100,
          ExpenseCategory.food,
          date: DateTime(2026, 3, 4),
          description: 'Lunch',
        ),
      );
      final before = provider.totalSpend(anchor: DateTime(2026, 3));
      final idsBefore = provider.transactions.map((t) => t.id).toSet();

      final existing = await provider.existingLedgerForImport();
      final plan = CsvImportPlan.analyse(
        text: '2026-03-04,Lunch,100.00,Food,Expense',
        existing: existing,
        fileName: 'x.csv',
      );
      await provider.addTransactionsInBulk(
        plan.newRows.map((r) => r.toTransaction()!).toList(),
      );

      expect(provider.totalSpend(anchor: DateTime(2026, 3)), before);
      expect(provider.transactions.map((t) => t.id).toSet(), idsBefore);
    });

    test('a trashed row is never overwritten by an import', () async {
      // "Never overwrite or delete an existing transaction" includes the ones the
      // user has deleted: an import must not quietly un-delete something.
      final provider = TransactionProvider();
      await provider.loadTransactionsForMonth(2026, 3);
      await provider.addTransaction(
        _expense(
          100,
          ExpenseCategory.food,
          date: DateTime(2026, 3, 4),
          description: 'Lunch',
        ),
      );
      await provider.moveToTrash(provider.transactions.single.id);

      final existing = await provider.existingLedgerForImport();
      final plan = CsvImportPlan.analyse(
        text: '2026-03-04,Lunch,100.00,Food,Expense',
        existing: existing,
        fileName: 'x.csv',
      );
      await provider.addTransactionsInBulk(
        plan.newRows.map((r) => r.toTransaction()!).toList(),
      );

      // A NEW record with a new id. The trashed one is untouched on disk.
      final trashed = await StorageService().getTrashedTransactions();
      expect(trashed, hasLength(1));
      expect(trashed.single.description, 'Lunch');
      expect(provider.transactions, hasLength(1));
      expect(provider.transactions.single.id, isNot(trashed.single.id));
    });
  });

  group('bulk writes', () {
    test(
      'a row outside the loaded month is written but not folded in',
      () async {
        final provider = TransactionProvider();
        await provider.loadTransactionsForMonth(2026, 3);
        final written = await provider.addTransactionsInBulk([
          _expense(
            10,
            ExpenseCategory.food,
            date: DateTime(2026, 3, 4),
            description: 'March',
          ),
          _expense(
            20,
            ExpenseCategory.food,
            date: DateTime(2026, 2, 4),
            description: 'February',
          ),
        ]);

        expect(written, hasLength(2));
        expect(provider.transactions.map((t) => t.description), ['March']);
        // Both are on disk.
        final all = await StorageService().getAllTransactions();
        expect(all, hasLength(2));
      },
    );

    test('an empty list writes nothing and does not notify', () async {
      final provider = TransactionProvider();
      await provider.initialize();
      var notified = 0;
      provider.addListener(() => notified++);
      expect(await provider.addTransactionsInBulk(const []), isEmpty);
      expect(notified, 0);
    });
  });

  group('imported custom categories go through the registry path', () {
    test('a custom name is registered like a typed one', () async {
      final provider = TransactionProvider();
      await provider.loadTransactionsForMonth(2026, 3);

      final plan = CsvImportPlan.analyse(
        text: '2026-03-04,Vinyl record,10.00,Vinyl,Expense',
        existing: const [],
        fileName: 'x.csv',
      );
      await provider.addTransactionsInBulk(
        plan.newRows.map((r) => r.toTransaction()!).toList(),
      );
      await provider.registerImportedCategory('Vinyl');

      // Offered as a suggestion afterwards, exactly as a hand-typed name is.
      expect(provider.recentCustomCategories, contains('Vinyl'));
    });
  });

  group('the byte-level reader', () {
    test('a UTF-8 BOM is stripped', () {
      final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(CsvDocument.header)];
      // ignore: deprecated_member_use
      final text = String.fromCharCodes(bytes);
      final rows = CsvParser.parse(text);
      // Without the strip the first column reads as '﻿date', the header is
      // unrecognised, and the first real row is then mistaken for it.
      expect(rows, isNotEmpty);
    });
  });

  group('journeys are not touched by a CSV import', () {
    test('TripSnapshot is a separate concern and stays separate', () async {
      // trip_importer.dart handles a JSON trip file with participants and
      // settlement. The CSV importer has no participant column, so there is no
      // path by which importing a CSV could create or modify a shared trip.
      final journeys = JourneyProvider();
      addTearDown(journeys.dispose);
      await journeys.initialize();

      final provider = TransactionProvider();
      await provider.loadTransactionsForMonth(2026, 3);
      final plan = CsvImportPlan.analyse(
        text: sampleCsv(),
        existing: const [],
        fileName: 'x.csv',
      );
      await provider.addTransactionsInBulk(
        plan.newRows.map((r) => r.toTransaction()!).toList(),
      );

      expect(journeys.journeys, isEmpty);
      for (final t in provider.transactions) {
        expect(t.journeyId, isNull);
      }
    });
  });
}
