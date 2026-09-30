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
/// Two deliberate details:
///
/// - A trip expense **I** paid DOES count toward an app-level category budget.
///   It left my account; it is my spending, and pretending otherwise would make
///   the budget disagree with the month total sitting directly above it. Only
///   OTHER people's trip expenses are excluded, and the journey-level budget is
///   a separate pool over the whole trip regardless of who paid.
/// - A trip expense with NO recorded payer is an ordinary expense, not a
///   stranger's. Every expense written before `paidByParticipantId` existed has
///   no payer, and treating those as somebody else's would erase real
///   historical spending from the ledger.
///
/// Settlement must NEVER write a Transaction — a reimbursement is not income
/// (see `journey_provider.dart`), so nothing here has to reason about one.
bool isMyLedgerEntry(Transaction transaction) {
  if (transaction.journeyId == null) return true;
  return transaction.paidByParticipantId == null;
}

/// [items] with everybody else's trip spending removed.
///
/// One definition, so a new screen is correct by default rather than by
/// remembering.
List<T> myLedgerOf<T extends Transaction>(Iterable<T> items) {
  return items.where(isMyLedgerEntry).toList(growable: false);
}
