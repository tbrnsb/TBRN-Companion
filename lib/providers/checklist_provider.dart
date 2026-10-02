import 'package:flutter/material.dart';
import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/services/packing_suggestions.dart';
import 'package:daily_companion/services/storage_service.dart';
import 'package:daily_companion/utils/iterable_ext.dart';

class ChecklistProvider extends ChangeNotifier {
  final StorageService _storageService = StorageService();

  List<Checklist> _checklists = [];
  bool _isLoading = false;
  String? _error;

  List<Checklist> get checklists => _checklists;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Get everyday essentials checklist
  Checklist? get everydayEssentials {
    try {
      return _checklists.firstWhere((c) => c.isEverydayEssentials);
    } catch (e) {
      return null;
    }
  }

  // Get checklists for a specific location
  List<Checklist> getChecklistsForLocation(String locationId) {
    return _checklists.where((c) => c.linkedLocationId == locationId).toList();
  }

  // Get checklists linked to a journey
  List<Checklist> getChecklistsForJourney(String journeyId) {
    return _checklists.where((c) => c.journeyId == journeyId).toList();
  }

  // Duplicate a checklist (with fresh item ids, all unchecked)
  Future<void> duplicateChecklist(String id) async {
    final source = _checklists.where((c) => c.id == id).firstOrNull;
    if (source == null) return;
    final copy = Checklist(
      name: '${source.name} (copy)',
      description: source.description,
      linkedLocationId: source.linkedLocationId,
      journeyId: source.journeyId,
      isEverydayEssentials: false,
    );
    await addChecklist(copy);
    for (final item in source.items) {
      await addItemToChecklist(
        copy.id,
        ChecklistItem(checklistId: copy.id, name: item.name),
      );
    }
  }

  // Remove all checked items from a checklist
  Future<void> clearCompletedItems(String checklistId) async {
    final checklist = _checklists.where((c) => c.id == checklistId).firstOrNull;
    if (checklist == null) return;
    final completed = checklist.items.where((i) => i.isChecked).toList();
    for (final item in completed) {
      await deleteChecklistItem(item.id);
    }
  }

  // Initialize - load all checklists
  Future<void> initialize() async {
    await loadChecklists();
  }

