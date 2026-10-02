import 'dart:math' as math;

import 'expense_category_meta.dart';

/// Which window a budget is measured over.
///
/// Deliberately three and no per-product scope: a limit per individual purchase
/// is not a budget, it is a validation rule, and one for every product would mean
/// a limit per line item with nothing left to roll up.
enum BudgetPeriod { month, week, year }

extension BudgetPeriodX on BudgetPeriod {
  String get label => switch (this) {
    BudgetPeriod.month => 'This month',
    BudgetPeriod.week => 'This week',
    BudgetPeriod.year => 'This year',
  };

  /// Short form for a chip row.
  String get shortLabel => switch (this) {
    BudgetPeriod.month => 'Month',
    BudgetPeriod.week => 'Week',
    BudgetPeriod.year => 'Year',
  };

  /// The half-open window `[start, end)` this period covers, given an anchor
  /// month.
  ///
  /// Half-open on purpose: `isBefore(end)` rather than `isAfter(start)` so a
  /// one-day range works. `isAfter` is strict, so a record at exactly midnight
  /// on the boundary was excluded and a single-day range returned nothing at
  /// all — a silent empty result rather than an error.
  ({DateTime start, DateTime end}) window(DateTime anchorMonth) {
    switch (this) {
      case BudgetPeriod.month:
        return (
          start: DateTime(anchorMonth.year, anchorMonth.month),
          end: DateTime(anchorMonth.year, anchorMonth.month + 1),
        );
      case BudgetPeriod.week:
        // Monday-start, matching the weekly chart, so "this week" means the same
        // seven days in both places.
        final thisMorning = DateTime(
          anchorMonth.year,
          anchorMonth.month,
          anchorMonth.day,
        );
        final offset = thisMorning.weekday - 1;
        return (
          start: thisMorning.subtract(Duration(days: offset)),
          end: thisMorning
              .subtract(Duration(days: offset))
              .add(const Duration(days: 7)),
        );
      case BudgetPeriod.year:
        return (
          start: DateTime(anchorMonth.year),
          end: DateTime(anchorMonth.year + 1),
        );
    }
  }
}

/// One budget's storage key: `cat:<name>:<period>` or `trip:<id>:<period>`.
///
/// The PERIOD is part of the key because the limit is for a period. A monthly
/// food budget and a weekly one are different numbers for different questions,
/// and before this the provider stored `cat:food` for both — so setting a weekly
/// limit silently replaced the monthly one, and reading either showed whichever
/// was written last.
///
/// Parsing lives here rather than in the provider because a key that is written
/// in one place and read in another is how a limit stops being found. A key that
/// has no period segment is [isLegacy], and the provider migrates it to month
/// rather than dropping it.
class BudgetKey {
  const BudgetKey._(
    this.raw,
    this.scope,
    this.label,
    this.period,
    this.isLegacy,
  );

  /// A key for an app-level category budget.
  factory BudgetKey.forCategory(String categoryName, BudgetPeriod period) =>
      BudgetKey._(
        'cat:$categoryName:${period.name}',
        null,
        categoryName,
        period,
        false,
      );

  /// A key for a journey-level budget.
  ///
  /// A journey id is a UUID and a category name is an enum name, so neither
  /// contains a colon and the last segment is unambiguously the period.
  factory BudgetKey.forJourney(String journeyId, BudgetPeriod period) =>
      BudgetKey._(
        'trip:$journeyId:${period.name}',
        journeyId,
        journeyId,
        period,
        false,
      );

