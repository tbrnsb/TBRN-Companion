import 'package:flutter_test/flutter_test.dart';

import 'package:daily_companion/models/expense_category_meta.dart';
import 'package:daily_companion/models/location.dart';
import 'package:daily_companion/models/transaction.dart';
import 'package:daily_companion/services/location_insight_service.dart';

/// The rules behind "save where you spend": the radius, the cluster threshold,
/// and that income counts as well as expense.
void main() {
  group('a checkpoint radius', () {
    // The default decides how bold a claim every place the user never thinks
    // about makes, so it is a decision and not an arbitrary 100.
    test('a new place defaults to 50 m', () {
      final place = Location(
        name: 'Corner shop',
        latitude: 27.7,
        longitude: 85.3,
        description: '',
      );

      expect(place.radiusMeters, 50.0);
      expect(Location.defaultRadiusMeters, 50.0);
    });

    test('a stored place with no radius gets the default, not 100', () {
      // The read path used to hard-code 100, which is how a record written
      // before the field existed silently became a 100 m place.
      final restored = Location.fromJson({
        'id': 'a',
        'name': 'Old place',
        'latitude': 27.7,
        'longitude': 85.3,
        'description': '',
        'createdAt': '2026-01-01T00:00:00.000',
        'updatedAt': '2026-01-01T00:00:00.000',
      });

      expect(restored.radiusMeters, Location.defaultRadiusMeters);
    });

    test('it can be raised up to 200 m', () {
      final wide = Location(
        name: 'Big market',
        latitude: 27.7,
        longitude: 85.3,
        description: '',
        radiusMeters: 200,
      );

      expect(wide.radiusMeters, 200.0);
      expect(Location.maxRadiusMeters, 200.0);
    });

    test('beyond 200 m is refused rather than silently reduced', () {
      // Clamped, so a 5 km "place" cannot be saved and then quietly behave as
      // 200 m while the field still reads 5000.
      final silly = Location(
        name: 'Whole district',
        latitude: 27.7,
        longitude: 85.3,
        description: '',
        radiusMeters: 5000,
      );

      expect(silly.radiusMeters, Location.maxRadiusMeters);
    });

    test('a hand-edited record outside the range is clamped on read', () {
      final restored = Location.fromJson({
        'id': 'b',
        'name': 'Hand edited',
        'latitude': 27.7,
        'longitude': 85.3,
        'description': '',
        'radiusMeters': 100000,
        'createdAt': '2026-01-01T00:00:00.000',
        'updatedAt': '2026-01-01T00:00:00.000',
      });

      expect(restored.radiusMeters, Location.maxRadiusMeters);
    });

    test('the radius is what decides "inside this place"', () {
      // ~111 m apart in latitude, which is just over 100 m and well under 200 m.
      final place = Location(
        name: 'Radius test',
        latitude: 27.7100,
        longitude: 85.3000,
        description: '',
      );

      expect(place.isWithinGeofence(27.7100, 85.3000), isTrue);
      // Inside 50 m, outside 200 m.
      expect(place.isWithinGeofence(27.7110, 85.3000), isFalse);

      final wide = place.copyWith(radiusMeters: 200);
      expect(wide.isWithinGeofence(27.7110, 85.3000), isTrue);
    });
  });

  group('clustering repeated visits to one spot', () {
    // Four distinct days at the same coordinates. The threshold is 4: low
    // enough to notice a routine forming, high enough that one lunch out is not
    // a suggestion to dismiss.
    List<Transaction> at({
      required int days,
      double lat = 27.7100,
      double lng = 85.3000,
    }) {
      return [
        for (var i = 0; i < days; i++)
          Expense(
            amount: 100,
            category: ExpenseCategory.food,
            description: 'Lunch $i',
            latitude: lat,
            longitude: lng,
            date: DateTime(2026, 10, 1 + i),
          ),
      ];
    }

    test('the threshold is four transactions', () {
      expect(LocationInsightService.visitThreshold, 4);
    });

    test('three visits are not enough', () {
      final found = LocationInsightService.findFrequentLocations(
        transactions: at(days: 3),
        savedLocations: const [],
      );

      expect(found, isEmpty);
    });

    test('four visits at one spot are', () {
      final found = LocationInsightService.findFrequentLocations(
        transactions: at(days: 4),
        savedLocations: const [],
      );

      expect(found, hasLength(1));
      expect(found.single.transactionCount, 4);
    });

    test('FOUR TRANSACTIONS ON ONE DAY DO COUNT — this was the bug', () {
      // The reported failure: five expenses recorded in one sitting at an
      // unsaved spot, and no prompt. The threshold was compared against
      // DISTINCT DAYS, so one day could never satisfy a threshold of four.
      //
      // "You have been spending here a lot" is a claim about how much you have
      // spent there, not about how spread out you were about it.
      final oneSitting = [
        for (var i = 0; i < 4; i++)
          Expense(
            amount: 100,
            category: ExpenseCategory.food,
            description: 'Item $i',
            latitude: 27.7100,
            longitude: 85.3000,
            date: DateTime(2026, 10, 1, 10, 15 + i),
          ),
      ];

      final found = LocationInsightService.findFrequentLocations(
        transactions: oneSitting,
        savedLocations: const [],
      );

      expect(found, hasLength(1));
      expect(found.single.transactionCount, 4);
      // The day spread is still REPORTED, so "one visit where you bought four
      // things" remains visible in the data — it just no longer silences the
      // prompt.
      expect(found.single.dayCount, 1);
    });

    test('three transactions are not enough even across three days', () {
      final found = LocationInsightService.findFrequentLocations(
        transactions: at(days: 3),
        savedLocations: const [],
      );

      expect(found, isEmpty);
    });

    test('a spot already covered by a saved place is not suggested', () {
      // The whole point is to name a place the user has NOT named. Offering to
      // save one they already saved is the app not reading its own data.
      final saved = Location(
        name: 'Lunch place',
        latitude: 27.7100,
        longitude: 85.3000,
        description: '',
      );

      final found = LocationInsightService.findFrequentLocations(
        transactions: at(days: 6),
        savedLocations: [saved],
      );

      expect(found, isEmpty);
    });

    test('INCOME counts toward the cluster too', () {
      // This is the gap that made a place you are paid at repeatedly invisible.
      // Both directions carry coordinates now, so a routine that is mostly
      // income has to reach the threshold exactly as a spending one does.
      final mixed = <Transaction>[
        for (var i = 0; i < 3; i++)
          Expense(
            amount: 100,
            category: ExpenseCategory.food,
            description: 'Lunch $i',
            latitude: 27.7100,
            longitude: 85.3000,
            date: DateTime(2026, 10, 1 + i),
          ),
        // Three income on DAYS THE EXPENSES DO NOT USE, so the visit count is
        // six distinct days and cannot be confused with three.
        for (var i = 0; i < 3; i++)
          Income(
            amount: 5000,
            category: 'salary',
            description: 'Payday $i',
            latitude: 27.7100,
            longitude: 85.3000,
            date: DateTime(2026, 10, 10 + i),
          ),
      ];

      final found = LocationInsightService.findFrequentLocations(
        transactions: mixed,
        savedLocations: const [],
      );

      expect(found, hasLength(1));
      expect(found.single.transactionCount, 6);
      expect(found.single.dayCount, 6);
      // The total is money MOVED, not money spent: 300 out, 15000 in.
      expect(found.single.totalSpent, 15300);
    });

    test('a transaction with no coordinates cannot join a cluster', () {
      final withGaps = <Transaction>[
        ...at(days: 4),
        Expense(
          amount: 999,
          category: ExpenseCategory.food,
          description: 'No fix on this one',
          date: DateTime(2026, 10, 9),
        ),
      ];

      final found = LocationInsightService.findFrequentLocations(
        transactions: withGaps,
        savedLocations: const [],
      );

      expect(found, hasLength(1));
      // The coordinate-less record is not in the money either.
      expect(found.single.totalSpent, 400);
    });
  });

  group('matching a fix to a saved place', () {
    final home = Location(
      id: 'home',
      name: 'Home',
      latitude: 27.7100,
      longitude: 85.3000,
      description: '',
    );

    test('a fix inside the radius matches', () {
      final match = LocationInsightService.suggestCheckpoint(
        [home],
        27.71005,
        85.30005,
      );

      expect(match?.id, 'home');
    });

    test('a fix well outside does not', () {
      final match = LocationInsightService.suggestCheckpoint(
        [home],
        27.7300,
        85.3200,
      );

      expect(match, isNull);
    });

    test('the nearest of several overlapping places wins', () {
      // Overlapping radii must resolve to the place the user is actually
      // standing in, not to whichever happens to be earlier in the list. Both
      // radii cover the point; only one is the nearer.
      final far = Location(
        id: 'far',
        name: 'Far',
        latitude: 27.7200,
        longitude: 85.3000,
        description: '',
        radiusMeters: 200,
      );
      final near = Location(
        id: 'near',
        name: 'Near',
        latitude: 27.7100,
        longitude: 85.3000,
        description: '',
        radiusMeters: 200,
      );

      final match = LocationInsightService.suggestCheckpoint(
        [far, near],
        27.71001,
        85.30001,
      );

      expect(match?.id, 'near');
    });
  });
}
