import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/models/journey.dart';

void main() {
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
