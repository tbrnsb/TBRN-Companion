import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/services/storage_service.dart';

/// Seeds and removes the app's sample data.
///
/// Demo records are identified by an id prefix, not by their text. Matching on
/// a name or description would delete a user's real checklist called "Demo
/// pack", and would miss a demo record whose text the user had edited. The id
/// is immutable in the UI, so a prefix on it is a reliable marker.
///
/// Nothing here runs on app start. Seeding is one explicit user action from
/// Settings, and clearing removes only what this class created.
class DemoDataService {
  DemoDataService._();

  /// Every seeded record's id starts with this.
  static const String idPrefix = 'demo-';

  /// Shown in the UI so demo records are obvious on sight, not just in the
  /// data.
  static const String label = '[Demo]';

  static bool isDemoId(String? id) => id != null && id.startsWith(idPrefix);

  static String newId() => '$idPrefix${const Uuid().v4()}';

  static DateTime _daysAgo(int days) =>
      DateTime.now().subtract(Duration(days: days));

  /// Writes one batch of demo data across all four sections.
  ///
  /// Every date lands in the current month or the past, never the future, so
  /// the records show up in the timeline and the month summary rather than
  /// hiding behind a date filter.
  static Future<void> seedAll() async {
    final storage = StorageService();

    final active = Journey(
      id: newId(),
      destination: '$label Pokhara',
      origin: 'Kathmandu',
      notes: 'Three days of walking and one very cold morning.',
      items: ['Boots', 'Waterproof jacket', 'Headlamp', 'Water bottle'],
      startTime: _daysAgo(2),
    );
    final completed = Journey(
      id: newId(),
      destination: '$label Sauraha',
      origin: 'Kathmandu',
      notes: 'A completed trip, kept so the timeline has history in it.',
      items: ['Binoculars', 'Field notebook'],
      startTime: _daysAgo(44),
      endTime: _daysAgo(41),
      completed: true,
    );
    // A shared trip, so the settlement is visible without anyone having to add
    // three people by hand. The amounts are the worked example from the README:
    // 5500 + 5400 + 3000 across three people, which does not divide, and leaves
    // Sita owing. A demo that settles to zero would show none of the feature.
    final shared = Journey(
      id: newId(),
      destination: '$label Annapurna Base Camp',
      origin: 'Kathmandu',
      notes: 'Four of us. Everyone paid for different things.',
      items: ['Boots', 'Waterproof jacket', 'Headlamp', 'Water bottle'],
      startTime: _daysAgo(9),
      endTime: _daysAgo(5),
      participants: [
        TripParticipant.create(name: 'You', id: '$idPrefix-you'),
        TripParticipant.create(name: 'Raj', id: '$idPrefix-raj'),
        TripParticipant.create(name: 'Sita', id: '$idPrefix-sita'),
      ],
      localParticipantId: '$idPrefix-you',
      tripCode: 'DEMO24',
    );
    await storage.addJourney(active);
    await storage.addJourney(shared);
    await storage.addJourney(completed);

    // Two packs, one partially checked so the progress bar has something to
    // show.
    final weekend = Checklist(
      id: newId(),
      name: '$label Weekend pack',
      description: 'Sample list for the sample trip.',
      journeyId: active.id,
    );
    await storage.addChecklist(weekend);
    for (final item in const [
      ('Tent', true),
      ('Sleeping bag', true),
      ('Headlamp', false),
      ('Waterproof jacket', false),
      ('Paper map', false),
    ]) {
      await storage.addChecklistItem(
        ChecklistItem(
          id: newId(),
          checklistId: weekend.id,
          name: item.$1,
          isChecked: item.$2,
        ),
      );
    }

    final essentials = Checklist(
      id: newId(),
      name: '$label Everyday essentials',
      description: 'Sample everyday list.',
      isEverydayEssentials: true,
    );
    await storage.addChecklist(essentials);
    for (final name in const ['Wallet', 'Phone charger', 'Medication']) {
      await storage.addChecklistItem(
        ChecklistItem(id: newId(), checklistId: essentials.id, name: name),
      );
    }

    // A third list, seasonal, on the completed trip — so the Pack tab has three
    // visibly different things in it rather than three variations on one list.
    // The suggestions card is driven by the ACTIVE trip, so this is what a
    // different trip's pack looks like next to Pokhara's.
    final winter = Checklist(
      id: newId(),
      name: '$label Cold season kit',
      description: 'Sample list for a winter trip.',
      journeyId: completed.id,
    );
    await storage.addChecklist(winter);
    for (final item in const [
      ('Thermal base layer', true),
      ('Insulated jacket', true),
      ('Wool hat', false),
      ('Gloves', false),
      ('Hand warmers', false),
      ('Lip balm', false),
    ]) {
      await storage.addChecklistItem(
        ChecklistItem(
          id: newId(),
          checklistId: winter.id,
          name: item.$1,
          isChecked: item.$2,
        ),
      );
    }

    for (final place in const [
      ('Phewa Lake', 28.2096, 83.9856),
      ('Sarangkot', 28.2437, 83.9490),
      ('Sauraha', 27.5798, 84.5213),
    ]) {
      await storage.addLocation(
        Location(
          id: newId(),
          name: '$label ${place.$1}',
          latitude: place.$2,
          longitude: place.$3,
          description: 'Sample place.',
          journeyId: active.id,
        ),
      );
    }

    // Spend: expenses and income, spread across categories and days so the
    // balance, both breakdowns and the charts all have something in them.
    final now = DateTime.now();
    for (final transaction in _spend(now)) {
      await storage.addTransaction(transaction);
    }
    for (final transaction in _pastSpend(now)) {
      await storage.addTransaction(transaction);
    }
    for (final transaction in _sharedTripSpend(shared.id)) {
      await storage.addTransaction(transaction);
    }
  }

