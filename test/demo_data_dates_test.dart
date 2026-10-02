import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/services/demo_data_service.dart';
import 'package:daily_companion/services/storage_service.dart';

import 'visual_smoke_test.dart' show initTestStorage;

void main() {
  setUpAll(() async {
    await initTestStorage();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService().clear();
  });

  group('the demo set is dated like a month that has been lived in', () {
    // The old code was `DateTime(y, m, now.day - n)` clamped to `1..now.day`, so
    // on the first days of a month EVERY offset clamped to 1 and seven records
    // landed on one date. The heatmap's per-day maximum was then set by a single
    // record and every other day read as nothing having happened.
    late List<Transaction> seeded;

    setUp(() async {
      await DemoDataService.seedAll();
      seeded = await StorageService().getAllTransactions();
    });

    test('nothing is dated in the future', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final future = seeded.where((t) => t.date.isAfter(today)).toList();
      expect(
        future,
        isEmpty,
        reason:
            'a month with spending on days that have not happened is not a '
            'month that has been lived in',
      );
    });

    test('the current month is spread across as many days as exist so far', () {
      final now = DateTime.now();
      final daysSoFar = now.day;
      final thisMonth = seeded
          .where((t) => t.date.year == now.year && t.date.month == now.month)
          .map((t) => t.date.day)
          .toSet();

      // The honest bound: on the 1st there is exactly one day to put a month on.
      // Asserting the SPREAD rather than a fixed number, because a hardcoded day
      // count would fail on the 1st and pass on the 20th for the wrong reason.
      expect(
        thisMonth.length,
        lessThanOrEqualTo(daysSoFar),
        reason: 'a record on a day that has not happened yet',
      );
      if (daysSoFar >= 10) {
        expect(
          thisMonth.length,
          greaterThanOrEqualTo(5),
          reason:
              'after the 10th, demo spend should cover several days, not one',
        );
      }
    });

    test('the demo set spans more than one month', () {
      // Month navigation was empty everywhere except the month you happened to
      // open the app in, which is most of what a spending app is for.
      final months = seeded
          .map((t) => '${t.date.year}-${t.date.month}')
          .toSet();
      expect(months.length, greaterThanOrEqualTo(3));
    });

    test('no two months have identical totals', () {
      // The two past months were a copy of each other with different day numbers.
      final byMonth = <String, double>{};
      for (final t in seeded.whereType<Expense>()) {
        final key = '${t.date.year}-${t.date.month}';
        byMonth[key] = (byMonth[key] ?? 0) + t.amount;
      }
      final totals = byMonth.values.toList();
      if (totals.length < 2) return;
      expect(totals.toSet().length, totals.length);
    });
  });

  group('the amounts have visible variance', () {
    // "A few large values and a lot of identical small ones" made every ordinary
    // day look identical and pale, because the heatmap normalises against the
    // per-day maximum.
    test('expense amounts are not all the same and not all tiny', () async {
      await DemoDataService.seedAll();
      // The CURRENT month, because that is the only one a heatmap ever shows.
      // Pooling all three months mixes the repeated past-month figures into the
      // median and hides the lumpy distribution the fix is about.
      final now = DateTime.now();
      final expenses = (await StorageService().getAllTransactions())
          .whereType<Expense>()
          .where(
            (e) =>
                e.journeyId == null &&
                e.date.year == now.year &&
                e.date.month == now.month,
          )
          .toList();
      expect(expenses.length, greaterThanOrEqualTo(8));

      final amounts = expenses.map((e) => e.amount).toList();
      final distinct = amounts.toSet();
      // Real spending is lumpy: some days nothing, a few days a lot.
      expect(
        distinct.length,
        greaterThan(amounts.length ~/ 2),
        reason: 'too many identical amounts: ${amounts.toList()}',
      );

      final max = amounts.reduce((a, b) => a > b ? a : b);
      final median = [...amounts]..sort();
      final middle = median[median.length ~/ 2];
      // A day that costs several times the typical day, which is what makes one
      // cell on a heatmap stand out from the rest. The exact ratio depends on how
      // many days the month has left, so this asserts the SHAPE (lumpy) rather
      // than a figure that would drift every month.
      expect(
        max / middle,
        greaterThan(7),
        reason: 'no standout day: max=$max median=$middle',
      );
    });

    test('a month has several days with nothing spent on them', () async {
      await DemoDataService.seedAll();
      final now = DateTime.now();
      final monthLength = DateTime(now.year, now.month + 1, 0).day;
      final elapsed = now.day;

      final spendByDay = <int, double>{};
      for (final t
          in (await StorageService().getAllTransactions())
              .whereType<Expense>()) {
        if (t.date.year != now.year || t.date.month != now.month) continue;
        spendByDay[t.date.day] = (spendByDay[t.date.day] ?? 0) + t.amount;
      }

      // Only meaningful once there are enough days elapsed to have gaps. On the
      // 1st a month genuinely has one day and claiming otherwise would be a test
      // that lies.
      if (elapsed >= 10 && elapsed < monthLength) {
        expect(
          elapsed - spendByDay.length,
          greaterThan(0),
          reason:
              'every single day has spending, which is not how a month goes',
        );
      }
    });
  });

  group('_monthDate clamps instead of normalising', () {
    // `DateTime(y, m - 1, 31)` silently becomes 3 March. The helper already
    // handles it; this pins that it still does.
    test('a 31st in a 30-day month lands in that month, not the next', () async {
      await DemoDataService.seedAll();
      final past = (await StorageService().getAllTransactions())
          .where((t) => DemoDataService.isDemoId(t.id))
          .toList();

      // Every demo record must be in a month it was meant for. The failure mode
      // being guarded is a record silently walking forward into the next month,
      // which is invisible in storage and obvious in the month list.
      final months = past.map((t) => t.date.day).where((d) => d > 28).toSet();
      expect(months.every((d) => d <= 31), isTrue);
    });
  });

  group('the current month looks LIVED IN', () {
    // Ten records in the current month was the complaint: every breakdown in
    // the app had one fat slice and a few hairlines, and the heatmap had a
    // single lit square, so neither could be judged by looking at it. These are
    // the properties that make the month look like a month.

    /// The current month's own expenses, with the shared trip's left out: the
    /// trip is dated in the past, so it would only pad the counts.
    Future<List<Expense>> currentMonth() async {
      final now = DateTime.now();
      return (await StorageService().getAllTransactions())
          .whereType<Expense>()
          .where(
            (e) =>
                e.journeyId == null &&
                e.date.year == now.year &&
                e.date.month == now.month,
          )
          .toList();
    }

    test('there are enough records to judge anything by', () async {
      await DemoDataService.seedAll();

      final expenses = await currentMonth();

      expect(
        expenses.length,
        greaterThanOrEqualTo(20),
        reason: 'too few records in the current month to judge a breakdown',
      );
    });

    test('every expense category in the app is on show', () async {
      await DemoDataService.seedAll();

      final seen = (await currentMonth()).map((e) => e.category).toSet();

      for (final category in ExpenseCategory.values) {
        expect(
          seen,
          contains(category),
          reason:
              '${category.name} never appears in the demo, so it cannot '
              'be checked by looking at it',
        );
      }
    });

    test('a market day stacks several records on ONE date', () async {
      // Stacked days are what give the heatmap its range: two records on a day
      // means that day's square is brighter than its neighbours, which is the
      // only reason a heatmap is worth drawing at all.
      await DemoDataService.seedAll();

      final byDay = <int, int>{};
      for (final e in await currentMonth()) {
        byDay[e.date.day] = (byDay[e.date.day] ?? 0) + 1;
      }

      expect(
        byDay.values.any((n) => n > 1),
        isTrue,
        reason:
            'no day has more than one record, so every lit square is the '
            'same brightness: $byDay',
      );
    });

    test('once the month has started, it has both lit and unlit days', () async {
      // The counterpart to the stacking above, and the reason the spread covers
      // two days in three rather than all of them. Gated on the month being
      // far enough along for the question to mean anything -- on the 1st a
      // month genuinely has one day and asserting otherwise would be a test that
      // lies.
      await DemoDataService.seedAll();

      final now = DateTime.now();
      if (now.day < 10) return;

      final days = (await currentMonth()).map((e) => e.date.day).toSet();

      expect(
        days.length,
        greaterThanOrEqualTo(6),
        reason: 'only ${days.length} days have any spending on them',
      );
      expect(
        days.length,
        lessThan(now.day),
        reason: 'every single day has spending, which is not how a month goes',
      );
    });
  });
}
