import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/providers/journey_provider.dart';
import 'package:daily_companion/providers/transaction_provider.dart';
import 'package:daily_companion/services/storage_service.dart';

import 'visual_smoke_test.dart' show initTestStorage;

Expense _expense(
  double amount,
  ExpenseCategory category, {
  DateTime? date,
  String? journeyId,
  String? paidByParticipantId,
}) {
  return Expense(
    amount: amount,
    category: category,
    description: 'Test expense',
    date: date ?? DateTime.now(),
    journeyId: journeyId,
    paidByParticipantId: paidByParticipantId,
  );
}

void main() {
  setUpAll(() async {
    await initTestStorage();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService().clear();
  });

  group('isMyLedgerEntry — the whole table', () {
    String? alwaysMe(String _) => 'me';
    String? alwaysNobody(String _) => null;

    test('no journey and no payer is an ordinary expense', () {
      final t = _expense(100, ExpenseCategory.food);
      expect(isMyLedgerEntry(t, localParticipantIdFor: alwaysMe), isTrue);
    });

    test('a payer on an expense with no trip still counts', () {
      // The rule is about TRIPS. A payer recorded on a solo expense is a fact
      // about that expense, not about a shared trip, and it is still the user's.
      final t = _expense(100, ExpenseCategory.food, paidByParticipantId: 'me');
      expect(isMyLedgerEntry(t, localParticipantIdFor: alwaysNobody), isTrue);
    });

    test('a trip expense with no payer counts — pre-field history', () {
      final t = _expense(100, ExpenseCategory.food, journeyId: 'trip-1');
      expect(isMyLedgerEntry(t, localParticipantIdFor: alwaysMe), isTrue);
    });

    test('a trip expense I paid counts', () {
      final t = _expense(
        100,
        ExpenseCategory.food,
        journeyId: 'trip-1',
        paidByParticipantId: 'me',
      );
      expect(isMyLedgerEntry(t, localParticipantIdFor: alwaysMe), isTrue);
    });

    test("a trip expense someone else paid does not count", () {
      final t = _expense(
        100,
        ExpenseCategory.food,
        journeyId: 'trip-1',
        paidByParticipantId: 'sita',
      );
      expect(isMyLedgerEntry(t, localParticipantIdFor: alwaysMe), isFalse);
    });

    test('"me" is per trip, so the same id can flip the answer', () {
      // The same payer id is "me" on one trip and a stranger on another. This is
      // why the predicate takes a resolver rather than comparing to a constant:
      // a version that assumed any non-null payer was somebody else silently
      // dropped the user's own trip spending while looking exactly correct.
      final t = _expense(
        100,
        ExpenseCategory.food,
        journeyId: 'trip-1',
        paidByParticipantId: 'p1',
      );
      expect(isMyLedgerEntry(t, localParticipantIdFor: (j) => 'p1'), isTrue);
      expect(isMyLedgerEntry(t, localParticipantIdFor: (j) => 'p2'), isFalse);
    });

    test('an unanswered trip falls back to excluding the trip expense', () {
      // A journey whose participants have not been answered resolves to null, so
      // no payer matches "me" and nobody else's spending leaks in. The
      // conservative direction, and it corrects itself on the next load.
      final t = _expense(
        100,
        ExpenseCategory.food,
        journeyId: 'trip-1',
        paidByParticipantId: 'p1',
      );
      expect(isMyLedgerEntry(t, localParticipantIdFor: (j) => null), isFalse);
    });

    test('myLedgerOf applies the same rule to a list', () {
      final items = [
        _expense(10, ExpenseCategory.food),
        _expense(
          20,
          ExpenseCategory.food,
          journeyId: 'trip-1',
          paidByParticipantId: 'sita',
        ),
        _expense(
          30,
          ExpenseCategory.food,
          journeyId: 'trip-1',
          paidByParticipantId: 'me',
        ),
      ];
      final mine = myLedgerOf(items, localParticipantIdFor: alwaysMe);
      expect(mine.map((t) => t.amount), [10, 30]);
    });
  });

  group('the provider knows who "me" is', () {
    test('it reads localParticipantId off the journeys', () async {
      final journeys = JourneyProvider();
      addTearDown(journeys.dispose);
      await journeys.initialize();
      await journeys.startJourney(
        destination: 'Pokhara',
        origin: 'Kathmandu',
        plannedStart: DateTime(2024, 5, 1),
      );
      final trip = journeys.journeys.first;
      await journeys.setLocalParticipant(trip.id, 'me');

      final provider = TransactionProvider();
      await provider.initialize();

      final mine = _expense(
        100,
        ExpenseCategory.food,
        journeyId: trip.id,
        paidByParticipantId: 'me',
      );
      final theirs = _expense(
        100,
        ExpenseCategory.food,
        journeyId: trip.id,
        paidByParticipantId: 'sita',
      );
      await provider.addTransaction(mine);
      await provider.addTransaction(theirs);

      final index = provider.spendIndex();
      expect(index.total, 100);
      expect(index.forJourney(trip.id), 100);
    });

    test('setLocalParticipant corrects the ledger without a reload', () async {
      // The user answers "which one are you?" long after the expenses exist, so
      // the ledger has to be able to change its mind in place.
      final provider = TransactionProvider();
      await provider.loadTransactionsForMonth(2024, 5);
      await provider.addTransaction(
        _expense(
          100,
          ExpenseCategory.food,
          date: DateTime(2024, 5, 4),
          journeyId: 'trip-1',
          paidByParticipantId: 'me',
        ),
      );

      // Nobody has answered yet, so the trip expense is conservatively excluded.
      expect(provider.spendIndex(anchor: DateTime(2024, 5)).total, 0);

      provider.setLocalParticipant('trip-1', 'me');
      expect(provider.spendIndex(anchor: DateTime(2024, 5)).total, 100);

      provider.setLocalParticipant('trip-1', null);
      expect(provider.spendIndex(anchor: DateTime(2024, 5)).total, 0);
    });
  });
}
