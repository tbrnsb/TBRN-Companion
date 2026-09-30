import 'package:uuid/uuid.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/services/storage_service.dart';

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
  /// Dates are clamped to the month rather than computed as
  /// `DateTime(y, m, now.day - n)`, which normalises into the previous month
  /// on the first few days and hides the records.
  static List<Transaction> _spend(DateTime now) {
    int day(int daysAgo) => (now.day - daysAgo).clamp(1, now.day);
    DateTime at(int daysAgo) => DateTime(now.year, now.month, day(daysAgo));

    // Built through a function so each record gets its own demo id at
    // construction time. copyWith cannot set an id.
    Transaction income(double amount, String category, String what, int ago) =>
        Income(
          id: newId(),
          amount: amount,
          category: category,
          description: '$label $what',
          date: at(ago),
        );

    Transaction expense(
      double amount,
      ExpenseCategory category,
      String what,
      int ago, {
      String? customName,
    }) => Expense(
      id: newId(),
      amount: amount,
      category: category,
      description: '$label $what',
      customCategoryName: customName,
      date: at(ago),
    );

    return [
      income(5000, 'salary', 'Monthly salary', 0),
      expense(150.00, ExpenseCategory.food, 'Grocery shopping', 1),
      expense(75.50, ExpenseCategory.travel, 'Gas for the weekend trip', 3),
      income(150.00, 'freelance', 'Freelance project', 4),
      expense(45.00, ExpenseCategory.entertainment, 'Movie tickets', 5),
      expense(120.00, ExpenseCategory.utilities, 'Electric bill', 10),
      expense(
        60.00,
        ExpenseCategory.other,
        'Coffee with the guide',
        12,
        customName: '$label Coffee',
      ),
    ];
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
