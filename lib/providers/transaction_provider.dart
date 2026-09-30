import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/services/demo_data_service.dart';
import 'package:flutter_application_1/services/storage_service.dart';

enum TransactionFilter { all, expenses, income }

class TransactionProvider extends ChangeNotifier {
  final StorageService _storageService = StorageService();

  /// Which participant is "me" on each shared trip, by journey id.
  ///
  /// The shared-trip rule cannot be evaluated without it — see
  /// `isMyLedgerEntry` — so it is read once here and handed to the predicate.
  /// Populated by [loadLocalParticipants], which [initialize] awaits.
  final Map<String, String?> _localParticipantByJourney = {};

  /// Resolves the local participant for a trip. Missing trips resolve to null,
  /// which is a real state: a journey whose participant list has not been
  /// answered yet.
  String? _localParticipantFor(String journeyId) =>
      _localParticipantByJourney[journeyId];

  /// Reads which participant the user is on every shared trip.
  ///
  /// Separate from the month load because it answers a different question, and
  /// because a trip's answer can change at any time — the user can say "that's
  /// me" long after the expenses exist. Safe to call again; it merges rather
  /// than replacing, so a journey added since the last read is picked up
  /// without dropping the ones already known.
  Future<void> loadLocalParticipants() async {
    try {
      for (final journey in await _storageService.getAllJourneys()) {
        if (journey.localParticipantId != null) {
          _localParticipantByJourney[journey.id] = journey.localParticipantId;
        }
      }
    } catch (e) {
      // Non-fatal, and deliberately silent. Failing here would leave the app with
      // no ledger at all, which is a far worse outcome than falling back to "no
      // trip expenses are mine" — a conservative wrong answer rather than a
      // blank screen.
      _error = null;
    }
  }

  /// Records which participant the user is on [journeyId], without a reload.
  ///
  /// Called by the trip screen the moment the answer changes, so the ledger
  /// corrects itself immediately rather than on the next month load.
  void setLocalParticipant(String journeyId, String? participantId) {
    if (participantId == null) {
      _localParticipantByJourney.remove(journeyId);
      return;
    }
    _localParticipantByJourney[journeyId] = participantId;
  }

  /// Every transaction on the device, for periods wider than the loaded month.
  ///
  /// [transactions] holds ONE month, because the screen browsing a month should
  /// not hold three years of records. A week or a year budget cannot be answered
  /// from that, though: reading [spendIndex] with a yearly period off a list
  /// containing one month would report a year of spending as a month's worth,
  /// which is worse than reporting nothing.
  ///
  /// Loaded alongside the month and kept in step with every write, so the two
  /// caches cannot disagree. Null until first loaded.
  List<Transaction>? _allTransactions;

  List<Transaction> _transactions = [];
  List<String> _recentCustomCategories = [];
  bool _isLoading = false;
  String? _error;
  DateTime? _currentMonth;
  TransactionFilter _filter = TransactionFilter.all;
  DateTime? _selectedDay;
  TransactionSearchQuery _search = TransactionSearchQuery.none;

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

  // ===== search =====

  /// The current search, or [TransactionSearchQuery.none].
  TransactionSearchQuery get search => _search;

  bool get hasActiveSearch => _search.isNotEmpty;

  set search(TransactionSearchQuery value) {
    if (value == _search) return;
    _search = value;
    notifyListeners();
  }

  void clearSearch() {
    if (_search == TransactionSearchQuery.none) return;
    _search = TransactionSearchQuery.none;
    notifyListeners();
  }

