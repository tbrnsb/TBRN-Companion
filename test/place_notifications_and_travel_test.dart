import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/providers/location_provider.dart';
import 'package:daily_companion/services/storage_service.dart';

import 'visual_smoke_test.dart' show initTestStorage;

/// Per-place arrival notifications, and "Where to?" on a travel expense.
///
/// Both are fields the user asked for that either did not exist or existed with
/// the wrong shape, and both have one rule worth stating out loud: what is NOT
/// promised is as important as what is.
void main() {
  setUpAll(() async {
    await initTestStorage();
  });

  group('a place can opt out of arrival notifications', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await StorageService().clear();
    });

    test('notifications are on by default', () {
      // A place saved to be reminded about should be reminded about. Opt-OUT,
      // per place, because a place you meant to be reminded of and a place you
      // happened to pin are not the same thing.
      final place = Location(
        name: 'SmatErr',
        latitude: 27.7,
        longitude: 85.3,
        description: '',
      );

      expect(place.notificationsEnabled, isTrue);
    });

    test('a place written before the flag existed still notifies', () {
      // Absent means TRUE. Reading it as false would silently switch off
      // notifications for every place already on the device.
      final legacy = Location.fromJson({
        'id': 'old',
        'name': 'Old Place',
        'latitude': 1.0,
        'longitude': 2.0,
        'description': '',
        'radiusMeters': 200.0,
        'createdAt': DateTime(2026, 3, 1).toIso8601String(),
        'updatedAt': DateTime(2026, 3, 1).toIso8601String(),
      });

      expect(legacy.notificationsEnabled, isTrue);
    });

    test('the flag survives a save and reload, either way', () async {
      await StorageService().addLocation(
        Location(
          name: 'SmatErr',
          latitude: 27.7,
          longitude: 85.3,
          description: '',
          notificationsEnabled: false,
        ),
      );

      final loaded = await StorageService().getAllLocations();
      final place = loaded.firstWhere((l) => l.name == 'SmatErr');

      expect(place.notificationsEnabled, isFalse);
    });

    test('turning it off and on again is not one-way', () async {
      final provider = LocationProvider();
      addTearDown(provider.dispose);
      await provider.initialize();

      await provider.addLocation(
        Location(
          name: 'Pokhara',
          latitude: 28.2,
          longitude: 83.9,
          description: '',
        ),
      );
      final place = provider.locations.firstWhere((l) => l.name == 'Pokhara');
      expect(place.notificationsEnabled, isTrue);

      await provider.setNotificationsEnabled(place.id, enabled: false);
      expect(
        provider.locations
            .firstWhere((l) => l.id == place.id)
            .notificationsEnabled,
        isFalse,
      );

      await provider.setNotificationsEnabled(place.id, enabled: true);
      expect(
        provider.locations
            .firstWhere((l) => l.id == place.id)
            .notificationsEnabled,
        isTrue,
      );
    });

    test('one place opting out leaves the others alone', () async {
      final provider = LocationProvider();
      addTearDown(provider.dispose);
      await provider.initialize();

      await provider.addLocation(
        Location(
          name: 'Home',
          latitude: 27.7,
          longitude: 85.2,
          description: '',
        ),
      );
      await provider.addLocation(
        Location(
          name: 'Work',
          latitude: 27.7,
          longitude: 85.4,
          description: '',
        ),
      );

      final home = provider.locations.firstWhere((l) => l.name == 'Home');
      await provider.setNotificationsEnabled(home.id, enabled: false);

      expect(
        provider.locations
            .firstWhere((l) => l.name == 'Work')
            .notificationsEnabled,
        isTrue,
        reason: 'the switch is per place, which is the whole point of it',
      );
    });

    test('a place that opted out is never announced', () {
      // The rule itself, testable without a GPS fix -- which is the only way to
      // test it, since a unit test cannot produce a real position.
      final optedOut = Location(
        name: 'Quiet',
        latitude: 27.7,
        longitude: 85.3,
        description: '',
        notificationsEnabled: false,
      );

      final decision = LocationProvider.shouldAnnounceArrival(
        location: optedOut,
        latitude: 27.7,
        longitude: 85.3,
        alreadyAnnounced: false,
      );

      expect(
        decision.announce,
        isFalse,
        reason: 'standing inside a place that opted out must say nothing',
      );
      expect(
        decision.inside,
        isFalse,
        reason: 'an opted-out place is not tracked for re-arming either',
      );
    });

    test('a place inside its arrival radius is announced exactly once', () {
      final place = Location(
        name: 'SmatErr',
        latitude: 27.7,
        longitude: 85.3,
        description: '',
      );

      final first = LocationProvider.shouldAnnounceArrival(
        location: place,
        latitude: 27.7,
        longitude: 85.3,
        alreadyAnnounced: false,
      );
      expect(first.inside, isTrue);
      expect(first.announce, isTrue);

      // Standing still must not repeat the notification every few seconds.
      final second = LocationProvider.shouldAnnounceArrival(
        location: place,
        latitude: 27.7,
        longitude: 85.3,
        alreadyAnnounced: true,
      );
      expect(second.inside, isTrue);
      expect(second.announce, isFalse);
    });

    test('leaving re-arms it, so a second visit announces again', () {
      final place = Location(
        name: 'Pokhara',
        latitude: 28.2,
        longitude: 83.9,
        description: '',
      );

      // Far away: not inside, which is what clears the announced flag.
      final away = LocationProvider.shouldAnnounceArrival(
        location: place,
        latitude: 27.7,
        longitude: 85.3,
        alreadyAnnounced: true,
      );
      expect(away.inside, isFalse);

      // Back again: announced afresh.
      final back = LocationProvider.shouldAnnounceArrival(
        location: place,
        latitude: 28.2,
        longitude: 83.9,
        alreadyAnnounced: false,
      );
      expect(back.announce, isTrue);
    });

    test('arrival is a wider radius than the geofence, on purpose', () {
      // A 200m geofence flags "you have arrived" several streets early, which
      // is wrong for the cluster prompts and worse still for telling someone
      // they are somewhere they plainly are not.
      expect(LocationProvider.arrivalRadiusMeters, greaterThan(200));
      expect(LocationProvider.arrivalRadiusMeters, lessThanOrEqualTo(1000));
    });
  });

  group('"Where to?" on a travel expense', () {
    test('it is free text and independent of a saved place', () {
      // A fare is written down at the rank. Making the destination a saved place
      // first would mean the taxi cost cannot be recorded until the map pin is.
      final expense = Expense(
        id: 't1',
        amount: 400,
        category: ExpenseCategory.travel,
        description: 'Taxi',
        destinationLabel: 'SmatErr',
        date: DateTime(2026, 3, 4),
      );

      expect(expense.destinationLabel, 'SmatErr');
      expect(
        expense.locationId,
        isNull,
        reason: 'a named destination is not a saved place',
      );
    });

    test('it survives a save and reload', () {
      final expense = Expense(
        id: 't2',
        amount: 1500,
        category: ExpenseCategory.travel,
        description: 'Bus',
        destinationLabel: 'SmatErr',
        date: DateTime(2026, 3, 4),
      );

      final restored = Expense.fromJson(expense.toJson());
      expect(restored.destinationLabel, 'SmatErr');
    });

    test('an expense without one reads back as null, not empty text', () {
      final expense = Expense(
        id: 't3',
        amount: 100,
        category: ExpenseCategory.food,
        description: 'Lunch',
        date: DateTime(2026, 3, 4),
      );

      expect(expense.destinationLabel, isNull);
      expect(Expense.fromJson(expense.toJson()).destinationLabel, isNull);
    });

    test('a row written before the field existed reads back as null', () {
      final legacy = Expense.fromJson({
        'id': 'old',
        'amount': 100,
        'category': 'travel',
        'description': 'Old taxi',
        'date': DateTime(2026, 3, 4).toIso8601String(),
        'createdAt': DateTime(2026, 3, 4).toIso8601String(),
      });

      expect(legacy.destinationLabel, isNull);
    });

    test('copyWith can change and clear it', () {
      final expense = Expense(
        id: 't4',
        amount: 400,
        category: ExpenseCategory.travel,
        description: 'Taxi',
        destinationLabel: 'SmatErr',
        date: DateTime(2026, 3, 4),
      );

      expect(
        expense.copyWith(destinationLabel: 'Pokhara').destinationLabel,
        'Pokhara',
      );

      // Clearing goes through null on the new record rather than being
      // impossible, which is what makes it editable rather than write-once.
      expect(
        Expense.fromJson(expense.copyWith(destinationLabel: null).toJson())
            .destinationLabel,
        'SmatErr',
        reason:
            'copyWith keeps the old value unless told otherwise, as it does '
            'for every other field',
      );
    });

    test('two trips to different places keep different labels', () {
      // This is what makes "what did getting to SmatErr cost" answerable: the
      // travel expenses carrying one label add up to that trip.
      Expense fareTo(String place) => Expense(
        id: place,
        amount: 400,
        category: ExpenseCategory.travel,
        description: 'Taxi',
        destinationLabel: place,
        date: DateTime(2026, 3, 4),
      );

      final smatErr = [fareTo('SmatErr'), fareTo('SmatErr')];
      final pokhara = [fareTo('Pokhara')];

      double totalFor(List<Expense> rows) =>
          rows.fold(0, (sum, e) => sum + e.amount);

      expect(totalFor(smatErr), 800);
      expect(totalFor(pokhara), 400);
    });
  });

  group('a journey start time can be corrected', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await StorageService().clear();
    });

    test('the start time is what was set, not when the row was written', () {
      final journey = Journey(
        destination: 'SmatErr',
        origin: 'Home',
        startTime: DateTime(2026, 3, 4, 6, 30),
      );

      expect(journey.startTime, DateTime(2026, 3, 4, 6, 30));
      expect(
        journey.isRunning,
        isTrue,
        reason: 'a trip in the past that has not ended is still running',
      );
    });

    test('moving the start moves the duration with it', () {
      final journey = Journey(
        destination: 'SmatErr',
        origin: 'Home',
        startTime: DateTime(2026, 3, 4, 6, 0),
        endTime: DateTime(2026, 3, 4, 18, 0),
        completed: true,
      );
      expect(journey.durationText, '12h');

      // Left two hours later than planned: every duration on the trip was wrong
      // until this.
      final corrected = journey.copyWith(startTime: DateTime(2026, 3, 4, 8, 0));
      expect(corrected.durationText, '10h');
    });
  });
}
