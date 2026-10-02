import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/providers/budget_provider.dart';
import 'package:daily_companion/providers/journey_provider.dart';
import 'package:daily_companion/providers/transaction_provider.dart';

import 'seed_fixture.dart';

import 'package:daily_companion/services/storage_service.dart';

import 'visual_smoke_test.dart' show initTestStorage;

// Taken from the fixture rather than hardcoded, so a test that reads a seeded
// trip and a test that builds its own agree on who is who.
const String _me = '${SeedFixture.idPrefix}you';
const String _sita = '${SeedFixture.idPrefix}sita';
const String _raj = '${SeedFixture.idPrefix}raj';

/// An expense on the shared trip, paid by [payer].
Expense _tripExpense(
  double amount,
  ExpenseCategory category, {
  required String journeyId,
  required String? payer,
  required DateTime date,
  String description = 'Trip expense',
}) {
  return Expense(
    amount: amount,
    category: category,
    description: description,
    journeyId: journeyId,
    paidByParticipantId: payer,
    date: date,
  );
}

/// A month carrying one row for every case in the four-case table.
///
/// Deliberately built in ONE function so the table cannot drift: each row below
/// is named after the case it stands for, and every test reads the same set.
Future<TransactionProvider> fourCaseProvider() async {
  final provider = TransactionProvider();
  await provider.loadTransactionsForMonth(2026, 3);
  provider.setLocalParticipant('trip-1', _me);

  await provider.addTransaction(
    Expense(
      amount: 100,
      category: ExpenseCategory.food,
      description: 'plain expense, no trip',
      date: DateTime(2026, 3, 2),
    ),
  );
  await provider.addTransaction(
    _tripExpense(
      200,
      ExpenseCategory.travel,
      journeyId: 'trip-1',
      payer: _me,
      date: DateTime(2026, 3, 3),
      description: 'trip, I paid',
    ),
  );
  await provider.addTransaction(
    _tripExpense(
      400,
      ExpenseCategory.food,
      journeyId: 'trip-1',
      payer: _sita,
      date: DateTime(2026, 3, 4),
      description: 'trip, Sita paid',
    ),
  );
  await provider.addTransaction(
    _tripExpense(
      800,
      ExpenseCategory.travel,
      journeyId: 'trip-1',
      payer: _raj,
      date: DateTime(2026, 3, 5),
      description: 'trip, Raj paid',
    ),
  );
  await provider.addTransaction(
    _tripExpense(
      3200,
      ExpenseCategory.health,
      journeyId: 'trip-1',
      payer: _raj,
      date: DateTime(2026, 3, 7),
      description: 'trip, Raj paid health only',
    ),
  );
  await provider.addTransaction(
    _tripExpense(
      1600,
      ExpenseCategory.food,
      journeyId: 'trip-1',
      payer: null,
      date: DateTime(2026, 3, 6),
      description: 'trip, no payer recorded',
    ),
  );
  return provider;
}

