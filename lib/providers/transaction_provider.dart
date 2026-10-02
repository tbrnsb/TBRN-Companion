import 'package:flutter/material.dart';
import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/services/csv_document.dart';
import 'package:daily_companion/services/storage_service.dart';
import 'package:daily_companion/utils/date_window.dart';

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
    // [myLedger]: these chips answer "what do I spend on", so another
    // participant's trip categories must not crowd out the user's own.
    final sorted = [...myLedger]..sort((a, b) => b.date.compareTo(a.date));
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
    for (final t in myLedger) {
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
    for (final t in myLedger) {
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
    // Reads [myLedger] rather than re-applying the shared-trip rule to
    // `_transactions`. Same reason as `_viewTransactions`: one definition of what
    // counts, reached two ways instead of spelled out twice.
    final ledger = myLedger;
    final query = _search;
    if (query.isEmpty) {
      return ledger.where(_filterAllows).toList();
    }
    return ledger.where((t) => _filterAllows(t) && query.matches(t)).toList();
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

  /// MY LEDGER for the loaded month: every transaction that counts as my
  /// spending, with other participants' trip expenses removed.
  ///
  /// THIS IS THE FIX, and it is one accessor rather than a sweep, on purpose. A
  /// screen-level filter is how you end up with six screens each remembering to
  /// filter and one forgetting — and Stage 7 proved the alternative already
  /// exists in two halves: `spendIndex` applied the shared-trip rule for budgets
  /// while `_viewTransactions` returned `_transactions` raw, so for September the
  /// summary card read 21070.50 while the budget beside it read 12670.50. Two
  /// numbers for one month, on one screen.
  ///
  /// Deliberately a computed property rather than a cached list. A cache has to
  /// be invalidated by every write — add, update, trash, restore, month change —
  /// and the trashed rows have to be dropped from it by hand, which is exactly
  /// the kind of thing that is correct on five of six paths. The filter is cheap
  /// enough to run on read and cannot go stale.
  ///
  /// Note what is NOT here: the All/Expenses/Income chips. Those are the user's
  /// own explicit choice about what kind of money to look at, they are applied by
  /// [filteredTransactions], and mixing them in would make it impossible to ask
  /// "what is in my month?" independently of "what am I currently looking at?".
  List<Transaction> get myLedger {
    final raw = _transactions.where((t) => !t.isDeleted);
    return raw
        .where(isMyLedgerEntryFor(_localParticipantFor))
        .toList(growable: false);
  }

  /// Transactions in [year]/[month], read WITHOUT changing what the ledger shows.
  ///
  /// A calendar needs to know which days in *its* month have anything on them,
  /// and it must not do that by calling [loadTransactionsForMonth] — that moves
  /// the ledger to that month and drops the selected day, so merely LOOKING at
  /// August from a calendar opened on the Transactions tab would yank the screen
  /// out from under the user.
  ///
  /// The shared-trip rule is applied here for the same reason it is applied to
  /// [myLedger]: a dot on a day is a claim about the user's own spending, and
  /// somebody else's trip expense is not theirs.
  Future<List<Transaction>> peekTransactionsForMonth(
    int year,
    int month,
  ) async {
    final raw = await _storageService.getTransactionsForMonth(year, month);
    return raw
        .where((t) => !t.isDeleted)
        .where(isMyLedgerEntryFor(_localParticipantFor))
        .toList(growable: false);
  }

  /// The transactions the screen should show: the selected day if there is one,
  /// otherwise the whole of [myLedger].
  ///
  /// Every total, every chart and every list on the screen reads through here, so
  /// the shared-trip rule is applied once and a new screen is correct by
  /// default.
  List<Transaction> get _viewTransactions {
    final day = _selectedDay;
    final ledger = myLedger;
    if (day == null) return ledger;
    return ledger
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
  /// NEVER SILENT. It used to return without feedback in two cases -- a day
  /// outside the loaded month, and a day equal to the current selection -- and a
  /// tap that produces no visible change is indistinguishable from a tap that did
  /// not register. The two refusals now come back as a [DaySelectionOutcome]
  /// the caller turns into something the user can see.
  DaySelectionOutcome setSelectedDay(DateTime? day) {
    if (day == null) {
      if (_selectedDay == null) return const DaySelectionAlreadyWholeMonth();
      _selectedDay = null;
      notifyListeners();
      return const DaySelectionCleared();
    }

    // A day that has not happened is refused too, not just a day in another
    // month. `lastDate` in the picker is capped at today, so a selected day past
    // today made `initialDate` LATER than `lastDate` and the sheet asserted on
    // open -- a crash reached by selecting a day. Caught by the item 4 test.
    final now = DateTime.now();
    if (day.year > now.year ||
        (day.year == now.year && day.month > now.month) ||
        (day.year == now.year && day.month == now.month && day.day > now.day)) {
      return const DayInTheFuture();
    }

    final loaded = _currentMonth;
    if (loaded != null &&
        (day.year != loaded.year || day.month != loaded.month)) {
      // Refused, and SAID SO. Silently ignoring a day in another month is what
      // made this feel broken: the user taps the 14th and nothing at all happens.
      return DayOutsideLoadedMonth(DateTime(loaded.year, loaded.month));
    }

    final current = _selectedDay;
    if (current != null &&
        current.year == day.year &&
        current.month == day.month &&
        current.day == day.day) {
      // Re-tapping the day you are already on. Also said out loud -- a tap with
      // no effect needs to be a tap that explains itself.
      return DayAlreadySelected(day);
    }

    _selectedDay = DateTime(day.year, day.month, day.day);
    notifyListeners();
    return DaySelected(day);
  }

  /// Every day in the loaded month that has at least one transaction, keyed by
  /// date. The day picker uses this to mark which days are worth tapping
  /// instead of offering 30 equally plausible empty cells.
  ///
  /// Built from [myLedger], and that is a DECISION rather than a consequence. A
  /// day whose only content is another participant's trip spending is not marked,
  /// because tapping it would show an empty list: the screen filters, so there is
  /// nothing there to see. Marking it would invite a tap that looks broken — the
  /// exact complaint that made the day picker's marks useful in the first place.
  Set<DateTime> get daysWithTransactions => myLedger
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

  /// Re-reads the user's own categories from storage.
  ///
  /// ALSO republishes them to [CategoryRegistry], which is what makes a colour
  /// or icon chosen in Settings show up in a breakdown, a budget row and a
  /// transaction tile. The registry is static and every one of those readers has
  /// no way to reach storage, so this is the one place the two are joined.
  ///
  /// PUBLIC and re-callable on purpose. It used to run once in [initialize], so a
  /// category added later -- from Settings, say -- was written to storage and
  /// never reached the pickers: the "Other" screen said "None saved yet" while
  /// Settings listed it. A cache that is only ever filled at startup is a cache
  /// that lies after the first write.
  Future<void> loadRecentCustomCategories() async {
    try {
      final stored = await _storageService.getCustomCategories();
      _recentCustomCategories = [for (final category in stored) category.name];
      CategoryRegistry.setCustomCategories(stored);
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load custom categories: $e';
    }
  }

  Future<void> addCustomCategory(String categoryName) async {
    final cleaned = categoryName.trim();
    if (cleaned.isEmpty) return;
    try {
      await _storageService.addExpenseCategory(cleaned);
      // Re-read rather than patch the cache: the name is now in storage, and the
      // record that came back carries the colour and icon too.
      await loadRecentCustomCategories();
      if (!_recentCustomCategories.contains(cleaned)) {
        _recentCustomCategories.insert(0, cleaned);
      }
      notifyListeners();
    } catch (e) {
      _error = 'Failed to save custom category: $e';
      notifyListeners();
    }
  }

  /// The loaded month as CSV, in the format `CsvImporter` reads back.
  ///
  /// WRITTEN BY THE IMPORTER, NOT BY HAND. The header, the column order, the
  /// quoting and the amount format are all [CsvDocument.header] and friends, so
  /// export and import cannot disagree about the format — the round trip is the
  /// thing that has to hold, and two hand-written versions of a CSV format
  /// drift the first time somebody adds a column.
  ///
  /// TWO DATA-QUALITY RULES, applied here:
  ///
  /// - A trashed record is not exported. It is not in the user's ledger and the
  ///   file is meant to be a copy of the ledger.
  /// - Another participant's trip expense is NOT exported. It is not the user's
  ///   spending — see `isMyLedgerEntry`. Exporting it would put a stranger's
  ///   expense into a file the user then shares, and re-importing that file would
  ///   bring it back as if it were theirs. The trip's own costs belong to the
  ///   trip's own share file, which is `TripSnapshot` and not this.
  String exportCurrentMonthCsv() {
    final live = _transactions
        .where((t) => !t.isDeleted)
        .where(isMyLedgerEntryFor(_localParticipantFor))
        .toList();

    final csvRows = <String>[
      CsvDocument.header,
      for (final t in live) CsvDocument.encodeRow(t, currencySymbol: ''),
    ];
    return csvRows.join('\n');
  }

  /// Every live, my-ledger transaction on [month], for the CSV importer.
  ///
  /// Reads the month from storage rather than from [transactions], because an
  /// import can carry records from any month and the duplicate check has to see
  /// what is already on the device — not only what the user happens to be looking
  /// at. Without that, importing a file twice while browsing October would add
  /// the same September row a second time.
  Future<List<Transaction>> existingLedgerForImport() async {
    final all = await _storageService.getAllTransactions();
    return all
        .where((t) => !t.isDeleted)
        .where(isMyLedgerEntryFor(_localParticipantFor))
        .toList();
  }

  /// Writes [items] in one pass, folding each into the loaded month.
  ///
  /// Add-only by construction: every item is a NEW record with its own id, so
  /// nothing existing is overwritten. Returns the ids actually written, so the
  /// caller can report a real count rather than the number it hoped to write.
  ///
  /// One pass rather than a loop over [addTransaction] because each call there
  /// notifies listeners, and a 200-row import would rebuild the screen 200 times
  /// — which on this provider means re-slicing the charts on every frame.
  Future<List<String>> addTransactionsInBulk(List<Transaction> items) async {
    if (items.isEmpty) return [];
    final written = <String>[];
    try {
      for (final item in items) {
        await _storageService.addTransaction(item);
        written.add(item.id);
        if (_isInLoadedMonth(item.date)) {
          _transactions.add(item);
        }
        _allTransactions?.add(item);
      }
      notifyListeners();
      return written;
    } catch (e) {
      _error = 'Failed to import transactions: $e';
      notifyListeners();
      return written;
    }
  }

  /// Registers [name] as a custom expense category, if it is not one already.
  ///
  /// The importer's custom categories go through the SAME registry path the
  /// "Other" screen uses, so a name imported from a file behaves exactly like one
  /// typed by hand — offered as a suggestion, filed as `ExpenseCategory.other`
  /// with a `customName`, never added as a new `ExpenseCategory` value.
  Future<void> registerImportedCategory(String name) => addCustomCategory(name);

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

  /// The trashed records, newest deletion first.
  ///
  /// A separate read rather than a filter of [transactions], because the whole
  /// point is that trashed rows are NOT in [transactions] — they were dropped
  /// from both caches when they were trashed, and from every storage query. The
  /// trash screen is the one place that wants them back.
  Future<List<Transaction>> loadTrashedTransactions() async {
    try {
      return await _storageService.getTrashedTransactions();
    } catch (e) {
      _error = 'Failed to load the trash: $e';
      notifyListeners();
      return [];
    }
  }

  /// Moves [id] to the trash. It disappears from the ledger immediately.
  ///
  /// SOFT: the row stays on disk with a `deletedAt` stamp, so restoring it is a
  /// flag change rather than a re-typed record. A hard delete cannot be undone
  /// and a mistake with it is unrecoverable — which is exactly what a personal
  /// finance ledger must not offer.
  ///
  /// Dropped from BOTH caches and written in one pass, because a cache that kept
  /// the row would keep counting it against every wide-period budget while the
  /// month list showed it correctly gone. Two screens disagreeing about whether
  /// an expense exists is worse than either answer alone.
  ///
  /// NOT tombstoned on the journey, unlike [deleteTransaction]. The trip's
  /// `removedIds` exists to stop an IMPORT resurrecting an expense the user
  /// really did remove from a shared file; a trashed record is still on disk and
  /// still in the trip, so tombstoning it would make a restore come back as a
  /// duplicate of something the importer already knows it may not re-add.
  Future<bool> moveToTrash(String id) async {
    final target = _findInCaches(id);
    if (target == null || target.isDeleted) return false;

    try {
      final trashed = target.withDeletedAt(DateTime.now());
      await _storageService.updateTransaction(trashed);

      // Dropped from BOTH caches by hand rather than delegated to
      // [updateTransaction], which by design KEEPS a row whose date is in the
      // loaded month — correct for an edit, wrong for a trash, because a trashed
      // row must not stay in any live list. One flag, one place that decides
      // what happens to a trashed record in the caches.
      _transactions.removeWhere((t) => t.id == id);
      _allTransactions?.removeWhere((t) => t.id == id);

      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to move to trash: $e';
      notifyListeners();
      return false;
    }
  }

  /// Puts [id] back into the ledger.
  ///
  /// Re-inserted into both caches and, if it belongs to a month other than the
  /// one on screen, it simply is not in the month list — which is correct. The
  /// user restores it and then sees it again when they navigate to the month it
  /// belongs to, rather than it appearing on a screen whose month says otherwise.
  Future<bool> restoreFromTrash(String id) async {
    final target = await _findTrashed(id);
    if (target == null || !target.isDeleted) return false;

    try {
      final live = target.withDeletedAt(null);
      await _storageService.updateTransaction(live);

      // Re-inserted into both caches. Into the MONTH list only when its date
      // belongs to the month on screen — restoring a March expense while looking
      // at October should not put it in an October list.
      _allTransactions?.removeWhere((t) => t.id == id);
      _allTransactions?.add(live);
      _transactions.removeWhere((t) => t.id == id);
      if (_isInLoadedMonth(live.date)) {
        _transactions.add(live);
      }

      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to restore: $e';
      notifyListeners();
      return false;
    }
  }

  /// Permanently removes [id]. Used by the trash screen's own delete action.
  ///
  /// The only irreversible path, and it is a deliberate tap behind the trash
  /// rather than a stray swipe. Tombstones the journey exactly as
  /// [deleteTransaction] does, because at this point the row really is going.
  Future<bool> deleteForever(String id) async {
    final target = await _findTrashed(id);
    if (target == null) return false;
    try {
      await deleteTransaction(id);
      // deleteTransaction already drops it from both caches; this is the
      // trashed row, which was never in either, so there is nothing left to do.
      // The method is here as the named, testable entry point the trash screen
      // calls, rather than the screen reaching into storage itself.
      return true;
    } catch (e) {
      _error = 'Failed to delete: $e';
      notifyListeners();
      return false;
    }
  }

  /// Empties the trash. Every trashed record, permanently.
  Future<int> emptyTrash() async {
    try {
      final trashed = await _storageService.getTrashedTransactions();
      for (final t in trashed) {
        await deleteTransaction(t.id);
      }
      return trashed.length;
    } catch (e) {
      _error = 'Failed to empty the trash: $e';
      notifyListeners();
      return 0;
    }
  }

  /// The record with [id] from whichever cache has it, live or trashed.
  ///
  /// A trashed row is in NEITHER cache — that is the point of trashing it — so
  /// this has to be able to look in the storage trash as well, or the trash
  /// screen's buttons would find nothing to act on.
  Future<Transaction?> _findTrashed(String id) async {
    final inCache = _findInCaches(id);
    if (inCache != null) return inCache;
    final trashed = await _storageService.getTrashedTransactions();
    for (final t in trashed) {
      if (t.id == id) return t;
    }
    return null;
  }

  Transaction? _findInCaches(String id) {
    for (final t in _transactions) {
      if (t.id == id) return t;
    }
    for (final t in _allTransactions ?? const <Transaction>[]) {
      if (t.id == id) return t;
    }
    return null;
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

  /// Expenses with coordinates, from [myLedger].
  ///
  /// Built with `whereType<Expense>` rather than a downcast on a
  /// `List<Transaction>`: `myLedger` is correctly typed `List<Transaction>`, and
  /// `as List<Expense>` on one of those fails at runtime rather than at compile
  /// time. Routing this through `myLedger` is what exposed it — the map would
  /// have thrown on every build the moment another participant's trip expense
  /// was involved.
  List<Expense> get locatedExpenses =>
      myLedger.whereType<Expense>().where((e) => e.hasCoordinates).toList();

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
    final sorted = [...myLedger]..sort((a, b) => b.date.compareTo(a.date));
    return sorted;
  }

  /// The trip's expenses, trashed ones included.
  ///
  /// Unfiltered ON PURPOSE — this feeds the trip's settlement, which must keep
  /// counting an expense the user deleted from their own ledger, because the
  /// money really was spent on the trip. See [getLiveTransactionsForJourney] for
  /// the display half.
  Future<List<Transaction>> getTransactionsByJourney(String journeyId) async {
    try {
      return await _storageService.getTransactionsByJourney(journeyId);
    } catch (e) {
      _error = 'Failed to get transactions: $e';
      notifyListeners();
      return [];
    }
  }

  /// The trip's expenses for DISPLAY — live rows only.
  Future<List<Transaction>> getLiveTransactionsForJourney(
    String journeyId,
  ) async {
    try {
      return await _storageService.getLiveTransactionsByJourney(journeyId);
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
  /// - [BudgetSpendIndex.byJourney] is the trip's costs **that are mine or
  ///   unattributed**. The shared-trip rule applies to it too: "another
  ///   participant's trip expense counts NOWHERE, ever" is the stated rule, and a
  ///   budget is one of the places it counts. This comment previously said
  ///   "whoever paid", which the code did not do — the rule is the one the user
  ///   decided and the implementation is what they asked for.
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
        ? myLedger
        : myLedgerOf(
            _allTransactions ?? _transactions,
            localParticipantIdFor: _localParticipantFor,
          );

    var total = 0.0;
    final byCategory = <String, double>{};
    final byJourney = <String, double>{};

    for (final t in source) {
      if (!t.isExpense) continue;
      // A trashed record is never spending. The storage layer already filters
      // these out and `myLedger` filters them again, so this line cannot be
      // reached today — but the wide branch walks a CACHE, and a cache is only as
      // correct as the writes that maintain it. If one write path ever forgets to
      // drop a trashed row, this is what stops a deleted expense being counted
      // against a yearly budget. A month-scoped test would never reach it.
      if (t.isDeleted) continue;
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
      // Keyed by the category's META id, not the enum name.
      //
      // The enum name put every custom category under "other", because they all
      // ARE `ExpenseCategory.other` with a different `customCategoryName`. So a
      // "Coffee" expense landed in the other budget, no budget could be set for
      // Coffee, and the money was unfalsifiably attributed. This is the same key
      // the spending breakdown uses, so a slice and a budget are the same thing.
      final expense = t as Expense;
      final key = expense.categoryMeta.id;
      byCategory[key] = (byCategory[key] ?? 0) + expense.amount;
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
    return myLedger
        .whereType<Income>()
        .where((t) => t.category == category)
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  List<MapEntry<ExpenseCategory, double>> getSpendingBreakdown() {
    Map<ExpenseCategory, double> spending = {};

    // [myLedger], not [_transactions]: this is a CHART, and a donut slice sized by
    // another participant's trip spending is a slice of my spending that is not.
    for (var t in myLedger.where((t) => t.isExpense)) {
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
    return myLedger
        .where(
          (t) =>
              !t.date.isBefore(startDate) &&
              t.date.isBefore(endDate.add(const Duration(days: 1))),
        )
        .toList();
  }

  /// The earliest month the view can reach, as the first of that month.
  ///
  /// The SAME floor the date pickers use ([AppDateWindow.monthFloor]), not a
  /// second copy of the arithmetic. A chevron that pages back past it lands on a
  /// month the user then cannot record anything in, which is a dead end rather
  /// than a boundary.
  DateTime get earliestMonth => AppDateWindow.monthFloor(DateTime.now());

  /// The latest month the view can reach: the current one.
  ///
  /// This is the CHANGE that fixes September 2046. `nextMonth` used to be
  /// unbounded, so holding the chevron walked the calendar forward without end
  /// and the header would eventually read a year nobody is budgeting for. The
  /// month formatting was never wrong; the navigation had no wall.
  DateTime get latestMonth => AppDateWindow.monthCeiling(DateTime.now());

  /// Whether there is a month before the one on screen.
  bool get canGoToPreviousMonth {
    final month = _currentMonth;
    if (month == null) return false;
    return DateTime(month.year, month.month).isAfter(earliestMonth);
  }

  /// Whether there is a month after the one on screen.
  bool get canGoToNextMonth {
    final month = _currentMonth;
    if (month == null) return false;
    return DateTime(month.year, month.month).isBefore(latestMonth);
  }

  Future<void> previousMonth() async {
    final month = _currentMonth;
    if (month == null) return;
    if (!canGoToPreviousMonth) return;
    final previous = DateTime(month.year, month.month - 1);
    await loadTransactionsForMonth(previous.year, previous.month);
  }

  Future<void> nextMonth() async {
    final month = _currentMonth;
    if (month == null) return;
    if (!canGoToNextMonth) return;
    final next = DateTime(month.year, month.month + 1);
    await loadTransactionsForMonth(next.year, next.month);
  }

  Future<void> goToCurrentMonth() async {
    final now = DateTime.now();
    await loadTransactionsForMonth(now.year, now.month);
  }

  double getTotalSpending() {
    return getSpendingByCategory();
  }
}
