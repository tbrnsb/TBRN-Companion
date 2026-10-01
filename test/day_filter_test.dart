import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/transaction_provider.dart';
import 'package:flutter_application_1/services/storage_service.dart';

import 'visual_smoke_test.dart' show initTestStorage;

Expense _expense(
  double amount,
  ExpenseCategory category, {
  required DateTime date,
  String description = 'Test expense',
}) {
  return Expense(
    amount: amount,
    category: category,
    description: description,
    date: date,
  );
}

/// The month these fixtures live in: LAST month, relative to the clock.
///
/// Every date in this file used to be a hardcoded March 2024. That is outside the
/// app's own two-year navigation window now, so `previousMonth` correctly refused
/// to move and a test about day-selection semantics was failing because of a
/// navigation bound. Fixed dates in tests rot; this one cannot.
late DateTime anchor;

void main() {
  setUpAll(() async {
    await initTestStorage();
  });

  setUp(() async {
    await StorageService().clear();
    final now = DateTime.now();
    anchor = DateTime(now.year, now.month - 1);
  });

  /// Loads a month with two transactions on different days.
  Future<TransactionProvider> providerWithTwoDays() async {
    final provider = TransactionProvider();
    await provider.loadTransactionsForMonth(anchor.year, anchor.month);

    await provider.addTransaction(
      _expense(
        100,
        ExpenseCategory.food,
        date: DateTime(anchor.year, anchor.month, 4),
      ),
    );
    await provider.addTransaction(
      _expense(
        250,
        ExpenseCategory.travel,
        date: DateTime(anchor.year, anchor.month, 9),
      ),
    );
    await provider.addTransaction(
      _expense(
        60,
        ExpenseCategory.food,
        date: DateTime(anchor.year, anchor.month, 4),
      ),
    );
    return provider;
  }

  group('narrowing the view to a day', () {
    test('the whole month is the default', () async {
      final provider = await providerWithTwoDays();

      expect(provider.isShowingSingleDay, isFalse);
      expect(provider.filteredTransactions, hasLength(3));
      expect(provider.totalExpenses, 410);
    });

    test('selecting a day narrows the list and the totals together', () async {
      final provider = await providerWithTwoDays();

      provider.setSelectedDay(DateTime(anchor.year, anchor.month, 4));

      expect(provider.isShowingSingleDay, isTrue);
      expect(provider.filteredTransactions, hasLength(2));
      // The balance has to agree with the list. Filtering only the list would
      // leave the summary card describing the whole month above a two-row list.
      expect(provider.totalExpenses, 160);
      expect(provider.balance, -160);
    });

    test('the breakdown charts follow the selected day', () async {
      final provider = await providerWithTwoDays();

      provider.setSelectedDay(DateTime(anchor.year, anchor.month, 9));

      final slices = provider.getSpendingBreakdownSlices();
      expect(slices, hasLength(1));
      expect(slices.single.meta.id, 'travel');
      expect(slices.single.amount, 250);
    });

    test('the average is the day\'s spend, not a day divided by 30', () async {
      final provider = await providerWithTwoDays();

      // Whole month: 410 over however many days it has.
      final daysInAnchor = DateTime(anchor.year, anchor.month + 1, 0).day;
      expect(
        provider.getAverageDailySpending(),
        closeTo(410 / daysInAnchor, 0.0001),
      );

      provider.setSelectedDay(DateTime(anchor.year, anchor.month, 4));
      // Dividing one day's spend by the length of the month would be nonsense.
      expect(provider.getAverageDailySpending(), 160);
    });

    test('clearing returns the whole month', () async {
      final provider = await providerWithTwoDays();
      provider.setSelectedDay(DateTime(anchor.year, anchor.month, 4));

      provider.setSelectedDay(null);

      expect(provider.isShowingSingleDay, isFalse);
      expect(provider.filteredTransactions, hasLength(3));
      expect(provider.totalExpenses, 410);
    });

    test('changing month drops the day selection', () async {
      final provider = await providerWithTwoDays();
      provider.setSelectedDay(DateTime(anchor.year, anchor.month, 4));
      expect(provider.isShowingSingleDay, isTrue);

      // A day belongs to a month. Carrying the selection into the month before
      // would leave the view narrowed to a day that is not loaded, and empty.
      await provider.previousMonth();

      expect(provider.currentMonth, DateTime(anchor.year, anchor.month - 1));
      expect(
        provider.isShowingSingleDay,
        isFalse,
        reason: 'a day selection cannot survive a month change',
      );
    });

    test('a day outside the loaded month is ignored', () async {
      final provider = await providerWithTwoDays();

      provider.setSelectedDay(DateTime(anchor.year, anchor.month + 6, 19));

      // Silently accepting it would empty the screen with no explanation.
      expect(provider.isShowingSingleDay, isFalse);
      expect(provider.filteredTransactions, hasLength(3));
    });

    test('a day with nothing on it is a legitimately empty view', () async {
      final provider = await providerWithTwoDays();

      provider.setSelectedDay(DateTime(anchor.year, anchor.month, 20));

      expect(provider.isShowingSingleDay, isTrue);
      expect(provider.filteredTransactions, isEmpty);
      expect(provider.totalExpenses, 0);
    });

    test('the type filter still applies within a selected day', () async {
      final provider = TransactionProvider();
      await provider.loadTransactionsForMonth(anchor.year, anchor.month);
      await provider.addTransaction(
        _expense(
          100,
          ExpenseCategory.food,
          date: DateTime(anchor.year, anchor.month, 4),
        ),
      );
      await provider.addTransaction(
        Income(
          amount: 900,
          category: 'salary',
          description: 'Payday',
          date: DateTime(anchor.year, anchor.month, 4),
        ),
      );

      provider.setSelectedDay(DateTime(anchor.year, anchor.month, 4));
      expect(provider.filteredTransactions, hasLength(2));

      provider.filter = TransactionFilter.income;
      expect(provider.filteredTransactions, hasLength(1));
      expect(provider.totalIncome, 900);
    });

    test(
      'the type filter narrows the list but not the period totals',
      () async {
        // Deliberate, and worth pinning: the summary card is a summary of the
        // period, and the All/Expenses/Income chips only filter the list below it.
        // Making the totals follow the chips too would mean the balance changes
        // every time you tap a filter, which reads as a bug rather than a mode.
        // A selected *day* is different: the user asked to see one day, so
        // everything describes that day.
        final provider = await providerWithTwoDays();

        provider.filter = TransactionFilter.income;
        expect(provider.filteredTransactions, isEmpty);
        expect(provider.totalExpenses, 410);
        expect(provider.totalIncome, 0);

        provider.setSelectedDay(DateTime(anchor.year, anchor.month, 4));
        expect(provider.totalExpenses, 160);
      },
    );

    test('daysWithTransactions reports distinct days', () async {
      final provider = await providerWithTwoDays();

      // Three transactions but only two distinct days.
      expect(provider.daysWithTransactions, hasLength(2));
      expect(
        provider.daysWithTransactions,
        contains(DateTime(anchor.year, anchor.month, 4)),
      );
      expect(
        provider.daysWithTransactions,
        contains(DateTime(anchor.year, anchor.month, 9)),
      );
    });

    test('selecting the same day twice notifies once', () async {
      final provider = await providerWithTwoDays();
      var notifications = 0;
      provider.addListener(() => notifications++);

      provider.setSelectedDay(DateTime(anchor.year, anchor.month, 4));
      expect(notifications, 1);

      // A redundant selection must not rebuild the screen for nothing.
      provider.setSelectedDay(DateTime(anchor.year, anchor.month, 4));
      expect(notifications, 1);
    });
  });

  group('daily totals for the charts', () {
    test('one entry per day that has something, oldest first', () async {
      final provider = TransactionProvider();
      await provider.loadTransactionsForMonth(anchor.year, anchor.month);
      await provider.addTransaction(
        _expense(
          100,
          ExpenseCategory.food,
          date: DateTime(anchor.year, anchor.month, 9),
        ),
      );
      await provider.addTransaction(
        _expense(
          50,
          ExpenseCategory.food,
          date: DateTime(anchor.year, anchor.month, 4),
        ),
      );
      await provider.addTransaction(
        Income(
          amount: 900,
          category: 'salary',
          description: 'Payday',
          date: DateTime(anchor.year, anchor.month, 4),
        ),
      );

      final totals = provider.dailyTotals;

      // Days with nothing are omitted rather than plotted as zero-height bars.
      // A chart padded out with empty days is what the journeys 7-day chart
      // was, and it was deleted for carrying no information.
      expect(totals, hasLength(2));
      expect(totals.first.day, DateTime(anchor.year, anchor.month, 4));
      expect(totals.first.income, 900);
      expect(totals.first.expenses, 50);
      expect(totals.last.day, DateTime(anchor.year, anchor.month, 9));
      expect(totals.last.expenses, 100);
      expect(totals.last.income, 0);
    });

    test('daily totals follow a selected day', () async {
      final provider = await providerWithTwoDays();

      provider.setSelectedDay(DateTime(anchor.year, anchor.month, 4));

      final totals = provider.dailyTotals;
      expect(totals, hasLength(1));
      expect(totals.single.expenses, 160);
    });

    test('a month with nothing recorded yields no chart data', () async {
      final provider = TransactionProvider();
      await provider.loadTransactionsForMonth(anchor.year, anchor.month - 2);
      expect(provider.dailyTotals, isEmpty);
    });
  });

  group('date ranges', () {
    test('a one-day range includes that day', () async {
      final provider = TransactionProvider();
      await provider.loadTransactionsForMonth(anchor.year, anchor.month);
      await provider.addTransaction(
        _expense(
          100,
          ExpenseCategory.food,
          date: DateTime(anchor.year, anchor.month, 12, 9),
        ),
      );
      await provider.addTransaction(
        _expense(
          50,
          ExpenseCategory.food,
          date: DateTime(anchor.year, anchor.month, 13, 9),
        ),
      );

      // The boundary used to be compared with isAfter, which is strict, so a
      // one-day range silently returned nothing.
      final onThe12th = provider.getTransactionsInDateRange(
        DateTime(anchor.year, anchor.month, 12),
        DateTime(anchor.year, anchor.month, 12),
      );
      expect(onThe12th, hasLength(1));
      expect(onThe12th.single.amount, 100);
    });

    test('a range includes both boundary days', () async {
      final provider = TransactionProvider();
      await provider.loadTransactionsForMonth(anchor.year, anchor.month);
      await provider.addTransaction(
        _expense(
          100,
          ExpenseCategory.food,
          date: DateTime(anchor.year, anchor.month, 12, 9),
        ),
      );
      await provider.addTransaction(
        _expense(
          50,
          ExpenseCategory.food,
          date: DateTime(anchor.year, anchor.month, 14, 9),
        ),
      );
      await provider.addTransaction(
        _expense(
          25,
          ExpenseCategory.food,
          date: DateTime(anchor.year, anchor.month, 15, 9),
        ),
      );

      final range = provider.getTransactionsInDateRange(
        DateTime(anchor.year, anchor.month, 12),
        DateTime(anchor.year, anchor.month, 14),
      );
      expect(range.map((t) => t.amount), [100, 50]);
    });
  });
}
