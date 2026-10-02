import 'package:hive_flutter/hive_flutter.dart';
import 'package:daily_companion/services/location_insight_service.dart';
import 'package:daily_companion/models/index.dart';

class StorageService {
  static const String checklistsBox = 'checklists';
  static const String checklistItemsBox = 'checklist_items';
  static const String locationsBox = 'locations';
  static const String locationLogsBox = 'location_logs';
  static const String transactionsBox = 'transactions';
  static const String journeysBox = 'journeys';
  static const String expenseCategoriesBox = 'expense_categories';

  static final StorageService _instance = StorageService._internal();

  late Box<Map> _checklistsBox;
  late Box<Map> _checklistItemsBox;
  late Box<Map> _locationsBox;
  late Box<Map> _locationLogsBox;
  late Box<Map> _transactionsBox;
  late Box<Map> _journeysBox;
  late Box<String> _expenseCategoriesBox;

  factory StorageService() {
    return _instance;
  }

  StorageService._internal();

  Future<void> initialize({String? hivePath}) async {
    if (hivePath != null) {
      Hive.init(hivePath);
    } else {
      await Hive.initFlutter();
    }

    _checklistsBox = await Hive.openBox<Map>(checklistsBox);
    _checklistItemsBox = await Hive.openBox<Map>(checklistItemsBox);
    _locationsBox = await Hive.openBox<Map>(locationsBox);
    _locationLogsBox = await Hive.openBox<Map>(locationLogsBox);
    _transactionsBox = await Hive.openBox<Map>(transactionsBox);
    _journeysBox = await Hive.openBox<Map>(journeysBox);
    _expenseCategoriesBox = await Hive.openBox<String>(expenseCategoriesBox);
    await LocationInsightService.initialize();
  }

  // ===== CHECKLIST OPERATIONS =====

  Future<void> addChecklist(Checklist checklist) async {
    await _checklistsBox.put(
      checklist.id,
      Map<String, dynamic>.from(checklist.toJson()),
    );
  }

  Future<List<Checklist>> getAllChecklists() async {
    List<Checklist> checklists = [];
    for (var entry in _checklistsBox.values) {
      final checklistData = Map<String, dynamic>.from(entry);
      final items = _getChecklistItems(checklistData['id']);
      checklists.add(Checklist.fromJson(checklistData, items));
    }
    return checklists;
  }

  Future<Checklist?> getChecklist(String id) async {
    final data = _checklistsBox.get(id);
    if (data == null) return null;

    final checklistData = Map<String, dynamic>.from(data);
    final items = _getChecklistItems(id);
    return Checklist.fromJson(checklistData, items);
  }

  Future<void> updateChecklist(Checklist checklist) async {
    await _checklistsBox.put(
      checklist.id,
      Map<String, dynamic>.from(checklist.toJson()),
    );
  }

  Future<void> deleteChecklist(String id) async {
    await _checklistsBox.delete(id);
    // Delete associated items.
    //
    // The box *key* has to be what gets deleted, and it is not reachable from
    // the value: `_checklistItemsBox.values` yields each item's field map, whose
    // first key is 'id', not the key Hive stored it under. Deleting
    // `item.keys.first` therefore passed a field name to the box, deleted
    // nothing, and left every item of the deleted checklist in storage
    // forever. `_toMap()` gives the real key for each value.
    final orphanedKeys = _checklistItemsBox
        .toMap()
        .entries
        .where((entry) => entry.value['checklistId'] == id)
        .map((entry) => entry.key)
        .toList();
    for (final key in orphanedKeys) {
      await _checklistItemsBox.delete(key);
    }
  }

  List<ChecklistItem> _getChecklistItems(String checklistId) {
    List<ChecklistItem> items = [];
    for (var entry in _checklistItemsBox.values) {
      final itemData = Map<String, dynamic>.from(entry);
      if (itemData['checklistId'] == checklistId) {
        items.add(ChecklistItem.fromJson(itemData));
      }
    }
    return items;
  }

