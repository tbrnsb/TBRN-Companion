import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/services/notification_service.dart';
import 'package:flutter_application_1/utils/format.dart';

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
  /// `budget_limit_<key>`, where key is `cat:<name>` or `trip:<id>`.
  ///
  /// One flat namespace rather than a serialised map under a single key: a
  /// single key would mean rewriting and re-serialising every budget to change
  /// one, and a corrupt value would lose all of them together.
  static const String _prefix = 'budget_limit_';

  final Map<String, double> _limits = {};

  /// Budgets already notified this session, so a crossing is announced once.
  final Set<String> _notified = {};

  /// Every limit currently set, as a stored reading.
  List<Budget> get budgets =>
      _limits.entries.map((e) => _budgetForKey(e.key, e.value)).toList()
        ..sort((a, b) => a.label.compareTo(b.label));

  /// The limit for a budget, or null when none is set.
  ///
  /// Null rather than 0 for "unset", because a zero limit would be permanently
  /// overspent and there is no reading of the input that means it.
  double? limitFor({String? scope, required String label}) =>
      _limits[_keyFor(scope, label)];

  bool hasLimit({String? scope, required String label}) =>
      _limits.containsKey(_keyFor(scope, label));

  /// Sets or clears a limit. A null or non-positive amount clears it.
  Future<void> setLimit({
    String? scope,
    required String label,
    required double? amount,
  }) async {
    final key = _keyFor(scope, label);
    if (amount == null || amount <= 0) {
      await clearLimit(scope: scope, label: label);
      return;
    }
    if (_limits[key] == amount) return;
    _limits[key] = amount;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_prefix$key', limitToUnits(amount));
    notifyListeners();
  }

  Future<void> clearLimit({String? scope, required String label}) async {
    final key = _keyFor(scope, label);
    if (!_limits.containsKey(key)) return;
    _limits.remove(key);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$key');
    notifyListeners();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final loaded = <String, double>{};
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_prefix)) continue;
      final units = prefs.getInt(key);
      if (units == null || units <= 0) continue;
      loaded[key.substring(_prefix.length)] = unitsToLimit(units);
    }
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
    required List<String> journeyLabels,
  }) {
    final results = <BudgetStatus>[];

    for (final budget in budgets) {
      if (budget.isJourneyLevel) {
        final spent = index.forJourney(budget.scope!);
        results.add(
          BudgetStatus(
            scope: budget.scope,
            label: journeyLabels.firstWhere(
              (name) => name == budget.label,
              orElse: () => budget.label,
            ),
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
    for (final budget in budgets) {
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

  static String _keyFor(String? scope, String label) =>
      scope == null ? 'cat:$label' : 'trip:$scope';

  Budget _budgetForKey(String key, double limit) {
    if (key.startsWith('trip:')) {
      return Budget(
        scope: key.substring(5),
        label: key.substring(5),
        limit: limit,
      );
    }
    return Budget(label: key.replaceFirst('cat:', ''), limit: limit);
  }
}