  /// Demo spend for the current month.
  ///
  /// Spread across the month by POSITION rather than by subtracting days from
  /// today. `DateTime(y, m, now.day - n)` is the version this replaces, and it
  /// collapses everything onto day 1 for the first few days of a month: every
  /// offset clamps to 1, so seven records land on the same date, the heatmap's
  /// per-day maximum is set by one of them and every other day reads as nothing
  /// happened. A month that looks like that has not been lived in.
  ///
  /// A month lived in is a few big bills and then the SAME small expenses
  /// repeating, roughly weekly. Ten records could not show that: it was a
  /// salary, a rent and a shopping list, so every breakdown in the app had one
  /// fat slice and four hairlines, and the heatmap had a single lit square. The
  /// repetition is deliberate -- a category that turns up every week is a
  /// category a person can recognise in a donut at a glance -- so the weeks are
  /// spelled out with their own amounts rather than generated from one, which
  /// would have made four weeks of identical numbers and a heatmap that
  /// normalises against a median of repeats.
  ///
  /// Every category in the app appears somewhere in here. A demo that never
  /// shows a category cannot be checked, and a user who finds one of them for
  /// the first time has to trust that it works.
  ///
  /// Two rules for the days, and they are different rules:
  ///
  /// - Position decides the day: record *i* of *n* lands on a day derived from
  ///   `monthLength * (i + 1) / n`, so the set covers the month evenly however
  ///   long it is.
  /// - Today caps it: a record cannot be dated in the future, because a month
  ///   with spending on days that have not happened is not a month that has been
  ///   lived in either.
  ///
  /// The second rule is why the set is still bunched on the 1st of a month, and
  /// that is honest: there is exactly one day to put thirty records on. From the
  /// 2nd onward the spread widens by itself.
  static List<Transaction> _spend(DateTime now) {
    // Thirty records, in roughly the order a month would run through them. Every
    // amount is distinct, because the heatmap normalises against the per-day
    // maximum and a set of identical figures reads as a flat pale block.
    const total = 30;
    var slot = 0;

    // Built through a function so each record gets its own demo id at
    // construction time. copyWith cannot set an id.
    Transaction income(double amount, String category, String what) => Income(
      id: newId(),
      amount: amount,
      category: category,
      description: '$label $what',
      date: _spreadDay(now, slot++, total),
    );

    Transaction expense(
      double amount,
      ExpenseCategory category,
      String what, {
      String? customName,
    }) => Expense(
      id: newId(),
      amount: amount,
      category: category,
      description: '$label $what',
      customCategoryName: customName,
      date: _spreadDay(now, slot++, total),
    );

    return [
      // Week one: the bills, and the first ordinary week.
      income(5000, 'salary', 'Monthly salary'),
      expense(1200.00, ExpenseCategory.housing, 'Rent, most of it'),
      expense(186.40, ExpenseCategory.food, 'Grocery shopping'),
      expense(12.50, ExpenseCategory.travel, 'Bus fare'),
      expense(64.00, ExpenseCategory.utilities, 'Electric bill'),
      expense(45.00, ExpenseCategory.entertainment, 'Cinema with a friend'),
      expense(
        6.50,
        ExpenseCategory.other,
        'Coffee with the guide',
        customName: '$label Coffee',
      ),
      expense(148.90, ExpenseCategory.shopping, 'New walking shoes'),
      expense(32.00, ExpenseCategory.health, 'Pharmacy'),
      expense(22.00, ExpenseCategory.food, 'Lunch out'),
      income(1500.00, 'freelance', 'Freelance project'),

      // Week two: the same categories, different amounts, as a real month does.
      expense(1180.00, ExpenseCategory.gear, 'A replacement sole'),
      expense(74.25, ExpenseCategory.food, 'Groceries for the week'),
      expense(15.00, ExpenseCategory.travel, 'Shared taxi to the trailhead'),
      expense(39.00, ExpenseCategory.utilities, 'Internet'),
      expense(28.00, ExpenseCategory.utilities, 'Phone bill'),
      expense(11.00, ExpenseCategory.food, 'Tea and a bun'),
      expense(95.00, ExpenseCategory.entertainment, 'Concert ticket'),
      expense(54.30, ExpenseCategory.shopping, 'A jacket for cold mornings'),
      expense(38.00, ExpenseCategory.health, 'Physiotherapy'),
      expense(9.00, ExpenseCategory.other, 'Tip for the porter'),

      // Week three.
      expense(210.00, ExpenseCategory.food, 'Groceries plus the weekend'),
      expense(18.00, ExpenseCategory.travel, 'Bus and a rickshaw'),
      expense(26.50, ExpenseCategory.food, 'Dinner with the group'),
      expense(165.00, ExpenseCategory.gear, 'A dry bag and a headtorch'),
      expense(43.00, ExpenseCategory.utilities, 'Water and waste'),
      expense(8.75, ExpenseCategory.other, 'Tea, second pot'),
      expense(132.00, ExpenseCategory.shopping, 'A present for Sita'),

      // Week four, and the tail of the month.
      expense(88.00, ExpenseCategory.entertainment, 'Museum entry'),
      expense(176.25, ExpenseCategory.food, 'Final groceries'),
    ];
  }

