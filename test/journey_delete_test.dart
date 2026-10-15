import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daily_companion/providers/journey_provider.dart';
import 'package:daily_companion/services/storage_service.dart';

import 'visual_smoke_test.dart' show initTestStorage;

/// `deleteJourney` emptied the active slot but never recomputed what goes in it.
///
/// `loadJourneys`, `addJourney` and `updateJourney` all call
/// `_refreshActiveJourney()` after touching the list; `deleteJourney` only
/// nulled the slot when the deleted trip was the one running. So deleting the
/// trip in progress left NO active trip even with another genuinely running
/// one right behind it, and that one was only promoted by some unrelated write
/// afterwards — the home card, the "Heading home?" prompt and the trip
/// reminders all went quiet while a trip was under way.
///
/// The rule these tests pin: deleting the running trip hands the slot to the
/// next unfinished trip, now.
void main() {
  setUpAll(() async {
    await initTestStorage();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService().clear();
  });

  test('deleting the running trip promotes the other unfinished one', () async {
    final journeys = JourneyProvider();
    addTearDown(journeys.dispose);
    await journeys.initialize();

    // Two trips, both started and neither finished. The list is kept newest
    // first and `_refreshActiveJourney` takes the first trip that has already
    // begun, so the LATER start is the one running now.
    final older = await journeys.startJourney(
      origin: 'Kathmandu',
      destination: 'Pokhara',
      plannedStart: DateTime.now().subtract(const Duration(hours: 2)),
    );
    final newer = await journeys.startJourney(
      origin: 'Pokhara',
      destination: 'Chitwan',
      plannedStart: DateTime.now().subtract(const Duration(hours: 1)),
    );

    expect(journeys.totalJourneys, 2);
    expect(
      journeys.activeJourney?.id,
      newer.id,
      reason: 'the test is about deleting the trip that IS running',
    );

    await journeys.deleteJourney(newer.id);

    expect(
      journeys.getJourneyById(newer.id),
      isNull,
      reason: 'the trip really was deleted',
    );
    expect(
      journeys.activeJourney,
      isNotNull,
      reason:
          'another trip is still running, so the active slot may not be left '
          'empty — an empty slot means no reminders and no "Heading home?" for '
          'a trip that is under way',
    );
    expect(journeys.activeJourney!.id, older.id);
    expect(journeys.activeJourney!.completed, isFalse);
  });

  test(
    'deleting a trip that is NOT running leaves the running one alone',
    () async {
      // The fix must not over-correct: recomputing the slot on every delete has
      // to land on the same trip the slot already held.
      final journeys = JourneyProvider();
      addTearDown(journeys.dispose);
      await journeys.initialize();

      final older = await journeys.startJourney(
        origin: 'Kathmandu',
        destination: 'Pokhara',
        plannedStart: DateTime.now().subtract(const Duration(hours: 2)),
      );
      final newer = await journeys.startJourney(
        origin: 'Pokhara',
        destination: 'Chitwan',
        plannedStart: DateTime.now().subtract(const Duration(hours: 1)),
      );

      await journeys.deleteJourney(older.id);

      expect(journeys.activeJourney?.id, newer.id);
    },
  );
}