  // ===== CHECKLIST ITEM OPERATIONS =====

  Future<void> addChecklistItem(ChecklistItem item) async {
    await _checklistItemsBox.put(
      item.id,
      Map<String, dynamic>.from(item.toJson()),
    );
  }

  Future<void> updateChecklistItem(ChecklistItem item) async {
    await _checklistItemsBox.put(
      item.id,
      Map<String, dynamic>.from(item.toJson()),
    );
  }

  Future<void> deleteChecklistItem(String id) async {
    await _checklistItemsBox.delete(id);
  }

  // ===== LOCATION OPERATIONS =====

  Future<void> addLocation(Location location) async {
    await _locationsBox.put(
      location.id,
      Map<String, dynamic>.from(location.toJson()),
    );
  }

  Future<List<Location>> getAllLocations() async {
    List<Location> locations = [];
    for (var entry in _locationsBox.values) {
      final locationData = Map<String, dynamic>.from(entry);
      locations.add(Location.fromJson(locationData));
    }
    return locations;
  }

  Future<Location?> getLocation(String id) async {
    final data = _locationsBox.get(id);
    if (data == null) return null;
    return Location.fromJson(Map<String, dynamic>.from(data));
  }

  Future<void> updateLocation(Location location) async {
    await _locationsBox.put(
      location.id,
      Map<String, dynamic>.from(location.toJson()),
    );
  }

  Future<void> deleteLocation(String id) async {
    await _locationsBox.delete(id);
  }

  // ===== LOCATION LOG OPERATIONS =====

  Future<void> addLocationLog(LocationLog log) async {
    await _locationLogsBox.put(log.id, Map<String, dynamic>.from(log.toJson()));
  }

  Future<List<LocationLog>> getLocationLogs(String locationId) async {
    List<LocationLog> logs = [];
    for (var entry in _locationLogsBox.values) {
      final logData = Map<String, dynamic>.from(entry);
      if (logData['locationId'] == locationId) {
        logs.add(LocationLog.fromJson(logData));
      }
    }
    return logs;
  }

  Future<List<LocationLog>> getLocationLogsInDateRange(
    String locationId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    List<LocationLog> logs = [];
    for (var entry in _locationLogsBox.values) {
      final logData = Map<String, dynamic>.from(entry);
      if (logData['locationId'] == locationId) {
        final log = LocationLog.fromJson(logData);
        if (log.arrivalTime.isAfter(startDate) &&
            log.arrivalTime.isBefore(endDate.add(const Duration(days: 1)))) {
          logs.add(log);
        }
      }
    }
    return logs;
  }

  Future<void> updateLocationLog(LocationLog log) async {
    await _locationLogsBox.put(log.id, Map<String, dynamic>.from(log.toJson()));
  }

  Future<void> deleteLocationLog(String id) async {
    await _locationLogsBox.delete(id);
  }

  Future<LocationLog?> getActiveLocationLog(String locationId) async {
    for (var entry in _locationLogsBox.values) {
      final logData = Map<String, dynamic>.from(entry);
      if (logData['locationId'] == locationId &&
          logData['departureTime'] == null) {
        return LocationLog.fromJson(logData);
      }
    }
    return null;
  }

  // ===== TRANSACTION OPERATIONS =====

  Future<void> addTransaction(Transaction transaction) async {
    await _transactionsBox.put(
      transaction.id,
      Map<String, dynamic>.from(transaction.toJson()),
    );
  }

  /// Every LIVE transaction.
  ///
  /// Soft-deleted rows are excluded. Excluded HERE rather than at each caller, so
  /// there is no read path that can forget: the month query, the location query,
  /// the journey query and this one all filter, and a new query added later
  /// filters too. Filtering in the UI instead would be the same class of bug
  /// six screens deep.
  Future<List<Transaction>> getAllTransactions() async {
    List<Transaction> transactions = [];
    for (var entry in _transactionsBox.values) {
      if (_isTrashed(entry)) continue;
      final transactionData = Map<String, dynamic>.from(entry);
      transactions.add(Transaction.fromJson(transactionData));
    }
    return transactions;
  }

