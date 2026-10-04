import 'package:flutter_test/flutter_test.dart';

import 'package:daily_companion/models/expense_category_meta.dart';
import 'package:daily_companion/models/transaction.dart';

/// Location on BOTH kinds of transaction, and the promise that adding it to
/// income does not disturb a single record already on disk.
void main() {
  group('income carries a location', () {
    // The gap this closes: `locationId`, `latitude`, `longitude` and
    // `locationCapturedAt` lived on Expense alone, so income — money arriving at
    // a place — recorded nothing about where. Every read went through extension
    // getters that returned null for half the records in the app.
    test('it round-trips through storage', () {
      final income = Income(
        amount: 5000,
        category: 'salary',
        description: 'Payday',
        locationId: 'home',
        latitude: 27.7172,
        longitude: 85.3240,
        locationCapturedAt: DateTime(2026, 10, 4, 9, 30),
        date: DateTime(2026, 10, 4),
      );

      final restored = Transaction.fromJson(income.toJson()) as Income;

      expect(restored.locationId, 'home');
      expect(restored.latitude, 27.7172);
      expect(restored.longitude, 85.3240);
      expect(restored.locationCapturedAt, DateTime(2026, 10, 4, 9, 30));
    });

    test('a record written before these fields existed still loads', () {
      // MIGRATION SAFETY: the whole point of moving the fields up to the base
      // class. This is the exact JSON an older build wrote, with no location keys
      // at all. It must deserialise into a usable income, not throw.
      final legacy = <String, dynamic>{
        'id': 'abc',
        'amount': 150.0,
        'type': 'income',
        'category': 'freelance',
        'description': 'A gig',
        'customCategoryName': null,
        'paymentMethod': null,
        'date': '2026-01-05T00:00:00.000',
        'createdAt': '2026-01-05T00:00:00.000',
        'deletedAt': null,
      };

      final restored = Transaction.fromJson(legacy) as Income;

      expect(restored.amount, 150.0);
      expect(restored.category, 'freelance');
      expect(restored.locationId, isNull);
      expect(restored.hasCoordinates, isFalse);
    });

    test('copyWith can clear a location without touching the rest', () {
      final income = Income(
        amount: 100,
        category: 'bonus',
        description: 'Keep me',
        latitude: 1,
        longitude: 2,
        locationCapturedAt: DateTime(2026, 1, 1),
      );

      final cleared = income.copyWith(clearCoordinates: true);

      expect(cleared.hasCoordinates, isFalse);
      expect(cleared.locationCapturedAt, isNull);
      // The rest of the record is untouched.
      expect(cleared.description, 'Keep me');
      expect(cleared.amount, 100);
    });
  });

  group('an expense is unaffected by the move', () {
    test('it still round-trips a location', () {
      // Moving the declaration up a class hierarchy must not move a byte on the
      // wire. Expense already wrote these keys at the top level of the same map.
      final expense = Expense(
        amount: 500,
        category: ExpenseCategory.food,
        description: 'Dinner',
        locationId: 'cafe',
        latitude: 28.2096,
        longitude: 83.9856,
        locationCapturedAt: DateTime(2026, 10, 4, 20, 15),
        date: DateTime(2026, 10, 4),
      );

      final json = expense.toJson();
      // Same KEY NAMES as before the move.
      expect(json.containsKey('latitude'), isTrue);
      expect(json.containsKey('longitude'), isTrue);
      expect(json.containsKey('locationId'), isTrue);
      expect(json.containsKey('locationCapturedAt'), isTrue);

      final restored = Transaction.fromJson(json) as Expense;
      expect(restored.locationId, 'cafe');
      expect(restored.latitude, 28.2096);
      expect(restored.hasCoordinates, isTrue);
    });

    test('an expense written by the older shape still loads', () {
      // The literal JSON an older build persisted for an expense.
      final legacy = <String, dynamic>{
        'id': 'old-1',
        'amount': 1250.50,
        'type': 'expense',
        'category': 'travel',
        'description': 'Bus to the trailhead',
        'customCategoryName': null,
        'paymentMethod': 'cash',
        'locationId': null,
        'latitude': 28.2096,
        'longitude': 83.9856,
        'locationCapturedAt': '2026-09-01T08:00:00.000',
        'journeyId': null,
        'paidByParticipantId': null,
        'date': '2026-09-01T00:00:00.000',
        'createdAt': '2026-09-01T00:00:00.000',
        'deletedAt': null,
      };

      final restored = Transaction.fromJson(legacy) as Expense;

      expect(restored.amount, 1250.50);
      expect(restored.paymentMethod, PaymentMethod.cash);
      expect(restored.latitude, 28.2096);
      expect(restored.locationCapturedAt, DateTime(2026, 9, 1, 8));
    });

    test('an integer latitude on disk survives the numeric widening', () {
      // Hand-edited JSON and some CSV imports produce whole numbers. `(x as num)`
      // rather than `as double`, because one of those records failing to load
      // takes the whole month with it.
      final legacy = <String, dynamic>{
        'id': 'int-1',
        'amount': 100,
        'type': 'expense',
        'category': 'food',
        'description': 'Whole numbers',
        'date': '2026-09-01T00:00:00.000',
        'createdAt': '2026-09-01T00:00:00.000',
        'latitude': 28,
        'longitude': 84,
      };

      final restored = Transaction.fromJson(legacy) as Expense;

      expect(restored.latitude, 28.0);
      expect(restored.longitude, 84.0);
    });
  });

  group('hasLocation is not the same claim as hasCoordinates', () {
    test('a capture attempt with no fix is not a location', () {
      final attempted = Expense(
        amount: 10,
        category: ExpenseCategory.food,
        description: 'No fix',
        locationCapturedAt: DateTime(2026, 10, 4),
      );

      // "We tried and timed out" must not read as "we know where this was".
      expect(attempted.hasCoordinates, isFalse);
      expect(attempted.hasLocation, isTrue);
    });

    test('a record with nothing location-shaped has neither', () {
      final plain = Expense(
        amount: 10,
        category: ExpenseCategory.food,
        description: 'Nothing',
      );

      expect(plain.hasCoordinates, isFalse);
      expect(plain.hasLocation, isFalse);
    });
  });
}
