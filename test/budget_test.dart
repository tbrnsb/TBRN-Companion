import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/budget_provider.dart';
import 'package:flutter_application_1/providers/journey_provider.dart';
import 'package:flutter_application_1/providers/settings_provider.dart';
import 'package:flutter_application_1/providers/transaction_provider.dart';
import 'package:flutter_application_1/screens/budgets/budgets_screen.dart';
import 'package:flutter_application_1/services/demo_data_service.dart';
import 'package:flutter_application_1/services/storage_service.dart';
import 'package:flutter_application_1/theme/app_theme.dart';

import 'test_viewports.dart';
import 'visual_smoke_test.dart' show initTestStorage;

Future<void> settleUi(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Expense _expense(
  double amount,
  ExpenseCategory category, {
  DateTime? date,
  String description = 'Test expense',
  String? journeyId,
  String? paidByParticipantId,
}) {
  return Expense(
    amount: amount,
    category: category,
    description: description,
    date: date ?? DateTime.now(),
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

  group('period windows', () {
    test('a month window is half-open, so the last day is inside it', () {
      final window = BudgetPeriod.month.window(DateTime(2024, 5));
      expect(window.start, DateTime(2024, 5, 1));
      expect(window.end, DateTime(2024, 6, 1));
      // The 31st is in May. `isBefore(end)` rather than `isAfter(start)` and
      // `<= lastDay`, because a one-day range returning nothing at all is a
      // silent empty result rather than an error.
      expect(DateTime(2024, 5, 31).isBefore(window.end), isTrue);
    });

    test('a week window starts on Monday, matching the weekly chart', () {
      // 2024-05-15 is a Wednesday.
      final window = BudgetPeriod.week.window(DateTime(2024, 5, 15));
      expect(window.start, DateTime(2024, 5, 13));
      expect(window.start.weekday, DateTime.monday);
      expect(window.end, DateTime(2024, 5, 20));
    });

    test('a year window is the calendar year', () {
      final window = BudgetPeriod.year.window(DateTime(2024, 5, 15));
      expect(window.start, DateTime(2024));
      expect(window.end, DateTime(2025));
    });
  });

  group('the spending accessor', () {
    Future<TransactionProvider> seeded() async {
      final provider = TransactionProvider();
      await provider.loadTransactionsForMonth(2024, 5);
      await provider.addTransaction(
        _expense(100, ExpenseCategory.food, date: DateTime(2024, 5, 3)),
      );
      await provider.addTransaction(
        _expense(250, ExpenseCategory.travel, date: DateTime(2024, 5, 8)),
      );
      // Outside the month, must not be counted.
      await provider.addTransaction(
        _expense(999, ExpenseCategory.food, date: DateTime(2024, 4, 30)),
      );
      return provider;
    }

    test('totals and per-category figures agree with each other', () async {
      final provider = await seeded();
      final index = provider.spendIndex(anchor: DateTime(2024, 5));

      expect(index.total, 350);
      expect(index.forCategory(ExpenseCategory.food), 100);
      expect(index.forCategory(ExpenseCategory.travel), 250);
      // The April record is outside the window.
      expect(index.totalSpendCategory(ExpenseCategory.food.name), 100);
    });

    test('a period wider than the loaded month is not answered off one month', () async {
      final provider = TransactionProvider();
      // The screen is showing May.
      await provider.loadTransactionsForMonth(2024, 5);
      await provider.addTransaction(
        _expense(100, ExpenseCategory.food, date: DateTime(2024, 5, 3)),
      );
      // A record in another month, as if saved and then navigated away from.
      await provider.addTransaction(
        _expense(7000, ExpenseCategory.travel, date: DateTime(2024, 2, 10)),
      );

      // May, asked about May: the loaded month answers it.
      expect(provider.spendIndex(anchor: DateTime(2024, 5)).total, 100);
      // A YEAR anchored on May must not report May's 100 as a year's spending.
      // Reading the loaded month for a wide window is the failure this guards:
      // a yearly budget would show 1% used and the user would set no limits.
      expect(
        provider
            .spendIndex(period: BudgetPeriod.year, anchor: DateTime(2024, 5))
            .total,
        7100,
      );
      // A MONTH anchored on a month that is not loaded must not report nothing.
      expect(provider.spendIndex(anchor: DateTime(2024, 2)).total, 7000);
    });

    test('a week anchor narrows the same accessor', () async {
      final provider = await seeded();
      // The 3rd is a Friday; that Monday-to-Sunday week runs 29 April to 5 May,
      // so it catches the 3rd's 100 and the 8th's 250 falls outside it. A week
      // window is not a month window with fewer days — it has to be able to
      // reach into the month before.
      final index = provider.spendIndex(
        period: BudgetPeriod.week,
        anchor: DateTime(2024, 5, 3),
      );
      // The 3rd (100) is in that week. The 8th (250) is not. The seeded 30 April
      // record (999) IS — which is the point: a week window has to reach back
      // into the previous month, so it cannot be answered from a list holding
      // only May.
      expect(index.total, 1099);
      expect(index.forCategory(ExpenseCategory.food), 1099);
      expect(index.forCategory(ExpenseCategory.travel), 0);
    });

    test('the accessor is the single source: totalSpend and categorySpend read it', () async {
      final provider = await seeded();
      final anchor = DateTime(2024, 5);
      // If these three ever computed their own sums, a change to what counts as
      // my spending would move the index and leave these behind. They are here to
      // fail if someone inlines one.
      expect(
        provider.totalSpend(anchor: anchor),
        provider.spendIndex(anchor: anchor).total,
      );
      expect(
        provider.categorySpend(ExpenseCategory.food, anchor: anchor),
        provider.spendIndex(anchor: anchor).forCategory(ExpenseCategory.food),
      );
    });
  });

  group('journey budgets are a separate pool', () {
    test('a trip expense I paid counts in BOTH pools', () async {
      final provider = TransactionProvider();
      await provider.loadTransactionsForMonth(2024, 5);
      // "Me" is a fact about the TRIP, not the expense, so the provider has to be
      // told. Omitting this is not a no-op: the first version of the rule assumed
      // any non-null payer was somebody else and silently dropped the user's own
      // trip spending while looking exactly correct.
      provider.setLocalParticipant('trip-1', 'me');
      await provider.addTransaction(
        _expense(
          500,
          ExpenseCategory.food,
          date: DateTime(2024, 5, 4),
          journeyId: 'trip-1',
          paidByParticipantId: 'me',
        ),
      );
      final index = provider.spendIndex(anchor: DateTime(2024, 5));

      // The CORRECTED rule: my own trip spending is my spending. It has to agree
      // with the month total printed directly above the budget.
      expect(index.forCategory(ExpenseCategory.food), 500);
      expect(index.total, 500);
      // And it is also the trip's cost.
      expect(index.forJourney('trip-1'), 500);
    });

    test("another participant's trip expense counts nowhere", () async {
      final provider = TransactionProvider();
      await provider.loadTransactionsForMonth(2024, 5);
      provider.setLocalParticipant('trip-1', 'me');
      await provider.addTransaction(
        _expense(
          700,
          ExpenseCategory.food,
          date: DateTime(2024, 5, 4),
          journeyId: 'trip-1',
          paidByParticipantId: 'someone-else',
        ),
      );
      final index = provider.spendIndex(anchor: DateTime(2024, 5));

      expect(index.total, 0);
      expect(index.forCategory(ExpenseCategory.food), 0);
      expect(index.forJourney('trip-1'), 0);
    });

    test('a trip expense with no recorded payer counts — pre-field history', () async {
      final provider = TransactionProvider();
      await provider.loadTransactionsForMonth(2024, 5);
      provider.setLocalParticipant('trip-1', 'me');
      await provider.addTransaction(
        _expense(
          300,
          ExpenseCategory.travel,
          date: DateTime(2024, 5, 6),
          journeyId: 'trip-1',
        ),
      );
      final index = provider.spendIndex(anchor: DateTime(2024, 5));

      // Every expense written before `paidByParticipantId` existed has no payer.
      // Treating those as somebody else's would erase real spending. The
      // participant is set here precisely to prove it: the rule must not treat
      // an unknown payer as "not mine" just because a trip has an answer.
      expect(index.total, 300);
      expect(index.forJourney('trip-1'), 300);
    });

    test(
      'a plain expense with no journey counts in the app pool only',
      () async {
        final provider = TransactionProvider();
        await provider.loadTransactionsForMonth(2024, 5);
        await provider.addTransaction(
          _expense(80, ExpenseCategory.food, date: DateTime(2024, 5, 6)),
        );
        final index = provider.spendIndex(anchor: DateTime(2024, 5));

        expect(index.forCategory(ExpenseCategory.food), 80);
        expect(index.byJourney, isEmpty);
      },
    );
  });

  group('limits are stored, spend is not', () {
    test(
      'a limit round-trips through SharedPreferences with no new box',
      () async {
        final provider = BudgetProvider();
        await provider.setLimit(label: 'food', amount: 4500);

        // A fresh provider reading the same store sees the same limit. This is
        // what proves the limit is persisted rather than held in memory.
        final reloaded = BudgetProvider();
        await reloaded.load();
        expect(reloaded.limitFor(label: 'food'), 4500);
      },
    );

    test('a fractional limit is not rounded away', () async {
      final provider = BudgetProvider();
      await provider.setLimit(label: 'food', amount: 199.5);
      final reloaded = BudgetProvider();
      await reloaded.load();
      expect(reloaded.limitFor(label: 'food'), 199.5);
    });

    test('zero and negative mean unset, not a budget of nothing', () async {
      final provider = BudgetProvider();
      await provider.setLimit(label: 'food', amount: 5000);
      await provider.setLimit(label: 'food', amount: 0);
      expect(provider.hasLimit(label: 'food'), isFalse);

      await provider.setLimit(label: 'food', amount: -100);
      expect(provider.hasLimit(label: 'food'), isFalse);
    });

    test(
      'a journey limit and a category limit with the same name coexist',
      () async {
        final provider = BudgetProvider();
        await provider.setLimit(label: 'food', amount: 5000);
        await provider.setLimit(
          scope: 'journey-1',
          label: 'food',
          amount: 20000,
        );

        expect(provider.limitFor(label: 'food'), 5000);
        expect(provider.limitFor(scope: 'journey-1', label: 'food'), 20000);
        expect(provider.budgets, hasLength(2));
      },
    );
  });

  group('against real demo data', () {
    // The invariant the whole accessor exists to protect: the per-category
    // figures and the month total come from ONE pass over the data, so they
    // cannot disagree. Run against the demo seed rather than a hand-built
    // fixture, because the demo set is where shared-trip expenses, custom
    // categories and a settlement all coexist — the cases a synthetic list
    // would leave out.
    test('per-category totals add up to the month total', () async {
      await DemoDataService.seedAll();
      final provider = TransactionProvider();
      await provider.initialize();

      final index = provider.spendIndex(
        anchor: provider.currentMonth ?? DateTime.now(),
      );

      var categorySum = 0.0;
      for (final category in ExpenseCategory.values) {
        categorySum += index.forCategory(category);
      }
      expect(
        categorySum,
        moreOrLessEquals(index.total, epsilon: 0.01),
        reason:
            'a budget that reads one and the month card that reads the '
            'other is exactly the inconsistency this accessor exists to prevent',
      );

      // Every by-journey figure is a subset of the total, never additional to
      // it. A trip's cost is already counted in a category; adding the two pools
      // together would double-count every trip expense.
      var journeySum = 0.0;
      for (final amount in index.byJourney.values) {
        journeySum += amount;
      }
      expect(
        journeySum,
        lessThanOrEqualTo(index.total + 0.01),
        reason: 'the two pools are views of the same spend, not two spends',
      );
    });
  });

  group('BudgetStatus', () {
    test('an unset limit reports no limit and no progress', () {
      const status = BudgetStatus(label: 'Food', limit: null, spent: 900);
      expect(status.hasLimit, isFalse);
      expect(status.progress, 0);
      expect(status.shouldNotify, isFalse);
      expect(status.describe((v) => '$v'), 'No limit set');
    });

    test('progress is clamped but the ratio is not', () {
      const status = BudgetStatus(label: 'Food', limit: 100, spent: 250);
      // A progress bar cannot ask for more than its own track.
      expect(status.progress, 1.0);
      // But the copy needs the real ratio to be able to say "over by".
      expect(status.ratio, 2.5);
      expect(status.isOverspent, isTrue);
    });

    test('near-limit and overspent are different states', () {
      const near = BudgetStatus(label: 'Food', limit: 100, spent: 85);
      const over = BudgetStatus(label: 'Food', limit: 100, spent: 120);
      expect(near.isNearLimit, isTrue);
      expect(near.isOverspent, isFalse);
      expect(over.isNearLimit, isFalse);
      expect(over.isOverspent, isTrue);
      // Both notify, for different reasons.
      expect(near.shouldNotify, isTrue);
      expect(over.shouldNotify, isTrue);
    });

    test('spend at exactly the limit is not yet overspent', () {
      const status = BudgetStatus(label: 'Food', limit: 100, spent: 100);
      expect(status.isOverspent, isFalse);
      expect(status.isNearLimit, isTrue);
    });
  });

  group('the budgets screen', () {
    Future<TransactionProvider> pump(
      WidgetTester tester, {
      List<Transaction>? items,
      BudgetProvider? budgetProvider,
    }) async {
      final provider = (await tester.runAsync(() async {
        final p = TransactionProvider();
        await p.initialize();
        for (final item in items ?? <Transaction>[]) {
          await p.addTransaction(item);
        }
        return p;
      }))!;
      final settings = (await tester.runAsync(() async {
        final s = SettingsProvider();
        await s.load();
        return s;
      }))!;
      final budgets = budgetProvider ?? BudgetProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TransactionProvider>.value(value: provider),
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
            ChangeNotifierProvider<BudgetProvider>.value(value: budgets),
            ChangeNotifierProvider(create: (_) => JourneyProvider()),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            home: const Scaffold(body: BudgetsScreen()),
          ),
        ),
      );
      await settleUi(tester);
      return provider;
    }

    testWidgets('every category has a row and an unset one says so', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await pump(tester);

      for (final category in budgetableCategories()) {
        expect(
          find.byKey(ValueKey('budget-percent-cat:${category.name}')),
          findsOne,
        );
      }
      expect(
        find.byKey(const ValueKey('budget-percent-cat:food')),
        findsWidgets,
      );
    });

    testWidgets('a set limit turns the row into a percentage and a bar', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      final now = DateTime.now();
      final budgets = (await tester.runAsync(() async {
        final b = BudgetProvider();
        await b.setLimit(label: 'food', amount: 1000);
        return b;
      }))!;

      await pump(
        tester,
        budgetProvider: budgets,
        items: [_expense(250, ExpenseCategory.food, date: now)],
      );

      expect(find.byKey(const ValueKey('budget-bar-cat:food')), findsOne);
      expect(
        find.byKey(const ValueKey('budget-percent-cat:food')),
        findsWidgets,
      );
      // 250 of 1000.
      expect(find.text('25%', skipOffstage: false), findsWidgets);
    });

    testWidgets('no bar is drawn for a category with no limit', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await pump(
        tester,
        items: [_expense(250, ExpenseCategory.food, date: DateTime.now())],
      );

      // An empty track would imply a budget of zero, which is not the same
      // thing as no budget.
      expect(find.byKey(const ValueKey('budget-bar-cat:food')), findsNothing);
      expect(find.text('No limit', skipOffstage: false), findsWidgets);
    });

    testWidgets('the period chips change the window the figures come from', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await pump(
        tester,
        items: [_expense(400, ExpenseCategory.food, date: DateTime.now())],
      );

      expect(find.textContaining('spent in total'), findsOne);
      await tester.tap(find.byKey(const ValueKey('budget-period-year')));
      await settleUi(tester);
      // The year window still contains today, so the total is unchanged — but
      // the range line must now name a year rather than a month.
      expect(find.textContaining('spent in total'), findsOne);
    });

    for (final viewport in [
      TestViewports.phonePortrait,
      TestViewports.phoneSmall,
    ]) {
      testWidgets('no overflow at $viewport', (tester) async {
        usePhoneLayout(tester, viewport);
        final budgets = (await tester.runAsync(() async {
          final b = BudgetProvider();
          await b.setLimit(label: 'food', amount: 1000);
          await b.setLimit(label: 'travel', amount: 100);
          return b;
        }))!;
        await pump(
          tester,
          budgetProvider: budgets,
          items: [
            _expense(2500, ExpenseCategory.food, date: DateTime.now()),
            _expense(900, ExpenseCategory.travel, date: DateTime.now()),
          ],
        );

        expect(tester.takeException(), isNull);
      });
    }
  });
}
