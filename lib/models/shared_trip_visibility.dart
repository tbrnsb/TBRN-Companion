import 'transaction.dart';

/// THE SHARED-TRIP RULE.
///
/// A trip expense records which participant fronted it (`paidByParticipantId`)
/// and which trip it belongs to (`journeyId`). Demo data writes those as real
/// `Expense` rows, and nothing used to look at either field, so Sita's groceries
/// and Raj's boat ride landed on the Transactions tab and were counted in the
/// month total, in every chart, in every budget, and in search.
///
/// The rule, in full:
///
///     journeyId set AND paidByParticipantId == me
///         -> COUNTS in my ledger, charts, budgets, heatmap, month total,
///            search. I paid it. It is my spending.
///     journeyId set AND paidByParticipantId != me
///         -> COUNTS NOWHERE app-wide. Belongs to the trip only.
///
/// **"Me" is a fact about the trip, not about the expense.** Which participant
/// is the user is stored on the journey (`localParticipantId`), and it is
/// different on every trip — the same id that means "me" on a trip to Pokhara
/// means "Raj" on one to Delhi. So the predicate has to be GIVEN that mapping.
/// The first version of this file assumed any non-null payer was somebody else,
/// which silently dropped the user's own trip spending from the month total while
/// looking exactly correct; that is why the resolver is a required argument
/// rather than a default of "nobody".
///
/// The full four-case table, which is what the tests assert:
///
/// | journeyId | paidBy        | counts?                       |
/// |-----------|---------------|-------------------------------|
/// | null      | null          | yes — an ordinary expense     |
/// | null      | anything      | yes — a payer on no trip       |
/// | set       | null          | yes — pre-field history        |
/// | set       | == me         | yes — I paid it                |
/// | set       | != me         | NO  — somebody else's          |
///
/// The `journeyId set / paidBy null` row is the subtle one. Every expense
/// written before `paidByParticipantId` existed has no payer, and those are real
/// historical spending. Treating "unknown payer" as "not mine" would erase it.
///
/// Settlement must NEVER write a Transaction — a reimbursement is not income
/// (see `journey_provider.dart`), so nothing here has to reason about one.
bool isMyLedgerEntry(
  Transaction transaction, {
  required String? Function(String journeyId) localParticipantIdFor,
}) {
  final journeyId = transaction.journeyId;
  if (journeyId == null) return true;

  final paidBy = transaction.paidByParticipantId;
  if (paidBy == null) return true;

  return paidBy == localParticipantIdFor(journeyId);
}

/// [items] with everybody else's trip spending removed.
///
/// One definition, so a new screen is correct by default rather than by
/// remembering. [localParticipantIdFor] resolves which participant is the user
/// on a given trip; see [isMyLedgerEntry] for why it cannot be defaulted.
List<T> myLedgerOf<T extends Transaction>(
  Iterable<T> items, {
  required String? Function(String journeyId) localParticipantIdFor,
}) {
  return items
      .where(
        (t) => isMyLedgerEntry(t, localParticipantIdFor: localParticipantIdFor),
      )
      .toList(growable: false);
}