  // Load all checklists from database
  Future<void> loadChecklists() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _checklists = await _storageService.getAllChecklists();
    } catch (e) {
      _error = 'Failed to load checklists: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Add new checklist
  Future<void> addChecklist(Checklist checklist) async {
    try {
      await _storageService.addChecklist(checklist);
      _checklists.add(checklist);
      notifyListeners();
    } catch (e) {
      _error = 'Failed to add checklist: $e';
      notifyListeners();
    }
  }

  // Update checklist
  Future<void> updateChecklist(Checklist checklist) async {
    try {
      await _storageService.updateChecklist(checklist);
      final index = _checklists.indexWhere((c) => c.id == checklist.id);
      if (index != -1) {
        _checklists[index] = checklist;
        notifyListeners();
      }
    } catch (e) {
      _error = 'Failed to update checklist: $e';
      notifyListeners();
    }
  }

  // Delete checklist
  Future<void> deleteChecklist(String id) async {
    try {
      await _storageService.deleteChecklist(id);
      _checklists.removeWhere((c) => c.id == id);
      notifyListeners();
    } catch (e) {
      _error = 'Failed to delete checklist: $e';
      notifyListeners();
    }
  }

  // Add item to checklist
  Future<void> addItemToChecklist(
    String checklistId,
    ChecklistItem item,
  ) async {
    try {
      await _storageService.addChecklistItem(item);

      final checklistIndex = _checklists.indexWhere((c) => c.id == checklistId);
      if (checklistIndex != -1) {
        _checklists[checklistIndex].items.add(item);
        notifyListeners();
      }
    } catch (e) {
      _error = 'Failed to add item: $e';
      notifyListeners();
    }
  }

  /// Whether [checklistId] already has an item called [name].
  ///
  /// Case-insensitive and whitespace-tolerant, because "Water bottle" and
  /// "water  bottle" are the same thing to a person and two rows to a list.
  /// Storage is unchanged: existing duplicates are left alone, since deleting
  /// something the user typed would be worse than showing it twice.
  bool checklistHasItem(String checklistId, String name) {
    final checklist = _checklists.where((c) => c.id == checklistId).firstOrNull;
    if (checklist == null) return false;
    return _containsItem(checklist, name);
  }

  /// Adds [name] to [checklistId] unless it is already there.
  ///
  /// Returns true when the item was added, false when it was already present.
  /// The bool is what lets a caller say "already on the list" rather than
  /// silently doing nothing and leaving the user wondering whether the tap
  /// landed.
  Future<bool> addItemByName(String checklistId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;

    final checklist = _checklists.where((c) => c.id == checklistId).firstOrNull;
    if (checklist == null) return false;
    if (_containsItem(checklist, trimmed)) return false;

    await addItemToChecklist(
      checklistId,
      ChecklistItem(checklistId: checklistId, name: trimmed),
    );
    return true;
  }

  /// Builds a checklist for [journey] in one tap.
  ///
  /// This is the join between the two systems that used to overlap. A trip
  /// carried its own `items` list that nobody could tick off, while the Pack tab
  /// carried real checklists with progress. Tapping this folds the trip's items
  /// in and adds what the trip itself implies, so the journey page can show
  /// "4 of 9 packed" and mean it.
  ///
  /// Returns the checklist, or null if the trip already has one — a second pack
  /// for the same trip is almost never what someone meant, and silently making
  /// a duplicate list is how a pack ends up with three of everything.
  Future<Checklist?> packForJourney(Journey journey) async {
    final existing = getChecklistsForJourney(journey.id).firstOrNull;
    if (existing != null) return null;

    final checklist = Checklist(
      name: journey.title.isEmpty ? 'Pack' : 'Pack for ${journey.title}',
      description: 'Packing list for ${journey.title}',
      journeyId: journey.id,
    );
    await addChecklist(checklist);

    // The trip's own items first — they are what the user actually wrote down —
    // then the suggestions, deduped against them.
    final names = <String>[
      for (final item in journey.items)
        if (item.trim().isNotEmpty) item.trim(),
      for (final suggestion in PackingSuggestions.forTrip(
        destination: journey.destination,
        startTime: journey.startTime,
        endTime: journey.endTime,
      ))
        suggestion.name,
    ];

    var seen = <String>{};
    for (final name in names) {
      final key = name.toLowerCase();
      if (!seen.add(key)) continue;
      await addItemToChecklist(
        checklist.id,
        ChecklistItem(checklistId: checklist.id, name: name),
      );
    }

    return _checklists.where((c) => c.id == checklist.id).firstOrNull;
  }

  /// How much of [journeyId]'s packing is done, for the journey card.
  ///
  /// Null when the trip has no checklist, so the caller can tell "nothing packed
  /// yet" from "nothing to pack", which are different facts and only one of
  /// them is a prompt to do something.
  PackProgress? packProgressFor(String journeyId) {
    final checklists = getChecklistsForJourney(journeyId);
    if (checklists.isEmpty) return null;

    var packed = 0;
    var total = 0;
    for (final checklist in checklists) {
      packed += checklist.items.where((i) => i.isChecked).length;
      total += checklist.items.length;
    }
    return PackProgress(packed: packed, total: total);
  }

  bool _containsItem(Checklist checklist, String name) {
    final wanted = _normalise(name);
    return checklist.items.any((i) => _normalise(i.name) == wanted);
  }

  static String _normalise(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  // Update item in checklist
  Future<void> updateChecklistItem(ChecklistItem item) async {
    try {
      await _storageService.updateChecklistItem(item);

      for (var checklist in _checklists) {
        final itemIndex = checklist.items.indexWhere((i) => i.id == item.id);
        if (itemIndex != -1) {
          checklist.items[itemIndex] = item;
          notifyListeners();
          break;
        }
      }
    } catch (e) {
      _error = 'Failed to update item: $e';
      notifyListeners();
    }
  }

  // Toggle item checked status
  Future<void> toggleItem(String itemId) async {
    for (var checklist in _checklists) {
      final itemIndex = checklist.items.indexWhere((i) => i.id == itemId);
      if (itemIndex != -1) {
        final item = checklist.items[itemIndex];
        final updatedItem = item.copyWith(isChecked: !item.isChecked);
        await updateChecklistItem(updatedItem);
        break;
      }
    }
  }

  // Delete item from checklist
  Future<void> deleteChecklistItem(String itemId) async {
    try {
      await _storageService.deleteChecklistItem(itemId);

      for (var checklist in _checklists) {
        checklist.items.removeWhere((i) => i.id == itemId);
      }
      notifyListeners();
    } catch (e) {
      _error = 'Failed to delete item: $e';
      notifyListeners();
    }
  }

  // Reset all items in checklist (uncheck all)
  Future<void> resetChecklist(String checklistId) async {
    final checklistIndex = _checklists.indexWhere((c) => c.id == checklistId);
    if (checklistIndex != -1) {
      final checklist = _checklists[checklistIndex];
      for (var item in checklist.items) {
        if (item.isChecked) {
          await updateChecklistItem(item.copyWith(isChecked: false));
        }
      }
    }
  }
}

/// How much of a trip is packed. "4 of 9".
class PackProgress {
  const PackProgress({required this.packed, required this.total});

  final int packed;
  final int total;

  /// "4 of 9 packed". An empty checklist reads as "nothing to pack" rather than
  /// "0 of 0", which is technically true and useless.
  String get label =>
      total == 0 ? 'nothing to pack' : '$packed of $total packed';

  double get fraction => total == 0 ? 0 : packed / total;
}
