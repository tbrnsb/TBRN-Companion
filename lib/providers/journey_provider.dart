import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/services/notification_service.dart';
import 'package:flutter_application_1/services/storage_service.dart';
import 'package:flutter_application_1/utils/iterable_ext.dart';

class JourneyProvider extends ChangeNotifier {
  final StorageService _storage = StorageService();
  Timer? _reminderTimer;

  List<Journey> _journeys = [];
  Journey? _activeJourney;
  DateTime? _lastReminderAt;
  bool _isLoading = false;
  String? _error;

  List<Journey> get journeys => _journeys;
  Journey? get activeJourney => _activeJourney;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Journey? getJourneyById(String id) =>
      _journeys.where((j) => j.id == id).firstOrNull;

  void _refreshActiveJourney() {
    // Prefer a journey that has already started over a future (upcoming) one.
    _activeJourney =
        _journeys
            .where((j) => !j.completed && !j.startTime.isAfter(DateTime.now()))
            .firstOrNull ??
        _journeys.where((j) => !j.completed).firstOrNull;
  }

  int get totalJourneys => _journeys.length;
  int get completedJourneys => _journeys.where((j) => j.completed).length;
  int get totalPackedItems => _journeys.expand((j) => j.items).length;

  List<Journey> getJourneysForMonth(DateTime month) {
    return _journeys
        .where(
          (journey) =>
              journey.startTime.year == month.year &&
              journey.startTime.month == month.month,
        )
        .toList();
  }

  Map<String, dynamic> getMonthlySummary(DateTime month) {
    final journeys = getJourneysForMonth(month);
    final totalMinutes = journeys.fold<int>(
      0,
      (sum, journey) => sum + journey.durationMinutes,
    );
    final completed = journeys.where((journey) => journey.completed).length;
    final longest = journeys.isEmpty
        ? 0
        : journeys
              .map((journey) => journey.durationMinutes)
              .reduce((a, b) => a > b ? a : b);

    return {
      'totalTrips': journeys.length,
      'completedTrips': completed,
      'averageMinutes': journeys.isEmpty ? 0 : totalMinutes / journeys.length,
      'longestMinutes': longest,
    };
  }

  String buildShareSummaryText({DateTime? month}) {
    final targetMonth = month ?? DateTime.now();
    final summary = getMonthlySummary(targetMonth);
    final lines = <String>[
      'Journey summary for ${DateTime(targetMonth.year, targetMonth.month).toString().substring(0, 7)}',
      'Trips: ${summary['totalTrips']}',
      'Completed: ${summary['completedTrips']}',
      'Average trip time: ${summary['averageMinutes'].round()} min',
      'Longest trip: ${summary['longestMinutes']} min',
      '---',
      ..._journeys
          .take(5)
          .map(
            (journey) =>
                '${journey.origin} → ${journey.destination} (${journey.completed ? 'Completed' : 'Active'})',
          ),
    ];
    return lines.join('\n');
  }

  double get averageJourneyMinutes {
    final completed = _journeys.where((j) => j.completed).toList();
    if (completed.isEmpty) return 0;
    final total = completed.fold<int>(
      0,
      (sum, item) => sum + item.durationMinutes,
    );
    return total / completed.length;
  }

  List<String> get smartReminders {
    final active = _activeJourney;
    if (active == null) return const [];

    final elapsedMinutes = DateTime.now()
        .difference(active.startTime)
        .inMinutes;
    final essentials = active.items.isEmpty
        ? 'documents, charger, wallet'
        : active.items.take(3).join(', ');

    if (elapsedMinutes < 15) {
      return [
        'Quick check: confirm your essentials before you leave.',
        'Don’t forget: $essentials.',
      ];
    }
    if (elapsedMinutes < 60) {
      return [
        'Your trip is active. Recheck route, weather, and travel documents.',
        'If you are planning a stop, check your packing list before leaving.',
      ];
    }
    return [
      'Trip is in motion — keep essentials visible and route notes handy.',
      'Use your saved place geofence to trigger the right reminder at your destination.',
    ];
  }

  Future<void> initialize() async {
    await loadJourneys();
    startReminderMonitoring();
  }

  void startReminderMonitoring() {
    _reminderTimer?.cancel();
    _reminderTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final active = _activeJourney;
      if (active == null) return;

      final shouldNotify =
          _lastReminderAt == null ||
          DateTime.now().difference(_lastReminderAt!).inMinutes >= 15;
      if (shouldNotify) {
        final elapsedMinutes = DateTime.now()
            .difference(active.startTime)
            .inMinutes;
        final reminder = elapsedMinutes < 30
            ? 'Your trip is active — double-check essentials before leaving.'
            : 'You are on the road. Keep your journey plan and destination notes close.';
        NotificationService.showTripReminder(
          title: 'Journey update',
          body: reminder,
        );
        _lastReminderAt = DateTime.now();
      }

      notifyListeners();
    });
  }

  Future<void> loadJourneys() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _journeys = await _storage.getAllJourneys();
      _refreshActiveJourney();
    } catch (e) {
      _error = 'Failed to load journeys: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addJourney(Journey journey) async {
    try {
      await _storage.addJourney(journey);
      _journeys.add(journey);
      _journeys.sort((a, b) => b.startTime.compareTo(a.startTime));
      _refreshActiveJourney();
      notifyListeners();
    } catch (e) {
      _error = 'Failed to add journey: $e';
      notifyListeners();
    }
  }

  Future<void> updateJourney(Journey journey) async {
    try {
      await _storage.updateJourney(journey);
      final index = _journeys.indexWhere((item) => item.id == journey.id);
      if (index != -1) {
        _journeys[index] = journey;
      } else {
        _journeys.add(journey);
      }
      _refreshActiveJourney();
      notifyListeners();
    } catch (e) {
      _error = 'Failed to update journey: $e';
      notifyListeners();
    }
  }

  Future<void> deleteJourney(String id) async {
    try {
      await _storage.deleteJourney(id);
      _journeys.removeWhere((j) => j.id == id);
      if (_activeJourney?.id == id) {
        _activeJourney = null;
      }
      notifyListeners();
    } catch (e) {
      _error = 'Failed to delete journey: $e';
      notifyListeners();
    }
  }

  Future<void> startJourney({
    required String destination,
    required String origin,
    String notes = '',
    List<String>? items,
    DateTime? plannedStart,
  }) async {
    final journey = Journey(
      destination: destination,
      origin: origin,
      notes: notes,
      items: items ?? const [],
      startTime: plannedStart ?? DateTime.now(),
      completed: false,
    );
    await addJourney(journey);
  }

  Future<void> completeJourney(String id) async {
    final journey = _journeys.firstWhere(
      (item) => item.id == id,
      orElse: () => _activeJourney ?? Journey(destination: '', origin: ''),
    );
    if (journey.destination.isEmpty && journey.origin.isEmpty) return;

    if (journey == _activeJourney) {
      _activeJourney = null;
    }

    final completed = journey.copyWith(
      endTime: DateTime.now(),
      completed: true,
    );
    await updateJourney(completed);
  }

  @override
  void dispose() {
    _reminderTimer?.cancel();
    super.dispose();
  }
}
