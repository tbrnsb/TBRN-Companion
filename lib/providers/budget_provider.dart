import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/services/notification_service.dart';
import 'package:daily_companion/utils/format.dart';

/// The limits the user has set, and nothing else.
///
/// This provider holds NO spending figures. It stores a limit per budget and
/// reads every amount through [TransactionProvider.spendIndex]. That separation
/// is the design: a stored total is a snapshot that goes stale the moment an
/// expense is added, and a budget that disagreed with the month total printed
/// above it would be worse than no budget at all.
///
/// Persistence follows [SettingsProvider] exactly — one `int` key per budget,
/// `getInt`/`setInt`, no new box and therefore no migration. Limits are stored
/// in hundredths rather than as doubles so a typed `199.50` survives a
/// round-trip.
class BudgetProvider extends ChangeNotifier {
  /// `budget_limit_<key>`, where key is `cat:<name>:<period>` or
  /// `trip:<id>:<period>`.
  ///
  /// The period is part of the key because a limit is FOR a period: a monthly
  /// food budget and a weekly one are different numbers answering different
  /// questions. The key used to be period-less, so setting one replaced the other
  /// and only whichever was written last was ever readable.
  ///
  /// One flat namespace rather than a serialised map under a single key: a
  /// single key would mean rewriting and re-serialising every budget to change
  /// one, and a corrupt value would lose all of them together.
  static const String _prefix = 'budget_limit_';

  /// How many legacy period-less keys were rewritten onto month keys by the last
  /// [load]. Read by the migration test; zero on every load after the first.
  int migrationsApplied = 0;

  final Map<String, double> _limits = {};

  /// Budgets already notified this session, so a crossing is announced once.
  final Set<String> _notified = {};

  /// Every limit currently set, as a stored reading.
  List<Budget> get budgets {
    final sorted =
        _limits.entries.map((e) => _budgetForKey(e.key, e.value)).toList()
          ..sort((a, b) => a.label.compareTo(b.label));
    // Alphabetical, except the Other bucket, which leads somewhere else and so
    // goes last. Sorting by label alone files it between "Office" and
    // "Personal" and puts a two-step row in the middle of a list of one-step
    // ones.
    return CategoryRegistry.othersLast(
      sorted,
      isOther: (b) => !b.isJourneyLevel && b.label == CategoryRegistry.otherId,
    );
  }

  /// The limit for a budget, or null when none is set.
  ///
  /// Null rather than 0 for "unset", because a zero limit would be permanently
  /// overspent and there is no reading of the input that means it.
  ///
  /// [period] defaults to month because that is where a period-less key lands,
  /// so a caller that has not been updated yet keeps reading the user's existing
  /// monthly limits instead of silently reporting every budget as unset.
  double? limitFor({
    String? scope,
    required String label,
    BudgetPeriod period = BudgetPeriod.month,
  }) => _limits[_keyFor(scope, label, period)];

  bool hasLimit({
    String? scope,
    required String label,
    BudgetPeriod period = BudgetPeriod.month,
  }) => _limits.containsKey(_keyFor(scope, label, period));

  /// Sets or clears a limit. A null or non-positive amount clears it.
  Future<void> setLimit({
    String? scope,
    required String label,
    required double? amount,
    BudgetPeriod period = BudgetPeriod.month,
  }) async {
    final key = _keyFor(scope, label, period);
    if (amount == null || amount <= 0) {
      await clearLimit(scope: scope, label: label, period: period);
      return;
    }
    if (_limits[key] == amount) return;
    _limits[key] = amount;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_prefix$key', limitToUnits(amount));
    notifyListeners();
  }