  /// Reads a stored key, or null when [raw] is not one of ours.
  ///
  /// Accepts the period-less form for migration. Anything with a trailing segment
  /// that is not a period is rejected rather than guessed at: a corrupt key
  /// reported as a real budget is worse than a key ignored.
  static BudgetKey? parse(String raw) {
    if (raw.startsWith('trip:')) {
      final rest = raw.substring(5);
      final split = rest.lastIndexOf(':');
      if (split < 0) {
        return BudgetKey._(raw, rest, rest, BudgetPeriod.month, true);
      }
      final id = rest.substring(0, split);
      final period = _periodNamed(rest.substring(split + 1));
      if (id.isEmpty || period == null) return null;
      return BudgetKey._(raw, id, id, period, false);
    }
    if (raw.startsWith('cat:')) {
      final rest = raw.substring(4);
      final split = rest.lastIndexOf(':');
      if (split < 0) {
        return BudgetKey._(raw, null, rest, BudgetPeriod.month, true);
      }
      final name = rest.substring(0, split);
      final period = _periodNamed(rest.substring(split + 1));
      if (name.isEmpty || period == null) return null;
      return BudgetKey._(raw, null, name, period, false);
    }
    return null;
  }

  static BudgetPeriod? _periodNamed(String name) {
    for (final period in BudgetPeriod.values) {
      if (period.name == name) return period;
    }
    return null;
  }

  /// The stored form.
  final String raw;

  /// The journey id for a journey-level budget, null for a category budget.
  final String? scope;

  /// The category name, or the journey id.
  final String label;

  final BudgetPeriod period;

  /// True when [raw] had no period segment and therefore needs migrating.
  final bool isLegacy;

  bool get isJourneyLevel => scope != null;

  /// The period-aware key to write to, for a legacy key.
  BudgetKey get migrated => isJourneyLevel
      ? BudgetKey.forJourney(scope!, BudgetPeriod.month)
      : BudgetKey.forCategory(label, BudgetPeriod.month);

  @override
  bool operator ==(Object other) => other is BudgetKey && other.raw == raw;

  @override
  int get hashCode => raw.hashCode;

  @override
  String toString() => 'BudgetKey($raw)';
}

/// One budget reading: what a limit was, what has been spent against it, and
/// what is left.
///
/// A value rather than a widget, so the same reading drives the screen, the
/// notification and the tests, and cannot disagree between them.
class BudgetStatus {
  const BudgetStatus({
    this.scope,
    required this.label,
    required this.limit,
    required this.spent,
    this.period = BudgetPeriod.month,
  });

  /// The journey id for a journey-level budget, null for an app-level category
  /// budget. Optional rather than required-nullable so a category reading is
  /// `BudgetStatus(label: 'Food', ...)` and not `scope: null` at every site.
  final String? scope;

  /// The category name, or the trip's destination.
  final String label;

  /// Zero or null means "no limit set", which is shown as unset rather than as
  /// a zero budget that is permanently overspent.
  final double? limit;

  final double spent;
  final BudgetPeriod period;

  /// True when this reading is a journey-level budget rather than an app-level
  /// category one.
  bool get isJourneyLevel => scope != null;

  bool get hasLimit => limit != null && limit! > 0;

  /// Clamped to 1.0 so a progress bar cannot ask for more than its own track.
  double get progress {
    if (!hasLimit || limit == 0) return 0;
    return (spent / limit!).clamp(0.0, 1.0);
  }

  /// The raw ratio, unclamped, so the copy can say "twice your limit" rather
  /// than showing two identical full bars.
  double get ratio {
    if (!hasLimit || limit == 0) return 0;
    return spent / limit!;
  }

  double get remaining => hasLimit ? limit! - spent : 0;

  bool get isOverspent => hasLimit && spent > limit!;

  /// Close enough that the user should be told NOW rather than at the end of the
  /// period, when there is nothing left to do about it.
  bool get isNearLimit => hasLimit && !isOverspent && ratio >= 0.8;

  /// Whether this reading should raise a notification.
  ///
  /// Overspend, or the last fifth of the limit. Nothing is raised for a budget
  /// with no limit set, and nothing is raised twice for the same overspend —
  /// the caller tracks that, because only it can see when a notification has
  /// already gone out.
  bool get shouldNotify => isOverspent || isNearLimit;

