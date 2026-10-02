import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/services/storage_service.dart';
import 'package:daily_companion/services/trip_snapshot.dart';

/// What a merge actually did, so the caller can tell the truth about it.
///
/// Counts what was added and what was already here, and never claims anything
/// changed: the merge rules below make it impossible for an import to modify
/// or remove an existing record.
class TripImportResult {
  const TripImportResult({
    required this.journeyId,
    required this.participantsAdded,
    required this.expensesAdded,
    required this.ticksAdded,
    required this.skippedAsExisting,
  });

  final String journeyId;
  final int participantsAdded;
  final int expensesAdded;
  final int ticksAdded;

  /// Records the file contained that were already on this phone. Not an error —
  /// re-importing is the intended workflow — but worth saying out loud, so a
  /// second import that adds nothing reads as "already here" rather than as a
  /// failure.
  final int skippedAsExisting;

  bool get addedAnything =>
      participantsAdded > 0 || expensesAdded > 0 || ticksAdded > 0;

  /// The one-line summary the import flow shows.
  String describe() {
    final parts = <String>[];
    if (participantsAdded > 0) {
      parts.add(
        '$participantsAdded ${participantsAdded == 1 ? 'person' : 'people'}',
      );
    }
    if (expensesAdded > 0) {
      parts.add(
        '$expensesAdded ${expensesAdded == 1 ? 'expense' : 'expenses'}',
      );
    }
    if (ticksAdded > 0) {
      parts.add(
        '$ticksAdded settled ${ticksAdded == 1 ? 'payment' : 'payments'}',
      );
    }

    if (parts.isEmpty) {
      final noun = skippedAsExisting == 1 ? 'record' : 'records';
      final already = '$skippedAsExisting $noun';
      return skippedAsExisting > 0
          ? 'Already on this phone — $already, nothing to add.'
          : 'Nothing in that file to add.';
    }
    final suffix = skippedAsExisting > 0
        ? ' $skippedAsExisting already here.'
        : '';
    return 'Added ${parts.join(', ')}.$suffix';
  }
}

/// Applying another person's trip file to this phone.
///
/// THREE RULES, and they are not negotiable. This function reads someone else's
/// financial record and writes it into the user's own data.
///
///  1. MERGE BY ID ONLY. A participant or expense is recognised by its `id` and
///     nothing else — not by name, not by amount, not by date. Matching on a
///     name would silently merge two different people both called Raj, and would
///     then hand one of them the other's spending.
///
///  2. ADD ONLY. An import NEVER deletes and NEVER overwrites. If an older
///     snapshot arrives after the user deleted an expense, that expense stays
///     deleted: quietly resurrecting something the user removed on purpose is
///     worse than any duplicate, because it looks like the app ignored them.
///     The price is that a file cannot undo a local edit — which is the correct
///     trade, since it also means no file can destroy data it did not create.
///
///  3. IDEMPOTENT. Importing the same file twice changes nothing the second
///     time, and changes nothing ever again however many times it is repeated.
///     This is what makes the re-share ping-pong — A exports, B imports, B adds,
///     B exports, A imports — safe to keep doing.
class TripImporter {
  const TripImporter();

