import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/services/demo_data_service.dart';
import 'package:flutter_application_1/services/storage_service.dart';

enum TransactionFilter { all, expenses, income }

class TransactionProvider extends ChangeNotifier {
  final StorageService _storageService = StorageService();

  List<Transaction> _transactions = [];
  List<String> _recentCustomCategories = [];
  bool _isLoading = false;
  String? _error;
  DateTime? _currentMonth;
  TransactionFilter _filter = TransactionFilter.all;
  DateTime? _selectedDay;

  List<Transaction> get transactions => _transactions;
  List<String> get recentCustomCategories => _recentCustomCategories;

  /// Most recently used categories, newest first.
  ///
  /// Resolves metadata through [TransactionExtensions.categoryMeta] so an
  /// expense yields expense metadata (icon + colour) and an income yields
  /// income metadata. Going through [CategoryRegistry.metaForIncome] for
  /// everything gave every expense the "Other Income" icon and colour.
  List<CategoryMeta> get recentCategories {
    final sorted = [..._transactions]..sort((a, b) => b.date.compareTo(a.date));
    final seen = <String>{};
    final result = <CategoryMeta>[];
    for (final t in sorted) {
      final meta = t.categoryMeta;
      if (seen.add(meta.id)) result.add(meta);
      if (result.length >= 5) break;
    }
    return result;
  }

  /// Most-used categories, highest count first.
  ///
  /// Feeds the expense category picker, so the empty fallback is expense
  /// categories — income categories here would offer salary/freelance chips
  /// where food/travel belong.
  List<CategoryMeta> get popularCategories {
    final counts = <String, int>{};
    final metas = <String, CategoryMeta>{};
    for (final t in _transactions) {
      final meta = t.categoryMeta;
      counts[meta.id] = (counts[meta.id] ?? 0) + 1;
      metas[meta.id] = meta;
    }
    final sorted = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    // Four, not five: the add sheet shows these as a wrapped row of chips, and
    // five pushes the category list itself below the fold on a small phone.
    final result = sorted.take(4).map((id) => metas[id]!).toList();
    if (result.isEmpty) {
      return CategoryRegistry.expenseCategories().take(4).toList();
    }
    return result;
  }

  Map<String, CategoryMeta> get categories {
    final map = <String, CategoryMeta>{};
    for (final t in _transactions) {
      if (!map.containsKey(t.effectiveCategoryName)) {
        final isExpense = t.isExpense;
        CategoryMeta meta;
        if (isExpense) {
          final expense = t as Expense;
          meta = expense.categoryMeta;
        } else {
          meta = CategoryRegistry.metaForIncome(t.effectiveCategoryName);
        }
        map[t.effectiveCategoryName] = meta;
      }
    }
    return map;
  }

  bool get isLoading => _isLoading;
  String? get error => _error;
  DateTime? get currentMonth => _currentMonth;
  TransactionFilter get filter => _filter;

  set filter(TransactionFilter value) {
    _filter = value;
    notifyListeners();
  }

  List<Transaction> get filteredTransactions {
    // A selected day narrows the view, so the balance, the breakdown charts and
    // the transaction list all describe the same slice. Filtering only the list
    // would leave the summary card describing the whole month next to a list of
    // one day.
    final view = _viewTransactions;
    switch (_filter) {
      case TransactionFilter.expenses:
        return view.where((t) => t.isExpense).toList();
      case TransactionFilter.income:
        return view.where((t) => t.isIncome).toList();
      case TransactionFilter.all:
        return view;
    }
  }

  /// The transactions the screen should show: the selected day if there is one,
  /// otherwise the whole loaded month.
  List<Transaction> get _viewTransactions {
    final day = _selectedDay;
    if (day == null) return _transactions;
    return _transactions
        .where(
          (t) =>
              t.date.year == day.year &&
              t.date.month == day.month &&
              t.date.day == day.day,
        )
        .toList();
  }

  /// The day the user narrowed the view to, or null for the whole month.
  DateTime? get selectedDay => _selectedDay;

  bool get isShowingSingleDay => _selectedDay != null;

  /// Narrows the view to one day, or back to the whole month with null.
  ///
  /// A day outside the loaded month is ignored rather than silently emptying
  /// the screen, which is what would otherwise happen if the caller passed one.
  void setSelectedDay(DateTime? day) {
    if (day == null) {
      if (_selectedDay == null) return;
      _selectedDay = null;
      notifyListeners();
      return;
    }

    final loaded = _currentMonth;
    if (loaded != null &&
        (day.year != loaded.year || day.month != loaded.month)) {
      return;
    }
    final current = _selectedDay;
    if (current != null &&
        current.year == day.year &&
        current.month == day.month &&
        current.day == day.day) {
      return;
    }

    _selectedDay = DateTime(day.year, day.month, day.day);
    notifyListeners();
  }

