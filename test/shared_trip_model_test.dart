import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/providers/journey_provider.dart';
import 'package:daily_companion/providers/transaction_provider.dart';
import 'package:daily_companion/services/storage_service.dart';
import 'package:daily_companion/services/trip_importer.dart';
import 'package:daily_companion/services/trip_snapshot.dart';
import 'package:daily_companion/services/trip_snapshot_export.dart';

import 'visual_smoke_test.dart' show initTestStorage;

TripParticipant _person(String id, String name) {
  return TripParticipant(id: id, name: name, createdAt: DateTime(2026, 1, 1));
}

Journey _sharedJourney({
  String id = 'trip-1',
  List<TripParticipant>? participants,
  String? localParticipantId,
  List<String>? settledTransfers,
  String? tripCode = 'BK4J8Q',
}) {
  return Journey(
    id: id,
    origin: 'Kathmandu',
    destination: 'Pokhara',
    startTime: DateTime(2026, 3, 1),
    participants:
        participants ?? [_person('you', 'You'), _person('raj', 'Raj')],
    localParticipantId: localParticipantId,
    settledTransfers: settledTransfers,
    tripCode: tripCode,
  );
}

Expense _expense({
  required String id,
  required double amount,
  String? paidBy,
  String? journeyId = 'trip-1',
  String description = 'Taxi',
}) {
  return Expense(
    id: id,
    amount: amount,
    category: ExpenseCategory.travel,
    description: description,
    journeyId: journeyId,
    paidByParticipantId: paidBy,
  );
}

