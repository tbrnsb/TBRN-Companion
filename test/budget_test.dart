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

/// The money figure out of the category row's caption, parsed back to a number.
///
/// Read from the CAPTION rather than from the provider: the caption is what the
/// user sees, and a test that read the model instead would pass while the screen
/// showed the wrong figure. [period] names the row explicitly, so this can never
/// quietly read the previous period's reading after the control switched.
double _foodTotal(WidgetTester tester, BudgetPeriod period) {
  final caption = tester.widget<Text>(
    find.byKey(ValueKey('budget-caption-cat:food:${period.name}')),
  );
  final match = RegExp(r'([\d,]+(?:\.\d+)?)').firstMatch(caption.data!);
  return double.parse(match!.group(1)!.replaceAll(',', ''));
}

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

  group('period-aware storage keys', () {
    // THE KEY IS THE PERIOD. It used to be `cat:food`, so a monthly food limit
    // and a weekly one shared one slot: setting the weekly number replaced the
    // monthly one, and only whichever was written last was ever readable.
    test('a limit for one period does not disturb another', () async {
      final budgets = BudgetProvider();
      await budgets.setLimit(
        label: 'food',
        amount: 2000,
        period: BudgetPeriod.month,
      );
      await budgets.setLimit(
        label: 'food',
        amount: 500,
        period: BudgetPeriod.week,
      );

      expect(budgets.limitFor(label: 'food', period: BudgetPeriod.month), 2000);
      expect(budgets.limitFor(label: 'food', period: BudgetPeriod.week), 500);
      expect(
        budgets.limitFor(label: 'food', period: BudgetPeriod.year),
        isNull,
      );

      // And they SURVIVE a reload, so this is not just in-memory bookkeeping.
      final reloaded = BudgetProvider();
      await reloaded.load();
      expect(
        reloaded.limitFor(label: 'food', period: BudgetPeriod.month),
        2000,
      );
      expect(reloaded.limitFor(label: 'food', period: BudgetPeriod.week), 500);
      expect(reloaded.budgets.length, 2);
    });

    test('a trip limit is period-aware too', () async {
      final budgets = BudgetProvider();
      await budgets.setLimit(
        scope: 'trip-1',
        label: 'trip-1',
        amount: 8000,
        period: BudgetPeriod.month,
      );
      await budgets.setLimit(
        scope: 'trip-1',
        label: 'trip-1',
        amount: 2000,
        period: BudgetPeriod.year,
      );

      expect(
        budgets.limitFor(
          scope: 'trip-1',
          label: 'trip-1',
          period: BudgetPeriod.month,
        ),
        8000,
      );
      expect(
        budgets.limitFor(
          scope: 'trip-1',
          label: 'trip-1',
          period: BudgetPeriod.year,
        ),
        2000,
      );
    });

    test('a key reads back with its period attached', () {
      expect(BudgetKey.parse('cat:food:week')!.period, BudgetPeriod.week);
      expect(BudgetKey.parse('cat:food:week')!.isLegacy, isFalse);
      expect(BudgetKey.parse('cat:food:week')!.label, 'food');
      expect(BudgetKey.parse('cat:food:week')!.isJourneyLevel, isFalse);

      final trip = BudgetKey.parse('trip:8f14e45f:year')!;
      expect(trip.scope, '8f14e45f');
      expect(trip.period, BudgetPeriod.year);
      expect(trip.isJourneyLevel, isTrue);

      // A segment that is not a period is REJECTED rather than guessed at: a
      // corrupt key reported as a real budget is worse than a key ignored.
      expect(BudgetKey.parse('cat:food:fortnight'), isNull);
      expect(BudgetKey.parse('nonsense'), isNull);
    });

    test(
      'only the budgets for a period are read against that spending',
      () async {
        // A monthly limit and a weekly one both exist, so reading every budget
        // against one period's spending would judge each against the wrong figure.
        final provider = BudgetProvider();
        await provider.setLimit(
          label: 'food',
          amount: 500,
          period: BudgetPeriod.week,
        );
        await provider.setLimit(
          label: 'food',
          amount: 2000,
          period: BudgetPeriod.month,
        );
        final index = BudgetSpendIndex(
          period: BudgetPeriod.week,
          anchorMonth: DateTime(2026, 10),
          total: 900,
          byCategory: {'food': 900},
          byJourney: const {},
        );
        final statuses = provider.statusesFor(index, journeyLabels: const {});
        expect(statuses.length, 1);
        expect(statuses.single.period, BudgetPeriod.week);
        expect(statuses.single.label, 'Food');
      },
    );

    test('a notification key is period-aware, so a crossing speaks twice', () {
      // With a period-less key, this week's crossing was suppressed as a
      // duplicate of this month's and the user was told about it once, ever.
      const month = BudgetStatus(
        label: 'Food',
        limit: 100,
        spent: 120,
        period: BudgetPeriod.month,
      );
      const week = BudgetStatus(
        label: 'Food',
        limit: 100,
        spent: 120,
        period: BudgetPeriod.week,
      );
      expect(month.storageKey, isNot(week.storageKey));
      expect(month.storageKey, 'cat:Food:month');
      expect(week.storageKey, 'cat:Food:week');
    });
  });

  group('the period-less key migration', () {
    // Limits were stored as `budget_limit_cat:food`. They belong to MONTH,
    // because month was the only period that ever existed. The old key is
    // REMOVED so the migration cannot run twice and cannot leave a shadow copy
    // that a later write would resurrect.
    test(
      'a period-less limit lands on month and the old key is gone',
      () async {
        // Stored in hundredths, so 4500 rupees is 450000. The first version of
        // this test wrote 4500 and expected 4500 back, which would also have
        // passed against a provider that ignored units entirely.
        SharedPreferences.setMockInitialValues({
          'budget_limit_cat:food': 450000,
        });
        final prefs = await SharedPreferences.getInstance();

        final budgets = BudgetProvider();
        await budgets.load();

        expect(budgets.migrationsApplied, 1);
        expect(
          budgets.limitFor(label: 'food', period: BudgetPeriod.month),
          4500,
        );
        expect(prefs.containsKey('budget_limit_cat:food'), isFalse);
        expect(prefs.getInt('budget_limit_cat:food:month'), 450000);

        // The migrated value survives a second load, and the migration does NOT
        // run again — the key it would migrate no longer exists.
        final again = BudgetProvider();
        await again.load();
        expect(again.migrationsApplied, 0);
        expect(again.limitFor(label: 'food', period: BudgetPeriod.month), 4500);
      },
    );

    test('a period-less trip limit migrates to month too', () async {
      // Not only categories: leaving trip limits on the old key would orphan
      // every limit the user had set for a trip.
      SharedPreferences.setMockInitialValues({
        'budget_limit_trip:abc123': 900000,
      });
      final prefs = await SharedPreferences.getInstance();

      final budgets = BudgetProvider();
      await budgets.load();

      expect(budgets.migrationsApplied, 1);
      expect(
        budgets.limitFor(
          scope: 'abc123',
          label: 'abc123',
          period: BudgetPeriod.month,
        ),
        9000,
      );
      expect(prefs.containsKey('budget_limit_trip:abc123'), isFalse);
      expect(prefs.getInt('budget_limit_trip:abc123:month'), 900000);
    });

    test('period-aware and legacy limits coexist after a migration', () async {
      SharedPreferences.setMockInitialValues({
        'budget_limit_cat:food': 450000,
        'budget_limit_cat:food:week': 50000,
      });

      final budgets = BudgetProvider();
      await budgets.load();

      expect(budgets.migrationsApplied, 1);
      expect(budgets.limitFor(label: 'food', period: BudgetPeriod.month), 4500);
      expect(budgets.limitFor(label: 'food', period: BudgetPeriod.week), 500);
      expect(budgets.budgets.length, 2);
    });

    test('an unparseable key is left alone rather than deleted', () async {
      // It might belong to a future version. Removing it would destroy a limit
      // this build has no way to interpret.
      SharedPreferences.setMockInitialValues({
        'budget_limit_cat:food:fortnight': 70000,
      });
      final prefs = await SharedPreferences.getInstance();

      final budgets = BudgetProvider();
      await budgets.load();

      expect(budgets.migrationsApplied, 0);
      expect(prefs.containsKey('budget_limit_cat:food:fortnight'), isTrue);
    });
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

    testWidgets('ONE category is the subject, and an unset one says so', (
      tester,
    ) async {
      // A limit is a question about ONE category. The screen used to list every
      // category with its own bar, which is a dashboard: nine readings and no way
      // to tell which was the subject. Food is the default subject.
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await pump(tester);

      expect(find.byKey(ValueKey('budget-percent-cat:food:month')), findsOne);
      // And only that one. If a second category's row is ever rendered, this is
      // the assertion that catches it.
      for (final category in budgetableCategories()) {
        if (category == ExpenseCategory.food) continue;
        expect(
          find.byKey(ValueKey('budget-percent-cat:${category.name}:month')),
          findsNothing,
          reason: '${category.name} is not the subject, so it has no row',
        );
      }
      // An unset limit says so rather than showing a percentage of nothing.
      expect(find.textContaining('no limit set'), findsOne);
    });

    testWidgets('there is exactly ONE category control, not two', (
      tester,
    ) async {
      // The control set is a decision, and two category controls means the user
      // can change the category two ways and be unsure which one took.
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await pump(tester);

      expect(find.byKey(const ValueKey('budget-category-select')), findsOne);
      // No chip row of categories anywhere: the dropdown is the selector.
      for (final category in budgetableCategories()) {
        expect(
          find.byKey(ValueKey('budget-category-chip-${category.name}')),
          findsNothing,
        );
      }
    });

    testWidgets('the period control is the hero, and names its range', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await pump(tester);

      // Above the fold, so it decides what everything below means.
      expect(find.byKey(const ValueKey('budget-period-control')), findsOne);
      final control = tester.getTopLeft(
        find.byKey(const ValueKey('budget-period-control')),
      );
      final subject = tester.getTopLeft(
        find.byKey(ValueKey('budget-percent-cat:food:month')),
      );
      expect(
        control.dy,
        lessThan(subject.dy),
        reason: 'the period decides what the reading below it means',
      );

      // The range is named, so "This week" is never a label to interpret.
      final range = find.byKey(const ValueKey('budget-range-label'));
      expect(range, findsOne);
      expect(find.textContaining('spent in total'), findsOne);
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

      expect(find.byKey(const ValueKey('budget-bar-cat:food:month')), findsOne);
      expect(
        find.byKey(const ValueKey('budget-percent-cat:food:month')),
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
      expect(
        find.byKey(const ValueKey('budget-bar-cat:food:month')),
        findsNothing,
      );
      expect(find.text('No limit', skipOffstage: false), findsWidgets);
    });

    testWidgets('the period control changes the window the figures come from', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      final now = DateTime.now();
      await pump(
        tester,
        items: [
          _expense(400, ExpenseCategory.food, date: now),
          // Last month: inside the year window, outside this month's.
          _expense(
            700,
            ExpenseCategory.food,
            date: DateTime(now.year, now.month - 1, 15),
          ),
        ],
      );

      final monthTotal = _foodTotal(tester, BudgetPeriod.month);
      await tester.tap(find.text('Year'));
      await settleUi(tester);

      // The year window still contains today AND last month, so the reading must
      // grow. A control that does not change the figure is not a control.
      expect(
        _foodTotal(tester, BudgetPeriod.year),
        greaterThan(monthTotal),
        reason: 'the year window covers last month, this month does not',
      );
      // And the range line now names a year, read through [BudgetPeriodX.window]
      // rather than recomputed here.
      expect(find.byKey(const ValueKey('budget-range-label')), findsOne);
    });

    testWidgets('switching period re-reads the SAME category through it', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      final now = DateTime.now();
      await pump(
        tester,
        items: [
          _expense(400, ExpenseCategory.food, date: now),
          _expense(
            700,
            ExpenseCategory.food,
            date: DateTime(now.year, now.month - 1, 15),
          ),
        ],
      );

      // Same subject, different lens: the row key changes with the period, and
      // the category does not.
      expect(find.byKey(ValueKey('budget-percent-cat:food:month')), findsOne);
      await tester.tap(find.text('Week'));
      await settleUi(tester);
      expect(find.byKey(ValueKey('budget-percent-cat:food:week')), findsOne);
      expect(
        find.byKey(ValueKey('budget-percent-cat:food:month')),
        findsNothing,
      );
    });

    testWidgets('trips are secondary but reachable', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await pump(tester);

      // Below the fold: the primary reading comes first.
      final subject = tester.getTopLeft(
        find.byKey(ValueKey('budget-percent-cat:food:month')),
      );
      final toggle = tester.getTopLeft(
        find.byKey(const ValueKey('budget-trips-toggle')),
      );
      expect(toggle.dy, greaterThan(subject.dy));

      // Reachable: tapping it opens the section rather than doing nothing.
      expect(find.byKey(const ValueKey('budget-trips-toggle')), findsOne);
      await tester.tap(find.byKey(const ValueKey('budget-trips-toggle')));
      await settleUi(tester);
      expect(find.textContaining('Trip budgets'), findsOne);
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
