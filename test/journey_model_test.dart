import 'package:flutter_test/flutter_test.dart';
import 'package:daily_companion/models/journey.dart';

void main() {
  group('duration', () {
    // The duration used to return 0 unless endTime was set, so an ACTIVE trip
    // read as "0m" -- a precise-looking wrong answer. It also meant the running
    // total across journeys under-reported by however long the user was away.
    test('a running trip counts up rather than reading zero', () {
      final journey = Journey(
        destination: 'Pokhara',
        origin: 'Kathmandu',
        startTime: DateTime.now().subtract(
          const Duration(hours: 6, minutes: 15),
        ),
      );

      expect(journey.isRunning, isTrue);
      expect(journey.durationMinutes, greaterThanOrEqualTo(375));
      expect(journey.durationText, isNot('0m'));
    });

    test('a trip that has just started says so', () {
      final journey = Journey(
        destination: 'Pokhara',
        origin: 'Kathmandu',
        startTime: DateTime.now(),
      );

      expect(journey.durationText, 'Just started');
    });

    test('a finished trip is no longer running', () {
      final journey = Journey(
        destination: 'Pokhara',
        origin: 'Kathmandu',
        startTime: DateTime(2026, 8, 15, 8, 0),
        endTime: DateTime(2026, 8, 16, 18, 30),
        completed: true,
      );

      expect(journey.isRunning, isFalse);
      expect(journey.durationMinutes, 34 * 60 + 30);
      expect(journey.durationText, '1d 10h 30m');
    });

    test('days are used, so a week does not read as 168h', () {
      final journey = Journey(
        destination: 'Somewhere',
        origin: 'Here',
        startTime: DateTime(2026, 8, 1, 9, 0),
        endTime: DateTime(2026, 8, 8, 11, 0),
        completed: true,
      );

      expect(journey.durationText, '7d 2h');
    });

    test('a whole number of hours carries no trailing 0m', () {
      final journey = Journey(
        destination: 'Somewhere',
        origin: 'Here',
        startTime: DateTime(2026, 8, 1, 9, 0),
        endTime: DateTime(2026, 8, 1, 15, 0),
        completed: true,
      );

      expect(journey.durationText, '6h');
    });

    test('minutes are printed when nothing larger carries information', () {
      final journey = Journey(
        destination: 'Somewhere',
        origin: 'Here',
        startTime: DateTime(2026, 8, 1, 9, 0),
        endTime: DateTime(2026, 8, 1, 9, 45),
        completed: true,
      );

      expect(journey.durationText, '45m');
    });
  });

  group('Journey', () {
    test('serializes and restores a completed journey correctly', () {
      final journey = Journey(
        destination: 'Paris',
        origin: 'Kathmandu',
        notes: 'Weekend trip',
        items: const ['Passport', 'Charger'],
        startTime: DateTime(2026, 8, 15, 8, 0),
        endTime: DateTime(2026, 8, 16, 18, 30),
        completed: true,
      );

      final map = journey.toJson();
      final restored = Journey.fromJson(map);

      expect(restored.destination, 'Paris');
      expect(restored.origin, 'Kathmandu');
      expect(restored.notes, 'Weekend trip');
      expect(restored.items, ['Passport', 'Charger']);
      expect(restored.completed, isTrue);
      expect(restored.durationMinutes, 2070);
    });
  });
}
