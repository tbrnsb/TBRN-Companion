import 'package:flutter/material.dart';
import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/services/storage_service.dart';
import 'package:flutter_application_1/utils/iterable_ext.dart';

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

  List<String> getRecommendedItemsForTrip({
    String? tripType,
    String? notes,
    String? destination,
  }) {
    final normalized = (tripType ?? notes ?? destination ?? '').toLowerCase();

    final key = normalized.contains('business') || normalized.contains('work')
        ? 'business'
        : normalized.contains('weekend') ||
              normalized.contains('leisure') ||
              normalized.contains('holiday')
        ? 'weekend'
        : normalized.contains('camp') ||
              normalized.contains('hike') ||
              normalized.contains('outdoor')
        ? 'outdoor'
        : normalized.contains('flight') ||
              normalized.contains('airport') ||
              normalized.contains('travel')
        ? 'travel'
        : 'essentials';

    final recommendations = {
      'business': [
        'Laptop',
        'Chargers',
        'Power bank',
        'ID/passport',
        'Presentation files',
        'Business cards',
      ],
      'weekend': [
        'Toiletries',
        'Comfortable clothes',
        'Phone charger',
        'Water bottle',
        'Snacks',
        'Travel pillow',
      ],
      'outdoor': [
        'Hiking shoes',
        'Layered jacket',
        'Water bottle',
        'Trail snacks',
        'Sunglasses',
        'First aid kit',
      ],
      'travel': [
        'Passport',
        'Wallet',
        'Headphones',
        'Medication',
        'Travel adapter',
        'Tickets',
      ],
      'essentials': [
        'Documents',
        'Wallet',
        'Phone charger',
        'Medication',
        'Water bottle',
        'Toiletries',
      ],
    };

    return recommendations[key] ?? recommendations['essentials']!;
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
