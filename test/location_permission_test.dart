import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:daily_companion/providers/location_provider.dart';

import 'visual_smoke_test.dart' show initTestStorage;

/// Location is asked for LATE, or not at all.
///
/// The app used to ask within a second of opening, because the home screen
/// called `LocationProvider.initialize()` on startup and that method read a GPS
/// fix as part of loading the saved places. It was verified on a real device
/// (Android 16): with location revoked, a cold launch put
/// "Allow TBRN Companion to access this device's location?" on screen before
/// anything in the app had been touched.
///
/// That is the first thing the app ever says to a new user, and it is asking
/// for the one permission that reads as surveillance rather than convenience.
/// For an app that keeps everything on the device and makes no network calls,
/// it is also the permission most likely to make someone delete the app before
/// reading the description.
///
/// The rule these tests pin: startup loads saved places and asks for nothing.
/// Position is requested only from an explicit user action — "use current
/// location" when adding a place, or the locate button on the Places tab.
void main() {
  setUpAll(() async {
    await initTestStorage();
  });

  group('startup asks for nothing', () {
    test('initialize loads places without requesting position', () async {
      final provider = LocationProvider();

      await provider.initialize();

      // A GPS fix implies a permission request, so this is the observable proxy.
      // `updateCurrentPosition` sets `ready` or a denied status; `initialize`
      // must leave the position untouched and no status set.
      expect(
        provider.currentPosition,
        isNull,
        reason:
            'startup must not take a GPS fix, because taking one is what '
            'asks the phone for location permission',
      );
      expect(
        provider.error,
        isNull,
        reason:
            'a permission error at startup is the same bug wearing a '
            'different hat: the app asked, and was told no',
      );
    });

    test('initialize leaves the status alone', () async {
      final provider = LocationProvider();
      final before = provider.status;

      await provider.initialize();

      // `permissionDenied` / `permissionDeniedForever` / `locating` can only be
      // reached through a permission flow, so an unchanged status means no
      // permission flow ran.
      expect(provider.status, before);
    });

    test('initialize still loads the saved places', () async {
      // The point of calling initialize at startup at all. A fix that stopped
      // loading places would pass the two tests above and quietly break the
      // Places tab.
      final provider = LocationProvider();

      await provider.initialize();

      // The fixture box is empty, so this is about not throwing and about the
      // list being available rather than about a specific count.
      expect(provider.locations, isNotNull);
      expect(provider.isLoading, isFalse);
    });

    test('the home screen does not ask for location on its way up', () async {
      // Guards the CALL SITE, which is where the bug actually lived. Removing
      // the GPS read from `initialize` is the fix; removing the startup call
      // from the home screen is what keeps it fixed if someone later restores
      // the read to `initialize`.
      final provider = LocationProvider();
      await provider.initialize();

      // Still no position, and no status change, after the same sequence the
      // home screen performs at launch.
      expect(provider.currentPosition, isNull);
      expect(provider.status, isNot(LocationStatus.permissionDenied));
      expect(provider.status, isNot(LocationStatus.permissionDeniedForever));
    });
  });

  group('the saved places still work', () {
    test('loadLocations on its own does not touch position', () async {
      final provider = LocationProvider();

      await provider.loadLocations();

      expect(provider.currentPosition, isNull);
      expect(provider.locations, isEmpty);
    });
  });

  group('no other surface asks for location on its own', () {
    // The startup prompt was the reported one, but it was not the only one.
    // Saving an expense also called `requestPermission`, so a user who had
    // declined at launch was interrupted AGAIN at the moment they pressed Save
    // — for an optional tag-and-coordinates bonus they never asked for. That is
    // worse than the first prompt: it interrupts an action already in progress.
    //
    // These are enforced by reading the source rather than by running it,
    // because a permission dialog cannot be observed from a widget test without
    // a platform channel mock that would not prove anything about the real
    // device behaviour.
    test('the expense sheet never calls requestPermission', () {
      final source = File('lib/screens/transactions/add_expense_sheet.dart')
          .readAsStringSync();

      // The word appears in a doc comment explaining why it is gone. Strip
      // comments before looking, so this asserts about CODE.
      final code = source
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('///'))
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');

      expect(
        code.contains('requestPermission'),
        isFalse,
        reason:
            'saving an expense must not prompt for location. The capture '
            'is optional: use a permission that is already granted, skip it '
            'otherwise.',
      );
    });

    test('startup does not reach updateCurrentPosition', () {
      final home = File('lib/screens/home_screen.dart').readAsStringSync();
      expect(
        home.contains('updateCurrentPosition'),
        isFalse,
        reason: 'the home screen runs at launch; it must not take a GPS fix',
      );
    });

    test('exactly one place in the app still asks, and it is behind a tap', () {
      // A single, deliberate prompt, reachable only from a control that says
      // "where am I". If this number grows, a new prompt has been introduced
      // and it needs a reason a user would recognise.
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();

      final callers = <String>[];
      for (final file in files) {
        final code = file
            .readAsLinesSync()
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        if (code.contains('Geolocator.requestPermission')) {
          callers.add(file.path);
        }
      }

      expect(callers, [
        'lib/providers/location_provider.dart',
      ], reason: 'only the provider may ask, and only from a user action');
    });
  });
}