  /// The day for slot [slot] of a set of [total] records in the current month.
  ///
  /// [slot] counts from 0. Two things are true at once, and both are visible in
  /// the app:
  ///
  /// - The records cover about two days in three, not all of them. A month with
  ///   spending on every single day has not been lived in, and the heatmap's
  ///   unlit cells are how that reads. Where two records land on the same day
  ///   they stack, which is also what a real day looks like: a market run is
  ///   three records on one date, not three dates.
  /// - Today caps it. There is no day in the future to put a record on.
  ///
  /// With only a couple of days elapsed this still bunches, and it has to: a
  /// month on the 2nd is two days long whatever the data says.
  static DateTime _spreadDay(DateTime now, int slot, int total) {
    // Days of the month that have actually happened. Not the month's length:
    // the 30th of a 30-day month is a day nobody has reached yet.
    final elapsed = now.day;

    // The days the set intends to occupy, evenly spread over the days elapsed.
    // At least one, so an empty day list cannot divide by zero.
    final occupied = math.max(1, (elapsed * 2 / 3).round());

    // Which of those days this record belongs to. The per-day pile is
    // `total / occupied`, which is 1.4 for a full month and 4.3 on the 10th --
    // so a month that has barely started has several records on each of the few
    // days it has, and a month nearly over has one or two on most of them.
    final perDay = total / occupied;
    final dayIndex = (slot / perDay).floor().clamp(0, occupied - 1);

    // Even spread of those days across the days elapsed, so a 28-day month and
    // a 31-day month both fill the space they have.
    final day = (((dayIndex + 1) * elapsed) / occupied).ceil().clamp(
      1,
      elapsed,
    );

    return DateTime(now.year, now.month, day);
  }

  /// Spend in the two months before this one.
  ///
  /// Month navigation was empty everywhere except the month you happened to open
  /// the app in, so you could not see what moving between months feels like —
  /// which is most of what a spending app is for. The charts and the weekly and
  /// daily rollups need history to be worth looking at at all.
  ///
  /// Day numbers are clamped to the real length of the month they land in. The
  /// current-month set above clamps for the same reason, and getting it wrong
  /// puts every record in the previous month, which looks like it worked.
  static List<Transaction> _pastSpend(DateTime now) {
    return [
      for (var monthsAgo = 1; monthsAgo <= 2; monthsAgo++) ...[
        Income(
          id: newId(),
          amount: 5000,
          category: 'salary',
          description: '$label Monthly salary',
          date: _monthDate(now, monthsAgo, 1),
        ),
        Expense(
          id: newId(),
          amount: 2450,
          category: ExpenseCategory.housing,
          description: '$label Rent',
          date: _monthDate(now, monthsAgo, 2),
        ),
        Expense(
          id: newId(),
          amount: 1850.50,
          category: ExpenseCategory.food,
          description: '$label Groceries and eating out',
          date: _monthDate(now, monthsAgo, 6),
        ),
        Expense(
          id: newId(),
          amount: 640,
          category: ExpenseCategory.travel,
          description: '$label Bus and a taxi',
          date: _monthDate(now, monthsAgo, 11),
        ),
        Expense(
          id: newId(),
          amount: 320,
          category: ExpenseCategory.health,
          description: '$label Pharmacy',
          date: _monthDate(now, monthsAgo, 15),
        ),
        Expense(
          id: newId(),
          amount: 1500,
          category: ExpenseCategory.gear,
          description: '$label Hiking boots',
          date: _monthDate(now, monthsAgo, 19),
        ),
        Expense(
          id: newId(),
          amount: 410,
          category: ExpenseCategory.utilities,
          description: '$label Electricity',
          date: _monthDate(now, monthsAgo, 24),
        ),
        Income(
          id: newId(),
          amount: 900,
          category: 'freelance',
          description: '$label Freelance work',
          date: _monthDate(now, monthsAgo, 26),
        ),
      ],
    ];
  }

