import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/transaction_provider.dart';
import 'package:flutter_application_1/services/storage_service.dart';
import 'package:flutter_application_1/utils/format.dart';

import 'visual_smoke_test.dart' show initTestStorage;

Expense _expense(
  double amount,
  ExpenseCategory category, {
  String? custom,
  DateTime? date,
  String description = 'Test expense',
}) {
  return Expense(
    amount: amount,
    category: category,
    customCategoryName: custom,
    description: description,
    date: date ?? DateTime(2024, 1, 10),
  );
}

Income _income(
  double amount,
  String category, {
  DateTime? date,
  String description = 'Test income',
}) {
  return Income(
    amount: amount,
    category: category,
    description: description,
    date: date ?? DateTime(2024, 1, 10),
  );
}

Future<TransactionProvider> _providerFor(int year, int month) async {
  final provider = TransactionProvider();
  await provider.loadTransactionsForMonth(year, month);
  return provider;
}

void main() {
  setUpAll(() async {
    await initTestStorage();
  });

  setUp(() async {
    await StorageService().clear();
  });

  group('filters', () {
    test('All / Expenses / Income each change the displayed set', () async {
      final provider = await _providerFor(2024, 1);
      await provider.addTransaction(_expense(100, ExpenseCategory.food));
      await provider.addTransaction(_income(200, 'salary'));
      await provider.addTransaction(_expense(50, ExpenseCategory.travel));

      provider.filter = TransactionFilter.all;
      expect(provider.filteredTransactions.length, 3);
      expect(provider.filteredTransactions.where((t) => t.isExpense).length, 2);
      expect(provider.filteredTransactions.where((t) => t.isIncome).length, 1);

      provider.filter = TransactionFilter.expenses;
      final expenses = provider.filteredTransactions;
      expect(expenses.length, 2);
      expect(expenses.every((t) => t.isExpense), isTrue);

      provider.filter = TransactionFilter.income;
      final income = provider.filteredTransactions;
      expect(income.length, 1);
      expect(income.every((t) => t.isIncome), isTrue);

      provider.filter = TransactionFilter.all;
      expect(provider.filteredTransactions.length, 3);
    });

    test('changing the filter notifies listeners', () async {
      final provider = await _providerFor(2024, 1);
      var notifications = 0;
      provider.addListener(() => notifications++);

      provider.filter = TransactionFilter.expenses;
      provider.filter = TransactionFilter.income;

      expect(notifications, 2);
      expect(provider.filter, TransactionFilter.income);
    });
  });

  group('totals, balance and average', () {
    test('totals only count their own transaction type', () async {
      final provider = await _providerFor(2024, 1);
      await provider.addTransaction(_expense(100, ExpenseCategory.food));
      await provider.addTransaction(_expense(50, ExpenseCategory.travel));
      await provider.addTransaction(_income(200, 'salary'));
      await provider.addTransaction(_income(25, 'gift'));

      expect(provider.totalExpenses, 150);
      expect(provider.totalIncome, 225);
      expect(provider.balance, 75);
    });

    test('totals are zero with nothing recorded', () async {
      final provider = await _providerFor(2024, 1);

      expect(provider.totalExpenses, 0);
      expect(provider.totalIncome, 0);
      expect(provider.balance, 0);
    });

    test('a negative balance happens when spending exceeds income', () async {
      final provider = await _providerFor(2024, 1);
      await provider.addTransaction(_expense(300, ExpenseCategory.gear));
      await provider.addTransaction(_income(100, 'salary'));

      expect(provider.balance, -200);
    });

    test('average daily spending divides expenses by days in month', () async {
      final provider = await _providerFor(2024, 1);
      await provider.addTransaction(_expense(310, ExpenseCategory.food));

      // January has 31 days.
      expect(provider.getAverageDailySpending(), closeTo(10, 0.0001));
    });

    test('average daily spending is zero without a month loaded', () async {
      final provider = TransactionProvider();

      expect(provider.getAverageDailySpending(), 0);
    });

    test('getTotalSpending matches totalExpenses', () async {
      final provider = await _providerFor(2024, 1);
      await provider.addTransaction(_expense(120, ExpenseCategory.utilities));
      await provider.addTransaction(_income(500, 'salary'));

      expect(provider.getTotalSpending(), 120);
      expect(provider.getTotalSpending(), provider.totalExpenses);
    });
  });

  group('category breakdowns', () {
    test('spending breakdown groups expenses by expense category', () async {
      final provider = await _providerFor(2024, 1);
      await provider.addTransaction(_expense(100, ExpenseCategory.food));
      await provider.addTransaction(_expense(50, ExpenseCategory.food));
      await provider.addTransaction(_expense(25, ExpenseCategory.travel));
      await provider.addTransaction(_income(999, 'salary'));

      final breakdown = provider.getSpendingBreakdown();

      expect(breakdown.length, 2);
      // Sorted largest first.
      expect(breakdown.first.key, ExpenseCategory.food);
      expect(breakdown.first.value, 150);
      expect(breakdown.last.key, ExpenseCategory.travel);
      expect(breakdown.last.value, 25);
    });

    test('income breakdown groups income by income category id', () async {
      final provider = await _providerFor(2024, 1);
      await provider.addTransaction(_income(200, 'salary'));
      await provider.addTransaction(_income(50, 'freelance'));
      await provider.addTransaction(_income(50, 'salary'));
      await provider.addTransaction(_expense(999, ExpenseCategory.food));

      final breakdown = provider.getIncomeBreakdown();

      expect(breakdown.length, 2);
      expect(breakdown.first.key, 'salary');
      expect(breakdown.first.value, 250);
      expect(breakdown.last.key, 'freelance');
      expect(breakdown.last.value, 50);
    });

    test('breakdown keys never fall back to a literal type name', () async {
      final provider = await _providerFor(2024, 1);
      await provider.addTransaction(_income(200, 'salary'));
      await provider.addTransaction(_expense(100, ExpenseCategory.food));

      expect(
        provider.getIncomeBreakdown().map((e) => e.key),
        isNot(contains('Income')),
      );
      expect(
        provider.getSpendingBreakdown().map((e) => e.key.name),
        isNot(contains('Expense')),
      );
    });

    test('every breakdown key resolves to real metadata', () async {
      final provider = await _providerFor(2024, 1);
      for (final category in ExpenseCategory.values) {
        await provider.addTransaction(_expense(10, category));
      }
      for (final category in IncomeCategory.values) {
        await provider.addTransaction(_income(10, category.name));
      }

      for (final entry in provider.getSpendingBreakdown()) {
        final meta = CategoryRegistry.metaFor(entry.key);
        // Resolves to its own category, never a substituted fallback entry.
        expect(meta.id, entry.key.name);
      }
      for (final entry in provider.getIncomeBreakdown()) {
        final meta = CategoryRegistry.metaForIncome(entry.key);
        expect(meta.id, entry.key);
      }
    });

    test('getIncomeByCategory matches the breakdown key', () async {
      final provider = await _providerFor(2024, 1);
      await provider.addTransaction(_income(200, 'salary'));
      await provider.addTransaction(_income(50, 'salary'));
      await provider.addTransaction(_income(70, 'bonus'));
      await provider.addTransaction(_expense(500, ExpenseCategory.food));

      expect(provider.getIncomeByCategory('salary'), 250);
      expect(provider.getIncomeByCategory('bonus'), 70);
      expect(provider.getIncomeByCategory('food'), 0);
      expect(provider.getIncomeByCategory('nope'), 0);
    });
  });

  group('persistence round trip', () {
    test('both types survive a write and reload from storage', () async {
      final provider = await _providerFor(2024, 1);
      final expense = _expense(100.5, ExpenseCategory.food);
      final income = _income(200.75, 'freelance');
      await provider.addTransaction(expense);
      await provider.addTransaction(income);

      await provider.loadAllTransactions();

      final reloadedExpense = provider.transactions.firstWhere(
        (t) => t.id == expense.id,
      );
      final reloadedIncome = provider.transactions.firstWhere(
        (t) => t.id == income.id,
      );

      expect(reloadedExpense, isA<Expense>());
      expect(reloadedExpense.amount, 100.5);
      expect((reloadedExpense as Expense).category, ExpenseCategory.food);

      expect(reloadedIncome, isA<Income>());
      expect(reloadedIncome.amount, 200.75);
      expect((reloadedIncome as Income).category, 'freelance');
    });

    test('a stored record with no type key loads as an expense', () async {
      // Write a record in the shape used before the `type` key existed,
      // straight into the same Hive box StorageService reads from.
      final box = await Hive.openBox<Map>(StorageService.transactionsBox);
      await box.put('legacy-1', <String, dynamic>{
        'id': 'legacy-1',
        'amount': 42.0,
        'description': 'Recorded before type existed',
        'category': 'food',
        'locationId': 'place-9',
        'date': DateTime(2023, 7, 4).toIso8601String(),
      });

      final provider = TransactionProvider();
      await provider.loadAllTransactions();

      final loaded = provider.transactions.firstWhere(
        (t) => t.id == 'legacy-1',
      );
      expect(loaded, isA<Expense>());
      expect(loaded.isExpense, isTrue);
      expect(loaded.amount, 42.0);
      expect(loaded.description, 'Recorded before type existed');
      expect((loaded as Expense).category, ExpenseCategory.food);
      expect(loaded.locationId, 'place-9');
    });

    test('a legacy record is counted as an expense in the totals', () async {
      final box = await Hive.openBox<Map>(StorageService.transactionsBox);
      await box.put('legacy-2', <String, dynamic>{
        'id': 'legacy-2',
        'amount': 60.0,
        'description': 'Legacy expense',
        'category': 'travel',
        'date': DateTime(2023, 7, 9).toIso8601String(),
      });

      final provider = TransactionProvider();
      await provider.loadTransactionsForMonth(2023, 7);

      expect(provider.totalExpenses, 60);
      expect(provider.totalIncome, 0);
      expect(
        provider.getSpendingBreakdown().single.key,
        ExpenseCategory.travel,
      );
    });

    test('createdAt is not lost across a storage round trip', () async {
      final provider = await _providerFor(2024, 1);
      final created = DateTime(2024, 1, 1, 8, 30);
      final expense = Expense(
        amount: 10,
        category: ExpenseCategory.gear,
        description: 'Stamped',
        date: DateTime(2024, 1, 10),
        createdAt: created,
      );
      final income = Income(
        amount: 20,
        category: 'bonus',
        description: 'Stamped',
        date: DateTime(2024, 1, 10),
        createdAt: created,
      );
      await provider.addTransaction(expense);
      await provider.addTransaction(income);

      await provider.loadAllTransactions();

      expect(
        provider.transactions.firstWhere((t) => t.id == expense.id).createdAt,
        created,
      );
      expect(
        provider.transactions.firstWhere((t) => t.id == income.id).createdAt,
        created,
      );
    });
  });

  group('edit and delete', () {
    test('an expense can be updated and reloaded', () async {
      final provider = await _providerFor(2024, 1);
      final expense = _expense(100, ExpenseCategory.food);
      await provider.addTransaction(expense);

      await provider.updateTransaction(
        expense.copyWith(
          amount: 175,
          description: 'Edited expense',
          category: ExpenseCategory.travel,
        ),
      );

      expect(provider.transactions.single.amount, 175);
      expect(provider.totalExpenses, 175);

      await provider.loadAllTransactions();
      final reloaded = provider.transactions.single;
      expect(reloaded.amount, 175);
      expect(reloaded.description, 'Edited expense');
      expect((reloaded as Expense).category, ExpenseCategory.travel);
    });

    test('an income can be updated and reloaded', () async {
      final provider = await _providerFor(2024, 1);
      final income = _income(200, 'salary');
      await provider.addTransaction(income);

      await provider.updateTransaction(
        income.copyWith(amount: 260, category: 'bonus'),
      );

      expect(provider.totalIncome, 260);

      await provider.loadAllTransactions();
      final reloaded = provider.transactions.single;
      expect(reloaded, isA<Income>());
      expect(reloaded.amount, 260);
      expect((reloaded as Income).category, 'bonus');
    });

    test('an edit keeps the record in place and preserves createdAt', () async {
      final provider = await _providerFor(2024, 1);
      final created = DateTime(2024, 1, 1, 8, 30);
      final income = Income(
        amount: 100,
        category: 'salary',
        description: 'Original',
        date: DateTime(2024, 1, 10),
        createdAt: created,
      );
      await provider.addTransaction(income);

      await provider.updateTransaction(income.copyWith(description: 'Edited'));

      expect(provider.transactions.length, 1);
      expect(provider.transactions.single.createdAt, created);
      expect(provider.transactions.single.description, 'Edited');
    });

    test('both types can be deleted', () async {
      final provider = await _providerFor(2024, 1);
      final expense = _expense(100, ExpenseCategory.food);
      final income = _income(200, 'salary');
      await provider.addTransaction(expense);
      await provider.addTransaction(income);

      await provider.deleteTransaction(expense.id);
      expect(provider.transactions.length, 1);
      expect(provider.transactions.single.id, income.id);

      await provider.deleteTransaction(income.id);
      expect(provider.transactions, isEmpty);
      expect(provider.totalExpenses, 0);
      expect(provider.totalIncome, 0);

      // Deletion must reach storage, not just the in-memory list.
      await provider.loadAllTransactions();
      expect(provider.transactions, isEmpty);
    });
  });

  group('category metadata for pickers', () {
    test(
      'recent categories use expense metadata, not income fallbacks',
      () async {
        final provider = await _providerFor(2024, 1);
        await provider.addTransaction(
          _expense(100, ExpenseCategory.food, date: DateTime(2024, 1, 20)),
        );
        await provider.addTransaction(
          _expense(50, ExpenseCategory.food, date: DateTime(2024, 1, 10)),
        );

        final recent = provider.recentCategories;

        expect(recent.length, 1);
        expect(recent.single.id, 'food');
        expect(recent.single.name, 'Food');
        expect(recent.single.icon, Icons.restaurant_rounded);
      },
    );

    test('recent categories resolve income metadata for income', () async {
      final provider = await _providerFor(2024, 1);
      await provider.addTransaction(_income(200, 'salary'));

      final recent = provider.recentCategories;

      expect(recent.single.id, 'salary');
      expect(recent.single.name, 'Salary');
    });

    test('recent categories keep a custom expense name', () async {
      final provider = await _providerFor(2024, 1);
      await provider.addTransaction(
        _expense(30, ExpenseCategory.other, custom: 'Coffee'),
      );

      final recent = provider.recentCategories;

      expect(recent.single.name, 'Coffee');
      // "Coffee" is one of the suggested "Other" types, so it now resolves to
      // that type and carries its own cup icon instead of the generic custom
      // sparkle. The name is still the user's own, which is what matters here.
      expect(recent.single.id, 'suggested:coffee');
    });

    test('a hand-typed name still gets the generic custom treatment', () async {
      final provider = await _providerFor(2024, 1);
      await provider.addTransaction(
        _expense(30, ExpenseCategory.other, custom: 'Temple Entry'),
      );

      final recent = provider.recentCategories;

      expect(recent.single.name, 'Temple Entry');
      expect(recent.single.id, 'custom:temple entry');
    });

    test('a suggested type keeps its own icon and colour', () async {
      // The point of the suggested types: "Fruits" should read as fruit in the
      // donut, not as an anonymous other.
      final fruits = CategoryRegistry.metaFor(
        ExpenseCategory.other,
        customName: 'Fruits',
      );

      expect(fruits.name, 'Fruits');
      expect(fruits.id, 'suggested:fruits');

      // A name the user typed gets the generic custom icon and colour; a
      // suggested one gets its own. If these ever matched, every suggested type
      // would be indistinguishable from a hand-typed name.
      final handTyped = CategoryRegistry.metaFor(
        ExpenseCategory.other,
        customName: 'Anything else',
      );
      expect(fruits.icon, isNot(handTyped.icon));
      expect(fruits.color, isNot(handTyped.color));
    });

    test('a suggested type is matched regardless of capitalisation', () {
      for (final spelling in ['Fruits', 'fruits', '  FRUITS  ']) {
        expect(
          CategoryRegistry.metaFor(
            ExpenseCategory.other,
            customName: spelling,
          ).id,
          'suggested:fruits',
          reason: spelling,
        );
      }
    });

    test('popular categories rank by usage and keep types distinct', () async {
      final provider = await _providerFor(2024, 1);
      await provider.addTransaction(_expense(100, ExpenseCategory.food));
      await provider.addTransaction(_expense(10, ExpenseCategory.food));
      await provider.addTransaction(_expense(50, ExpenseCategory.travel));
      await provider.addTransaction(_income(999, 'salary'));

      final popular = provider.popularCategories;

      // Two food expenses beat one travel expense.
      expect(popular.first.id, 'food');
      expect(popular.map((m) => m.id).toSet(), {'food', 'travel', 'salary'});
      // An income category keeps its own metadata instead of being reported
      // as an expense.
      expect(popular.firstWhere((m) => m.id == 'salary').name, 'Salary');
    });

    test(
      'popular categories fall back to expense categories when empty',
      () async {
        final provider = await _providerFor(2024, 1);

        final popular = provider.popularCategories;
        final expenseIds = CategoryRegistry.expenseCategories()
            .map((m) => m.id)
            .toSet();

        expect(popular, isNotEmpty);
        for (final meta in popular) {
          expect(expenseIds, contains(meta.id));
        }
      },
    );
  });

  group('demo data', () {
    test('every demo record lands in the current month', () async {
      final now = DateTime.now();
      final provider = TransactionProvider();
      await provider.initialize();
      await provider.addDemoData();
      await provider.loadTransactionsForMonth(now.year, now.month);

      final demo = provider.transactions
          .where((t) => t.description.startsWith('[Demo]'))
          .toList();

      expect(demo.length, 7);
      for (final t in demo) {
        expect(
          t.date.year,
          now.year,
          reason: '${t.description} left the month',
        );
        expect(
          t.date.month,
          now.month,
          reason: '${t.description} left the month',
        );
      }
    });
  });

  group('write outcome and month isolation', () {
    test('addTransaction reports that the write succeeded', () async {
      final provider = await _providerFor(2024, 1);

      final ok = await provider.addTransaction(
        _expense(100, ExpenseCategory.food),
      );

      expect(ok, isTrue);
      expect(provider.error, isNull);
    });

    test(
      'a record dated in another month is not appended to the loaded month',
      () async {
        final provider = await _providerFor(2024, 1);
        await provider.addTransaction(_expense(100, ExpenseCategory.food));

        // The income sheet lets the user pick any past date, so a save can land
        // outside the month currently on screen. Appending it anyway would put
        // a foreign row into January's totals, chart and list — and that row
        // would silently vanish on the next month reload.
        await provider.addTransaction(
          _income(500, 'salary', date: DateTime(2024, 2, 5)),
        );

        expect(provider.transactions.length, 1);
        expect(provider.totalIncome, 0);
        expect(provider.balance, -100);

        // Still written to storage — the fix is about the in-memory month view,
        // never about dropping the user's record.
        final all = await StorageService().getAllTransactions();
        expect(all.length, 2);
        expect(all.whereType<Income>().single.date, DateTime(2024, 2, 5));

        // And it shows up when the user navigates to its own month.
        await provider.loadTransactionsForMonth(2024, 2);
        expect(provider.transactions.length, 1);
        expect(provider.totalIncome, 500);
      },
    );

    test(
      'an edit that moves a record to another month clears it from this one',
      () async {
        final provider = await _providerFor(2024, 1);
        final income = _income(200, 'salary');
        await provider.addTransaction(income);
        expect(provider.transactions.length, 1);

        await provider.updateTransaction(
          income.copyWith(date: DateTime(2024, 3, 2)),
        );

        // Re-dating a record used to leave the old January row in place, so the
        // same income was counted twice in the UI until the month reloaded.
        expect(provider.transactions, isEmpty);
        expect(provider.totalIncome, 0);

        await provider.loadTransactionsForMonth(2024, 3);
        expect(provider.transactions.length, 1);
        expect(provider.totalIncome, 200);
      },
    );

    test('an edit that moves a record into the loaded month adds it', () async {
      final provider = await _providerFor(2024, 1);
      final income = _income(200, 'salary', date: DateTime(2023, 12, 2));
      await provider.addTransaction(income);
      expect(provider.transactions, isEmpty);

      await provider.updateTransaction(
        income.copyWith(date: DateTime(2024, 1, 9)),
      );

      expect(provider.transactions.length, 1);
      expect(provider.totalIncome, 200);
    });
  });

  group('money formatting', () {
    test('the currency symbol is not spaced twice', () {
      expect(AppFormat.money(1234.5, symbol: 'Rs. '), 'Rs. 1,234.5');
      expect(AppFormat.money(1234.5, symbol: '\$'), '\$1,234.5');
      expect(AppFormat.money(1234.5, symbol: '€ '), '€ 1,234.5');
    });

    test('signedMoney marks expenses negative and income positive', () {
      expect(
        AppFormat.signedMoney(100, isExpense: true, symbol: 'Rs. '),
        '-Rs. 100',
      );
      expect(
        AppFormat.signedMoney(100, isExpense: false, symbol: 'Rs. '),
        '+Rs. 100',
      );
    });

    test('signedMoney is safe for an amount that is already negative', () {
      expect(
        AppFormat.signedMoney(-50, isExpense: false, symbol: '\$'),
        '+\$50',
      );
    });
  });
}
