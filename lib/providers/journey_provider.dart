import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/services/notification_service.dart';
import 'package:flutter_application_1/services/storage_service.dart';
import 'package:flutter_application_1/services/trip_importer.dart';
import 'package:flutter_application_1/services/trip_snapshot.dart';
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

  /// Journeys whose start date falls on [day].
  List<Journey> journeysStartingOn(DateTime day) {
    return _journeys.where((j) => _isSameDay(j.startTime, day)).toList();
  }

  /// Journeys that finished on [day].
  ///
  /// An open-ended journey has no end date, so it is not "finishing" on any
  /// particular day and is excluded.
  List<Journey> journeysEndingOn(DateTime day) {
    return _journeys
        .where((j) => j.endTime != null && _isSameDay(j.endTime!, day))
        .toList();
  }

  /// Whether anything at all is recorded on [day].
  bool hasActivityOn(DateTime day) {
    return journeysStartingOn(day).isNotEmpty ||
        journeysEndingOn(day).isNotEmpty;
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

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

  // ===== SHARED TRIP COSTS =====
  //
  // Everything below is about one question — who owes whom — and nothing here
  // creates a transaction. Ticking a settled payment deliberately writes NO
  // income record: a reimbursement is money coming back to you for money you
  // already spent, and counting it as income would inflate income, corrupt the
  // balance, double it in the charts and push every budget off. The expense
  // still counts FULLY against the user's own spending; what the split tracks is
  // a receivable, not a second expense.

  /// Adds someone to the trip's roster, by name.
  ///
  /// Returns the new participant, or null when the name was blank or already on
  /// the list. Two people with the same name are a real thing — a trip with two
  /// Rajs needs distinguishing — so the check is on the exact string the user
  /// typed and they are told rather than blocked.
  Future<TripParticipant?> addParticipant(String journeyId, String name) async {
    final journey = getJourneyById(journeyId);
    final trimmed = name.trim();
    if (journey == null || trimmed.isEmpty) return null;

    final participant = TripParticipant.create(name: trimmed);
    await _saveSharedTripFields(
      journey,
      participants: [...journey.participants, participant],
    );
    return participant;
  }

  Future<void> removeParticipant(String journeyId, String participantId) async {
    final journey = getJourneyById(journeyId);
    if (journey == null) return;

    final participants = journey.participants
        .where((p) => p.id != participantId)
        .toList();

    await _saveSharedTripFields(
      journey,
      participants: participants,
      // Removing the person who was "me" has to clear it too, or the app would
      // go on reporting a balance for someone no longer on the trip.
      localParticipantId: journey.localParticipantId == participantId
          ? null
          : journey.localParticipantId,
      clearLocalParticipant: journey.localParticipantId == participantId,
      // A tombstone, so a re-shared file that still lists them does not put
      // them straight back. Their expenses stay — the money was really spent on
      // this trip — they just stop being attributable to a person, which the
      // settlement reports as unassigned rather than dropping from the total.
      removedIds: [
        ...journey.removedIds,
        if (!journey.removedIds.contains(participantId)) participantId,
      ],
      settledTransfers: journey.settledTransfers
          // Any tick naming the removed person is meaningless now.
          .where((key) => !key.startsWith('$participantId>'))
          .toList(),
    );
  }

  /// Records which participant on this trip is the user.
  ///
  /// This is the step that makes an imported trip answer "what do I owe?",
  /// which is the only number the person importing actually wants. It is asked
  /// during import and changeable afterwards.
  Future<void> setLocalParticipant(
    String journeyId,
    String? participantId,
  ) async {
    final journey = getJourneyById(journeyId);
    if (journey == null) return;
    await _saveSharedTripFields(
      journey,
      localParticipantId: participantId,
      clearLocalParticipant: participantId == null,
    );
  }

  /// Gives the trip a short code friends can read aloud.
  ///
  /// Generated only when the trip has none. Re-importing a file must not change
  /// the code: the code is what two people compare, and a code that silently
  /// changed would make them look like they are on different trips.
  Future<String> ensureTripCode(String journeyId) async {
    final journey = getJourneyById(journeyId);
    if (journey == null) return '';
    final existing = journey.tripCode;
    if (existing != null && existing.isNotEmpty) return existing;

    final code = generateTripCode();
    await _saveSharedTripFields(journey, tripCode: code);
    return code;
  }

  /// What each participant on [journeyId] paid, from the trip's own expenses.
  ///
  /// The roster is the journey's participant list, so someone who has paid
  /// nothing still appears with a zero — which matters, because they still owe
  /// their share. An expense with no payer (saved before "Paid by" existed, or
  /// whose payer is not on the roster) is NOT counted into anyone's total: it
  /// stays in the trip's headline spend, and the summary says so rather than
  /// quietly splitting it between people who never paid it.
  Future<List<ParticipantTotal>> participantTotalsFor(String journeyId) async {
    final journey = getJourneyById(journeyId);
    if (journey == null) return const [];

    final expenses = await _storage.getTransactionsByJourney(journeyId);
    final paidById = <String, int>{};
    final rosterIds = journey.participants.map((p) => p.id).toSet();

    for (final transaction in expenses) {
      if (transaction is! Expense) continue;
      final payer = transaction.paidByParticipantId;
      if (payer == null || !rosterIds.contains(payer)) continue;
      paidById[payer] = (paidById[payer] ?? 0) + paise(transaction.amount);
    }

    return [
      for (final participant in journey.participants)
        ParticipantTotal(
          id: participant.id,
          name: participant.name,
          amountPaidInPaise: paidById[participant.id] ?? 0,
        ),
    ];
  }

  /// Trip money that belongs to no named participant, in paise.
  ///
  /// An expense on this trip with no payer — saved before "Paid by" existed, or
  /// whose payer is not on the roster — still counts as spent. It is reported
  /// separately rather than folded into somebody's total, because dividing it
  /// between people who never paid it would quietly make the settlement wrong
  /// in the direction that suits them.
  Future<int> unattributedInPaiseFor(String journeyId) async {
    final journey = getJourneyById(journeyId);
    if (journey == null) return 0;

    final rosterIds = journey.participants.map((p) => p.id).toSet();
    var total = 0;
    for (final transaction in await _storage.getTransactionsByJourney(
      journeyId,
    )) {
      if (transaction is! Expense) continue;
      final payer = transaction.paidByParticipantId;
      if (payer != null && rosterIds.contains(payer)) continue;
      total += paise(transaction.amount);
    }
    return total;
  }

  /// The full settlement for a shared trip, read from storage.
  ///
  /// One function because the balances and the transfers have to be the same
  /// answer; a screen that showed one and settled with the other would be
  /// confidently wrong.
  Future<TripSettlement> tripSettlement(String journeyId) async {
    return settlementFor(
      await participantTotalsFor(journeyId),
      unattributedInPaise: await unattributedInPaiseFor(journeyId),
    );
  }

  /// Marks one transfer paid, or unmarks it.
  ///
  /// Records a KEY, not a row. The settlement is recomputed from the expenses
  /// every time it is shown, so a stored row would drift out of step the moment
  /// anyone added an expense. `fromId>toId:amountInPaise` is deterministic, so
  /// the same transfer keeps its tick across recomputes, and a file imported
  /// from another phone carries the same keys.
  ///
  /// NO TRANSACTION IS WRITTEN HERE, and that is deliberate rather than an
  /// oversight. See the note at the head of this section: a reimbursement is not
  /// income, and recording one would inflate income, the balance, the charts and
  /// every budget, while the original expense still counted in full.
  Future<void> toggleTransferSettled(
    String journeyId,
    String transferKey,
  ) async {
    final journey = getJourneyById(journeyId);
    if (journey == null) return;

    final ticks = [...journey.settledTransfers];
    final index = ticks.indexOf(transferKey);
    if (index == -1) {
      ticks.add(transferKey);
    } else {
      ticks.removeAt(index);
    }
    await _saveSharedTripFields(journey, settledTransfers: ticks);
  }

  /// "We're even" — clears every outstanding tick in one action.
  ///
  /// People say this and move on. Without it the app nags about an outstanding
  /// balance after the group has already settled over a table, which is worse
  /// than saying nothing at all. It records the keys rather than hiding them, so
  /// what happened is still in the data.
  Future<void> markWholeTripSettled(String journeyId) async {
    final journey = getJourneyById(journeyId);
    if (journey == null) return;

    final settlement = await tripSettlement(journeyId);
    if (settlement.transfers.isEmpty) return;

    final keys = {
      ...journey.settledTransfers,
      for (final transfer in settlement.transfers) transfer.key,
    }.toList();
    await _saveSharedTripFields(journey, settledTransfers: keys);
  }

  /// Undoes "we're even".
  Future<void> clearSettledTransfers(String journeyId) async {
    final journey = getJourneyById(journeyId);
    if (journey == null) return;
    await _saveSharedTripFields(journey, settledTransfers: const []);
  }

  bool isTransferSettled(Journey journey, String transferKey) {
    return journey.settledTransfers.contains(transferKey);
  }

  /// Every shared trip with money still outstanding, across all journeys.
  ///
  /// Drives the "On `trip`" card on Transactions. Uses each trip's own stored
  /// ticks rather than assuming nothing is settled, so a trip the user has
  /// already closed stops appearing.
  Future<List<TripOutstanding>> outstandingAcrossTrips() async {
    final outstanding = <TripOutstanding>[];
    for (final journey in _journeys) {
      if (!journey.isShared) continue;
      final settlement = await tripSettlement(journey.id);
      final remaining = settlement.transfers
          .where((t) => !journey.settledTransfers.contains(t.key))
          .toList();
      if (remaining.isEmpty) continue;

      final localId = journey.localParticipantId;
      final localNet = settlement.balanceFor(localId)?.netInPaise ?? 0;
      outstanding.add(
        TripOutstanding(
          journey: journey,
          settlement: settlement,
          remainingTransfers: remaining,
          localNetInPaise: localNet,
        ),
      );
    }
    return outstanding;
  }

  /// Builds the file to hand to a friend.
  Future<TripSnapshot> buildSnapshot(String journeyId) async {
    final journey = getJourneyById(journeyId);
    if (journey == null) {
      return TripSnapshot(
        journey: Journey(destination: '', origin: ''),
        expenses: const [],
        exportedBy: 'Someone',
      );
    }
    final localName = journey.localParticipant?.name;
    return TripSnapshot.fromJourney(
      journey: journey,
      expenses: await _storage.getTransactionsByJourney(journeyId),
      exportedBy: localName ?? 'Someone',
    );
  }

  /// Applies a snapshot from another phone.
  Future<TripImportResult> importSnapshot(TripSnapshot snapshot) async {
    final result = await const TripImporter().apply(
      snapshot: snapshot,
      // Merge into this phone's copy of the same trip when there is one. The
      // trip's own id is what links the two: two phones that exported the same
      // trip carry the same id, which is how a re-import lands in the trip it
      // came from instead of creating a second copy of it.
      existing: getJourneyById(snapshot.journey.id),
    );
    await loadJourneys();
    return result;
  }

  /// Persists only the shared-trip fields, leaving everything else alone.
  ///
  /// One place, because each of these is an optional key on a record that also
  /// carries a packing list and a date range, and a caller assembling that
  /// journey itself is how an unrelated field gets clobbered.
  Future<void> _saveSharedTripFields(
    Journey journey, {
    List<TripParticipant>? participants,
    String? localParticipantId,
    bool clearLocalParticipant = false,
    List<String>? settledTransfers,
    String? tripCode,
    List<String>? removedIds,
  }) async {
    await updateJourney(
      journey.copyWith(
        participants: participants,
        localParticipantId: localParticipantId,
        clearLocalParticipant: clearLocalParticipant,
        settledTransfers: settledTransfers,
        tripCode: tripCode,
        removedIds: removedIds,
      ),
    );
  }

  /// Notes on [journey] that [transactionId] was deleted here.
  ///
  /// Called by `TransactionProvider` when an expense on a shared trip is
  /// deleted. Without the tombstone, the next file a friend shares would put the
  /// expense back and the user would have no way to stop it — the app would be
  /// undoing a deletion on purpose, forever.
  ///
  /// Best-effort by design: a failed note is worth a swallowed error, because
  /// the deletion itself has already happened and reporting a failure here would
  /// suggest otherwise.
  Future<void> noteRemovedOnSharedTrip(
    String? journeyId,
    String transactionId,
  ) async {
    if (journeyId == null) return;
    final journey = getJourneyById(journeyId);
    if (journey == null || !journey.isShared) return;
    if (journey.removedIds.contains(transactionId)) return;

    try {
      await updateJourney(
        journey.copyWith(removedIds: [...journey.removedIds, transactionId]),
      );
    } catch (_) {
      // See above.
    }
  }

  @override
  void dispose() {
    _reminderTimer?.cancel();
    super.dispose();
  }
}

/// A shared trip that still owes somebody money, for the Transactions card.
///
/// `remainingTransfers` holds the transfers that still need paying.
class TripOutstanding {
  const TripOutstanding({
    required this.journey,
    required this.settlement,
    required this.remainingTransfers,
    required this.localNetInPaise,
  });

  final Journey journey;
  final TripSettlement settlement;

  /// Transfers not yet ticked. The full list stays on [settlement] for the
  /// screen that shows every row; this is what is actually outstanding.
  final List<Transfer> remainingTransfers;

  /// The local user's position, in paise. Positive means they are owed it.
  final int localNetInPaise;

  double get localNet => localNetInPaise / 100;

  int get remainingCount => remainingTransfers.length;

  /// Only meaningful when [localNetInPaise] is non-zero — before the user says
  /// which participant they are, "you are owed" has no answer.
  bool get localIsOwed => localNetInPaise > 0;
  bool get localOwes => localNetInPaise < 0;
}