void main() {
  setUpAll(() async {
    await initTestStorage();
  });

  setUp(() async {
    await StorageService().clear();
  });

  group('TripParticipant', () {
    test('round-trips through JSON', () {
      final original = TripParticipant(
        id: 'abc',
        name: 'Sita',
        createdAt: DateTime(2026, 3, 2, 14, 30),
      );

      final restored = TripParticipant.fromJson(original.toJson());

      expect(restored.id, 'abc');
      expect(restored.name, 'Sita');
      expect(restored.createdAt, DateTime(2026, 3, 2, 14, 30));
    });

    test('a record with no createdAt still loads', () {
      final restored = TripParticipant.fromJson({'id': 'abc', 'name': 'Sita'});

      expect(restored.id, 'abc');
      expect(restored.name, 'Sita');
      expect(restored.createdAt, isA<DateTime>());
    });

    test('a record with no id is given one rather than dropped', () {
      // A nameless-or-idless entry the user did add must survive the load.
      final restored = TripParticipant.fromJson({'name': 'Bikash'});

      expect(restored.id, isNotEmpty);
      expect(restored.name, 'Bikash');
    });

    test('a record with no name still loads', () {
      expect(TripParticipant.fromJson({'id': 'x'}).name, '');
    });

    test('a garbage createdAt does not throw', () {
      final restored = TripParticipant.fromJson({
        'id': 'x',
        'name': 'n',
        'createdAt': 'not a date',
      });

      expect(restored.name, 'n');
    });

    test('a list of non-maps is skipped, not thrown', () {
      final parsed = participantsFromJson([
        {'id': 'a', 'name': 'A'},
        'garbage',
        42,
        null,
        {'id': 'b', 'name': 'B'},
      ]);

      expect(parsed.map((p) => p.name), ['A', 'B']);
    });

    test('a participants field of the wrong type reads as empty', () {
      expect(participantsFromJson('nonsense'), isEmpty);
      expect(participantsFromJson(null), isEmpty);
      expect(participantsFromJson(7), isEmpty);
    });
  });

  group('Journey gains shared-trip fields', () {
    test('they survive a JSON round trip', () {
      final original = _sharedJourney(
        participants: [
          _person('you', 'You'),
          _person('raj', 'Raj'),
          _person('sita', 'Sita'),
        ],
        localParticipantId: 'raj',
        settledTransfers: ['sita>raj:76700', 'sita>you:86667'],
      );

      final restored = Journey.fromJson(original.toJson());

      expect(restored.participants.map((p) => p.name), ['You', 'Raj', 'Sita']);
      expect(restored.localParticipantId, 'raj');
      expect(restored.settledTransfers, ['sita>raj:76700', 'sita>you:86667']);
      expect(restored.tripCode, 'BK4J8Q');
      expect(restored.isShared, isTrue);
      expect(restored.localParticipant?.name, 'Raj');
    });

    test('a record written before the feature still loads', () {
      // The migration case: a journey stored by a build that knew nothing about
      // sharing. Every new field must read as its default.
      final legacy = <String, dynamic>{
        'id': 'old-1',
        'destination': 'Pokhara',
        'origin': 'Kathmandu',
        'notes': 'notes',
        'items': ['Boots', 'Map'],
        'startTime': '2026-01-01T00:00:00.000',
        'endTime': null,
        'completed': 0,
        'createdAt': '2026-01-01T00:00:00.000',
        'updatedAt': '2026-01-01T00:00:00.000',
      };

      final restored = Journey.fromJson(legacy);

      expect(restored.participants, isEmpty);
      expect(restored.settledTransfers, isEmpty);
      expect(restored.localParticipantId, isNull);
      expect(restored.tripCode, isNull);
      expect(restored.isShared, isFalse);
      expect(restored.hasLocalParticipant, isFalse);
      // And the fields it always had are untouched.
      expect(restored.destination, 'Pokhara');
      expect(restored.items, ['Boots', 'Map']);
    });

    test('a participants field holding nonsense reads as empty', () {
      final restored = Journey.fromJson({
        'id': 'x',
        'destination': 'd',
        'origin': 'o',
        'startTime': '2026-01-01T00:00:00.000',
        'createdAt': '2026-01-01T00:00:00.000',
        'updatedAt': '2026-01-01T00:00:00.000',
        'participants': 'nonsense',
        'settledTransfers': 12,
        'localParticipantId': 99,
        'tripCode': 5,
      });

      expect(restored.participants, isEmpty);
      expect(restored.settledTransfers, isEmpty);
      expect(restored.localParticipantId, '99');
      expect(restored.tripCode, '5');
    });

    test('settled transfers of a mixed type all load as strings', () {
      final restored = Journey.fromJson({
        'id': 'x',
        'destination': 'd',
        'origin': 'o',
        'startTime': '2026-01-01T00:00:00.000',
        'createdAt': '2026-01-01T00:00:00.000',
        'updatedAt': '2026-01-01T00:00:00.000',
        'settledTransfers': ['a>b:1', 7, null],
      });

      expect(restored.settledTransfers, ['a>b:1', '7', 'null']);
    });

    test('a localParticipantId naming nobody is not a who-am-I', () {
      // Deleted on another phone, or a file imported before the participants
      // merged. It must not read as "you", which would produce a wrong answer.
      final journey = _sharedJourney(localParticipantId: 'gone');

      expect(journey.localParticipant, isNull);
      expect(journey.hasLocalParticipant, isFalse);
    });

    test('participantName falls back rather than showing nothing', () {
      final journey = _sharedJourney();

      expect(journey.participantName('raj'), 'Raj');
      expect(journey.participantName('unknown-id'), 'unknown-id');
      expect(journey.participantName(null), 'Unassigned');
      expect(journey.participantName(''), 'Unassigned');
    });

    test('isShared needs two people', () {
      expect(_sharedJourney(participants: []).isShared, isFalse);
      expect(
        _sharedJourney(participants: [_person('a', 'A')]).isShared,
        isFalse,
      );
      expect(
        _sharedJourney(participants: [_person('a', 'A'), _person('b', 'B')])
            .isShared,
        isTrue,
      );
    });

    test('copyWith can clear who-am-I and the code', () {
      final journey = _sharedJourney(localParticipantId: 'raj');

      expect(
        journey.copyWith(clearLocalParticipant: true).localParticipantId,
        isNull,
      );
      expect(journey.copyWith(clearTripCode: true).tripCode, isNull);
    });

    test('copyWith leaves shared fields alone when not asked', () {
      final journey = _sharedJourney(
        localParticipantId: 'raj',
        settledTransfers: ['a>b:1'],
      );

      final updated = journey.copyWith(destination: 'Bhaktapur');

      expect(updated.destination, 'Bhaktapur');
      expect(updated.participants, journey.participants);
      expect(updated.localParticipantId, 'raj');
      expect(updated.settledTransfers, ['a>b:1']);
      expect(updated.tripCode, 'BK4J8Q');
    });
  });

  group('Expense gains paidByParticipantId', () {
    test('it survives a JSON round trip', () {
      final restored = Expense.fromJson(
        _expense(id: 'e1', amount: 400, paidBy: 'raj').toJson(),
      );

      expect(restored.paidByParticipantId, 'raj');
    });

    test('an expense written before the field still loads', () {
      final legacy = <String, dynamic>{
        'id': 'e1',
        'amount': 400,
        'description': 'Taxi',
        'category': 'travel',
        'journeyId': 'trip-1',
        'date': '2026-03-01T00:00:00.000',
        'createdAt': '2026-03-01T00:00:00.000',
      };

      final restored = Expense.fromJson(legacy);

      expect(restored.paidByParticipantId, isNull);
      expect(restored.amount, 400);
      expect(restored.journeyId, 'trip-1');
    });

    test('an unknown payer id loads rather than throwing', () {
      // The migration-adjacent case: an expense whose payer is not on the roster
      // must still be readable. Throwing here would make the whole trip fail to
      // load over one bad field.
      final restored = Expense.fromJson(
        _expense(id: 'e1', amount: 400, paidBy: 'someone-deleted').toJson(),
      );

      expect(restored.paidByParticipantId, 'someone-deleted');
    });

    test('copyWith can clear the payer', () {
      final expense = _expense(id: 'e1', amount: 400, paidBy: 'raj');

      expect(
        expense.copyWith(clearPaidByParticipant: true).paidByParticipantId,
        isNull,
      );
      expect(expense.copyWith().paidByParticipantId, 'raj');
    });

    test('income has no payer', () {
      final income = Income(
        amount: 100,
        category: 'salary',
        description: 'Pay',
      );

      expect(income.paidByParticipantId, isNull);
      expect(Transaction.fromJson(income.toJson()).paidByParticipantId, isNull);
    });

    test('the extension reads through the sealed base class', () {
      final Transaction expense = _expense(id: 'e1', amount: 1, paidBy: 'raj');

      expect(expense.paidByParticipantId, 'raj');
    });
  });

  group('trip codes', () {
    // The codes are GONE as a feature, but the field is not.
    //
    // Removal was of GENERATION, not of storage: a trip that already has a code
    // still round-trips through export, import and the model, because a code
    // written by an older build is data the user has and dropping it would
    // quietly change a trip they already exported. What cannot be done any more
    // is making a new one.
    test('an existing code still round-trips', () {
      expect(_sharedJourney(tripCode: 'BK4J8Q').tripCode, 'BK4J8Q');
    });

    test('a trip simply has no code unless one was already there', () {
      expect(_sharedJourney(tripCode: null).tripCode, isNull);
    });

    test('a malformed stored value is read as text, not trusted', () {
      // This is what is left of the old validation: whatever is in the file is
      // kept as a string, because the importer is reading a user's data rather
      // than generating something.
      final restored = Journey.fromJson({
        ..._sharedJourney().toJson(),
        'tripCode': 5,
      });
      expect(restored.tripCode, '5');
    });
  });

  group('the exported snapshot', () {
    TripSnapshot snapshotOf() => TripSnapshot.fromJourney(
      journey: _sharedJourney(
        participants: [
          _person('you', 'You'),
          _person('raj', 'Raj'),
          _person('sita', 'Sita'),
        ],
      ),
      expenses: [
        _expense(id: 'e1', amount: 4000, paidBy: 'you'),
        _expense(id: 'e2', amount: 1500, paidBy: 'you'),
        _expense(id: 'e3', amount: 3000, paidBy: 'raj'),
        _expense(id: 'e4', amount: 2000, paidBy: 'sita'),
        _expense(id: 'e5', amount: 1000, paidBy: 'sita'),
      ],
      exportedBy: 'You',
    );

    test('carries the journey, the names and who paid', () {
      final json = snapshotOf().toJson();

      expect(json['kind'], 'tbrn-trip-snapshot');
      expect(json['exportedBy'], 'You');
      expect((json['journey'] as Map)['participants'], hasLength(3));
      expect(
        ((json['journey'] as Map)['participants'] as List).map(
          (p) => (p as Map)['name'],
        ),
        containsAll(['You', 'Raj', 'Sita']),
        reason: 'names are denormalised so an imported file is readable alone',
      );
      expect(json['expenses'], hasLength(5));
      expect(
        ((json['expenses'] as List).first as Map)['paidByParticipantId'],
        'you',
      );
    });

    test('excludes expenses belonging to another trip', () {
      final snapshot = TripSnapshot.fromJourney(
        journey: _sharedJourney(),
        expenses: [
          _expense(id: 'e1', amount: 100, paidBy: 'you'),
          _expense(
            id: 'other',
            amount: 999,
            paidBy: 'you',
            journeyId: 'trip-2',
          ),
        ],
        exportedBy: 'You',
      );

      expect(snapshot.expenses, hasLength(1));
    });

    test('excludes income, which is not a trip cost', () {
      final snapshot = TripSnapshot.fromJourney(
        journey: _sharedJourney(),
        expenses: [
          _expense(id: 'e1', amount: 100, paidBy: 'you'),
          Income(
            id: 'sal',
            amount: 50000,
            category: 'salary',
            description: 'Pay',
          ),
        ],
        exportedBy: 'You',
      );

      expect(snapshot.expenses, hasLength(1));
    });

    test('round-trips through encode and decode', () {
      final original = snapshotOf();

      final decoded = TripSnapshot.decode(original.encode()).snapshot!;

      expect(decoded.journey.id, original.journey.id);
      expect(decoded.journey.tripCode, 'BK4J8Q');
      expect(decoded.exportedBy, 'You');
      expect(decoded.expenses, hasLength(5));
      expect(decoded.participantTotals().map((t) => t.amountPaidInPaise), [
        550000,
        300000,
        300000,
      ]);
    });

    test('the totals feed the settlement', () {
      final settlement = settlementFor(snapshotOf().participantTotals());

      expect(
        settlement.transfers.map((t) => '${t.fromName}->${t.toName}').toList(),
        // You paid 5500 of 11500 and Raj and Sita 3000 each, so both of them
        // owe You 833.33. Raj goes first only because the ids break the tie.
        ['Raj->You', 'Sita->You'],
      );
      expect(settlement.total, 11500);
    });

    test('a person who paid nothing is still on the roster', () {
      // Otherwise they vanish and stop owing their share, which would make the
      // settlement wrong in the direction that favours them.
      final snapshot = TripSnapshot.fromJourney(
        journey: _sharedJourney(
          participants: [
            _person('you', 'You'),
            _person('raj', 'Raj'),
            _person('bikash', 'Bikash'),
          ],
        ),
        expenses: [_expense(id: 'e1', amount: 900, paidBy: 'you')],
        exportedBy: 'You',
      );

      final totals = snapshot.participantTotals();

      expect(totals.map((t) => t.name), ['You', 'Raj', 'Bikash']);
      expect(totals.firstWhere((t) => t.name == 'Bikash').amountPaidInPaise, 0);
    });

    test('an expense with no payer counts into nobody', () {
      final snapshot = TripSnapshot.fromJourney(
        journey: _sharedJourney(),
        expenses: [_expense(id: 'e1', amount: 500, paidBy: null)],
        exportedBy: 'You',
      );

      expect(
        snapshot.participantTotals().every((t) => t.amountPaidInPaise == 0),
        isTrue,
      );
      expect(snapshot.total, 500);
    });
  });

  group('reading a file this build cannot use', () {
    test('non-JSON is refused, not thrown', () {
      final result = TripSnapshot.decode('this is not json at all');

      expect(result.isValid, isFalse);
      expect(result.message, contains('readable JSON'));
    });

    test('JSON that is not an object is refused', () {
      expect(TripSnapshot.decode('[1,2,3]').isValid, isFalse);
      expect(TripSnapshot.decode('42').isValid, isFalse);
    });

    test('a file from another app is refused', () {
      final result = TripSnapshot.decode(
        jsonEncode({'kind': 'something-else', 'journey': <String, dynamic>{}}),
      );

      expect(result.isValid, isFalse);
      expect(result.message, contains('not a TBRN Companion trip'));
    });

    test('a snapshot with no journey is refused', () {
      final result = TripSnapshot.decode(
        jsonEncode({'kind': 'tbrn-trip-snapshot'}),
      );

      expect(result.isValid, isFalse);
      expect(result.message, contains('no trip'));
    });

    test('one unreadable expense row does not fail the whole file', () {
      final result = TripSnapshot.decode(
        jsonEncode({
          'kind': 'tbrn-trip-snapshot',
          'exportedBy': 'Raj',
          'journey': _sharedJourney().toJson(),
          'expenses': [
            _expense(id: 'good1', amount: 100, paidBy: 'you').toJson(),
            // No date and no amount: unreadable as a transaction.
            {'id': 'broken', 'description': 'x'},
            'not even a map',
            _expense(id: 'good2', amount: 200, paidBy: 'raj').toJson(),
          ],
        }),
      );

      expect(result.isValid, isTrue);
      expect(result.snapshot!.expenses.map((e) => e.id), ['good1', 'good2']);
    });

    test(
      'an income row in the file is skipped rather than treated as a cost',
      () {
        final result = TripSnapshot.decode(
          jsonEncode({
            'kind': 'tbrn-trip-snapshot',
            'exportedBy': 'Raj',
            'journey': _sharedJourney().toJson(),
            'expenses': [
              Income(
                id: 'sal',
                amount: 50000,
                category: 'salary',
                description: 'Pay',
              ).toJson(),
              _expense(id: 'e1', amount: 100, paidBy: 'you').toJson(),
            ],
          }),
        );

        expect(result.snapshot!.expenses.map((e) => e.id), ['e1']);
      },
    );

    test('an empty file is valid and empty', () {
      final result = TripSnapshot.decode(
        jsonEncode({
          'kind': 'tbrn-trip-snapshot',
          'journey': _sharedJourney().toJson(),
          'expenses': <dynamic>[],
        }),
      );

      expect(result.isValid, isTrue);
      expect(result.snapshot!.expenses, isEmpty);
      expect(result.snapshot!.exportedBy, 'Someone');
    });

    test('a file from a build with unknown extra keys still loads', () {
      final result = TripSnapshot.decode(
        jsonEncode({
          'kind': 'tbrn-trip-snapshot',
          'somethingNewInAFutureBuild': {'a': 1},
          'journey': {..._sharedJourney().toJson(), 'futureField': 'whatever'},
          'expenses': [
            {
              ..._expense(id: 'e1', amount: 100, paidBy: 'you').toJson(),
              'future': 1,
            },
          ],
        }),
      );

      expect(result.isValid, isTrue);
      expect(result.snapshot!.expenses, hasLength(1));
    });
  });

  group('a trip with money nobody has claimed', () {
    test('the snapshot total includes it and the settlement does not', () async {
      // Two screens about one trip: the journey page says "spent Rs 15,000" and
      // the summary must say the same. Folding an unclaimed expense into
      // somebody's total would make the settlement wrong in the direction that
      // suits them, and dropping it would make the two screens disagree.
      final snapshot = TripSnapshot.fromJourney(
        journey: _sharedJourney(
          participants: [_person('you', 'You'), _person('raj', 'Raj')],
        ),
        expenses: [
          _expense(id: 'mine', amount: 500, paidBy: 'you'),
          _expense(id: 'theirs', amount: 500, paidBy: 'raj'),
          _expense(id: 'unclaimed', amount: 200),
        ],
        exportedBy: 'You',
      );

      expect(snapshot.total, 1200);

      final settlement = settlementFor(
        snapshot.participantTotals(),
        unattributedInPaise: 20000,
      );
      expect(settlement.total, 1000);
      expect(settlement.tripTotal, 1200);
      expect(settlement.hasUnattributed, isTrue);
      // Nobody's share is inflated by the money nobody claimed.
      expect(settlement.balances.every((b) => b.shareInPaise == 50000), isTrue);
    });

    test('an expense whose payer is not on the roster is not attributed', () async {
      final snapshot = TripSnapshot.fromJourney(
        journey: _sharedJourney(
          participants: [_person('you', 'You'), _person('raj', 'Raj')],
        ),
        expenses: [
          _expense(id: 'mine', amount: 500, paidBy: 'you'),
          _expense(id: 'ghost', amount: 300, paidBy: 'someone-not-here'),
        ],
        exportedBy: 'You',
      );

      // The payer id is KEPT on the record — it is real data — but it resolves
      // to nobody, so it is not folded into anyone's total.
      expect(snapshot.expenses.last.paidByParticipantId, 'someone-not-here');
      expect(
        snapshot.participantTotals().fold<int>(
          0,
          (s, t) => s + t.amountPaidInPaise,
        ),
        50000,
      );
    });
  });

  group('a snapshot whose trip will not parse', () {
    test('is refused with a message, not thrown', () {
      // The journey came from somebody else's phone. A truncated download or a
      // hand-edited date must not take the import flow down with an unhandled
      // FormatException.
      final result = TripSnapshot.decode(
        jsonEncode({
          'kind': 'tbrn-trip-snapshot',
          'exportedBy': 'Raj',
          'journey': {
            'id': 'x',
            'destination': 'Pokhara',
            'origin': 'Kathmandu',
            'startTime': 'not a date at all',
          },
          'expenses': <dynamic>[],
        }),
      );

      expect(result.isValid, isFalse);
      expect(result.message, contains('could not be read'));
    });
  });

  group('the exported file on disk', () {
    test('is written as JSON with a safe name', () async {
      final snapshot = TripSnapshot.fromJourney(
        journey: _sharedJourney(),
        expenses: [_expense(id: 'e1', amount: 100, paidBy: 'you')],
        exportedBy: 'You',
      );

      final file = await TripSnapshotExport.writeSnapshot(
        snapshot,
        snapshot.journey,
      );

      expect(file.path.endsWith('.json'), isTrue);
      expect(
        TripSnapshotExport.fileNameFor(_sharedJourney()),
        'tbrn-trip-pokhara-bk4j8q.json',
      );
      final contents = await file.readAsString();
      expect(jsonDecode(contents)['kind'], 'tbrn-trip-snapshot');
    });

    test('a trip title cannot escape the directory', () async {
      // A title with a slash or a colon must not produce a path outside the temp
      // dir; this is the user's own title going into a filename.
      final awkward = _sharedJourney();
      final renamed = Journey(
        id: awkward.id,
        origin: 'Kathmandu',
        destination: '../../etc/passwd: with slash',
      );

      final name = TripSnapshotExport.fileNameFor(renamed);

      expect(name.contains('/'), isFalse);
      expect(name.contains('..'), isFalse);
      expect(name, startsWith('tbrn-trip-'));
      expect(name, endsWith('.json'));
    });

    test('an empty title still produces a usable name', () {
      final blank = Journey(destination: '', origin: '');

      expect(TripSnapshotExport.fileNameFor(blank), 'tbrn-trip-trip.json');
    });
  });

  group('importing into an empty phone', () {
    TripSnapshot incoming() => TripSnapshot.fromJourney(
      journey: _sharedJourney(
        participants: [_person('you', 'You'), _person('raj', 'Raj')],
      ),
      expenses: [
        _expense(id: 'e1', amount: 4000, paidBy: 'you'),
        _expense(id: 'e2', amount: 3000, paidBy: 'raj'),
      ],
      exportedBy: 'Raj',
    );

    test('creates the trip with its participants and expenses', () async {
      final result = await const TripImporter().apply(
        snapshot: incoming(),
        existing: null,
      );

      final journey = await StorageService().getJourney('trip-1');
      expect(journey, isNotNull);
      expect(journey!.participants.map((p) => p.name), ['You', 'Raj']);
      expect(journey.tripCode, 'BK4J8Q');

      final expenses = await StorageService().getTransactionsByJourney(
        'trip-1',
      );
      expect(expenses, hasLength(2));
      expect(result.participantsAdded, 2);
      expect(result.expensesAdded, 2);
    });

    test('does not decide who the importer is', () async {
      // Raj's file naming Raj as "me" must not make Sita Raj. The import flow
      // asks; it never guesses.
      final snapshot = TripSnapshot.fromJourney(
        journey: _sharedJourney(localParticipantId: 'raj'),
        expenses: [_expense(id: 'e1', amount: 100, paidBy: 'raj')],
        exportedBy: 'Raj',
      );

      await const TripImporter().apply(snapshot: snapshot, existing: null);

      final journey = await StorageService().getJourney('trip-1');
      expect(journey!.localParticipantId, isNull);
    });
  });

  group('re-importing the same file', () {
    TripSnapshot incoming() => TripSnapshot.fromJourney(
      journey: _sharedJourney(
        participants: [_person('you', 'You'), _person('raj', 'Raj')],
        settledTransfers: ['you>raj:100'],
      ),
      expenses: [_expense(id: 'e1', amount: 4000, paidBy: 'you')],
      exportedBy: 'You',
    );

    test('the second import changes nothing at all', () async {
      const importer = TripImporter();
      await importer.apply(snapshot: incoming(), existing: null);

      final first = await StorageService().getAllTransactions();
      final afterFirst = await StorageService().getJourney('trip-1');

      final stored = await StorageService().getJourney('trip-1');
      final second = await importer.apply(
        snapshot: incoming(),
        existing: stored,
      );

      expect(
        await StorageService().getAllTransactions(),
        hasLength(first.length),
      );
      final afterSecond = await StorageService().getJourney('trip-1');
      expect(
        afterSecond!.participants,
        hasLength(afterFirst!.participants.length),
        reason: 'a second import must not add a duplicate participant',
      );
      expect(
        afterSecond.participants.map((p) => p.id).toSet(),
        afterFirst.participants.map((p) => p.id).toSet(),
      );
      expect(second.expensesAdded, 0);
      expect(second.participantsAdded, 0);
      expect(second.skippedAsExisting, 1);
      expect(second.addedAnything, isFalse);
    });

    test('a third time is still nothing', () async {
      const importer = TripImporter();
      await importer.apply(snapshot: incoming(), existing: null);

      for (var i = 0; i < 2; i++) {
        await importer.apply(
          snapshot: incoming(),
          existing: await StorageService().getJourney('trip-1'),
        );
      }

      expect(await StorageService().getAllTransactions(), hasLength(1));
      final journey = await StorageService().getJourney('trip-1');
      expect(journey!.settledTransfers, ['you>raj:100']);
    });

    test('the summary says so rather than reading as a failure', () async {
      const importer = TripImporter();
      await importer.apply(snapshot: incoming(), existing: null);
      final result = await importer.apply(
        snapshot: incoming(),
        existing: await StorageService().getJourney('trip-1'),
      );

      expect(result.describe(), contains('Already on this phone'));
    });
  });

  group('merge is add-only', () {
    test('a locally deleted expense is NOT resurrected by an old file', () async {
      // The rule that matters most. If an older snapshot could bring it back,
      // the app would be silently undoing a deletion the user made on purpose.
      //
      // Driven through the PROVIDER, not straight at storage, because that is
      // where the deletion tombstone is written. Deleting straight in storage
      // would be testing a flow no user can reach.
      const importer = TripImporter();
      final snapshot = TripSnapshot.fromJourney(
        journey: _sharedJourney(),
        expenses: [
          _expense(id: 'keep', amount: 100, paidBy: 'you'),
          _expense(id: 'deleted-here', amount: 200, paidBy: 'you'),
        ],
        exportedBy: 'You',
      );

      await importer.apply(snapshot: snapshot, existing: null);

      final transactions = TransactionProvider();
      await transactions.initialize();
      addTearDown(transactions.dispose);
      await transactions.deleteTransaction('deleted-here');

      expect(
        await StorageService().getTransactionsByJourney('trip-1'),
        hasLength(1),
      );
      // The tombstone is what makes the next import respect the deletion.
      expect((await StorageService().getJourney('trip-1'))!.removedIds, [
        'deleted-here',
      ]);

      await importer.apply(
        snapshot: snapshot,
        existing: await StorageService().getJourney('trip-1'),
      );

      final after = await StorageService().getTransactionsByJourney('trip-1');
      expect(after.map((e) => e.id), ['keep']);
      expect(after.any((e) => e.id == 'deleted-here'), isFalse);
    });

    test('a personal trip is not given a tombstone', () async {
      // Nothing is imported into a trip that is not shared, so there is nothing
      // for a later file to resurrect and no reason to remember anything.
      await StorageService().addJourney(
        Journey(id: 'solo', origin: 'a', destination: 'b'),
      );
      await StorageService().addTransaction(
        _expense(id: 'e1', amount: 10, journeyId: 'solo'),
      );

      final transactions = TransactionProvider();
      await transactions.initialize();
      addTearDown(transactions.dispose);
      await transactions.deleteTransaction('e1');

      expect((await StorageService().getJourney('solo'))!.removedIds, isEmpty);
    });

    test(
      'a locally removed participant is NOT brought back by an old file',
      () async {
        const importer = TripImporter();
        final snapshot = TripSnapshot.fromJourney(
          journey: _sharedJourney(
            participants: [_person('you', 'You'), _person('raj', 'Raj')],
          ),
          expenses: [_expense(id: 'e1', amount: 100, paidBy: 'you')],
          exportedBy: 'You',
        );

        await importer.apply(snapshot: snapshot, existing: null);

        final journeys = JourneyProvider();
        await journeys.initialize();
        addTearDown(journeys.dispose);
        await journeys.removeParticipant('trip-1', 'raj');

        expect(
          (await StorageService().getJourney('trip-1'))!.participants
              .map((p) => p.name),
          ['You'],
        );

        await importer.apply(
          snapshot: snapshot,
          existing: await StorageService().getJourney('trip-1'),
        );

        final journey = await StorageService().getJourney('trip-1');
        expect(journey!.participants.map((p) => p.name), ['You']);
        // Their expenses stay — the money was really spent — they just stop
        // being attributable to a person.
        expect(
          await StorageService().getTransactionsByJourney('trip-1'),
          hasLength(1),
        );
      },
    );

    test('a locally edited expense is NOT overwritten', () async {
      const importer = TripImporter();
      final snapshot = TripSnapshot.fromJourney(
        journey: _sharedJourney(),
        expenses: [_expense(id: 'e1', amount: 100, paidBy: 'you')],
        exportedBy: 'You',
      );
      await importer.apply(snapshot: snapshot, existing: null);

      final edited = _expense(
        id: 'e1',
        amount: 999,
        paidBy: 'raj',
      ).copyWith(journeyId: 'trip-1');
      await StorageService().updateTransaction(edited);

      await importer.apply(
        snapshot: snapshot,
        existing: await StorageService().getJourney('trip-1'),
      );

      final stored = (await StorageService().getTransactionsByJourney('trip-1'))
          .single;
      expect(stored.amount, 999);
      expect(stored.paidByParticipantId, 'raj');
    });

    test('a locally edited trip name is not overwritten by the file', () async {
      const importer = TripImporter();
      final snapshot = TripSnapshot.fromJourney(
        journey: _sharedJourney(),
        expenses: [_expense(id: 'e1', amount: 100, paidBy: 'you')],
        exportedBy: 'You',
      );
      await importer.apply(snapshot: snapshot, existing: null);

      final mine = (await StorageService().getJourney('trip-1'))!
          .copyWith(destination: 'My own name for it');
      await StorageService().updateJourney(mine);

      await importer.apply(snapshot: snapshot, existing: mine);

      final journey = await StorageService().getJourney('trip-1');
      expect(journey!.destination, 'My own name for it');
    });

    test('new records from a later file are still added', () async {
      const importer = TripImporter();
      final first = TripSnapshot.fromJourney(
        journey: _sharedJourney(),
        expenses: [_expense(id: 'e1', amount: 100, paidBy: 'you')],
        exportedBy: 'You',
      );
      await importer.apply(snapshot: first, existing: null);

      // Raj adds an expense and re-exports.
      final second = TripSnapshot.fromJourney(
        journey: _sharedJourney(
          participants: [
            _person('you', 'You'),
            _person('raj', 'Raj'),
            _person('sita', 'Sita'),
          ],
        ),
        expenses: [
          _expense(id: 'e1', amount: 100, paidBy: 'you'),
          _expense(id: 'e2', amount: 250, paidBy: 'raj'),
          _expense(id: 'e3', amount: 300, paidBy: 'sita'),
        ],
        exportedBy: 'Raj',
      );

      final result = await importer.apply(
        snapshot: second,
        existing: await StorageService().getJourney('trip-1'),
      );

      expect(result.expensesAdded, 2);
      expect(result.skippedAsExisting, 1);
      expect(result.participantsAdded, 1);

      final journey = await StorageService().getJourney('trip-1');
      expect(journey!.participants.map((p) => p.name), ['You', 'Raj', 'Sita']);
      expect(
        await StorageService().getTransactionsByJourney('trip-1'),
        hasLength(3),
      );
    });

    test('the local trip code is not replaced by the file\'s', () async {
      // Two people compare codes to confirm they are on the same trip. A code
      // that changed on import would make them look like they are not.
      const importer = TripImporter();
      final snapshot = TripSnapshot.fromJourney(
        journey: _sharedJourney(tripCode: 'FROMFILE'),
        expenses: [_expense(id: 'e1', amount: 100, paidBy: 'you')],
        exportedBy: 'Raj',
      );
      await importer.apply(snapshot: snapshot, existing: null);

      final mine = (await StorageService().getJourney('trip-1'))!
          .copyWith(tripCode: 'MINE');
      await StorageService().updateJourney(mine);

      await importer.apply(
        snapshot: snapshot,
        existing: await StorageService().getJourney('trip-1'),
      );

      expect((await StorageService().getJourney('trip-1'))?.tripCode, 'MINE');
    });
  });

  group('the removal tombstones are capped', () {
    test('the list never grows past 200, dropping the oldest', () {
      // removedIds only ever grows, and a trip shared between friends can
      // accumulate deletions for years. The stored record has to stay bounded.
      var journey = Journey(id: 't', destination: 'd', origin: 'o');
      for (var i = 0; i < 250; i++) {
        journey = journey.withRemoved('id-$i');
      }

      expect(journey.removedIds, hasLength(200));
      // Oldest dropped, newest kept — the newest deletion is the one most
      // likely to still have a file in flight that would otherwise resurrect it.
      expect(journey.removedIds.first, 'id-50');
      expect(journey.removedIds.last, 'id-249');
      expect(journey.isRemoved('id-0'), isFalse);
      expect(journey.isRemoved('id-249'), isTrue);
    });

    test('the newest tombstone still protects a deletion', () {
      var journey = Journey(id: 't', destination: 'd', origin: 'o');
      for (var i = 0; i < 500; i++) {
        journey = journey.withRemoved('id-$i');
      }
      expect(journey.removedIds, hasLength(200));
      expect(journey.isRemoved('id-499'), isTrue);
    });

    test('adding the same id twice does not grow the list', () {
      var journey = Journey(id: 't', destination: 'd', origin: 'o');
      journey = journey.withRemoved('same');
      journey = journey.withRemoved('same');
      journey = journey.withRemoved('same');

      expect(journey.removedIds, ['same']);
    });

    test('an empty id is not tombstoned', () {
      final journey = Journey(id: 't', destination: 'd', origin: 'o');

      expect(journey.withRemoved('').removedIds, isEmpty);
    });

    test('reading a record already over the cap does not drop tombstones', () {
      // Truncating on READ is how a deleted expense comes back. Loading is
      // deliberately lossless; the cap applies the next time one is added.
      final json = Journey.fromJson({
        'id': 't',
        'destination': 'd',
        'origin': 'o',
        'startTime': '2026-01-01T00:00:00.000',
        'createdAt': '2026-01-01T00:00:00.000',
        'updatedAt': '2026-01-01T00:00:00.000',
        'removedIds': [for (var i = 0; i < 300; i++) 'id-$i'],
      });

      expect(json.removedIds, hasLength(300));
      expect(json.isRemoved('id-0'), isTrue);
      expect(json.withRemoved('new').removedIds, hasLength(200));
      expect(json.withRemoved('new').isRemoved('id-0'), isFalse);
    });

    test('a trip with no tombstones loads from before the field existed', () {
      final legacy = Journey.fromJson({
        'id': 'old',
        'destination': 'Pokhara',
        'origin': 'Kathmandu',
        'startTime': '2026-01-01T00:00:00.000',
        'createdAt': '2026-01-01T00:00:00.000',
        'updatedAt': '2026-01-01T00:00:00.000',
      });

      expect(legacy.removedIds, isEmpty);
    });
  });

  group('merge is by id, not by name', () {
    test('two different people with the same name stay two people', () async {
      const importer = TripImporter();
      final snapshot = TripSnapshot.fromJourney(
        journey: _sharedJourney(
          participants: [
            _person('raj-1', 'Raj'),
            _person('raj-2', 'Raj'),
            _person('me', 'Me'),
          ],
        ),
        expenses: [
          _expense(id: 'e1', amount: 100, paidBy: 'raj-1'),
          _expense(id: 'e2', amount: 100, paidBy: 'raj-2'),
        ],
        exportedBy: 'Raj',
      );

      await importer.apply(snapshot: snapshot, existing: null);

      final journey = await StorageService().getJourney('trip-1');
      expect(journey!.participants, hasLength(3));
      // Each one's spending stays behind their own id, even though both are
      // called Raj.
      final paidBy = {
        for (final expense in await StorageService().getTransactionsByJourney(
          'trip-1',
        ))
          expense.id: expense.paidByParticipantId,
      };
      expect(paidBy['e1'], 'raj-1');
      expect(paidBy['e2'], 'raj-2');
    });
  });

  group('settled transfers across an import', () {
    test('ticks from the file are unioned, not replaced', () async {
      const importer = TripImporter();
      final snapshot = TripSnapshot.fromJourney(
        journey: _sharedJourney(settledTransfers: ['from-file>you:100']),
        expenses: [_expense(id: 'e1', amount: 100, paidBy: 'you')],
        exportedBy: 'Raj',
      );
      await importer.apply(snapshot: snapshot, existing: null);

      final mine = (await StorageService().getJourney('trip-1'))!
          .copyWith(settledTransfers: ['mine>you:50']);
      await StorageService().updateJourney(mine);

      await importer.apply(
        snapshot: snapshot,
        existing: await StorageService().getJourney('trip-1'),
      );

      final journey = await StorageService().getJourney('trip-1');
      expect(
        journey!.settledTransfers,
        containsAll(['from-file>you:100', 'mine>you:50']),
      );
    });

    test('a re-import does not duplicate ticks', () async {
      const importer = TripImporter();
      final snapshot = TripSnapshot.fromJourney(
        journey: _sharedJourney(settledTransfers: ['a>you:100']),
        expenses: [_expense(id: 'e1', amount: 100, paidBy: 'you')],
        exportedBy: 'Raj',
      );
      await importer.apply(snapshot: snapshot, existing: null);

      for (var i = 0; i < 3; i++) {
        await importer.apply(
          snapshot: snapshot,
          existing: await StorageService().getJourney('trip-1'),
        );
      }

      final journey = await StorageService().getJourney('trip-1');
      expect(journey!.settledTransfers, ['a>you:100']);
    });
  });

  group('the ping-pong', () {
    test('two phones exchange a trip and converge', () async {
      // The intended workflow, end to end: A exports, B imports, B adds, B
      // exports, A imports. Both ends must hold the same expenses.
      const importer = TripImporter();

      // Phone A: You paid for the taxi.
      await StorageService().clear();
      await importer.apply(
        snapshot: TripSnapshot.fromJourney(
          journey: _sharedJourney(
            participants: [_person('you', 'You'), _person('raj', 'Raj')],
          ),
          expenses: [_expense(id: 'e1', amount: 4000, paidBy: 'you')],
          exportedBy: 'You',
        ),
        existing: null,
      );
      final aExport = TripSnapshot.fromJourney(
        journey: (await StorageService().getJourney('trip-1'))!,
        expenses: await StorageService().getTransactionsByJourney('trip-1'),
        exportedBy: 'You',
      );

      // Phone B: imports it.
      await StorageService().clear();
      await importer.apply(snapshot: aExport, existing: null);
      // Raj adds what he paid.
      await StorageService().addTransaction(
        _expense(id: 'e2', amount: 3000, paidBy: 'raj', description: 'Boat'),
      );
      final bExport = TripSnapshot.fromJourney(
        journey: (await StorageService().getJourney('trip-1'))!,
        expenses: await StorageService().getTransactionsByJourney('trip-1'),
        exportedBy: 'Raj',
      );

      // Phone A: imports Raj's file back.
      await importer.apply(
        snapshot: bExport,
        existing: await StorageService().getJourney('trip-1'),
      );

      final aExpenses = await StorageService().getTransactionsByJourney(
        'trip-1',
      );
      final bExpenses = await importer
          .apply(
            snapshot: aExport,
            existing: await StorageService().getJourney('trip-1'),
          )
          .then((_) => StorageService().getTransactionsByJourney('trip-1'));

      expect(aExpenses.map((e) => e.id).toSet(), {'e1', 'e2'});
      expect(
        aExpenses.map((e) => e.id).toSet(),
        bExpenses.map((e) => e.id).toSet(),
      );

      // And both phones settle the same trip identically, which is what makes a
      // ticked payment mean the same thing on each one.
      final settlement = settlementFor([
        const ParticipantTotal(
          id: 'you',
          name: 'You',
          amountPaidInPaise: 400000,
        ),
        const ParticipantTotal(
          id: 'raj',
          name: 'Raj',
          amountPaidInPaise: 300000,
        ),
      ]);

      // 7000 across two people: Raj owes You the 500 difference, not the full amount.
      expect(settlement.transfers.map((t) => t.key), ['raj>you:50000']);
    });
  });
}
