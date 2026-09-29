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
    await storage.addJourney(active);
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
