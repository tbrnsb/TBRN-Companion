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
}