  /// The shared trip's costs, in the README's worked example exactly.
  ///
  /// 5500 + 5400 + 3000 = 13900 across three people. It does not divide, which
  /// is the interesting case, and it leaves Sita owing — so the summary has
  /// transfers to show, the Transactions card has something outstanding, and the
  /// rounding is visible rather than being a tidy round number that hides it.
  static List<Transaction> _sharedTripSpend(String journeyId) {
    Transaction paid(
      double amount,
      String payer,
      String what,
      ExpenseCategory category,
      int daysAgo,
    ) => Expense(
      id: newId(),
      amount: amount,
      category: category,
      description: '$label $what',
      journeyId: journeyId,
      paidByParticipantId: payer,
      date: _daysAgo(daysAgo),
    );

    return [
      paid(
        4000,
        '$idPrefix-you',
        'Taxi to the trailhead',
        ExpenseCategory.travel,
        8,
      ),
      paid(1500, '$idPrefix-you', 'Lunch', ExpenseCategory.food, 8),
      paid(3000, '$idPrefix-raj', 'Boat on Phewa', ExpenseCategory.travel, 7),
      paid(2400, '$idPrefix-raj', 'Dinner', ExpenseCategory.food, 6),
      paid(2000, '$idPrefix-sita', 'Groceries', ExpenseCategory.food, 7),
      paid(
        1000,
        '$idPrefix-sita',
        'Museum entry',
        ExpenseCategory.entertainment,
        5,
      ),
    ];
  }

  /// A day in [now] minus [monthsAgo] months, on [day], clamped to that month's
  /// real length.
  ///
  /// `DateTime(y, m - 1, 31)` silently becomes 3 March, so a fixed day number
  /// walks records into the wrong month and a naive subtraction from
  /// `now.day` lands in the month before whenever the date is early. Both
  /// happened; both are handled here in one place.
  static DateTime _monthDate(DateTime now, int monthsAgo, int day) {
    var year = now.year;
    var month = now.month - monthsAgo;
    while (month < 1) {
      month += 12;
      year -= 1;
    }
    // DateTime normalises an out-of-range day forward into the next month, so
    // the length has to be known before the date is built.
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, day.clamp(1, lastDay));
  }

  /// Removes every demo record, in every month and every section, and returns
  /// how many were removed.
  ///
  /// The previous implementation iterated the in-memory list of whatever month
  /// happened to be loaded and deleted all of it — demo and real alike — so it
  /// removed neither reliably nor safely. This reads every box instead.
  static Future<int> clearAll() async {
    final storage = StorageService();
    var removed = 0;

    for (final transaction in await storage.getAllTransactions()) {
      if (isDemoId(transaction.id)) {
        await storage.deleteTransaction(transaction.id);
        removed++;
      }
    }

    for (final journey in await storage.getAllJourneys()) {
      if (isDemoId(journey.id)) {
        await storage.deleteJourney(journey.id);
        removed++;
      }
    }

    for (final location in await storage.getAllLocations()) {
      if (!isDemoId(location.id)) continue;
      // Logs belong to the place, so they go with it.
      for (final log in await storage.getLocationLogs(location.id)) {
        await storage.deleteLocationLog(log.id);
        removed++;
      }
      await storage.deleteLocation(location.id);
      removed++;
    }

    for (final checklist in await storage.getAllChecklists()) {
      if (!isDemoId(checklist.id)) continue;
      // deleteChecklist removes the checklist's items along with it, but those
      // items are separate records in their own box, so they are counted here
      // for the return value to reflect every row actually deleted.
      removed += checklist.items.length;
      await storage.deleteChecklist(checklist.id);
      removed++;
    }

    return removed;
  }
}
