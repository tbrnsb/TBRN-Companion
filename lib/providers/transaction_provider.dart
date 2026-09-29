import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_application_1/models/index.dart';
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
    final result = sorted.take(5).map((id) => metas[id]!).toList();
    if (result.isEmpty) {
      return CategoryRegistry.expenseCategories().take(3).toList();
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
    switch (_filter) {
      case TransactionFilter.expenses:
        return _transactions.where((t) => t.isExpense).toList();
      case TransactionFilter.income:
        return _transactions.where((t) => t.isIncome).toList();
      case TransactionFilter.all:
        return _transactions;
    }
  }

  double get totalIncome => _transactions
      .where((t) => t.isIncome)
      .fold(0.0, (sum, t) => sum + t.amount);

  double get totalExpenses => _transactions
      .where((t) => t.isExpense)
      .fold(0.0, (sum, t) => sum + t.amount);

  double get balance => totalIncome - totalExpenses;

  List<String> get categorySuggestions {
    const defaults = [
      'Food',
      'Travel',
      'Gear',
      'Entertainment',
      'Utilities',
      'Housing',
      'Shopping',
      'Health',
      'Other',
    ];
    final merged = [...defaults, ..._recentCustomCategories];
    final unique = merged.toSet().toList();
    return unique;
  }

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
    } catch (e) {
      _error = 'Failed to load transactions: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addTransaction(Transaction transaction) async {
    try {
      await _storageService.addTransaction(transaction);
      _transactions.add(transaction);
      notifyListeners();
    } catch (e) {
      _error = 'Failed to add transaction: $e';
      notifyListeners();
    }
  }

  Future<void> updateTransaction(Transaction transaction) async {
    try {
      await _storageService.updateTransaction(transaction);
      final index = _transactions.indexWhere((t) => t.id == transaction.id);
      if (index != -1) {
        _transactions[index] = transaction;
        notifyListeners();
      }
    } catch (e) {
      _error = 'Failed to update transaction: $e';
      notifyListeners();
    }
  }

  Future<void> deleteTransaction(String id) async {
    try {
      await _storageService.deleteTransaction(id);
      _transactions.removeWhere((t) => t.id == id);
      notifyListeners();
    } catch (e) {
      _error = 'Failed to delete transaction: $e';
      notifyListeners();
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
    return _transactions
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

  /// Income totals keyed by income category id (`salary`, `freelance`, …), so
  /// callers can look the key straight back up via
  /// [CategoryRegistry.metaForIncome]. Sorted largest first.
  List<MapEntry<String, double>> getIncomeBreakdown() {
    Map<String, double> income = {};

    for (var t in _transactions.whereType<Income>()) {
      income[t.category] = (income[t.category] ?? 0) + t.amount;
    }

    final entries = income.entries.where((entry) => entry.value > 0).toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  double getAverageDailySpending() {
    if (_currentMonth == null) return 0;

    int daysInMonth = DateTime(
      _currentMonth!.year,
      _currentMonth!.month + 1,
      0,
    ).day;

    return getSpendingByCategory() / daysInMonth;
  }

  List<Transaction> getTransactionsInDateRange(
    DateTime startDate,
    DateTime endDate,
  ) {
    return _transactions
        .where(
          (t) =>
              t.date.isAfter(startDate) &&
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

  Future<void> addDemoData() async {
    final now = DateTime.now();

    final expenses = [
      Expense(
        amount: 150.00,
        category: ExpenseCategory.food,
        description: '[Demo] Grocery shopping',
        date: _demoDate(now, 1),
      ),
      Expense(
        amount: 75.50,
        category: ExpenseCategory.travel,
        description: '[Demo] Gas for weekend trip',
        date: _demoDate(now, 3),
      ),
      Expense(
        amount: 45.00,
        category: ExpenseCategory.entertainment,
        description: '[Demo] Movie tickets',
        date: _demoDate(now, 5),
      ),
      Expense(
        amount: 120.00,
        category: ExpenseCategory.utilities,
        description: '[Demo] Electric bill',
        date: _demoDate(now, 10),
      ),
    ];

    final incomes = [
      Income(
        amount: 500.00,
        category: 'salary',
        description: '[Demo] Monthly salary',
        date: DateTime(now.year, now.month, 1),
      ),
      Income(
        amount: 150.00,
        category: 'freelance',
        description: '[Demo] Freelance project',
        date: _demoDate(now, 4),
      ),
      Income(
        amount: 75.00,
        category: 'gift',
        description: '[Demo] Birthday gift',
        date: _demoDate(now, 14),
      ),
    ];

    for (final expense in expenses) {
      await addTransaction(expense);
    }

    for (final income in incomes) {
      await addTransaction(income);
    }
  }

  /// [daysAgo] days before [now], but never leaving the current month.
  ///
  /// `DateTime(y, m, now.day - n)` normalises overflow into the previous month
  /// — on the 3rd, `day - 5` lands in the prior month and the entry vanishes
  /// from the current-month view. Clamping the day to 1 keeps demo rows
  /// visible in the month they were added.
  static DateTime _demoDate(DateTime now, int daysAgo) {
    final day = (now.day - daysAgo).clamp(1, now.day);
    return DateTime(now.year, now.month, day);
  }

  Future<void> clearDemoData() async {
    for (final transaction in [..._transactions]) {
      await deleteTransaction(transaction.id);
    }
  }
}
