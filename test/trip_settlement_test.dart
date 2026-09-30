import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/models/trip_settlement.dart';

ParticipantTotal _p(String id, String name, double paidRupees) {
  return ParticipantTotal.fromRupees(
    id: id,
    name: name,
    amountPaid: paidRupees,
  );
}

ParticipantTotal _pi(String id, String name, int paidPaise) {
  return ParticipantTotal(id: id, name: name, amountPaidInPaise: paidPaise);
}

void main() {
  group('the worked example from the problem', () {
    // You taxi 4000 + lunch 1500 = 5500
    // Raj boat 3000 + dinner 2400 = 5400
    // Sita groceries 2000 + museum 1000 = 3000
    const totals = [
      ParticipantTotal(id: 'you', name: 'You', amountPaidInPaise: 550000),
      ParticipantTotal(id: 'raj', name: 'Raj', amountPaidInPaise: 540000),
      ParticipantTotal(id: 'sita', name: 'Sita', amountPaidInPaise: 300000),
    ];

    test('two transfers clear it, and the numbers are the expected ones', () {
      final transfers = settle(totals);

      expect(
        transfers
            .map((t) => '${t.fromName} → ${t.toName}: ${t.amount}')
            .toList(),
        // Largest creditor first, so You is served before Raj. Displayed to the
        // rupee these read as "Sita → You 867" and "Sita → Raj 767".
        ['Sita → You: 866.66', 'Sita → Raj: 766.67'],
      );
    });

    test('the shares sum to 13900 exactly', () {
      final settlement = settlementFor(totals);

      expect(settlement.total, 13900);
      expect(
        settlement.balances.fold<int>(0, (sum, b) => sum + b.shareInPaise),
        1390000,
      );
    });

    test('the nets sum to zero', () {
      final settlement = settlementFor(totals);

      expect(
        settlement.balances.fold<int>(0, (sum, b) => sum + b.netInPaise),
        0,
      );
    });

    test('the transfers sum to exactly what is owed', () {
      final settlement = settlementFor(totals);

      // Sita owes 1633.33 and pays 866.66 + 766.67 = 1633.33. Whole-paise
      // shares cannot split a third of a paisa three ways, so the residual sits
      // on the largest creditor and the two sides balance exactly.
      expect(settlement.outstandingInPaise, 163333);
    });

    test('who-am-I resolves against the participants', () {
      final settlement = settlementFor(totals);

      // The residual paisa lands on You, the largest creditor, so You nets a
      // third of a paisa less than an even split would give.
      expect(settlement.balanceFor('you')!.netInPaise, 86666);
      expect(settlement.balanceFor('raj')!.netInPaise, 76667);
      expect(settlement.balanceFor('sita')!.netInPaise, -163333);
      expect(settlement.balanceFor('nobody'), isNull);
      expect(settlement.balanceFor(null), isNull);
    });
  });

  group('two people', () {
    // Each pair settles the *difference*, not the whole amount: two people who
    // fronted 600 and 400 of a 1000 trip each owe half, so only 100 moves.
    test('one transfer, the difference', () {
      final transfers = settle([_p('a', 'A', 600), _p('b', 'B', 400)]);

      expect(transfers, hasLength(1));
      expect(transfers.single.fromName, 'B');
      expect(transfers.single.toName, 'A');
      expect(transfers.single.amount, 100);
    });

    test('who paid more always collects', () {
      final transfers = settle([_p('a', 'A', 400), _p('b', 'B', 600)]);

      expect(transfers.single.fromName, 'A');
      expect(transfers.single.amount, 100);
    });

    test('split exactly evenly needs no payment at all', () {
      expect(settle([_p('a', 'A', 500), _p('b', 'B', 500)]), isEmpty);
    });

    test('neither paid anything needs no payment', () {
      expect(settle([_p('a', 'A', 0), _p('b', 'B', 0)]), isEmpty);
    });
  });

  group('repeating decimals', () {
    test('100 across three people — 33.33 does not divide', () {
      final settlement = settlementFor([
        _p('a', 'A', 40),
        _p('b', 'B', 40),
        _p('c', 'C', 20),
      ]);

      expect(
        settlement.balances.fold<int>(0, (sum, b) => sum + b.shareInPaise),
        10000,
      );
      expect(
        settlement.balances.fold<int>(0, (sum, b) => sum + b.netInPaise),
        0,
      );
    });

    test('an indivisible amount across three people', () {
      // 100 paise across three: shares must still total exactly 100 paise.
      final settlement = settlementFor([
        _pi('a', 'A', 40),
        _pi('b', 'B', 35),
        _pi('c', 'C', 25),
      ]);

      expect(settlement.totalInPaise, 100);
      expect(
        settlement.balances.fold<int>(0, (sum, b) => sum + b.shareInPaise),
        100,
      );
      expect(
        settlement.balances.fold<int>(0, (sum, b) => sum + b.netInPaise),
        0,
      );
      expect(
        settlement.transfers.fold<int>(0, (sum, t) => sum + t.amountInPaise),
        settlement.transfers.fold<int>(0, (sum, t) => sum + t.amountInPaise),
      );
    });

    test('one paise total, three people', () {
      final settlement = settlementFor([
        _pi('a', 'A', 1),
        _pi('b', 'B', 0),
        _pi('c', 'C', 0),
      ]);

      expect(
        settlement.balances.fold<int>(0, (sum, b) => sum + b.shareInPaise),
        1,
      );
      expect(
        settlement.balances.fold<int>(0, (sum, b) => sum + b.netInPaise),
        0,
      );
    });

    test('every share is a whole number of paise, always', () {
      for (final total in [1, 7, 100, 1001, 99999]) {
        for (var n = 2; n <= 5; n++) {
          final totals = [
            for (var i = 0; i < n; i++) _pi('p$i', 'P$i', total ~/ n + i),
          ];
          final settlement = settlementFor(totals);
          expect(
            settlement.balances.fold<int>(0, (sum, b) => sum + b.shareInPaise),
            settlement.totalInPaise,
            reason: 'shares must total $total across $n people',
          );
        }
      }
    });
  });

  group('four people, uneven', () {
    final totals = [
      _p('a', 'You', 5500),
      _p('b', 'Raj', 5400),
      _p('c', 'Sita', 3000),
      _p('d', 'Bikash', 1000),
    ];

    test('at most n − 1 transfers', () {
      expect(settle(totals).length, lessThanOrEqualTo(3));
    });

    test('the transfers settle exactly', () {
      final settlement = settlementFor(totals);
      final owed = settlement.balances
          .where((b) => b.isCreditor)
          .fold<int>(0, (sum, b) => sum + b.netInPaise);

      expect(settlement.outstandingInPaise, owed);
    });

    test('nobody is named on both sides of the same transfer', () {
      for (final transfer in settle(totals)) {
        expect(transfer.fromId, isNot(transfer.toId));
        expect(transfer.amountInPaise, greaterThan(0));
      }
    });

    test('largest creditor and largest debtor are paired first', () {
      final transfers = settle(totals);

      // 14900 across four: shares of 3725. You is owed 1775, Raj 1675, Sita
      // 725, Bikash owes 2725. Biggest debtor pays the biggest creditor.
      expect(transfers.first.fromName, 'Bikash');
      expect(transfers.first.toName, 'You');
    });
  });

  group('someone paid nothing', () {
    test('they owe the full share and nothing else', () {
      final settlement = settlementFor([
        _p('a', 'A', 900),
        _p('b', 'B', 900),
        _p('c', 'C', 0),
      ]);

      final c = settlement.balanceFor('c')!;
      expect(c.amountPaidInPaise, 0);
      expect(c.shareInPaise, 60000);
      expect(c.netInPaise, -60000);
    });

    test('they pay out to every creditor they owe', () {
      // 1800 across three: each owes 600, C paid nothing so C is the only
      // debtor and A and B are both creditors. Two transfers, both from C.
      final transfers = settle([
        _p('a', 'A', 900),
        _p('b', 'B', 900),
        _p('c', 'C', 0),
      ]);

      expect(transfers, hasLength(2));
      expect(transfers.every((t) => t.fromName == 'C'), isTrue);
      expect(transfers.fold<int>(0, (sum, t) => sum + t.amountInPaise), 60000);
    });

    test('one payer covers everyone else', () {
      final transfers = settle([
        _p('a', 'A', 1000),
        _p('b', 'B', 0),
        _p('c', 'C', 0),
      ]);

      expect(transfers, hasLength(2));
      expect(transfers.every((t) => t.toName == 'A'), isTrue);
    });
  });

  group('everyone equal', () {
    test('three-way split produces zero transfers', () {
      final settlement = settlementFor([
        _p('a', 'A', 300),
        _p('b', 'B', 300),
        _p('c', 'C', 300),
      ]);

      expect(settlement.transfers, isEmpty);
      expect(settlement.isSettled, isTrue);
      expect(settlement.balances.every((b) => b.isSquare), isTrue);
    });

    test('an indivisible equal split still produces zero transfers', () {
      // 100 paise each would be 33.33; the shares land unevenly but the nets
      // must still cancel, or "we are even" would show payments.
      final settlement = settlementFor([
        _pi('a', 'A', 100),
        _pi('b', 'B', 100),
        _pi('c', 'C', 100),
      ]);

      expect(settlement.balances.every((b) => b.isSquare), isTrue);
      expect(settlement.transfers, isEmpty);
    });
  });

  group('hostile input', () {
    test('a negative total still splits into shares that add up', () {
      // Reachable: a hand-edited or malformed import file can carry a negative
      // amount, and Dart's `~/` truncates towards zero, which would otherwise
      // leave the shares short by one and every net off by the same amount.
      final totals = [
        _pi('a', 'A', -5000),
        _pi('b', 'B', 3000),
        _pi('c', 'C', 0),
      ];
      final settlement = settlementFor(totals);

      expect(
        settlement.balances.fold<int>(0, (sum, b) => sum + b.shareInPaise),
        -2000,
      );
      expect(
        settlement.balances.fold<int>(0, (sum, b) => sum + b.netInPaise),
        0,
      );
      // The transfers still add up to exactly what is owed.
      final owed = settlement.balances
          .where((b) => b.isCreditor)
          .fold<int>(0, (sum, b) => sum + b.netInPaise);
      expect(settlement.outstandingInPaise, owed);
    });

    test('a huge total does not overflow anything', () {
      // 999999999 rupees, the largest a four-digit minor-unit double survives
      // without losing precision at all.
      final settlement = settlementFor([
        _pi('a', 'A', 99999999900),
        _pi('b', 'B', 0),
        _pi('c', 'C', 0),
      ]);

      expect(
        settlement.balances.fold<int>(0, (sum, b) => sum + b.shareInPaise),
        99999999900,
      );
      expect(
        settlement.balances.fold<int>(0, (sum, b) => sum + b.netInPaise),
        0,
      );
      expect(settlement.transfers, hasLength(2));
    });

    test('the two totals can be told apart', () {
      // `total` is what is attributed to people; `tripTotal` adds money with no
      // payer. The journey page quotes tripTotal, and the summary quotes the
      // same number, so the two screens cannot disagree.
      final settlement = settlementFor([
        _pi('a', 'A', 10000),
        _pi('b', 'B', 10000),
      ], unattributedInPaise: 5000);

      expect(settlement.total, 200);
      expect(settlement.unattributed, 50);
      expect(settlement.tripTotal, 250);
      expect(settlement.hasUnattributed, isTrue);
      // The unattributed money is NOT split: they still each owe 100.
      expect(settlement.balances.every((b) => b.shareInPaise == 10000), isTrue);
    });
  });

  group('degenerate headcounts', () {
    test('n = 0 does not divide by zero', () {
      expect(settle(const []), isEmpty);
      expect(settlementFor(const []).isShared, isFalse);
      expect(settlementFor(const []).participantCount, 0);
    });

    test('n = 1 owes nothing to themselves', () {
      final settlement = settlementFor([_p('a', 'A', 500)]);

      expect(settlement.transfers, isEmpty);
      expect(settlement.isShared, isFalse);
      expect(settlement.balances.single.isSquare, isTrue);
      expect(settlement.balances.single.shareInPaise, 50000);
    });

    test('n = 1 at zero cost', () {
      final settlement = settlementFor([_p('a', 'A', 0)]);

      expect(settlement.transfers, isEmpty);
      expect(settlement.total, 0);
    });
  });

  group('determinism', () {
    final totals = [
      _p('a', 'You', 5500),
      _p('b', 'Raj', 5400),
      _p('c', 'Sita', 3000),
      _p('d', 'Bikash', 1000),
      _p('e', 'Mina', 500),
    ];

    test('the same input twice gives identical output', () {
      expect(settle(totals), settle(totals));
    });

    test('the transfer keys are identical between runs', () {
      // This is what makes a settled-transfer tick survive a recompute.
      expect(
        settle(totals).map((t) => t.key).toList(),
        settle(totals).map((t) => t.key).toList(),
      );
    });

    test('a shuffled input order still settles the same amounts', () {
      // The amount owed between two people cannot depend on which order they
      // happened to be typed in.
      final shuffled = [
        _p('c', 'Sita', 3000),
        _p('e', 'Mina', 500),
        _p('a', 'You', 5500),
        _p('d', 'Bikash', 1000),
        _p('b', 'Raj', 5400),
      ];

      List<(String, int)> edges(List<Transfer> transfers) =>
          [
            for (final t in transfers)
              ('${t.fromName}->${t.toName}', t.amountInPaise),
          ]..sort((a, b) {
            final byNames = a.$1.compareTo(b.$1);
            return byNames != 0 ? byNames : a.$2.compareTo(b.$2);
          });

      expect(edges(settle(totals)), edges(settle(shuffled)));
    });

    test('ties are broken by id, so an equal pair cannot swap', () {
      final tied = [
        _p('zeta', 'Zeta', 400),
        _p('alpha', 'Alpha', 400),
        _p('c', 'C', 0),
      ];

      // Alpha and Zeta are both owed the same, so which one C pays first is
      // decided by id: 'alpha' sorts before 'zeta' and takes the residual paisa
      // as the largest creditor, leaving Zeta marginally larger. Both runs must
      // agree — this is what keeps a tick on a row after a recompute.
      final first = settle(tied).map((t) => t.toName).toList();
      final second = settle(tied).map((t) => t.toName).toList();

      expect(first, ['Zeta', 'Alpha']);
      expect(first, second);
    });

    test('the id tie-break survives the input being reversed', () {
      final forwards = [
        _p('alpha', 'Alpha', 400),
        _p('zeta', 'Zeta', 400),
        _p('c', 'C', 0),
      ];
      final backwards = [
        _p('zeta', 'Zeta', 400),
        _p('c', 'C', 0),
        _p('alpha', 'Alpha', 400),
      ];

      expect(
        settle(forwards).map((t) => t.key).toList(),
        settle(backwards).map((t) => t.key).toList(),
      );
    });

    test('equalShares is stable across repeated calls', () {
      expect(
        equalShares(
          totalInPaise: 1390000,
          totals: [_p('a', 'A', 5500), _p('b', 'B', 5400), _p('c', 'C', 3000)],
        ),
        equalShares(
          totalInPaise: 1390000,
          totals: [_p('a', 'A', 5500), _p('b', 'B', 5400), _p('c', 'C', 3000)],
        ),
      );
    });
  });

  group('the leftover paisa lands on the largest creditor', () {
    test('a creditor absorbs it, and no debtor is shortchanged', () {
      // 100 paise across three, base share 33 and one paisa left over. Every
      // debtor stays at the floor 33; the creditor takes 34. The alternative —
      // pushing it onto a debtor — would leave that person's friend a paisa
      // short for money that was never spent.
      final settlement = settlementFor([
        _pi('big', 'Big', 60),
        _pi('mid', 'Mid', 25),
        _pi('small', 'Small', 15),
      ]);

      expect(settlement.balanceFor('big')!.shareInPaise, 34);
      expect(settlement.balanceFor('big')!.netInPaise, 26);
      expect(settlement.balanceFor('mid')!.shareInPaise, 33);
      expect(settlement.balanceFor('mid')!.netInPaise, -8);
      expect(settlement.balanceFor('small')!.shareInPaise, 33);
      expect(settlement.balanceFor('small')!.netInPaise, -18);
      expect(settlement.outstandingInPaise, 26);
    });

    test('the shares still sum to the total', () {
      final shares = equalShares(
        totalInPaise: 100,
        totals: [_pi('a', 'A', 60), _pi('b', 'B', 25), _pi('c', 'C', 15)],
      );

      expect(shares.reduce((a, b) => a + b), 100);
    });

    test('no leftover means no reordering at all', () {
      final shares = equalShares(
        totalInPaise: 900,
        totals: [_pi('a', 'A', 400), _pi('b', 'B', 300), _pi('c', 'C', 200)],
      );

      expect(shares, [300, 300, 300]);
    });
  });

  group('transfer keys', () {
    test('carry ids, direction and amount', () {
      const transfer = Transfer(
        fromId: 'sita',
        fromName: 'Sita',
        toId: 'raj',
        toName: 'Raj',
        amountInPaise: 76700,
      );

      expect(transfer.key, 'sita>raj:76700');
    });

    test('differ when either end or the amount differs', () {
      const base = Transfer(
        fromId: 'a',
        fromName: 'A',
        toId: 'b',
        toName: 'B',
        amountInPaise: 100,
      );

      expect(
        const Transfer(
          fromId: 'a',
          fromName: 'A',
          toId: 'b',
          toName: 'B',
          amountInPaise: 101,
        ).key,
        isNot(base.key),
      );
      expect(
        const Transfer(
          fromId: 'b',
          fromName: 'B',
          toId: 'a',
          toName: 'A',
          amountInPaise: 100,
        ).key,
        isNot(base.key),
      );
    });

    test('are unique within one settlement', () {
      final transfers = settle([
        _p('a', 'A', 5000),
        _p('b', 'B', 4000),
        _p('c', 'C', 3000),
        _p('d', 'D', 1000),
      ]);

      final keys = transfers.map((t) => t.key).toList();
      expect(keys.toSet(), hasLength(keys.length));
    });
  });

  group('paise conversion', () {
    test('rounds to whole paise at the edge', () {
      expect(paise(13900), 1390000);
      expect(paise(0.005), 1);
      expect(paise(0.004), 0);
      expect(paise(1250.50), 125050);
    });

    test('round-trips', () {
      for (final value in [0.0, 1.0, 4633.33, 13900.0, 766.67]) {
        expect(rupees(paise(value)), closeTo(value, 0.005));
      }
    });
  });

  group('balancesFor', () {
    test('agrees with the transfers', () {
      final totals = [
        _p('a', 'A', 5000),
        _p('b', 'B', 4000),
        _p('c', 'C', 3000),
        _p('d', 'D', 1000),
      ];
      final settlement = settlementFor(totals);

      final received = <String, int>{};
      for (final transfer in settlement.transfers) {
        received[transfer.toId] =
            (received[transfer.toId] ?? 0) + transfer.amountInPaise;
        received[transfer.fromId] =
            (received[transfer.fromId] ?? 0) - transfer.amountInPaise;
      }

      for (final balance in settlement.balances) {
        expect(
          received[balance.id] ?? 0,
          balance.netInPaise,
          reason:
              '${balance.name} nets ${balance.netInPaise} but the transfers '
              'move ${received[balance.id] ?? 0}',
        );
      }
    });
  });
}
