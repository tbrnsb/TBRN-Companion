import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_application_1/services/location_insight_service.dart';
import 'package:flutter_application_1/models/index.dart';

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
    final orphanedKeys = _checklistItemsBox.toMap().entries
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

  Future<List<Transaction>> getAllTransactions() async {
    List<Transaction> transactions = [];
    for (var entry in _transactionsBox.values) {
      final transactionData = Map<String, dynamic>.from(entry);
      transactions.add(Transaction.fromJson(transactionData));
    }
    return transactions;
  }

  Future<List<Transaction>> getTransactionsForMonth(int year, int month) async {
    List<Transaction> transactions = [];
    final monthStr =
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';

    for (var entry in _transactionsBox.values) {
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
      final transactionData = Map<String, dynamic>.from(entry);
      if (transactionData['locationId'] == locationId) {
        transactions.add(Transaction.fromJson(transactionData));
      }
    }
    return transactions;
  }

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

  Future<void> updateJourney(Journey journey) async {
    await _journeysBox.put(
      journey.id,
      Map<String, dynamic>.from(journey.toJson()),
    );
  }

  Future<void> deleteJourney(String id) async {
    await _journeysBox.delete(id);
  }

  Future<List<String>> getExpenseCategories() async {
    return _expenseCategoriesBox.values.toList();
  }

  Future<void> addExpenseCategory(String categoryName) async {
    final cleaned = categoryName.trim();
    if (cleaned.isEmpty) return;
    final existing = _expenseCategoriesBox.values.toList();
    if (existing.contains(cleaned)) {
      return;
    }
    await _expenseCategoriesBox.add(cleaned);
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
      transactions: _transactionsBox.length,
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
    required this.journeys,
    required this.customCategories,
  });

  final int checklists;
  final int checklistItems;
  final int locations;
  final int locationLogs;
  final int transactions;
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
