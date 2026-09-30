/// Shared-trip settlement — the smallest set of transfers that clears a trip.
///
/// Deliberately free of any `package:flutter` import. This is arithmetic on
/// money, not UI, so it lives in plain Dart where it can be tested without a
/// widget tree, a Hive box or a pump. Everything the screens show about
/// "who owes whom" comes from here.
///
/// THE PROBLEM THIS SOLVES. Not "divide a bill by N" — that is one subtraction.
/// The real situation is that N people each fronted different things at
/// different places, and at the end nobody can compute who owes whom. So the
/// input is what each person *paid*, and the output is the shortest list of
/// payments that leaves everyone square.
///
///     You   taxi 4000 + lunch 1500       = 5500
///     Raj   boat 3000 + dinner 2400      = 5400
///     Sita  groceries 2000 + museum 1000 = 3000
///     total 13900, three people, fair share 4633.33
///     SETTLEMENT: Sita → Raj 767, Sita → You 867. Two transfers clear it.
///
/// WHAT "SMALLEST" MEANS. Greedily matching the largest creditor against the
/// largest debtor, largest-first, produces at most `n - 1` transfers. There are
/// many valid settlements — six transfers can also settle that trip — but a
/// group of friends will not do six, and a list they cannot follow is the same
/// as no list at all.
///
/// DETERMINISM IS A REQUIREMENT, not a nicety. Both sides are sorted
/// *descending*, with the participant id as the tie-break, before matching. The
/// same input therefore always produces identical output, which is what lets a
/// settled transfer be recorded under a stable key: re-running the settlement
/// after a new expense is added must not reshuffle the ticks the user already
/// made, or the UI reorders under their thumb on every rebuild.
library;

/// One person's contribution to a shared trip.
///
/// [amountPaidInPaise] is an integer count of paise (1 rupee = 100 paise), not a
/// double. 13900 split three ways is 4633.33…, and accumulating that in binary
/// floating point is how a settlement screen ends up disagreeing with the amount
/// printed at the top of it by a paisa. All arithmetic below is integer.
class ParticipantTotal {
  const ParticipantTotal({
    required this.id,
    required this.name,
    required this.amountPaidInPaise,
  });

  /// The participant's id. Stable across phones, because it comes from the
  /// trip's own record.
  final String id;

  /// The display name. Denormalised into an exported snapshot on purpose: an
  /// imported file has to be readable without resolving ids against anything.
  final String name;

  /// What this person paid, in paise.
  final int amountPaidInPaise;

  /// Convenience for callers holding a rupee `double`, such as the sum of a
  /// person's expenses. Rounded once, here at the edge, rather than smeared
  /// through the arithmetic as a double.
  factory ParticipantTotal.fromRupees({
    required String id,
    required String name,
    required double amountPaid,
  }) {
    return ParticipantTotal(
      id: id,
      name: name,
      amountPaidInPaise: paise(amountPaid),
    );
  }

  @override
  String toString() => 'ParticipantTotal($id, $name, $amountPaidInPaise paise)';
}

/// A single payment that clears part of the balance.
class Transfer {
  const Transfer({
    required this.fromId,
    required this.fromName,
    required this.toId,
    required this.toName,
    required this.amountInPaise,
  });

  /// Who pays.
  final String fromId;
  final String fromName;

  /// Who receives.
  final String toId;
  final String toName;

  /// How much, in paise. Always a whole number: the result of [settle] has no
  /// fractional paise in it.
  final int amountInPaise;

  /// The stable key a settled transfer is recorded under.
  ///
  /// A key and not a row: the settlement is recomputed from the expenses every
  /// time it is shown, so a tick has to be recognisable in the *next* run of the
  /// same computation. `fromId>toId:amountInPaise` survives that, and two
  /// devices that both imported the same snapshot compute the same key for the
  /// same transfer — which is what stops a re-import duplicating ticks.
  String get key => '$fromId>$toId:$amountInPaise';

  /// The amount in rupees, for display. Exact: [amountInPaise] is a whole
  /// number of paise, so this never shows a spurious decimal.
  double get amount => amountInPaise / 100;