  /// The trashed rows, newest deletion first.
  ///
  /// The one query that deliberately does NOT filter them out. A trash screen
  /// that could not see its own contents would be useless, and this is the only
  /// caller that is allowed to want them.
  Future<List<Transaction>> getTrashedTransactions() async {
    List<Transaction> transactions = [];
    for (var entry in _transactionsBox.values) {
      if (!_isTrashed(entry)) continue;
      final transactionData = Map<String, dynamic>.from(entry);
      transactions.add(Transaction.fromJson(transactionData));
    }
    // By when it was deleted, not by the date it happened: the newest deletion is
    // the one a user wants to undo, and sorting by the transaction's own date
    // would bury it under an expense from last month.
    transactions.sort((a, b) {
      final aAt = a.deletedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bAt = b.deletedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bAt.compareTo(aAt);
    });
    return transactions;
  }

  /// Whether a stored record carries a trash flag.
  ///
  /// Reads the RAW key rather than a decoded [Transaction], because decoding
  /// every row to answer "is this trashed" would parse the whole box to then
  /// discard most of it. Null and empty both mean live, which is what makes
  /// every pre-trash record load unchanged.
  static bool _isTrashed(Map<dynamic, dynamic> entry) {
    final raw = entry['deletedAt'];
    if (raw == null) return false;
    if (raw is String) return raw.isNotEmpty;
    return true;
  }

  Future<List<Transaction>> getTransactionsForMonth(int year, int month) async {
    List<Transaction> transactions = [];
    final monthStr =
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';

    for (var entry in _transactionsBox.values) {
      if (_isTrashed(entry)) continue;
      final transactionData = Map<String, dynamic>.from(entry);
      final date = DateTime.parse(transactionData['date']);
      final dateMonthStr =
          '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';

      if (dateMonthStr == monthStr) {
        transactions.add(Transaction.fromJson(transactionData));
      }
    }
    return transactions;
  }

  Future<List<Transaction>> getTransactionsByLocation(String locationId) async {
    List<Transaction> transactions = [];
    for (var entry in _transactionsBox.values) {
      if (_isTrashed(entry)) continue;
      final transactionData = Map<String, dynamic>.from(entry);
      if (transactionData['locationId'] == locationId) {
        transactions.add(Transaction.fromJson(transactionData));
      }
    }
    return transactions;
  }

  /// EVERY expense on [journeyId], including trashed ones.
  ///
  /// Deliberately UNFILTERED, and this is the important asymmetry in the trash
  /// feature. This is the settlement's data path: `equalShares`, the participant
  /// totals, the unattributed total and the snapshot export all read through it.
  /// Filtering trashed rows out of here would silently change settlement
  /// arithmetic the moment anyone deleted a trip expense — and settlement is the
  /// one figure that must not move for a reason the user never asked about. The
  /// money really was spent on the trip; deleting it from a personal ledger is
  /// not undoing it for the people splitting it.
  ///
  /// The trip's own UI list wants live rows only and uses
  /// [getLiveTransactionsByJourney] for that.
  Future<List<Transaction>> getTransactionsByJourney(String journeyId) async {
    List<Transaction> transactions = [];
    for (var entry in _transactionsBox.values) {
      final transactionData = Map<String, dynamic>.from(entry);
      if (transactionData['journeyId'] == journeyId) {
        transactions.add(Transaction.fromJson(transactionData));
      }
    }
    transactions.sort((a, b) => b.date.compareTo(a.date));
    return transactions;
  }

  /// Live expenses on [journeyId] — what the trip's expense list should show.
  ///
  /// The trashed-filtered twin of [getTransactionsByJourney]. Split into two
  /// named methods rather than a `bool includeDeleted` flag, because a flag makes
  /// "which one did this call site mean?" a question with no answer at the call
  /// site, and that question has to be answered correctly eleven times.
  Future<List<Transaction>> getLiveTransactionsByJourney(
    String journeyId,
  ) async {
    final all = await getTransactionsByJourney(journeyId);
    return all.where((t) => !t.isDeleted).toList();
  }