  /// The one sentence the card and the notification both use.
  ///
  /// [money] is a formatter, not a string, because the amount inside the
  /// sentence changes — "over" and "left of" are different figures — and a
  /// formatter passed in keeps the currency symbol and rounding in the caller's
  /// hands, where the rest of the screen already resolves them.
  String describe(String Function(double) money) {
    if (!hasLimit) return 'No limit set';
    if (isOverspent) {
      return '${money(spent - limit!)} over your $label limit';
    }
    return '${money(remaining)} left of your $label limit';
  }

  /// A stable key for persistence, for notification de-duplication and for
  /// tests, so two readings of the same budget are never treated as two.
  ///
  /// Period-aware, because a crossing in this month and a crossing in this week
  /// are different facts: with a period-less key the second one was suppressed
  /// as a duplicate of the first and the user was told about it once, ever.
  String get storageKey => scope == null
      ? BudgetKey.forCategory(label, period).raw
      : BudgetKey.forJourney(scope!, period).raw;
}

/// A limit the user has set, with the scope it applies to.
///
/// Limits are stored, spend is read live from the provider. Nothing here is a
/// captured total: a stored figure that outlived its data was how a budget
/// started disagreeing with the month total printed above it.
class Budget {
  const Budget({
    this.scope,
    required this.label,
    this.limit,
    this.period = BudgetPeriod.month,
  });

  /// Null for an app-level category budget.
  final String? scope;
  final String label;
  final double? limit;

  /// The period this limit is FOR. Month is the default only because a
  /// period-less key migrates to it; nothing new is written without one.
  final BudgetPeriod period;

  bool get isJourneyLevel => scope != null;

  /// The key this budget is stored under.
  String get storageKey => isJourneyLevel
      ? BudgetKey.forJourney(scope!, period).raw
      : BudgetKey.forCategory(label, period).raw;

  Map<String, dynamic> toJson() => {
    'scope': scope,
    'label': label,
    'limit': limit,
    'period': period.name,
  };
}

/// How much has been spent in one budget's period and scope, keyed by
/// [Budget.storageKey].
///
/// Read through this rather than by recomputing sums at each call site. The
/// shared-trip rule is applied INSIDE the provider's accessor, so a change to
/// what counts as my spending moves every budget at once and no budget screen
/// has to remember.
class BudgetSpendIndex {
  const BudgetSpendIndex({
    required this.period,
    required this.anchorMonth,
    required this.total,
    required this.byCategory,
    required this.byJourney,
  });

  final BudgetPeriod period;
  final DateTime anchorMonth;

  /// Total expense spend in the period, my trip expenses included.
  final double total;

  /// Expense spend keyed by [CategoryMeta.id].
  ///
  /// The meta id, NOT the enum name. A custom category IS
  /// `ExpenseCategory.other` with a different name, so keying by the enum put
  /// "Coffee", "Fruits" and "Petrol" all in one bucket called "other": no budget
  /// could be set for any of them and the money was unfalsifiably attributed.
  /// `meta.id` is `food` for Food and `custom:coffee` for Coffee, which is also
  /// what the spending breakdown uses, so a slice and a budget are one thing.
  final Map<String, double> byCategory;

  /// Expense spend keyed by `journeyId`. A separate pool from [byCategory]: a
  /// trip's costs are the trip's, and the journey-level limit is what governs
  /// them. The two never sum into one another.
  final Map<String, double> byJourney;

  /// Total for a journey, or 0 for a journey with no expenses in the period.
  double forJourney(String journeyId) => byJourney[journeyId] ?? 0;

  /// Total for a category, or 0.
  double forCategory(ExpenseCategory category) => forCategoryId(category.name);

  /// Total for a category named by its meta id, or 0.
  ///
  /// Custom categories are addressed by `custom:<name>`, so a caller holding one
  /// cannot go through [forCategory] and has to come here.
  double forCategoryId(String metaId) => byCategory[metaId] ?? 0;

  /// Total for a category named by its enum `name`, or 0.
  ///
  /// For callers that hold a label rather than the enum — a persisted budget key
  /// is a string, and reading it back must not need a `firstWhere` that quietly
  /// falls back to `other` and reports the wrong figure.
  double totalSpendCategory(String categoryName) =>
      byCategory[categoryName] ?? 0;
}