  /// Value equality, so two runs of [settle] over the same input compare equal.
  ///
  /// Not cosmetic: [settle] builds a fresh list every time it is called, so
  /// without this the determinism guarantee could only be tested by comparing
  /// [key]s, and nothing could ever put a [Transfer] in a `Set` or compare it
  /// against a stored one.
  @override
  bool operator ==(Object other) {
    return other is Transfer &&
        other.fromId == fromId &&
        other.toId == toId &&
        other.amountInPaise == amountInPaise;
  }

  @override
  int get hashCode => Object.hash(fromId, toId, amountInPaise);

  @override
  String toString() => 'Transfer($fromName → $toName, $amountInPaise paise)';
}

/// A person's position on a shared trip, in whole paise.
class ParticipantBalance {
  const ParticipantBalance({
    required this.id,
    required this.name,
    required this.amountPaidInPaise,
    required this.shareInPaise,
    required this.netInPaise,
  });

  final String id;
  final String name;
  final int amountPaidInPaise;

  /// Their equal share of the trip, in paise.
  final int shareInPaise;

  /// What they paid minus their share. Positive means they are owed it;
  /// negative means they owe it.
  final int netInPaise;

  bool get isCreditor => netInPaise > 0;
  bool get isDebtor => netInPaise < 0;
  bool get isSquare => netInPaise == 0;

  double get paid => amountPaidInPaise / 100;
  double get share => shareInPaise / 100;
  double get net => netInPaise / 100;
}

/// What a trip looks like before anyone asks who owes whom.
class TripSettlement {
  const TripSettlement({
    required this.balances,
    required this.transfers,
    required this.totalInPaise,
    required this.isShared,
  });

  /// One entry per participant, in the input order.
  final List<ParticipantBalance> balances;

  /// The payments that settle the trip. Empty when nobody owes anything.
  final List<Transfer> transfers;

  /// Everything the trip cost, in paise.
  final int totalInPaise;

  /// False when there is nobody to settle between.
  ///
  /// A trip needs at least two participants before "who owes whom" is a
  /// question; with one participant the answer is trivially zero, and dividing by
  /// the headcount would be a division by one dressed up as a calculation.
  final bool isShared;

  double get total => totalInPaise / 100;

  int get participantCount => balances.length;

  /// True when no money needs to move at all — either nobody owes anything, or
  /// there is nobody to owe between.
  bool get isSettled => !isShared || transfers.isEmpty;

  /// What still needs to move, in paise. Zero once [isSettled].
  int get outstandingInPaise =>
      transfers.fold<int>(0, (sum, t) => sum + t.amountInPaise);

  /// [id]'s balance, or null when they are not on this trip.
  ///
  /// Null rather than a zero balance: a participant id from a file that has not
  /// been applied yet must not read as "you owe nothing", which is the one
  /// answer that would be confidently wrong.
  ParticipantBalance? balanceFor(String? id) {
    if (id == null) return null;
    for (final balance in balances) {
      if (balance.id == id) return balance;
    }
    return null;
  }
}

/// [amount] rupees as whole paise, rounded half away from zero.
int paise(double amount) => (amount * 100).round();

/// [value] in whole paise as rupees. Exact both ways for any whole paise.
double rupees(int value) => value / 100;

/// The whole picture: every balance plus the transfers that clear them.
///
/// Separate from [settle] because the summary screen shows both — "Sita owes
/// Rs 1,633" and "2 payments settle everything" — and computing them in two
/// places is how they come to disagree.
TripSettlement settlementFor(List<ParticipantTotal> totals) {
  return TripSettlement(
    balances: balancesFor(totals),
    transfers: settle(totals),
    totalInPaise: totals.fold<int>(0, (sum, t) => sum + t.amountPaidInPaise),
    isShared: isShared(totals),
  );
}

/// Whether [totals] describes something worth settling between people.
///
/// Exposed because a screen has to ask this before it offers a summary at all,
/// and the answer must not be "totals.length > 0" in three places.
bool isShared(List<ParticipantTotal> totals) => totals.length >= 2;

