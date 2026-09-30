import 'dart:convert';

import 'package:flutter_application_1/models/index.dart';

/// The shape of an exported trip snapshot.
///
/// One file, one JSON object, no schema version and no migration: the whole
/// point of the file is that it is a thing a person can also read, open in a
/// text editor, and send over whatever chat they already use. A snapshot carries
/// the journey, its participants with their names, and the expenses attached to
/// it with who paid.
class TripSnapshot {
  const TripSnapshot({
    required this.journey,
    required this.expenses,
    required this.exportedBy,
  });

  /// The trip, including its participants and its settled-transfer keys.
  final Journey journey;

  /// The expenses on this trip, each with its `paidByParticipantId`.
  ///
  /// Only expenses already pointing at this trip are exported. Copying the
  /// condition rather than filtering inside [fromJourney] keeps the caller in
  /// charge of which rows leave the phone.
  final List<Expense> expenses;

  /// The display name of whoever exported it, shown in the import preview so a
  /// file is attributable before it is applied.
  ///
  /// A NAME and nothing else — no identifier, no account, nothing that could
  /// follow the file around. This app has one user and no accounts.
  final String exportedBy;

  Map<String, dynamic> toJson() {
    return {
      // Named so a file opened in any text editor says what it is.
      'kind': 'tbrn-trip-snapshot',
      'exportedBy': exportedBy,
      'exportedAt': DateTime.now().toIso8601String(),
      'journey': journey.toJson(),
      // Participant NAMES are denormalised into the journey record already —
      // the journey's own `participants` list carries them — so an imported file
      // is readable without resolving ids against anything on this phone.
      'expenses': [for (final expense in expenses) expense.toJson()],
    };
  }

  String encode({bool pretty = true}) {
    final encoder = pretty
        ? const JsonEncoder.withIndent('  ')
        : const JsonEncoder();
    return encoder.convert(toJson());
  }

  /// Builds a snapshot from a journey and the expenses attached to it.
  static TripSnapshot fromJourney({
    required Journey journey,
    required List<Transaction> expenses,
    required String exportedBy,
  }) {
    return TripSnapshot(
      journey: journey,
      expenses: [
        for (final transaction in expenses)
          if (transaction is Expense && transaction.journeyId == journey.id)
            transaction,
      ],
      exportedBy: exportedBy,
    );
  }

  /// Parses a snapshot, defensively.
  ///
  /// Returns null for anything that is not a snapshot this build can read: not
  /// JSON, not an object, no journey, or a `kind` from a different app. Throwing
  /// is not an option — the file came from someone else's phone, and a parse
  /// error the user cannot see the cause of is a dead end. The import flow shows
  /// the message from [TripSnapshotParseResult] instead.
  static TripSnapshotParseResult decode(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return const TripSnapshotParseResult.invalid(
        'That file is not readable JSON.',
      );
    }

    if (decoded is! Map) {
      return const TripSnapshotParseResult.invalid(
        'That file does not contain a trip.',
      );
    }

    final map = Map<String, dynamic>.from(decoded);

    // A `kind` we do not recognise is not "load it anyway". A CSV export, or a
    // snapshot from a future build with a different meaning for the same keys,
    // would otherwise be applied as if it were a trip.
    if (map['kind'] != 'tbrn-trip-snapshot') {
      return const TripSnapshotParseResult.invalid(
        'That file is not a TBRN trip.',
      );
    }

    final rawJourney = map['journey'];
    if (rawJourney is! Map) {
      return const TripSnapshotParseResult.invalid(
        'That file has no trip in it.',
      );
    }

    final journey = Journey.fromJson(Map<String, dynamic>.from(rawJourney));

    // Expenses are read one at a time and a row that will not parse is skipped
    // rather than failing the whole file. Half a trip beats none of it, and the
    // preview tells the user the count that did come through.
    final expenses = <Expense>[];
    final rawExpenses = map['expenses'];
    if (rawExpenses is List) {
      for (final entry in rawExpenses) {
        if (entry is! Map) continue;
        final decodedExpense = _tryExpense(Map<String, dynamic>.from(entry));
        if (decodedExpense != null) expenses.add(decodedExpense);
      }
    }

    return TripSnapshotParseResult.valid(
      TripSnapshot(
        journey: journey,
        expenses: expenses,
        exportedBy: map['exportedBy']?.toString() ?? 'Someone',
      ),
    );
  }

  /// Everything in the trip, in paise.
  int get totalInPaise {
    return expenses.fold<int>(0, (sum, e) => sum + paise(e.amount));
  }

  double get total => totalInPaise / 100;

  /// What each participant paid, ready for `settle`.
  ///
  /// The trip's own participant list is the roster, so a person who has been
  /// added but has not paid anything appears with a zero rather than vanishing.
  /// That matters: someone who fronted nothing still owes their share.
  List<ParticipantTotal> participantTotals() {
    final paidById = <String, int>{};
    for (final expense in expenses) {
      final payer = expense.paidByParticipantId;
      if (payer == null || payer.isEmpty) continue;
      paidById[payer] = (paidById[payer] ?? 0) + paise(expense.amount);
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
}

/// Reads one expense, returning null instead of throwing.
Expense? _tryExpense(Map<String, dynamic> json) {
  try {
    final transaction = Transaction.fromJson(json);
    // An income record is not part of a trip's costs. Filing one into the
    // expenses list would put money the trip did not spend into the settlement.
    return transaction is Expense ? transaction : null;
  } catch (_) {
    return null;
  }
}

/// The outcome of reading a snapshot file.
class TripSnapshotParseResult {
  const TripSnapshotParseResult.valid(this.snapshot)
    : message = null,
      isValid = true;

  const TripSnapshotParseResult.invalid(this.message)
    : snapshot = null,
      isValid = false;

  final TripSnapshot? snapshot;
  final String? message;
  final bool isValid;
}