void main() {
  setUpAll(() async {
    await initTestStorage();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService().clear();
  });

  group('the four-case table, against the view', () {
    // THE CONTRACT, asserted against `_viewTransactions` rather than against
    // the predicate. Asserting the predicate only would pass while the view
    // returned raw rows — which is precisely what was wrong before this item.
    test('exactly the right rows are in the view', () async {
      final provider = await fourCaseProvider();

      final descriptions = provider.filteredTransactions
          .map((t) => t.description)
          .toSet();

      expect(descriptions, contains('plain expense, no trip'));
      expect(descriptions, contains('trip, I paid'));
      expect(descriptions, contains('trip, no payer recorded'));
      expect(descriptions, isNot(contains('trip, Sita paid')));
      expect(descriptions, isNot(contains('trip, Raj paid')));
    });

    test('and the two excluded rows are still on the device', () async {
      await fourCaseProvider();

      // The rule is a VIEW, not a deletion. Storage still holds everything, so a
      // trip summary can still show the whole trip's costs.
      final all = await StorageService().getAllTransactions();
      expect(all, hasLength(6));
      expect(
        all.map((t) => t.description),
        containsAll(['trip, Sita paid', 'trip, Raj paid']),
      );
    });
  });

  group('the totals a user reads', () {
    test('a trip expense I paid IS in totalExpenses', () async {
      final provider = await fourCaseProvider();
      // 100 plain + 200 mine + 1600 with no payer recorded.
      expect(provider.totalExpenses, 1900);
    });

    test('a trip expense someone else paid is NOT', () async {
      final provider = await fourCaseProvider();
      // Removing them changes nothing at all.
      expect(provider.totalExpenses, 1900);
      final sita = provider.transactions.firstWhere(
        (t) => t.description == 'trip, Sita paid',
      );
      expect(
        provider.filteredTransactions.any((t) => t.id == sita.id),
        isFalse,
      );
    });

    test('a trip expense with paidBy null IS counted', () async {
      final provider = await fourCaseProvider();
      final unpaid = provider.transactions.firstWhere(
        (t) => t.description == 'trip, no payer recorded',
      );
      expect(unpaid.journeyId, isNotNull);
      expect(unpaid.paidByParticipantId, isNull);
      expect(
        provider.filteredTransactions.any((t) => t.id == unpaid.id),
        isTrue,
      );
      // 1600 of the 1900 is exactly this one row. The fourth row of the table
      // is the migration trap: treating an unknown payer as somebody else's
      // would erase real historical spending.
      expect(provider.totalExpenses - 300, 1600);
    });

    test(
      'income is unaffected, because the rule cannot match an Income',
      () async {
        final provider = TransactionProvider();
        await provider.loadTransactionsForMonth(2026, 3);
        await provider.addTransaction(
          Income(
            amount: 5000,
            category: 'salary',
            description: 'Payday',
            date: DateTime(2026, 3, 1),
          ),
        );
        expect(provider.totalIncome, 5000);
        expect(provider.balance, 5000);
      },
    );

    test(
      'a shared-trip income, if one ever exists, is judged the same way',
      () async {
        // `Income` carries no journeyId or paidByParticipantId at all, so
        // `isMyLedgerEntry` reads journeyId as null and counts it. That is the
        // answer, and it is the right one: the rule is about expenses somebody else
        // fronted, and there is no such thing here.
        final provider = TransactionProvider();
        await provider.loadTransactionsForMonth(2026, 3);
        provider.setLocalParticipant('trip-1', _me);
        await provider.addTransaction(
          Income(
            amount: 900,
            category: 'gift',
            description: 'Trip refund',
            date: DateTime(2026, 3, 7),
          ),
        );
        expect(provider.totalIncome, 900);
        expect(provider.filteredTransactions, hasLength(1));
      },
    );
  });

  group('every consumer inherits the same view', () {
    test(
      'dailyTotals, the breakdown slices and the charts all drop them',
      () async {
        final provider = await fourCaseProvider();

        // dailyTotals feeds the pager's daily and balance pages.
        final byDay = {for (final d in provider.dailyTotals) d.day.day: d};
        expect(byDay[2]!.expenses, 100);
        expect(byDay[3]!.expenses, 200);
        expect(byDay[4], isNull, reason: 'Sita paid that day; nothing of mine');
        expect(byDay[5], isNull, reason: 'Raj paid that day; nothing of mine');
        expect(byDay[6]!.expenses, 1600);

        // The category-level roll-up.
        final rollup = {
          for (final e in provider.getSpendingBreakdown()) e.key: e.value,
        };
        expect(rollup[ExpenseCategory.food], 1700); // 100 + 1600
        expect(rollup[ExpenseCategory.travel], 200);

        // The resolved slices, which is what the donut actually draws.
        final sliceTotals = provider.getSpendingBreakdownSlices().fold<double>(
          0,
          (sum, s) => sum + s.amount,
        );
        expect(sliceTotals, 1900);

        final incomeBreakdown = provider.getIncomeBreakdown();
        expect(incomeBreakdown, isEmpty);
      },
    );

    test(
      'average daily spending follows, because it reads the same total',
      () async {
        final provider = await fourCaseProvider();
        // 1900 over 31 days in March 2026, read through getSpendingByCategory.
        expect(provider.getAverageDailySpending(), closeTo(1900 / 31, 0.001));
      },
    );

    test('located expenses and recent transactions drop them too', () async {
      final provider = await fourCaseProvider();
      // None of these rows carry coordinates, so the map helpers are empty either
      // way — which is itself worth pinning, because a future coordinate would
      // otherwise be the first thing to leak a trip expense onto a map.
      expect(provider.locatedExpenses, isEmpty);
      expect(provider.recentTransactions, hasLength(3));
      expect(
        provider.recentTransactions.map((t) => t.description),
        isNot(contains('trip, Raj paid health only')),
      );
      expect(
        provider.getTransactionsInDateRange(
          DateTime(2026, 3, 1),
          DateTime(2026, 3, 31),
        ),
        hasLength(3),
      );
    });

    test('the category suggestion helpers describe MY spending', () async {
      final provider = await fourCaseProvider();
      // `health` appears nowhere in my ledger — only Raj ever spent on it. If it
      // shows up on a chip, the helpers are still reading raw rows.
      // `categories` is keyed by DISPLAY NAME, so compare on what it actually
      // holds rather than on the enum name it looks like it should.
      expect(provider.categories.keys, isNot(contains('Health')));
      expect(
        provider.popularCategories.map((m) => m.id),
        isNot(contains('health')),
      );
      expect(
        provider.recentCategories.map((m) => m.id),
        isNot(contains('health')),
      );
      // And travel IS here, because the 200 I paid put it there. Its presence is
      // not the leak; its absence would be the bug.
      expect(provider.categories.keys, contains('Travel'));
    });

    test(
      'daysWithTransactions does not mark a day that would show nothing',
      () async {
        final provider = await fourCaseProvider();
        final days = provider.daysWithTransactions.map((d) => d.day).toSet();
        expect(days, {2, 3, 6});
        // The decision: marking the 4th would invite a tap that shows an empty
        // list, which reads as a broken screen rather than as an empty day.
        expect(days.contains(4), isFalse);
        expect(days.contains(5), isFalse);
      },
    );
  });

  group('the split-brain test', () {
    // THE ONE THAT MATTERS. Budgets read `spendIndex`; the summary card read
    // `_viewTransactions`. For September the two disagreed by 8400 — two numbers
    // for one month, on one screen, with a budget card next to the total it
    // contradicted.
    test('totalExpenses and spendIndex().total agree', () async {
      await SeedFixture.seed();
      final provider = TransactionProvider();
      await provider.initialize();

      final anchor = provider.currentMonth!;
      expect(
        provider.totalExpenses,
        provider.spendIndex(anchor: anchor).total,
        reason:
            'the month card and the budget beside it must quote the same '
            'number for the same month',
      );
    });

    test('and they agree per category too', () async {
      await SeedFixture.seed();
      final provider = TransactionProvider();
      await provider.initialize();

      final index = provider.spendIndex(anchor: provider.currentMonth!);
      final slices = provider.getSpendingBreakdownSlices();
      final fromSlices = slices.fold<double>(0, (sum, s) => sum + s.amount);

      expect(fromSlices, closeTo(index.total, 0.01));
      expect(provider.totalExpenses, closeTo(index.total, 0.01));
    });

    test('and the day view is that day\'s slice of the ledger', () async {
      await SeedFixture.seed();
      final provider = TransactionProvider();
      await provider.initialize();

      // Read the ledger's rows for a chosen day, then select it and ask the view.
      // This is the one place the two could disagree while the monthly totals
      // agree, because the day filter is a second narrowing on top.
      final ledger = provider.myLedger;
      final day = DateTime(
        ledger.first.date.year,
        ledger.first.date.month,
        ledger.first.date.day,
      );
      final expected = ledger
          .where(
            (t) =>
                t.date.year == day.year &&
                t.date.month == day.month &&
                t.date.day == day.day,
          )
          .where((t) => t.isExpense)
          .fold<double>(0, (sum, t) => sum + t.amount);

      provider.setSelectedDay(day);
      expect(provider.totalExpenses, closeTo(expected, 0.01));
      expect(
        provider.filteredTransactions,
        hasLength(
          ledger
              .where(
                (t) =>
                    t.date.day == day.day &&
                    t.date.month == day.month &&
                    t.date.year == day.year,
              )
              .length,
        ),
      );
    });
  });

  group('search, budgets, trash, export', () {
    test('search cannot find or total another participant trip expense', () async {
      final provider = await fourCaseProvider();

      provider.search = const TransactionSearchQuery(text: 'trip');
      final found = provider.searchResults.map((t) => t.description).toSet();
      expect(found, contains('trip, I paid'));
      expect(found, contains('trip, no payer recorded'));
      expect(found, isNot(contains('trip, Sita paid')));
      expect(found, isNot(contains('trip, Raj paid')));

      // And the total shown beside the results comes from the same rows. 1900,
      // not 1800: the term 'trip' also matches 'plain expense, no trip'.
      expect(provider.searchTotalExpenses, 1900);
    });

    test('a budget counts my trip expense and not theirs', () async {
      final provider = await fourCaseProvider();
      final budgets = BudgetProvider();
      final anchor = DateTime(2026, 3);
      await budgets.setLimit(label: 'travel', amount: 1000);

      final statuses = budgets.statusesFor(
        provider.spendIndex(anchor: anchor),
        journeyLabels: const <String, String>{},
      );
      final status = statuses.single;
      // 200 is mine; the 800 Raj paid would have pushed this to 1000/1000.
      expect(status.spent, 200);
      expect(status.isOverspent, isFalse);

      // And a JOURNEY budget still sees the whole trip, because its pool is the
      // trip's own costs whoever paid. The two pools disagree deliberately.
      await budgets.setLimit(scope: 'trip-1', label: 'trip-1', amount: 5000);
      final tripStatus = budgets
          .statusesFor(
            provider.spendIndex(anchor: anchor),
            journeyLabels: const {'trip-1': 'Pokhara'},
          )
          .firstWhere((s) => s.isJourneyLevel);
      expect(tripStatus.label, 'Pokhara');
      // 200 (I paid) + 1600 (no payer) = 1800. NOT 3000: the stated rule is
      // that another participant's trip expense counts NOWHERE, ever, and a
      // budget is one of the places it counts. The journey pool is separate
      // from the category pool but filtered by the same rule.
      expect(tripStatus.spent, 1800);
    });

    test('a trashed trip expense of MINE stops counting', () async {
      final provider = await fourCaseProvider();
      expect(provider.totalExpenses, 1900);

      final mine = provider.transactions.firstWhere(
        (t) => t.description == 'trip, I paid',
      );
      await provider.moveToTrash(mine.id);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(provider.totalExpenses, 1700);
      expect(
        provider.spendIndex(anchor: DateTime(2026, 3)).total,
        1700,
        reason: 'the trash flag and the shared-trip rule must compose',
      );
    });

    test('CSV export omits theirs and keeps mine', () async {
      final provider = await fourCaseProvider();
      final csv = provider.exportCurrentMonthCsv();
      expect(csv, contains('trip, I paid'));
      expect(csv, isNot(contains('trip, Sita paid')));
      expect(csv, isNot(contains('trip, Raj paid')));
    });

    test(
      'the import ledger offered to the importer is also my ledger',
      () async {
        final provider = await fourCaseProvider();
        final existing = await provider.existingLedgerForImport();
        expect(
          existing.map((t) => t.description),
          isNot(contains('trip, Raj paid')),
        );
      },
    );
  });

  group('settlement does not move', () {
    // THE ONE THING THAT MUST NOT CHANGE. `getTransactionsByJourney` is
    // deliberately unfiltered, so deleting or hiding a trip expense from my
    // ledger cannot move what I owe Raj.
    test('the settlement still sees the whole trip', () async {
      await SeedFixture.seed();
      final journeys = JourneyProvider();
      addTearDown(journeys.dispose);
      await journeys.initialize();

      final provider = TransactionProvider();
      await provider.initialize();

      final trip = journeys.journeys.firstWhere((j) => j.isShared);
      final forSettlement = await provider.getTransactionsByJourney(trip.id);
      final forDisplay = await provider.getLiveTransactionsForJourney(trip.id);

      final total = await journeys.tripSettlement(trip.id);
      final expectedInPaise = forSettlement.whereType<Expense>().fold<int>(
        0,
        (sum, e) => sum + (e.amount * 100).round(),
      );

      expect(
        total.totalInPaise,
        expectedInPaise,
        reason:
            'settlement must count 100% of the trip whatever my ledger shows',
      );

      // And the two views genuinely differ, so the test above is not comparing a
      // number against itself.
      expect(forSettlement.length, greaterThan(0));
      final myLedgerDescriptions = provider.transactions
          .map((t) => t.description)
          .toSet();
      expect(
        forDisplay.any((t) => !myLedgerDescriptions.contains(t.description)),
        isTrue,
        reason: 'the display twin drops rows my ledger does not have',
      );
    });
  });

  group('an unanswered trip', () {
    test('falls back to excluding, and corrects itself when answered', () async {
      final provider = TransactionProvider();
      await provider.loadTransactionsForMonth(2026, 3);
      await provider.addTransaction(
        _tripExpense(
          500,
          ExpenseCategory.food,
          journeyId: 'trip-1',
          payer: _me,
          date: DateTime(2026, 3, 4),
        ),
      );

      // Nobody has said which participant is "me", so no payer matches and the
      // row is conservatively excluded rather than wrongly claimed.
      expect(provider.totalExpenses, 0);

      provider.setLocalParticipant('trip-1', _me);
      expect(provider.totalExpenses, 500);

      // And the user answering later fixes it in place, with no reload.
      provider.setLocalParticipant('trip-1', _sita);
      expect(provider.totalExpenses, 0);
    });
  });
}