  /// The rows a search returns, in the order the screen shows them.
  ///
  /// Read from [transactions] — the whole loaded MONTH — and not from
  /// [filteredTransactions]. `filteredTransactions` is already narrowed twice
  /// over, by a selected day and by the All/Expenses/Income chips, so searching
  /// inside it hides whatever the other two choices happen to be excluding. A
  /// search that cannot find a row because of an unrelated toggle is a search
  /// that looks broken.
  ///
  /// What IS composed in, and why each part is a separate condition rather than
  /// a fold into `filteredTransactions`:
  ///
  /// - the [TransactionFilter] chips, because those are the user's own explicit
  ///   choice about what kind of money to look at;
  /// - the shared-trip rule, [isMyLedgerEntry], as its own clause. It is NOT part
  ///   of the month or filter composition, and folding it in there would make a
  ///   correctness rule invisible and re-derivable in the wrong place. Another
  ///   participant's trip spending must not be findable and must not be counted
  ///   in any total a search shows.
  ///
  /// A selected day deliberately does NOT narrow this. The day filter is a
  /// browsing convenience; a search is a question about the month, and the user
  /// can always narrow further with the day picker.
  List<Transaction> get searchResults {
    final query = _search;
    if (query.isEmpty) {
      return _transactions
          .where(
            (t) =>
                _filterAllows(t) &&
                isMyLedgerEntry(t, localParticipantIdFor: _localParticipantFor),
          )
          .toList();
    }
    return _transactions
        .where(
          (t) =>
              _filterAllows(t) &&
              isMyLedgerEntry(t, localParticipantIdFor: _localParticipantFor) &&
              query.matches(t),
        )
        .toList();
  }

  bool _filterAllows(Transaction t) => switch (_filter) {
    TransactionFilter.all => true,
    TransactionFilter.expenses => t.isExpense,
    TransactionFilter.income => t.isIncome,
  };

  /// Money out of the search result set, and money into it.
  ///
  /// Deliberately read from [searchResults] rather than recomputed, so a total
  /// shown beside search results can never disagree with the rows above it.
  double get searchTotalExpenses => searchResults
      .where((t) => t.isExpense)
      .fold(0.0, (sum, t) => sum + t.amount);

  double get searchTotalIncome => searchResults
      .where((t) => t.isIncome)
      .fold(0.0, (sum, t) => sum + t.amount);

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
    // Before the month load, because a trip expense is only ever classified once
    // the map that says who "me" is has been read.
    await loadLocalParticipants();
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
      final all = await _storageService.getAllTransactions();
      _transactions = all;
      _allTransactions = all;
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
      // The wide cache is a separate read rather than a filter of the month just
      // loaded: a year budget has to see eleven other months, and rebuilding the
      // whole list here would put the cost of every month change on a screen that
      // only ever shows one of them.
      _allTransactions = await _storageService.getAllTransactions();
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
      // The wide cache has to hear about the write too, or a year budget would
      // keep reporting the figure from before this expense existed.
      _allTransactions?.add(transaction);
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
      _replaceInWideCache(
        transaction,
        keepInMonth: _isInLoadedMonth(transaction.date),
      );
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
      _allTransactions?.removeWhere((t) => t.id == id);
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

