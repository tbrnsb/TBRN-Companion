import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daily_companion/providers/journey_provider.dart';
import 'package:daily_companion/services/storage_service.dart';

import 'visual_smoke_test.dart' show initTestStorage;

/// `completeJourney` used to answer an unknown id with the ACTIVE journey.
///
/// The `orElse` fell back to `_activeJourney`, so any id that matched nothing
/// — a screen that rebuilt, a trip already completed elsewhere, a trip that
/// has since been deleted — completed whichever trip happened to be running,
/// and completed it silently. The caller asked to end one trip and a different
/// one ended.
///
/// The rule these tests pin: an id that matches no journey changes nothing.
void main() {
  setUpAll(() async {
    await initTestStorage();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService().clear();
  });

  test(
    'an unknown id leaves the active journey running and untouched',
    () async {
      final journeys = JourneyProvider();
      addTearDown(journeys.dispose);
      await journeys.initialize();

      final active = await journeys.startJourney(
        origin: 'Kathmandu',
        destination: 'Pokhara',
      );

      await journeys.completeJourney('no-such-trip');

      expect(
        journeys.activeJourney,
        isNotNull,
        reason:
            'completing a trip that does not exist must not end the trip that '
            'happens to be running',
      );
      expect(journeys.activeJourney!.id, active.id);
      expect(journeys.activeJourney!.completed, isFalse);

      final stored = journeys.getJourneyById(active.id);
      expect(stored, isNotNull);
      expect(
        stored!.completed,
        isFalse,
        reason: 'nothing was written for an id that matched no journey',
      );
      expect(stored.endTime, isNull);
      expect(journeys.completedJourneys, 0);
    },
  );

  test('an unknown id writes nothing to storage either', () async {
    final journeys = JourneyProvider();
    addTearDown(journeys.dispose);
    await journeys.initialize();
    await journeys.startJourney(origin: 'Kathmandu', destination: 'Pokhara');

    await journeys.completeJourney('no-such-trip');

    // Re-read from storage rather than from the provider's own list, so a
    // fix that only skipped the in-memory update is caught.
    final reloaded = JourneyProvider();
    addTearDown(reloaded.dispose);
    await reloaded.initialize();

    expect(reloaded.totalJourneys, 1);
    expect(reloaded.completedJourneys, 0);
    expect(reloaded.activeJourney, isNotNull);
  });

  test('a real id still completes that journey', () async {
    // The guard must not over-correct: the ordinary path — end the trip you
    // are looking at — has to keep working.
    final journeys = JourneyProvider();
    addTearDown(journeys.dispose);
    await journeys.initialize();

    final trip = await journeys.startJourney(
      origin: 'Kathmandu',
      destination: 'Pokhara',
    );

    await journeys.completeJourney(trip.id);

    expect(journeys.getJourneyById(trip.id)!.completed, isTrue);
    expect(journeys.getJourneyById(trip.id)!.endTime, isNotNull);
    expect(journeys.activeJourney, isNull);
  });
}
