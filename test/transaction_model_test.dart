import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/models/index.dart';

void main() {
  group('Transaction', () {
    test('Expense serializes and restores correctly', () {
      final expense = Expense(
        amount: 100.50,
        category: ExpenseCategory.food,
        description: 'Test expense',
        date: DateTime(2024, 1, 15),
      );

      final map = expense.toJson();
      final restored = Expense.fromJson(map);

      expect(restored.amount, 100.50);
      expect(restored.category, ExpenseCategory.food);
      expect(restored.description, 'Test expense');
      expect(restored.date, DateTime(2024, 1, 15));
      expect(restored.isExpense, isTrue);
      expect(restored.hasCoordinates, isFalse);
    });

    test('Income serializes and restores correctly', () {
      final income = Income(
        amount: 200.75,
        category: 'salary',
        description: 'Test income',
        date: DateTime(2024, 1, 20),
      );

      final map = income.toJson();
      final restored = Income.fromJson(map);

      expect(restored.amount, 200.75);
      expect(restored.category, 'salary');
      expect(restored.description, 'Test income');
      expect(restored.date, DateTime(2024, 1, 20));
      expect(restored.isIncome, isTrue);
    });

    test('Transaction.fromJson handles expense type', () {
      final expense = Expense(
        amount: 50.0,
        category: ExpenseCategory.travel,
        description: 'Trip expense',
      );

      final json = expense.toJson();
      final restored = Transaction.fromJson(json);

      expect(restored, isA<Expense>());
      expect(restored.amount, 50.0);
      expect(restored.isExpense, isTrue);
    });

    test('Transaction.fromJson handles income type', () {
      final income = Income(
        amount: 300.0,
        category: 'freelance',
        description: 'Freelance work',
      );

      final json = income.toJson();
      final restored = Transaction.fromJson(json);

      expect(restored, isA<Income>());
      expect(restored.amount, 300.0);
      expect(restored.isIncome, isTrue);
    });

    test('Transaction copyWith works for expense', () {
      final expense = Expense(
        amount: 100.0,
        category: ExpenseCategory.food,
        description: 'Original',
      );

      final updated = expense.copyWith(amount: 150.0, description: 'Updated');

      expect(updated.amount, 150.0);
      expect(updated.description, 'Updated');
    });

    test('Transaction copyWith works for income', () {
      final income = Income(
        amount: 200.0,
        category: 'salary',
        description: 'Original',
      );

      final updated = income.copyWith(amount: 250.0, description: 'Updated');

      expect(updated.amount, 250.0);
      expect(updated.description, 'Updated');
    });
  });

  group('TransactionType', () {
    test('TransactionType label is correct', () {
      expect(TransactionType.expense.label, 'Expense');
      expect(TransactionType.income.label, 'Income');
    });
  });

  group('effectiveCategoryName', () {
    test('expense reports its real category, not the literal "Expense"', () {
      final expense = Expense(
        amount: 10,
        category: ExpenseCategory.food,
        description: 'Lunch',
      );

      expect(expense.effectiveCategoryName, 'Food');
      expect(expense.effectiveCategoryName, isNot('Expense'));
    });

    test('every expense category resolves to its own label', () {
      for (final category in ExpenseCategory.values) {
        final expense = Expense(
          amount: 10,
          category: category,
          description: 'x',
        );
        expect(
          expense.effectiveCategoryName,
          CategoryRegistry.metaFor(category).name,
        );
        expect(expense.effectiveCategoryName, isNot('Expense'));
      }
    });

    test('income reports its real category, not the literal "Income"', () {
      final income = Income(
        amount: 10,
        category: 'salary',
        description: 'Payday',
      );

      expect(income.effectiveCategoryName, 'Salary');
      expect(income.effectiveCategoryName, isNot('Income'));
    });

    test('every income category resolves to its own label', () {
      for (final category in IncomeCategory.values) {
        final income = Income(
          amount: 10,
          category: category.name,
          description: 'x',
        );
        expect(
          income.effectiveCategoryName,
          CategoryRegistry.metaForIncome(category.name).name,
        );
        expect(income.effectiveCategoryName, isNot('Income'));
      }
    });

    test('custom category name wins for ExpenseCategory.other', () {
      final expense = Expense(
        amount: 10,
        category: ExpenseCategory.other,
        customCategoryName: 'Coffee',
        description: 'Flat white',
      );

      expect(expense.effectiveCategoryName, 'Coffee');
      expect(expense.categoryMeta.name, 'Coffee');
    });

    test('ExpenseCategory.other without a custom name stays "Other"', () {
      final expense = Expense(
        amount: 10,
        category: ExpenseCategory.other,
        description: 'Misc',
      );

      expect(expense.effectiveCategoryName, 'Other');
    });

    test('categoryMeta never falls through to income metadata', () {
      final expense = Expense(
        amount: 10,
        category: ExpenseCategory.travel,
        description: 'Train',
      );
      final income = Income(
        amount: 10,
        category: 'freelance',
        description: 'Gig',
      );

      expect(expense.categoryMeta.id, 'travel');
      expect(
        expense.categoryMeta.icon,
        CategoryRegistry.metaFor(ExpenseCategory.travel).icon,
      );
      expect(income.categoryMeta.id, 'freelance');
    });
  });

  group('backward compatibility', () {
    test('a payload with NO type key comes back as an Expense', () {
      // This is the migration guarantee: every record written before the
      // `type` key existed is an expense and must keep loading as one.
      final legacy = <String, dynamic>{
        'id': 'legacy-1',
        'amount': 42.0,
        'description': 'Recorded before type existed',
        'category': 'food',
        'date': DateTime(2023, 7, 4).toIso8601String(),
      };
      expect(legacy.containsKey('type'), isFalse);

      final restored = Transaction.fromJson(legacy);

      expect(restored, isA<Expense>());
      expect(restored.isExpense, isTrue);
      expect(restored.type, TransactionType.expense);
      expect(restored.id, 'legacy-1');
      expect(restored.amount, 42.0);
      expect(restored.description, 'Recorded before type existed');
      expect(restored.date, DateTime(2023, 7, 4));
      expect((restored as Expense).category, ExpenseCategory.food);
    });

    test('an unrecognised type value falls back to Expense', () {
      final restored = Transaction.fromJson(<String, dynamic>{
        'id': 'weird-1',
        'amount': 10.0,
        'type': 'not_a_real_type',
        'description': 'From a future writer',
        'category': 'gear',
        'date': DateTime(2023, 7, 4).toIso8601String(),
      });

      expect(restored, isA<Expense>());
      expect(restored.isExpense, isTrue);
    });

    test('a legacy record survives a full round trip through Expense', () {
      final legacy = <String, dynamic>{
        'id': 'legacy-2',
        'amount': 7.5,
        'description': 'Legacy',
        'category': 'travel',
        'locationId': 'place-1',
        'date': DateTime(2023, 7, 4).toIso8601String(),
      };

      final once = Transaction.fromJson(legacy);
      final twice = Transaction.fromJson(once.toJson());

      expect(twice, isA<Expense>());
      expect(twice.id, 'legacy-2');
      expect(twice.amount, 7.5);
      expect((twice as Expense).category, ExpenseCategory.travel);
      expect(twice.locationId, 'place-1');
    });
  });

  group('createdAt', () {
    test('is preserved across a JSON round trip', () {
      final created = DateTime(2024, 3, 4, 5, 6, 7);
      final expense = Expense(
        amount: 10,
        category: ExpenseCategory.food,
        description: 'x',
        date: DateTime(2024, 3, 4),
        createdAt: created,
      );

      expect(Expense.fromJson(expense.toJson()).createdAt, created);
    });

    test('is preserved across income copyWith', () {
      final created = DateTime(2024, 3, 4, 5, 6, 7);
      final income = Income(
        amount: 10,
        category: 'salary',
        description: 'x',
        createdAt: created,
      );

      final updated = income.copyWith(amount: 20);

      expect(updated.amount, 20);
      expect(updated.createdAt, created);
    });

    test('is preserved across expense copyWith', () {
      final created = DateTime(2024, 3, 4, 5, 6, 7);
      final expense = Expense(
        amount: 10,
        category: ExpenseCategory.gear,
        description: 'x',
        createdAt: created,
      );

      expect(expense.copyWith(amount: 20).createdAt, created);
    });

    test('defaults to now when not supplied', () {
      final before = DateTime.now();
      final expense = Expense(
        amount: 10,
        category: ExpenseCategory.gear,
        description: 'x',
      );

      expect(expense.createdAt.isBefore(before), isFalse);
    });

    test('a record without createdAt still loads', () {
      final restored = Expense.fromJson(<String, dynamic>{
        'id': 'old',
        'amount': 5.0,
        'description': 'no createdAt',
        'category': 'food',
        'date': DateTime(2022, 1, 1).toIso8601String(),
      });

      expect(restored.id, 'old');
    });
  });
}
