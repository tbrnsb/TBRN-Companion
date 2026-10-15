import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/providers/journey_provider.dart';
import 'package:daily_companion/providers/location_provider.dart';
import 'package:daily_companion/providers/settings_provider.dart';
import 'package:daily_companion/providers/transaction_provider.dart';
import 'package:daily_companion/screens/locations/location_detail_screen.dart';
import 'package:daily_companion/services/notification_service.dart';
import 'package:daily_companion/services/storage_service.dart';
import 'package:daily_companion/theme/app_theme.dart';

import 'test_viewports.dart';
import 'visual_smoke_test.dart' show initTestStorage;

/// The moment somebody actually wants an alert: turning a place's "Notify when
/// I arrive" switch ON.
///
/// Before this, the ONLY place Android 13+ could ever be asked for
/// `POST_NOTIFICATIONS` was the Settings "Alerts" row. Flip this switch and
/// never visit Settings, and the toggle reads ON while the system drops every
/// arrival alert in silence. These tests drive that switch on a phone that has
/// never been asked, one that refuses, and one that has already been asked.
void main() {
  const notificationsChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const geolocatorChannel = MethodChannel('flutter.baseflow.com/geolocator');

  final calls = <MethodCall>[];
  final settingsCalls = <MethodCall>[];

  /// What `areNotificationsEnabled` says. False, because that is the state a
  /// fresh Android 13+ install is in until the permission is granted.
  var enabled = false;

  /// What the permission prompt answers.
  var grantOnRequest = true;

  setUpAll(() async {
    await initTestStorage();
    // The platform interface keeps its instance in a `late` field that only a
    // real registration fills, so the Android implementation has to be
    // installed by hand before the plugin can resolve it.
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NotificationService.resetForTesting();
    calls.clear();
    settingsCalls.clear();
    enabled = false;
    grantOnRequest = true;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'areNotificationsEnabled':
              return enabled;
            case 'requestNotificationsPermission':
              enabled = grantOnRequest;
              return grantOnRequest;
            default:
              return null;
          }
        });

    // What the SnackBar's "Settings" action talks to. The intent has no plugin
    // behind it in a test, so without this the tap would throw.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(geolocatorChannel, (call) async {
          settingsCalls.add(call);
          return true;
        });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(notificationsChannel, null);
    messenger.setMockMethodCallHandler(geolocatorChannel, null);
  });

  /// Runs [body] as if it were running on Android.
  ///
  /// The plugin resolves its implementation from the target platform and this
  /// machine reports linux — a platform with nothing to ask — so the override
  /// has to be on while the screen is built and tapped. It must be OFF again
  /// before the test body ends: flutter_test checks every foundation debug
  /// variable before `tearDown` runs, and a leftover override fails the test
  /// as "changed by the test".
  Future<void> onAndroid(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  Location place({bool notificationsEnabled = false}) => Location(
    id: 'home',
    name: 'Home',
    latitude: 27.7100,
    longitude: 85.3000,
    description: 'Where I live',
    icon: 'home',
    notificationsEnabled: notificationsEnabled,
  );

  Future<void> settleUi(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// The place screen, with [location] written through STORAGE first so the
  /// provider reads what it draws.
  Future<LocationProvider> pumpPlace(
    WidgetTester tester,
    Location location,
  ) async {
    final locations = (await tester.runAsync(() async {
      await StorageService().addLocation(location);
      final p = LocationProvider();
      await p.initialize();
      return p;
    }))!;

    final settings = (await tester.runAsync(() async {
      final s = SettingsProvider();
      await s.load();
      return s;
    }))!;

    final transactions = (await tester.runAsync(() async {
      final p = TransactionProvider();
      await p.initialize();
      return p;
    }))!;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LocationProvider>.value(value: locations),
          ChangeNotifierProvider<TransactionProvider>.value(
            value: transactions,
          ),
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider(create: (_) => JourneyProvider()),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: LocationDetailScreen(location: location),
        ),
      ),
    );
    await settleUi(tester);

    return locations;
  }

  /// Flips `place-notifications-toggle` and lets the async work it starts —
  /// the provider write and then the permission request — actually finish.
  ///
  /// The tap is wrapped in `runAsync` for the same reason the switch test in
  /// `location_crosslink_test` is: the write goes to storage and the request
  /// crosses a method channel, neither of which a fake-async pump alone drives
  /// to completion.
  Future<void> toggleOn(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(
        find.byKey(const ValueKey('place-notifications-toggle')),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await settleUi(tester);
  }

  List<String> notificationCalls() => calls.map((c) => c.method).toList();

  testWidgets('turning alerts ON asks a permission that was never asked', (
    tester,
  ) {
    return onAndroid(() async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final locations = await pumpPlace(tester, place());
      expect(
        tester.widget<Switch>(find.byType(Switch, skipOffstage: false)).value,
        isFalse,
        reason:
            'this test starts from a place that opted out, so ONE tap is '
            'the act of asking for alerts',
      );

      await toggleOn(tester);

      expect(
        notificationCalls(),
        contains('requestNotificationsPermission'),
        reason:
            'this is the moment the user wants an alert; a phone that has '
            'never been asked must be asked right here, not in Settings',
      );
      expect(
        locations.getLocationById('home')!.notificationsEnabled,
        isTrue,
        reason: 'the permission flow must not swallow the switch itself',
      );
      expect(
        find.textContaining('Your phone is blocking alerts'),
        findsNothing,
        reason: 'the prompt was granted, so there is nothing to explain',
      );
    });
  });

  testWidgets('a refusal is explained in words, with a way into Settings', (
    tester,
  ) {
    return onAndroid(() async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      grantOnRequest = false;

      await pumpPlace(tester, place());
      await toggleOn(tester);

      expect(notificationCalls(), contains('requestNotificationsPermission'));

      // THE FAULT. The toggle reports ON and the phone shows nothing; the one
      // thing missing was a sentence saying why.
      expect(
        find.textContaining('Your phone is blocking alerts'),
        findsOneWidget,
        reason: 'the user is told the phone is blocking the alerts, in words',
      );
      expect(
        find.textContaining('will not appear'),
        findsOneWidget,
        reason:
            'and it says what the consequence is, not just that something '
            'failed',
      );

      // The offer, not just the explanation.
      expect(find.text('Settings'), findsOneWidget);
      await tester.tap(find.text('Settings'));
      await settleUi(tester);
      expect(
        settingsCalls.map((c) => c.method),
        contains('openAppSettings'),
        reason:
            'the action has to actually open system Settings, where the '
            'switch that fixes this lives',
      );

      // Let the SnackBar's dismissal timer fire, so the test does not end with
      // a pending timer it never ran.
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();
    });
  });

  testWidgets('after the first ask, the next ON goes straight to the '
      'explanation', (tester) {
    return onAndroid(() async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      // Android answers POST_NOTIFICATIONS at most once per install, so the
      // second request would be a dialog nobody ever sees.
      SharedPreferences.setMockInitialValues({
        'notification_permission_asked': true,
      });
      NotificationService.resetForTesting();
      enabled = false;

      await pumpPlace(tester, place());
      await toggleOn(tester);

      expect(
        notificationCalls().where((m) => m == 'requestNotificationsPermission'),
        isEmpty,
        reason:
            'hasAskedPermission() is the guard: re-prompting here is a '
            'dialog the system swallows without showing anyone',
      );
      expect(
        find.textContaining('Your phone is blocking alerts'),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();
    });
  });

  testWidgets('the SnackBar\'s Settings action is safe once the screen is '
      'gone', (tester) {
    return onAndroid(() async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      grantOnRequest = false;

      await pumpPlace(tester, place());
      await toggleOn(tester);
      expect(
        find.textContaining('Your phone is blocking alerts'),
        findsOneWidget,
      );

      // The action is captured HERE, while the screen is still on the tree.
      final action = tester.widget<SnackBarAction>(find.byType(SnackBarAction));
      expect(action.label, 'Settings');

      // Then the screen goes — a back press, a pop from anywhere else — and
      // only afterwards is the action tapped. It fires up to eight seconds
      // after it was built, so whatever it uses has to be safe by then.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      action.onPressed();
      await settleUi(tester);

      expect(
        settingsCalls.map((c) => c.method),
        isEmpty,
        reason:
            'the screen that built the SnackBar is gone; a stale context must '
            'not open Settings on a tap nobody is looking at',
      );
      expect(tester.takeException(), isNull);

      // Let the SnackBar's own dismissal timer, if any survived the unmount,
      // run out rather than ending the test with it pending.
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();
    });
  });
}