  Future<void> updateTransaction(Transaction transaction) async {
    await _transactionsBox.put(
      transaction.id,
      Map<String, dynamic>.from(transaction.toJson()),
    );
  }

  Future<void> deleteTransaction(String id) async {
    await _transactionsBox.delete(id);
  }

  // ===== UTILITY OPERATIONS =====

  // ===== JOURNEY OPERATIONS =====

  Future<void> addJourney(Journey journey) async {
    await _journeysBox.put(
      journey.id,
      Map<String, dynamic>.from(journey.toJson()),
    );
  }

  Future<List<Journey>> getAllJourneys() async {
    final journeys = <Journey>[];
    for (final entry in _journeysBox.values) {
      final data = Map<String, dynamic>.from(entry);
      journeys.add(Journey.fromJson(data));
    }
    journeys.sort((a, b) => b.startTime.compareTo(a.startTime));
    return journeys;
  }

  /// One journey by id, or null.
  ///
  /// A plain read. Used where a specific trip is being looked at — importing a
  /// snapshot into the trip it came from, say — where scanning the whole box for
  /// one record would be wasteful and slightly obscure about which record it
  /// meant.
  Future<Journey?> getJourney(String id) async {
    final data = _journeysBox.get(id);
    if (data == null) return null;
    return Journey.fromJson(Map<String, dynamic>.from(data));
  }

  Future<void> updateJourney(Journey journey) async {
    await _journeysBox.put(
      journey.id,
      Map<String, dynamic>.from(journey.toJson()),
    );
  }

  Future<void> deleteJourney(String id) async {
    await _journeysBox.delete(id);
  }

  /// Every custom category, as full records.
  ///
  /// THE SAME BOX, holding richer values. A category used to be a bare name in a
  /// `Box<String>`, and a category now carries a kind, a colour and an emoji. A
  /// new box would have meant a migration that copies every user's categories
  /// across and a window where the two disagree; keeping one box means a legacy
  /// value and a new one are read by the same line of code, with
  /// [CustomCategory.fromStored] recognising which is which.
  ///
  /// Unreadable values are DROPPED rather than thrown on, and never deleted: a
  /// value this build cannot parse might be perfectly readable by the next one,
  /// so it is left where it is and simply not shown.
  Future<List<CustomCategory>> getCustomCategories() async {
    final out = <CustomCategory>[];
    for (final stored in _expenseCategoriesBox.values) {
      final parsed = CustomCategory.fromStored(stored);
      if (parsed != null) out.add(parsed);
    }
    return out;
  }

  /// The custom category NAMES, which is what the old accessor returned and what
  /// the pickers and CSV import still want.
  Future<List<String>> getExpenseCategories() async {
    final out = <String>[];
    for (final category in await getCustomCategories()) {
      out.add(category.name);
    }
    return out;
  }

  /// Creates a category, or does nothing if one of that name already exists.
  ///
  /// Matched case-INSENSITIVELY, because "Coffee" and "coffee" are one category
  /// to a person and two rows in the picker without it. [CustomCategory.id] is
  /// lowercased for the same reason, so the two spellings cannot end up stored
  /// under different ids and split a budget.
  Future<bool> addCustomCategory(CustomCategory category) async {
    final cleaned = category.name.trim();
    if (cleaned.isEmpty) {
      return false;
    }
    final existing = await getCustomCategories();
    final wanted = cleaned.toLowerCase();
    if (existing.any((c) => c.name.trim().toLowerCase() == wanted)) {
      return false;
    }
    await _expenseCategoriesBox.add(category.copyWith(name: cleaned).encode());
    return true;
  }

  Future<void> addExpenseCategory(String categoryName) async {
    await addCustomCategory(CustomCategory(name: categoryName));
  }

