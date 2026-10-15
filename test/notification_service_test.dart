import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daily_companion/services/notification_service.dart';

/// The plugin's own method channel, mocked so the permission flow can be
/// driven without a phone. Nothing registers a plugin in a test, so without
/// this every call would fail with `MissingPluginException`.
const MethodChannel _channel = MethodChannel(
  'dexterous.com/flutter/local_notifications',
);

void main() {
  final recorded = <MethodCall>[];

  /// What `areNotificationsEnabled` will say.
  var enabled = true;

  /// What the permission prompt will answer.
  var grantOnRequest = true;

  /// Whether the channel fails outright rather than answering.
  var broken = false;

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // The platform interface keeps its instance in a `late` field that only a
    // real registration fills, so the Android implementation has to be
    // installed by hand before `resolvePlatformSpecificImplementation` can
    // find anything to talk to.
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
  });

  setUp(() {
    // The plugin picks its implementation from the target platform, and this
    // machine reports linux — a platform with nothing to ask. Android is what
    // the bug is on, so Android is what the test runs as.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    // The "already asked" flag is persisted, so the tests need a store that
    // answers — and a fresh one each time, or a refusal in one test would
    // silence the prompt in the next.
    SharedPreferences.setMockInitialValues({});
    NotificationService.resetForTesting();
    recorded.clear();
    enabled = true;
    grantOnRequest = true;
    broken = false;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          recorded.add(call);
          if (broken) {
            throw PlatformException(code: 'channel-down');
          }
          switch (call.method) {
            case 'areNotificationsEnabled':
              return enabled;
            case 'requestNotificationsPermission':
              return grantOnRequest;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  List<String> methods() => recorded.map((c) => c.method).toList();

  group('the permission helper reports state without prompting', () {
    test('already allowed: says so and never opens the prompt', () async {
      enabled = true;

      final allowed = await NotificationService.ensurePermission();

      expect(allowed, isTrue);
      expect(
        methods(),
        ['areNotificationsEnabled'],
        reason:
            'a prompt for a permission the user has already granted is a '
            'dialog they have to dismiss for nothing',
      );
      expect(
        await NotificationService.hasAskedPermission(),
        isFalse,
        reason: 'nothing was asked, so nothing must be recorded as asked',
      );
    });

    test('notificationsEnabled reads the state and asks for nothing', () async {
      enabled = true;
      expect(await NotificationService.notificationsEnabled(), isTrue);
      expect(methods(), ['areNotificationsEnabled']);

      recorded.clear();
      enabled = false;
      expect(await NotificationService.notificationsEnabled(), isFalse);
      expect(methods(), [
        'areNotificationsEnabled',
      ], reason: 'reading state must never re-prompt — Android ignores it');
    });
  });

  group(
    'the prompt is asked for exactly once, and a refusal is not an error',
    () {
      test('not yet asked: the prompt runs after the state check', () async {
        enabled = false;
        grantOnRequest = true;

        final allowed = await NotificationService.ensurePermission();

        expect(allowed, isTrue);
        expect(methods(), [
          'areNotificationsEnabled',
          'requestNotificationsPermission',
        ]);
        expect(await NotificationService.hasAskedPermission(), isTrue);
      });

      test('a refusal comes back as false, and does not throw', () async {
        enabled = false;
        grantOnRequest = false;

        // Reaching the expectations at all is the point: before this helper
        // existed there was no refusal to report anywhere, and a helper that
        // threw would take the app's startup down with it.
        final allowed = await NotificationService.ensurePermission();

        expect(allowed, isFalse);
        expect(await NotificationService.hasAskedPermission(), isTrue);
      });

      test('the second attempt in a run does not ask again', () async {
        enabled = false;
        grantOnRequest = false;

        await NotificationService.ensurePermission();
        final again = await NotificationService.ensurePermission();

        expect(again, isFalse);
        expect(
          recorded.where((c) => c.method == 'requestNotificationsPermission'),
          hasLength(1),
          reason:
              "Android answers the POST_NOTIFICATIONS prompt once; a second "
              'request is a silent no-op that the UI must not wait on',
        );
      });

      test('a refusal is remembered after a restart', () async {
        enabled = false;
        grantOnRequest = false;

        await NotificationService.ensurePermission();

        // A new run: every in-memory flag this class holds is gone, and only
        // what made it to storage survives.
        NotificationService.resetForTesting();

        final allowed = await NotificationService.ensurePermission();

        expect(allowed, isFalse);
        expect(
          recorded.where((c) => c.method == 'requestNotificationsPermission'),
          hasLength(1),
          reason:
              'Android answers the prompt once per install; asking again '
              'after a restart is a dialog nobody ever sees',
        );
      });
    },
  );

  group('a platform that cannot be reached never takes the caller down', () {
    test('a failing channel reports false instead of throwing', () async {
      broken = true;

      expect(await NotificationService.ensurePermission(), isFalse);
      expect(await NotificationService.notificationsEnabled(), isFalse);
    });

    test(
      'a platform with nothing to ask reports allowed, and asks nothing',
      () async {
        // Linux and Windows have no runtime notification permission at all, so
        // the Settings row's "Off" / "Tap to turn them on" would be pointing
        // at a page with no switch on it.
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;

        expect(await NotificationService.ensurePermission(), isTrue);
        expect(await NotificationService.notificationsEnabled(), isTrue);
        expect(recorded, isEmpty);
      },
    );
  });

  group('two alerts in the same second get two different ids', () {
    // The id used to be `DateTime.now().millisecondsSinceEpoch ~/ 1000` —
    // second resolution. Two arrivals inside one second replaced each other,
    // so the user saw one alert and the earlier one silently vanished.
    test('ids do not collide', () {
      final ids = [
        for (var i = 0; i < 500; i++) NotificationService.nextNotificationId(),
      ];

      expect(
        ids.toSet(),
        hasLength(ids.length),
        reason: 'an id that repeats replaces the notification already shown',
      );
    });

    test('ids are seeded from the clock, not from zero', () {
      NotificationService.resetForTesting();
      final before = DateTime.now().millisecondsSinceEpoch;

      final id = NotificationService.nextNotificationId();

      final after = DateTime.now().millisecondsSinceEpoch;
      expect(
        id,
        greaterThanOrEqualTo(before),
        reason: 'an id below the clock would collide with ids already used',
      );
      expect(
        id,
        lessThanOrEqualTo(after),
        reason: 'the first id of a run is the clock, so it starts near now',
      );
    });
  });
}