/// Each participant's paid amount, share and net.
///
/// Shares come from the same allocation [settle] uses, so the numbers a
/// participant sees beside their name cannot drift from the transfers below.
List<ParticipantBalance> balancesFor(List<ParticipantTotal> totals) {
  if (totals.isEmpty) return const [];
  final shares = equalShares(totalInPaise: _totalOf(totals), totals: totals);
  return [
    for (var i = 0; i < totals.length; i++)
      ParticipantBalance(
        id: totals[i].id,
        name: totals[i].name,
        amountPaidInPaise: totals[i].amountPaidInPaise,
        shareInPaise: shares[i],
        netInPaise: totals[i].amountPaidInPaise - shares[i],
      ),
  ];
}

/// The minimum set of transfers that leaves everyone on the trip square.
///
/// The steps, in the order they matter:
///
/// 1. Fewer than two participants is not a settlement. Returns empty rather
///    than dividing by the headcount, so an empty participant list cannot
///    produce a division by zero or a nonsense answer on screen.
/// 2. Every share is a whole number of paise and the shares sum to the total
///    *exactly* — 13900 across three people does not divide, and a screen whose
///    per-person shares do not add up to the headline figure is worse than one
///    with no settlement at all.
/// 3. `net = paid − share`, so creditors and debtors fall out of the same
///    subtraction and the nets sum to zero by construction.
/// 4. Greedy largest-first matching.
///
/// [totals] is not mutated; the returned list is a fresh, ordered one.
List<Transfer> settle(List<ParticipantTotal> totals) {
  if (!isShared(totals)) return const [];

  final n = totals.length;
  final totalInPaise = _totalOf(totals);
  final shares = equalShares(totalInPaise: totalInPaise, totals: totals);

  final nets = <_Balance>[
    for (var i = 0; i < n; i++)
      _Balance(
        id: totals[i].id,
        name: totals[i].name,
        netInPaise: totals[i].amountPaidInPaise - shares[i],
      ),
  ];

  // The whole design rests on this. If it ever failed, the transfers below
  // would not add up to what is owed and the screen would be confidently wrong,
  // so it is asserted rather than assumed.
  assert(
    nets.fold<int>(0, (sum, e) => sum + e.netInPaise) == 0,
    'participant shares must sum to the trip total exactly; '
    '${shares.fold<int>(0, (sum, v) => sum + v)} against $totalInPaise',
  );

  final creditors = nets.where((e) => e.netInPaise > 0).toList()
    ..sort(_byCredit);
  // Debtiest first, which is the *most negative* net. Sorting debtors by net
  // descending — the same direction as the creditors — would pair the smallest
  // debt against the largest credit and can emit an extra transfer, so the two
  // sides are sorted by magnitude in opposite directions.
  final debtors = nets.where((e) => e.netInPaise < 0).toList()..sort(_byDebt);

  final transfers = <Transfer>[];
  var creditor = 0;
  var debtor = 0;

  while (creditor < creditors.length && debtor < debtors.length) {
    final to = creditors[creditor];
    final from = debtors[debtor];

    // Both sides are whole paise, so min() is exact and never leaves a
    // fractional remainder behind for the next pair.
    final amount = to.remaining < -from.remaining
        ? to.remaining
        : -from.remaining;

    transfers.add(
      Transfer(
        fromId: from.id,
        fromName: from.name,
        toId: to.id,
        toName: to.name,
        amountInPaise: amount,
      ),
    );

    to.remaining -= amount;
    from.remaining += amount;

    // Advance a side only once it is square, so a creditor smaller than the
    // current debtor is fully paid off before the next debtor is considered.
    if (to.remaining == 0) creditor++;
    if (from.remaining == 0) debtor++;
  }

  // Every net summed to zero and each step moved the same amount from a debtor
  // to a creditor, so nothing can be left over. Asserted rather than patched:
  // a residual here would mean the arithmetic above is wrong, and quietly
  // pushing it onto somebody would hide that.
  assert(
    transfers.fold<int>(0, (sum, t) => sum + t.amountInPaise) ==
        creditors.fold<int>(0, (sum, c) => sum + c.netInPaise),
    'transfers must total exactly what is owed',
  );

  return transfers;
}