  /// Replaces a stored category, matched on its current name.
  ///
  /// Rename is expressed as a replace rather than an in-place edit because the
  /// name is part of the id, so a rename has to rewrite the id. Anything already
  /// filed under the old id keeps pointing at it — the record is matched on the
  /// OLD name and written with the new one, so a rename here changes what the
  /// category is called without silently re-filing past transactions. Migrating
  /// those is a separate, deliberate operation.
  Future<void> updateCustomCategory({
    required String currentName,
    required CustomCategory updated,
  }) async {
    final wanted = currentName.trim().toLowerCase();
    final all = await getCustomCategories();
    final index = all.indexWhere((c) => c.name.trim().toLowerCase() == wanted);
    if (index < 0) return;

    // Hive's `put` needs a key, and this box is keyed by an auto-increment. The
    // record is therefore replaced in place by rewriting the value at the key
    // the OLD record sits under, found by matching the stored string.
    for (final key in _expenseCategoriesBox.keys) {
      final stored = _expenseCategoriesBox.get(key);
      if (stored is! String) continue;
      final parsed = CustomCategory.fromStored(stored);
      if (parsed == null) continue;
      if (parsed.name.trim().toLowerCase() == wanted) {
        await _expenseCategoriesBox.put(key, updated.encode());
        return;
      }
    }
  }

  /// Removes a custom category by name, if it is there.
  Future<void> deleteCustomCategory(String name) async {
    final wanted = name.trim().toLowerCase();
    for (final key in _expenseCategoriesBox.keys.toList()) {
      final stored = _expenseCategoriesBox.get(key);
      if (stored is! String) continue;
      final parsed = CustomCategory.fromStored(stored);
      if (parsed == null) continue;
      if (parsed.name.trim().toLowerCase() == wanted) {
        await _expenseCategoriesBox.delete(key);
        return;
      }
    }
  }

  Future<void> clear() async {
    await _checklistsBox.clear();
    await _checklistItemsBox.clear();
    await _locationsBox.clear();
    await _locationLogsBox.clear();
    await _transactionsBox.clear();
    await _journeysBox.clear();
    await _expenseCategoriesBox.clear();
  }

  /// How many records each box holds, so the settings screen can show the user
  /// what a wipe is about to destroy before they confirm it.
  ///
  /// Read-only. Counts the records themselves rather than deserialising them,
  /// so this stays cheap enough to call while the screen is being built.
  Future<StorageCounts> getStorageCounts() async {
    return StorageCounts(
      checklists: _checklistsBox.length,
      checklistItems: _checklistItemsBox.length,
      locations: _locationsBox.length,
      locationLogs: _locationLogsBox.length,
      // The RAW box length, trashed rows included: "Remove all data" has to
      // count everything it would actually delete, and a trashed record is
      // still a record on disk. The live/trashed split is reported separately.
      transactions: _transactionsBox.length,
      trashedTransactions: await getTrashedTransactions().then(
        (list) => list.length,
      ),
      journeys: _journeysBox.length,
      customCategories: _expenseCategoriesBox.length,
    );
  }
}

/// Record counts for every box [StorageService] owns.
class StorageCounts {
  const StorageCounts({
    required this.checklists,
    required this.checklistItems,
    required this.locations,
    required this.locationLogs,
    required this.transactions,
    required this.trashedTransactions,
    required this.journeys,
    required this.customCategories,
  });

  final int checklists;
  final int checklistItems;
  final int locations;
  final int locationLogs;

  /// Every transaction row on disk, live and trashed.
  final int transactions;

  /// The trashed subset of [transactions]. Drives the settings entry, which is
  /// hidden when this is zero — an entry leading to an empty screen teaches
  /// people the screen is not worth opening.
  final int trashedTransactions;

  final int journeys;
  final int customCategories;

  /// Everything [StorageService.clear] would delete.
  int get total =>
      checklists +
      checklistItems +
      locations +
      locationLogs +
      transactions +
      journeys +
      customCategories;

  /// True when there is nothing to lose, so a destructive action can be
  /// disabled instead of offering a wipe that does nothing.
  bool get isEmpty => total == 0;
}