  /// Applies [snapshot] to storage.
  ///
  /// [existing] is the trip already on this phone, or null when this is a new
  /// trip. Passed in rather than looked up so the caller chooses the merge
  /// target, and so this is testable without a provider.
  Future<TripImportResult> apply({
    required TripSnapshot snapshot,
    required Journey? existing,
  }) async {
    final storage = StorageService();
    final incoming = snapshot.journey;

    // The trip itself is created once and then left alone. An import never
    // renames a trip or moves its dates: the user's own copy of the trip is
    // theirs, and the file's copy is a record of what someone else had.
    final targetJourney = existing ?? incoming;

    final participants = existing == null
        ? incoming.participants
        : _mergeParticipants(
            existing.participants,
            incoming.participants,
            existing,
          );

    final participantsAdded = existing == null
        ? participants.length
        : participants
              .where((p) => !existing.participants.any((k) => k.id == p.id))
              .length;

    // Settled transfers are unioned. Keys, not rows: the settlement is recomputed
    // from the expenses every time it is shown, so a tick is only recognisable
    // across devices if both compute the same key for the same transfer.
    final existingTicks = existing?.settledTransfers ?? const <String>[];
    final ticks = <String>{
      ...existingTicks,
      ...incoming.settledTransfers,
    }.toList();

    // Who-am-I is deliberately NOT merged. It is the one field that describes
    // this phone rather than the trip: if Raj's file records Raj as "me", Sita
    // importing it must not end up as Raj. The import flow asks instead.
    final merged = targetJourney.copyWith(
      participants: participants,
      settledTransfers: ticks,
      localParticipantId: existing?.localParticipantId,
      clearLocalParticipant: existing?.localParticipantId == null,
      tripCode: existing?.tripCode ?? incoming.tripCode,
    );

    if (existing == null) {
      await storage.addJourney(merged);
    } else {
      await storage.updateJourney(merged);
    }

    // One read of the box, not one per expense: this loop runs over a file the
    // user did not write and cannot bound, and re-reading every transaction per
    // row would make a big import quadratic on their own storage.
    final storedIds = {
      for (final transaction in await storage.getAllTransactions())
        transaction.id,
    };

    var expensesAdded = 0;
    var skipped = 0;
    for (final expense in snapshot.expenses) {
      if (!storedIds.add(expense.id)) {
        skipped++;
        continue;
      }
      // The deletion wins. A file is a snapshot of what someone else had, and
      // this phone is the one where somebody deliberately removed a row; an
      // older snapshot must not resurrect it, or the user watches it reappear
      // every time a friend re-shares with nothing they can do about it.
      if (merged.isRemoved(expense.id)) {
        skipped++;
        continue;
      }
      // Re-pointed at the local trip id, so a row from the file can never point
      // at a trip this phone does not have — which would put it in no summary
      // and out of the settlement entirely.
      await storage.addTransaction(
        expense.copyWith(
          journeyId: merged.id,
          paidByParticipantId: _payerId(expense),
        ),
      );
      expensesAdded++;
    }

    return TripImportResult(
      journeyId: merged.id,
      participantsAdded: participantsAdded,
      expensesAdded: expensesAdded,
      ticksAdded: ticks.length - existingTicks.length,
      skippedAsExisting: skipped,
    );
  }

  /// Keeps an unresolvable payer id rather than dropping it.
  ///
  /// An id that resolves to nobody is a real state: the participant may arrive in
  /// a later snapshot from the same trip. Dropping it would file the expense as
  /// "nobody paid", which makes the settlement quietly wrong in a way the user
  /// has no way to see. [Journey.participantName] renders an unknown id as the
  /// id, so it stays visible as an outstanding problem instead.
  String? _payerId(Expense expense) {
    final payer = expense.paidByParticipantId;
    if (payer == null || payer.isEmpty) return null;
    return payer;
  }

  /// Existing first, then anything new, in file order.
  ///
  /// Order is what makes the roster readable: the people this phone already knew
  /// about keep their positions in the list. Anything [existing] has a tombstone
  /// for is skipped, for the same reason a deleted expense is.
  List<TripParticipant> _mergeParticipants(
    List<TripParticipant> existing,
    List<TripParticipant> incoming,
    Journey? existingJourney,
  ) {
    final seen = existing.map((p) => p.id).toSet();
    final merged = [...existing];
    for (final participant in incoming) {
      if (seen.contains(participant.id)) continue;
      if (existingJourney != null &&
          existingJourney.isRemoved(participant.id)) {
        continue;
      }
      seen.add(participant.id);
      merged.add(participant);
    }
    return merged;
  }
}