  /// Every day in the loaded month that has at least one transaction, keyed by
  /// date. The day picker uses this to mark which days are worth tapping
  /// instead of offering 30 equally plausible empty cells.
  Set<DateTime> get daysWithTransactions => _transactions
      .map((t) => DateTime(t.date.year, t.date.month, t.date.day))
      .toSet();

  /// Money in and out per day, oldest first, for days that have any.
  ///
  /// Only days with something on them are included. A daily chart across the
  /// whole month pads most of its width with zeroes, which is the same reason
  /// the journeys 7-day bar chart was deleted: a chart of mostly empty bars
  /// looks like a rendering fault and carries no information.
  List<({DateTime day, double income, double expenses})> get dailyTotals {
    final totals = <DateTime, ({double income, double expenses})>{};

    for (final t in _viewTransactions) {
      final day = DateTime(t.date.year, t.date.month, t.date.day);
      final current = totals[day] ?? (income: 0.0, expenses: 0.0);
      totals[day] = (
        income: current.income + (t.isIncome ? t.amount : 0),
        expenses: current.expenses + (t.isExpense ? t.amount : 0),
      );
    }

    final days = totals.keys.toList()..sort();
    return [
      for (final day in days)
        (
          day: day,
          income: totals[day]!.income,
          expenses: totals[day]!.expenses,
        ),
    ];
  }

  /// Money in and out for the current view.
  ///
  /// Follows a selected day, because the user asked to see one day and
  /// everything on screen should describe it. Deliberately does *not* follow
  /// [filter]: the All/Expenses/Income chips narrow the list below this, while
  /// this is a summary of the period. Making the balance change every time a
  /// filter is tapped reads as a fault rather than a mode.
  double get totalIncome => _viewTransactions
      .where((t) => t.isIncome)
      .fold(0.0, (sum, t) => sum + t.amount);

  double get totalExpenses => _viewTransactions
      .where((t) => t.isExpense)
      .fold(0.0, (sum, t) => sum + t.amount);

  double get balance => totalIncome - totalExpenses;

  Future<void> initialize() async {
    _currentMonth = DateTime.now();
    await loadRecentCustomCategories();
    await loadTransactionsForMonth(_currentMonth!.year, _currentMonth!.month);
  }

  Future<void> loadRecentCustomCategories() async {
    try {
      _recentCustomCategories = await _storageService.getExpenseCategories();
    } catch (e) {
      _error = 'Failed to load custom categories: $e';
    }
  }

  Future<void> addCustomCategory(String categoryName) async {
    final cleaned = categoryName.trim();
    if (cleaned.isEmpty) return;
    try {
      await _storageService.addExpenseCategory(cleaned);
      if (!_recentCustomCategories.contains(cleaned)) {
        _recentCustomCategories.insert(0, cleaned);
      }
      notifyListeners();
    } catch (e) {
      _error = 'Failed to save custom category: $e';
      notifyListeners();
    }
  }

  Future<String> exportCurrentMonthCsv() async {
    final csvRows = <String>[
      'date,description,amount,category,type',
      ..._transactions.map(
        (t) =>
            '${DateFormat('yyyy-MM-dd').format(t.date)},${_escapeCsv(t.description)},${t.amount.toStringAsFixed(2)},${_escapeCsv(t.effectiveCategoryName)},${t.type}',
      ),
    ];
    return csvRows.join('\n');
  }