  Future<void> clearLimit({
    String? scope,
    required String label,
    BudgetPeriod period = BudgetPeriod.month,
  }) async {
    final key = _keyFor(scope, label, period);
    if (!_limits.containsKey(key)) return;
    _limits.remove(key);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$key');
    notifyListeners();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final loaded = <String, double>{};
    var migrated = 0;

    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_prefix)) continue;
      final units = prefs.getInt(key);
      if (units == null || units <= 0) continue;
      final raw = key.substring(_prefix.length);
      final parsed = BudgetKey.parse(raw);
      // A key that does not parse is left ALONE rather than deleted. It might be
      // a budget written by a future version; removing it would destroy a limit
      // this build has no way to interpret.
      if (parsed == null) {
        loaded[raw] = unitsToLimit(units);
        continue;
      }
      if (parsed.isLegacy) {
        // The one-time migration: a period-less limit belongs to month, because
        // month was the only period that ever existed here. The old key is
        // REMOVED, so the migration cannot run twice and cannot leave a shadow
        // copy that a later write would resurrect.
        final target = parsed.migrated;
        loaded[target.raw] = unitsToLimit(units);
        await prefs.setInt('$_prefix${target.raw}', units);
        await prefs.remove(key);
        migrated++;
        continue;
      }
      loaded[parsed.raw] = unitsToLimit(units);
    }

    migrationsApplied = migrated;
    _limits
      ..clear()
      ..addAll(loaded);
    notifyListeners();
  }

  /// The readings for one period, against [index].
  ///
  /// [index] is passed in rather than fetched here so the caller reads spending
  /// from the ONE accessor and hands the result over. A budget screen that
  /// fetched its own figures would be a second place the shared-trip rule has
  /// to be remembered.
  List<BudgetStatus> statusesFor(
    BudgetSpendIndex index, {
    required Map<String, String> journeyLabels,
  }) {
    final results = <BudgetStatus>[];

    // Only budgets FOR this period. With period in the key, a monthly limit and
    // a weekly one both exist at once, so reading every budget against one
    // period's spending would judge each against the wrong figure — which is
    // exactly the bug that made a period-less key a period-less budget.
    for (final budget in budgets.where((b) => b.period == index.period)) {
      if (budget.isJourneyLevel) {
        final spent = index.forJourney(budget.scope!);
        results.add(
          BudgetStatus(
            scope: budget.scope,
            // Resolved to the trip's DESTINATION, which is what a user recognises.
            // This used to take a `List<String>` and search it for the label, which
            // could only ever find the label — so every trip budget was titled with
            // its raw id. Same lookup as [notifyCrossed], so the two agree.
            label: journeyLabels[budget.scope] ?? budget.label,
            limit: budget.limit,
            spent: spent,
            period: index.period,
          ),
        );
        continue;
      }

      final category = ExpenseCategory.values.firstWhere(
        (c) => c.name == budget.label,
        orElse: () => ExpenseCategory.other,
      );
      results.add(
        BudgetStatus(
          label: CategoryRegistry.metaFor(category).name,
          limit: budget.limit,
          spent: index.forCategory(category),
          period: index.period,
        ),
      );
    }
    return results;
  }

  /// Raises a notification for any budget in [index] that has just crossed its
  /// line, and never twice for the same crossing.
  ///
  /// Called AFTER a write, never before it, and it never blocks or refuses. An
  /// expense over budget still has to be recorded — the user spent it, and an app
  /// that will not accept the transaction is an app that loses data. The
  /// notification is information, not a gate.
  ///
  /// De-duplicated per session because this runs after every write: without the
  /// set, saving the same expense path twice would notify twice, and scrolling
  /// the list would do the same.
  Future<void> notifyCrossed({
    required BudgetSpendIndex index,
    required String currencySymbol,
    required Map<String, String> journeyLabels,
  }) async {
    for (final budget in budgets.where((b) => b.period == index.period)) {
      final status = budget.isJourneyLevel
          ? BudgetStatus(
              scope: budget.scope,
              label: journeyLabels[budget.scope] ?? budget.label,
              limit: budget.limit,
              spent: index.forJourney(budget.scope!),
              period: index.period,
            )
          : BudgetStatus(
              label: budget.label,
              limit: budget.limit,
              spent: index.totalSpendCategory(budget.label),
              period: index.period,
            );

      if (!status.shouldNotify) continue;
      if (!_notified.add(status.storageKey)) continue;

      await NotificationService.showTripReminder(
        title: status.isOverspent
            ? 'Over your ${status.label} budget'
            : 'Close to your ${status.label} budget',
        body: status.describe(
          (value) => AppFormat.money(value, symbol: currencySymbol),
        ),
      );
    }
  }

  /// Forgets which budgets have been notified, so a crossing notifies again.
  ///
  /// Called when the period rolls over or the month being browsed changes: the
  /// same budget going over in a new month is new information, and staying
  /// silent about it because March already said so would be a bug.
  void resetNotifications() {
    if (_notified.isEmpty) return;
    _notified.clear();
  }

  static String _keyFor(String? scope, String label, BudgetPeriod period) =>
      scope == null
      ? BudgetKey.forCategory(label, period).raw
      : BudgetKey.forJourney(scope, period).raw;

  Budget _budgetForKey(String key, double limit) {
    final parsed = BudgetKey.parse(key);
    // An unparseable key is still shown, as a category budget under whatever
    // label is left. Dropping it would hide a limit the user can see in storage.
    if (parsed == null) {
      return Budget(label: key.replaceFirst('cat:', ''), limit: limit);
    }
    return Budget(
      scope: parsed.scope,
      label: parsed.label,
      limit: limit,
      period: parsed.period,
    );
  }
}