/// Every category, in the order a budget list should show them.
List<ExpenseCategory> budgetableCategories() => ExpenseCategory.values;

/// The budget key meaning "every category at once", rather than one of them.
///
/// A limit on this is a limit on total spending in the period, which is the
/// thing most people actually want to cap, and it was unreachable because the
/// screen only offered one category at a time with no way to say "the lot".
///
/// A star, because it cannot collide with a meta id: real ones are `food`,
/// `travel` or `custom:<name>`. Kept here rather than in the screen so the
/// writer, the reader and the storage key can never drift apart.
const String allCategoriesKey = '*';

/// Whether [label] is the "all categories" budget rather than one category.
bool isAllCategories(String label) => label == allCategoriesKey;

/// The integer a rupee amount is stored as, and back.
///
/// Limits are persisted as whole units rather than doubles because
/// `SharedPreferences` is typed and a double key would invite a
/// `double.toInt()` round-trip that quietly rounds a limit like `199.50` to
/// `199`. Paise would be more exact, but a budget the user typed in rupees is
/// a budget in rupees, and a limit of 0.5 rupees is not a thing anyone sets.
int limitToUnits(double? amount) => amount == null ? 0 : (amount * 100).round();

double unitsToLimit(int units) => units / 100;

/// A limit, or null when [units] is zero.
///
/// Zero means "unset", not "spend nothing": a budget of zero would be
/// permanently overspent and there is no way for the user to have meant that.
double? limitFromUnits(int units) => units == 0 ? null : units / 100;

/// Ceiling division, so a bar built from [BudgetStatus.progress] never needs a
/// guard at the call site.
int percentOf(double part, double whole) {
  if (whole <= 0) return 0;
  return math.min(100, (part / whole * 100).round());
}

/// Why a day selection did or did not take effect.
///
/// Exists so "nothing happened" is never the answer. Every refusal has to be
/// turned into something the user can SEE -- a message, or a control that is
/// visibly unavailable -- because a tap that produces no change is
/// indistinguishable from a tap that did not register.
sealed class DaySelectionOutcome {
  const DaySelectionOutcome();

  /// Whether the view actually changed.
  bool get changed;

  /// A sentence for the user, or null when nothing needs saying.
  String? get message;
}

class DaySelected extends DaySelectionOutcome {
  const DaySelected(this.day);
  final DateTime day;
  @override
  bool get changed => true;
  @override
  String? get message => null;
}

class DaySelectionCleared extends DaySelectionOutcome {
  const DaySelectionCleared();
  @override
  bool get changed => true;
  @override
  String? get message => null;
}

/// The day is already the one on screen. Explains itself rather than doing
/// nothing.
class DayAlreadySelected extends DaySelectionOutcome {
  const DayAlreadySelected(this.day);
  final DateTime day;
  @override
  bool get changed => false;
  @override
  String? get message => 'Already showing that day.';
}

/// The day belongs to a month that is not loaded. Names the month it IS in, so
/// the user can act on the answer rather than guess.
class DayOutsideLoadedMonth extends DaySelectionOutcome {
  const DayOutsideLoadedMonth(this.loadedMonth);
  final DateTime loadedMonth;
  @override
  bool get changed => false;
  @override
  String? get message => null;
}

/// The day has not happened yet. Refused, and explained.
///
/// Found by the item 4 tests: the picker's `lastDate` is capped at today, so a
/// selection past today made `initialDate` later than `lastDate` and the sheet
/// threw on open.
class DayInTheFuture extends DaySelectionOutcome {
  const DayInTheFuture();
  @override
  bool get changed => false;
  @override
  String? get message => 'That day has not happened yet.';
}

/// Clearing while nothing is selected.
class DaySelectionAlreadyWholeMonth extends DaySelectionOutcome {
  const DaySelectionAlreadyWholeMonth();
  @override
  bool get changed => false;
  @override
  String? get message => 'Already showing the whole month.';
}