  String _escapeCsv(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  Future<void> loadAllTransactions() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _transactions = await _storageService.getAllTransactions();
    } catch (e) {
      _error = 'Failed to load transactions: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadTransactionsForMonth(int year, int month) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _transactions = await _storageService.getTransactionsForMonth(
        year,
        month,
      );
      _currentMonth = DateTime(year, month);
      // A day belongs to a month. Moving months has to drop the selection, or
      // the view stays narrowed to a day that is not loaded.
      _selectedDay = null;
    } catch (e) {
      _error = 'Failed to load transactions: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// True when [date] falls inside the month currently on screen.
  ///
  /// [transactions] is the *month view*, not a global list, so anything outside
  /// [currentMonth] must not be folded into it.
  bool _isInLoadedMonth(DateTime date) {
    final month = _currentMonth;
    if (month == null) return false;
    return date.year == month.year && date.month == month.month;
  }

  /// Writes [transaction] and folds it into the loaded month view.
  ///
  /// Returns whether the write actually reached storage. Callers may ignore the
  /// result, but the add/edit sheets must not: the write used to fail silently
  /// into [error] while the sheet popped anyway, so a failed save threw away
  /// the amount the user had just typed and left the button disabled forever.
  ///
  /// A record dated outside [currentMonth] is deliberately NOT appended to
  /// [transactions]. The add sheets let the user pick any past date, so this is
  /// routine — and appending anyway put a foreign row into this month's totals,
  /// breakdown chart and list, which then disagreed with storage until the month
  /// was reloaded. The write still happens, so the record is there when the user
  /// visits the month it belongs to.
  Future<bool> addTransaction(Transaction transaction) async {
    try {
      await _storageService.addTransaction(transaction);
      if (_isInLoadedMonth(transaction.date)) {
        _transactions.add(transaction);
      }
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to add transaction: $e';
      notifyListeners();
      return false;
    }
  }

  /// Writes [transaction] and keeps the loaded month view consistent.
  ///
  /// Re-dating a record out of [currentMonth] drops the stale row, and re-dating
  /// one into it adds the new row. Both directions used to leave the month view
  /// disagreeing with storage: the first left a duplicate counting towards the
  /// totals, the second made a just-saved record invisible.
  Future<bool> updateTransaction(Transaction transaction) async {
    try {
      await _storageService.updateTransaction(transaction);
      final index = _transactions.indexWhere((t) => t.id == transaction.id);

      if (_isInLoadedMonth(transaction.date)) {
        if (index == -1) {
          _transactions.add(transaction);
        } else {
          _transactions[index] = transaction;
        }
      } else if (index != -1) {
        _transactions.removeAt(index);
      }
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to update transaction: $e';
      notifyListeners();
      return false;
    }
  }

  /// Deletes a transaction.
  ///
  /// When it is an expense on a SHARED trip, the trip is also told it was
  /// deleted. That tombstone is what stops the next file a friend shares from
  /// putting the expense straight back: an import only ever adds, so without a
  /// record of the deletion the user would watch it reappear every time, with
  /// nothing they can do about it.
  Future<void> deleteTransaction(String id) async {
    final transaction = _transactions
        .where((t) => t.id == id)
        .cast<Transaction?>()
        .firstWhere((_) => true, orElse: () => null);

    try {
      await _storageService.deleteTransaction(id);
      _transactions.removeWhere((t) => t.id == id);
      notifyListeners();

      if (transaction != null) {
        await _noteRemovalOnJourney(transaction);
      }
    } catch (e) {
      _error = 'Failed to delete transaction: $e';
      notifyListeners();
    }
  }

  /// Writes the tombstone directly to storage.
  ///
  /// Deliberately not through [JourneyProvider]: that provider caches journeys
  /// and re-saving one from a stale copy here would overwrite whatever else
  /// changed since it was loaded. Read, append one id, write back — three
  /// statements against the source of truth.
  Future<void> _noteRemovalOnJourney(Transaction transaction) async {
    final journeyId = transaction.journeyId;
    if (journeyId == null) return;

    final journey = await _storageService.getJourney(journeyId);
    if (journey == null || !journey.isShared) return;

    try {
      // withRemoved is the only way to add a tombstone, so the size cap lives
      // with the data rather than at each call site.
      await _storageService.updateJourney(journey.withRemoved(transaction.id));
    } catch (_) {
      // The deletion already succeeded. Failing here would report a problem the
      // user cannot act on, and the cost is only that a re-shared file might
      // offer the expense back once.
    }
  }

  List<Expense> get locatedExpenses =>
      _transactions
              .where((t) => t.isExpense && (t as Expense).hasCoordinates)
              .toList()
          as List<Expense>;

  Future<List<Expense>> getAllLocatedExpenses() async {
    try {
      final all = await _storageService.getAllTransactions();
      return all
              .where((t) => t.isExpense && (t as Expense).hasCoordinates)
              .toList()
          as List<Expense>;
    } catch (e) {
      _error = 'Failed to load transactions: $e';
      notifyListeners();
      return [];
    }
  }

  List<Transaction> get recentTransactions {
    final sorted = [..._transactions]..sort((a, b) => b.date.compareTo(a.date));
    return sorted;
  }

  Future<List<Transaction>> getTransactionsByJourney(String journeyId) async {
    try {
      return await _storageService.getTransactionsByJourney(journeyId);
    } catch (e) {
      _error = 'Failed to get transactions: $e';
      notifyListeners();
      return [];
    }
  }

  Future<List<Transaction>> getTransactionsByLocation(String locationId) async {
    try {
      return await _storageService.getTransactionsByLocation(locationId);
    } catch (e) {
      _error = 'Failed to get transactions: $e';
      notifyListeners();
      return [];
    }
  }

  double getSpendingByCategory() {
    return _viewTransactions
        .where((t) => t.isExpense)
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  /// Total income recorded under [category], which is an income category id
  /// such as `salary` (see `IncomeCategory`).
  double getIncomeByCategory(String category) {
    return _transactions
        .whereType<Income>()
        .where((t) => t.category == category)
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  List<MapEntry<ExpenseCategory, double>> getSpendingBreakdown() {
    Map<ExpenseCategory, double> spending = {};

    for (var t in _transactions.where((t) => t.isExpense)) {
      final expense = t as Expense;
      spending[expense.category] = (spending[expense.category] ?? 0) + t.amount;
    }

    final entries = spending.entries.where((entry) => entry.value > 0).toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  /// Expense breakdown resolved to real, distinct slices, largest first.
  ///
  /// `ExpenseCategory.other` rows can each carry their own custom name
  /// ("Coffee", "Groceries"), so they are deliberately NOT merged into one
  /// bucket: a breakdown keyed by the enum alone summed them together and
  /// labelled the slice with whichever name happened to sort first, which made
  /// the chart disagree with the transaction tiles. Rows under `.other` with no
  /// custom name still share the single literal "Other" slice, because that is
  /// genuinely what they are.
  ///
  /// [getSpendingBreakdown] remains available as the category-level roll-up.
  List<CategorySlice> getSpendingBreakdownSlices() {
    final slices = <String, CategorySlice>{};

    for (final t in _viewTransactions.whereType<Expense>()) {
      if (!t.amount.isFinite || t.amount <= 0) continue;
      // `metaFor` gives every custom name its own `custom:<name>` id, so
      // distinct names stay distinct slices.
      final meta = t.categoryMeta;
      final existing = slices[meta.id];
      slices[meta.id] = CategorySlice(
        meta: meta,
        amount: (existing?.amount ?? 0) + t.amount,
      );
    }

    final result = slices.values.toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    return List.unmodifiable(result);
  }

  /// Income totals keyed by income category id (`salary`, `freelance`, …), so
  /// callers can look the key straight back up via
  /// [CategoryRegistry.metaForIncome]. Sorted largest first.
  List<MapEntry<String, double>> getIncomeBreakdown() {
    Map<String, double> income = {};

    for (var t in _viewTransactions.whereType<Income>()) {
      income[t.category] = (income[t.category] ?? 0) + t.amount;
    }

    final entries = income.entries.where((entry) => entry.value > 0).toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  /// Spending per day across the current view.
  ///
  /// For a whole month that is the month's spending over its length. For a
  /// selected day it is simply that day's spending, because dividing one day's
  /// spend by 30 would be meaningless.
  double getAverageDailySpending() {
    final day = _selectedDay;
    if (day != null) return getSpendingByCategory();

    if (_currentMonth == null) return 0;
    final daysInMonth = DateTime(
      _currentMonth!.year,
      _currentMonth!.month + 1,
      0,
    ).day;

    return getSpendingByCategory() / daysInMonth;
  }

  /// Transactions between [startDate] and [endDate], both inclusive.
  ///
  /// The start is compared with `isBefore` rather than `isAfter` so that a
  /// one-day range works. `isAfter` is strict, so a transaction recorded at
  /// exactly midnight on the boundary was excluded and `getTransactionsInDateRange(d, d)`
  /// returned nothing at all — a silent empty result rather than an error.
  List<Transaction> getTransactionsInDateRange(
    DateTime startDate,
    DateTime endDate,
  ) {
    return _transactions
        .where(
          (t) =>
              !t.date.isBefore(startDate) &&
              t.date.isBefore(endDate.add(const Duration(days: 1))),
        )
        .toList();
  }

  Future<void> previousMonth() async {
    if (_currentMonth == null) return;
    final previousMonth = DateTime(
      _currentMonth!.year,
      _currentMonth!.month - 1,
    );
    await loadTransactionsForMonth(previousMonth.year, previousMonth.month);
  }

  Future<void> nextMonth() async {
    if (_currentMonth == null) return;
    final nextMonth = DateTime(_currentMonth!.year, _currentMonth!.month + 1);
    await loadTransactionsForMonth(nextMonth.year, nextMonth.month);
  }

  Future<void> goToCurrentMonth() async {
    final now = DateTime.now();
    await loadTransactionsForMonth(now.year, now.month);
  }

  double getTotalSpending() {
    return getSpendingByCategory();
  }

  /// Seeds one batch of sample data across checklists, journeys, places and
  /// transactions.
  ///
  /// Delegated to [DemoDataService] so the demo records for the whole app live
  /// in one place, rather than spend-only seeding hidden on this provider.
  /// The caller is responsible for reloading the providers afterwards; nothing
  /// runs on app start.
  Future<void> addDemoData() => DemoDataService.seedAll();

  /// Removes every demo record, in every month and every section.
  ///
  /// This used to iterate [transactions] — only the loaded month — and delete
  /// every one of them, demo and real alike, while its dialog claimed "Clear
  /// All Data". It removed neither all the demo data nor only the demo data.
  /// The real user's records were the ones at risk. It now delegates to
  /// [DemoDataService.clearAll], which reads every box and matches on the demo
  /// id prefix, so nothing the user created can be caught by it.
  Future<int> clearDemoData() => DemoDataService.clearAll();
}
