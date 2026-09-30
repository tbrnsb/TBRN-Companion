import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/transaction_provider.dart';
import 'package:flutter_application_1/services/storage_service.dart';

import 'visual_smoke_test.dart' show initTestStorage;

Expense _expense(
  double amount,
  ExpenseCategory category, {
  String description = 'Test expense',
  DateTime? date,
  String? journeyId,
  String? paidByParticipantId,
}) {
  return Expense(
    amount: amount,
    category: category,
    description: description,
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
    await StorageService().clear();
  });

  group('TransactionSearchQuery', () {
    test('an empty query matches everything and is not "active"', () {
      const query = TransactionSearchQuery.none;
      expect(query.isEmpty, isTrue);
      expect(query.matches(_expense(100, ExpenseCategory.food)), isTrue);
    });

    test('text matching is case-insensitive and trims', () {
      const query = TransactionSearchQuery(text: '  COFFee  ');
      expect(
        query.matches(
          _expense(10, ExpenseCategory.food, description: 'Morning coffee'),
        ),
        isTrue,
      );
      expect(
        query.matches(
          _expense(10, ExpenseCategory.food, description: 'Train ticket'),
        ),
        isFalse,
      );
    });

    test('amount bounds are inclusive at both ends', () {
      const query = TransactionSearchQuery(minAmount: 100, maxAmount: 200);
      expect(query.matches(_expense(100, ExpenseCategory.food)), isTrue);
      expect(query.matches(_expense(200, ExpenseCategory.food)), isTrue);
      expect(query.matches(_expense(99.99, ExpenseCategory.food)), isFalse);
      expect(query.matches(_expense(200.01, ExpenseCategory.food)), isFalse);
    });

    test('criteria are ANDed, not ORed', () {
      const query = TransactionSearchQuery(text: 'bus', minAmount: 1000);
      // Right word, wrong amount.
      expect(
        query.matches(
          _expense(10, ExpenseCategory.travel, description: 'bus fare'),
        ),
        isFalse,
      );
      // Right amount, wrong word.
      expect(
        query.matches(
          _expense(1000, ExpenseCategory.travel, description: 'taxi'),
        ),
        isFalse,
      );
      expect(
        query.matches(
          _expense(1200, ExpenseCategory.travel, description: 'bus fare'),
        ),
        isTrue,
      );
    });

    test(
      'an empty category set means no category filter, not match-nothing',
      () {
        // Otherwise opening search and picking nothing returns zero rows, which is
        // the opposite of what a user who never touched the chips expects.
        const query = TransactionSearchQuery(categories: {});
        expect(query.matches(_expense(10, ExpenseCategory.food)), isTrue);
      },
    );

    test('a custom category name is separately selectable from its enum', () {
      // An `other` row filed as "Coffee" resolves to its own id, so filtering on
      // the enum must not pick it up and must not lump it in with `other`.
      final coffee = Expense(
        amount: 80,
        category: ExpenseCategory.other,
        customCategoryName: 'Coffee',
        description: 'Flat white',
        date: DateTime.now(),
      );
      // "Coffee" is one of the suggested types, so it keeps its own id rather
      // than collapsing to the generic custom sparkle. Read the id off the model
      // instead of hardcoding it, so the assertion is about the behaviour —
      // that it is neither `other` nor a suggested type's own bucket — and
      // survives the registry being reordered.
      expect(coffee.categoryMeta.id, isNot('other'));
      expect(
        coffee.categoryMeta.id,
        CategoryRegistry.metaFor(
          ExpenseCategory.other,
          customName: 'Coffee',
        ).id,
      );

      const byOther = TransactionSearchQuery(categories: {'other'});
      expect(byOther.matches(coffee), isFalse);

      final byName = TransactionSearchQuery(
        categories: {coffee.categoryMeta.id},
      );
      expect(byName.matches(coffee), isTrue);
    });

    test(
      'activeCriteria counts the three groups, not the individual fields',
      () {
        // A min and a max are one criterion. Reporting "2" for a single range
        // would overstate how much is being filtered.
        const query = TransactionSearchQuery(
          text: 'tea',
          minAmount: 10,
          maxAmount: 20,
          categories: {'food'},
        );
        expect(query.activeCriteria, 3);
      },
    );

    test('clearMin and clearMax take precedence over the new value', () {
      const start = TransactionSearchQuery(minAmount: 5, maxAmount: 50);
      final cleared = start.copyWith(
        minAmount: 9,
        clearMin: true,
        maxAmount: 60,
      );
      expect(cleared.minAmount, isNull);
      expect(cleared.maxAmount, 60);
    });

    test('value equality holds so the provider can skip a notify', () {
      const a = TransactionSearchQuery(text: 'x', categories: {'food'});
      const b = TransactionSearchQuery(text: 'x', categories: {'food'});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('provider search results', () {
    Future<TransactionProvider> loaded() async {
      final provider = TransactionProvider();
      await provider.loadTransactionsForMonth(2024, 5);
      await provider.addTransaction(
        _expense(
          100,
          ExpenseCategory.food,
          description: 'Lunch',
          date: DateTime(2024, 5, 3),
        ),
      );
      await provider.addTransaction(
        _expense(
          500,
          ExpenseCategory.travel,
          description: 'Train',
          date: DateTime(2024, 5, 8),
        ),
      );
      return provider;
    }

    test(
      'with no query active, results are the month under the chips',
      () async {
        final provider = await loaded();

        expect(provider.hasActiveSearch, isFalse);
        expect(provider.searchResults, hasLength(2));

        provider.filter = TransactionFilter.income;
        expect(provider.searchResults, isEmpty);
      },
    );

    test('a search total is read from the results, not recomputed', () async {
      final provider = await loaded();

      provider.search = const TransactionSearchQuery(text: 'lunch');

      // The point of reading the total off the result set: a figure shown beside
      // search results can never disagree with the rows above it.
      expect(provider.searchTotalExpenses, 100);
      expect(provider.searchTotalIncome, 0);
    });

    test('search ignores a selected day but honours the chips', () async {
      final provider = await loaded();
      provider.setSelectedDay(DateTime(2024, 5, 3));
      provider.search = const TransactionSearchQuery(text: 'train');

      // The train is on the 8th and the view is pinned to the 3rd. Search reads
      // the month, so it still finds it.
      expect(provider.searchResults, hasLength(1));
    });
  });
}
