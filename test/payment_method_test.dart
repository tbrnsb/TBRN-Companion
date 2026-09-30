import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/models/index.dart';

/// A date the fixtures all share, so nothing depends on the clock.
final _day = DateTime(2024, 5, 4, 13, 30);

Expense _expense({PaymentMethod? paid, String description = 'Lunch'}) {
  return Expense(
    amount: 250,
    category: ExpenseCategory.food,
    description: description,
    paymentMethod: paid,
    date: _day,
  );
}

void main() {
  group('how an expense was paid', () {
    test('round-trips through storage', () {
      for (final method in PaymentMethod.values) {
        final restored = Expense.fromJson(_expense(paid: method).toJson());
        expect(restored.paymentMethod, method, reason: method.name);
      }
    });

    test('is stored by name, not by index', () {
      // Reordering the enum must not change what a saved record means.
      expect(
        _expense(paid: PaymentMethod.online).toJson()['paymentMethod'],
        'online',
      );
      expect(
        _expense(paid: PaymentMethod.cash).toJson()['paymentMethod'],
        'cash',
      );
    });

    test('a record written before the field existed loads as unknown', () {
      // The migration story for existing data: the key is simply absent.
      final restored = Expense.fromJson({
        'id': 'old',
        'amount': 100,
        'category': 'food',
        'description': 'Old lunch',
        'date': _day.toIso8601String(),
        'createdAt': _day.toIso8601String(),
      });

      expect(restored.paymentMethod, isNull);
    });

    test('an unrecognised stored value is treated as unknown, not a crash', () {
      // A record written by a future build must still load.
      final restored = Expense.fromJson({
        'id': 'future',
        'amount': 100,
        'category': 'food',
        'description': 'Wallet',
        'paymentMethod': 'crypto',
        'date': _day.toIso8601String(),
        'createdAt': _day.toIso8601String(),
      });

      expect(restored.paymentMethod, isNull);
    });

    test('copyWith keeps the method', () {
      final edited = _expense(paid: PaymentMethod.cash).copyWith(amount: 300);
      expect(edited.paymentMethod, PaymentMethod.cash);
      expect(edited.amount, 300);
    });
  });

  group('the payment method itself', () {
    test('is cash or online, and nothing else', () {
      // Several accounts/wallets was considered and deliberately not built, so
      // the set of answers is asserted: adding a wallet would fail here.
      expect(PaymentMethod.values, [PaymentMethod.cash, PaymentMethod.online]);
    });

    test('has readable labels', () {
      expect(PaymentMethod.cash.label, 'Cash');
      expect(PaymentMethod.online.label, 'Online');
    });

    test('reads a stored name, ignoring an unknown one', () {
      expect(PaymentMethodX.fromName('cash'), PaymentMethod.cash);
      expect(PaymentMethodX.fromName('online'), PaymentMethod.online);
      expect(PaymentMethodX.fromName('CASH'), isNull);
      expect(PaymentMethodX.fromName(null), isNull);
      expect(PaymentMethodX.fromName(''), isNull);
    });
  });

  group('income carries it too', () {
    test('an income round-trips its method', () {
      final income = Income(
        amount: 5000,
        category: 'allowance',
        description: 'Monthly',
        paymentMethod: PaymentMethod.online,
        date: _day,
      );
      final restored = Income.fromJson(income.toJson());

      expect(restored.paymentMethod, PaymentMethod.online);
      expect(restored.category, 'allowance');
    });

    test('an old income with no method still loads', () {
      final restored = Income.fromJson({
        'id': 'old',
        'amount': 5000,
        'type': 'income',
        'category': 'salary',
        'description': 'Salary',
        'date': _day.toIso8601String(),
        'createdAt': _day.toIso8601String(),
      });

      expect(restored.paymentMethod, isNull);
    });
  });
}