  /// Puts [transaction] into the wide cache, or drops it.
  ///
  /// [keepInMonth] is false when the record has been re-dated out of the month
  /// the cache would keep it in — but the wide cache keeps EVERYTHING, so it
  /// only ever needs a replace, never a drop. Named for the month-list
  /// decision so both caches are updated from the same call site and cannot
  /// drift.
  void _replaceInWideCache(
    Transaction transaction, {
    required bool keepInMonth,
  }) {
    final cache = _allTransactions;
    if (cache == null) return;
    final index = cache.indexWhere((t) => t.id == transaction.id);
    if (index == -1) {
      cache.add(transaction);
    } else {
      cache[index] = transaction;
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

  // ===== the one spending accessor =====

  /// THE accessor. Everything that measures money reads through here.
  ///
  /// Budgets read this and nothing else — no reaching into [_transactions], no
  /// recomputing a sum at a call site. That is the whole point: the set of
  /// transactions that counts as my spending is a DATA-LAYER decision (see
  /// `isMyLedgerEntry`), and a rule that lives in one place is a rule that every
  /// consumer picks up at once. A budget that folded its own sum would need
  /// editing the day that rule changed, and would be the one place left
  /// disagreeing with the month total printed above it.
  ///
  /// Scoped by [period] and anchored on [currentMonth] when no anchor is given,
  /// so a budget follows the month the user is browsing rather than the wall
  /// clock — browsing to March should show March's spending, not a March limit
  /// judged against today's numbers.
  ///
  /// Two pools, never mixed:
  /// - [BudgetSpendIndex.byCategory] is app-level spending. It INCLUDES trip
  ///   expenses I paid, because that money left my account and the month total
  ///   directly above the budget counts it. It EXCLUDES expenses another
  ///   participant paid, which is not my spending anywhere in the app.
  /// - [BudgetSpendIndex.byJourney] is the trip's own costs, whoever paid. A
  ///   journey-level limit governs the whole trip, and a reimbursement is not
  ///   spend: settlement writes no transaction, so there is nothing to exclude.
  BudgetSpendIndex spendIndex({
    BudgetPeriod period = BudgetPeriod.month,
    DateTime? anchor,
  }) {
    final month = anchor ?? _currentMonth ?? DateTime.now();
    final window = period.window(DateTime(month.year, month.month));

    // The source list, chosen by whether the loaded month can answer the window.
    //
    // [transactions] holds ONE month — the one on screen. It can answer a month
    // period only when asked about that same month. In every other case the
    // window silently clips to whatever happens to be in the loaded list, so a
    // yearly budget would report a year of spending as a month's worth, and a
    // month budget anchored on a month the user is not browsing would report
    // nothing at all. The all-transactions cache is what makes those honest.
    final anchorMonth = DateTime(month.year, month.month);
    final loaded = _currentMonth;
    final loadedIsAnchor =
        loaded != null &&
        loaded.year == anchorMonth.year &&
        loaded.month == anchorMonth.month;
    final canUseLoaded = period == BudgetPeriod.month && loadedIsAnchor;

    // Falls back to the loaded month when the wide cache has not been read, so
    // an index is still produced rather than nothing. It will be incomplete for
    // a wide period, and that is documented on [_allTransactions].
    final source = canUseLoaded
        ? _transactions
        : (_allTransactions ?? _transactions);

    var total = 0.0;
    final byCategory = <String, double>{};
    final byJourney = <String, double>{};

    for (final t in source) {
      if (!t.isExpense) continue;
      // The shared-trip rule, applied here and nowhere else. Another
      // participant's trip expense is excluded from BOTH pools: it is not my
      // spending, and it is not the trip's cost either — the trip's costs are
      // the expenses, and this one is already counted against the person who
      // paid it.
      if (!isMyLedgerEntry(t, localParticipantIdFor: _localParticipantFor)) {
        continue;
      }
      if (t.date.isBefore(window.start) || !t.date.isBefore(window.end)) {
        continue;
      }

      total += t.amount;
      final category = (t as Expense).category;
      byCategory[category.name] = (byCategory[category.name] ?? 0) + t.amount;
      final journeyId = t.journeyId;
      if (journeyId != null) {
        byJourney[journeyId] = (byJourney[journeyId] ?? 0) + t.amount;
      }
    }

    return BudgetSpendIndex(
      period: period,
      anchorMonth: DateTime(month.year, month.month),
      total: total,
      byCategory: Map.unmodifiable(byCategory),
      byJourney: Map.unmodifiable(byJourney),
    );
  }

  /// App-level spend for one category in one period.
  ///
  /// A convenience over [spendIndex] for the call sites that only need one
  /// number. It still reads the same index rather than summing, so a
  /// single-category caller cannot drift from the list it sits in.
  double categorySpend(
    ExpenseCategory category, {
    BudgetPeriod period = BudgetPeriod.month,
    DateTime? anchor,
  }) => spendIndex(period: period, anchor: anchor).forCategory(category);

  /// Total expense spend in one period.
  double totalSpend({
    BudgetPeriod period = BudgetPeriod.month,
    DateTime? anchor,
  }) => spendIndex(period: period, anchor: anchor).total;

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