/// Splits [totalInPaise] into `totals.length` integer shares summing to it.
///
/// When it does not divide — 13900 across three people does not, and a trip of
/// friends rarely does — the leftover paise has to land somewhere, and where it
/// lands is a visible number on a screen people are about to argue about. So the
/// shares are made to sum to the total *exactly*, and the residual goes to the
/// **largest creditor**.
///
/// That is the same rule [settle] ends on: if a paiso has to be pushed
/// somewhere, it goes onto the person the group is already paying. It keeps
/// every debtor's share at the floor, so no one is shortchanged by the rounding,
/// and it costs one paisa of rounding on the creditor rather than on someone who
/// has to find the cash.
///
/// Ties break by largest paid, then by id, so the result is deterministic
/// whatever the input order. A trip where nobody is a creditor at all — everyone
/// owes nothing because they paid the same — falls back to the largest payer,
/// which is also safe: the nets stay balanced and no transfer appears.
List<int> equalShares({
  required int totalInPaise,
  required List<ParticipantTotal> totals,
}) {
  final count = totals.length;
  if (count == 0) return const [];

  final base = totalInPaise ~/ count;
  final leftover = totalInPaise - base * count;
  final shares = List<int>.filled(count, base);

  if (leftover == 0) return shares;

  // Which participant absorbs the residual. A creditor by net, falling back to
  // the largest payer when the trip nets out square.
  var target = _largestCreditorIndex(totals, base);
  target ??= _largestPayerIndex(totals);

  for (var i = 0; i < leftover; i++) {
    shares[target]++;
  }

  assert(
    shares.fold<int>(0, (sum, v) => sum + v) == totalInPaise,
    'shares must sum to $totalInPaise exactly',
  );

  return shares;
}

/// Index of whoever is owed the most once everyone has been given [share].
int? _largestCreditorIndex(List<ParticipantTotal> totals, int share) {
  int? best;
  var bestNet = 0;
  for (var i = 0; i < totals.length; i++) {
    final net = totals[i].amountPaidInPaise - share;
    if (net <= 0) continue;
    if (best == null ||
        net > bestNet ||
        (net == bestNet && _prefer(i, best, totals))) {
      best = i;
      bestNet = net;
    }
  }
  return best;
}

int _largestPayerIndex(List<ParticipantTotal> totals) {
  var best = 0;
  for (var i = 1; i < totals.length; i++) {
    if (_prefer(i, best, totals)) best = i;
  }
  return best;
}

/// Largest paid first, then id, so the choice never depends on input order.
bool _prefer(int a, int b, List<ParticipantTotal> totals) {
  final byPaid = totals[b].amountPaidInPaise.compareTo(
    totals[a].amountPaidInPaise,
  );
  if (byPaid != 0) return byPaid < 0;
  return totals[a].id.compareTo(totals[b].id) < 0;
}

int _totalOf(List<ParticipantTotal> totals) {
  return totals.fold<int>(0, (sum, t) => sum + t.amountPaidInPaise);
}

/// Largest creditor first: net descending, id as the tie-break.
int _byCredit(_Balance a, _Balance b) {
  final byNet = b.netInPaise.compareTo(a.netInPaise);
  if (byNet != 0) return byNet;
  return a.id.compareTo(b.id);
}

/// Largest debtor first: net ascending, since a debt is stored as a negative
/// net. Ids break ties.
int _byDebt(_Balance a, _Balance b) {
  final byNet = a.netInPaise.compareTo(b.netInPaise);
  if (byNet != 0) return byNet;
  return a.id.compareTo(b.id);
}

/// A mutable running balance, used only inside [settle]'s matching loop.
class _Balance {
  _Balance({required this.id, required this.name, required this.netInPaise});

  final String id;
  final String name;
  final int netInPaise;

  /// What is still owed to this creditor, or still owed by this debtor.
  late int remaining = netInPaise;
}
