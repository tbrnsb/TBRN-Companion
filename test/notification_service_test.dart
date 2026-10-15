import 'dart:async';

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

  /// Whether the permission prompt never answers at all — the process died
  /// with the system dialog on screen, so the request is still outstanding.
  var hangOnRequest = false;

  /// Whether the permission prompt throws instead of answering.
  var throwOnRequest = false;

  /// The completer behind a hung prompt, so a test can let it finish.
  Completer<dynamic>? pendingRequest;

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
    hangOnRequest = false;
    throwOnRequest = false;
    pendingRequest = null;
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
              if (hangOnRequest) {
                final completer = Completer<dynamic>();
                pendingRequest = completer;
                return completer.future;
              }
              if (throwOnRequest) {
                throw PlatformException(code: 'prompt-down');
              }
              return grantOnRequest;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    // A prompt that never came back is only ever held open inside a test that
    // finishes it; do not carry one into the next one.
    pendingRequest?.complete(false);
    pendingRequest = null;
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

  group('the flag records an attempt the system actually saw, not one it might '
      'have missed', () {
    // THE DEFECT. `_markPermissionAsked` used to run BEFORE the request went
    // out. A process killed while the system prompt is on screen — OOM kill,
    // swipe-away, a crash — never comes back to do anything, but the flag
    // had already been persisted as `true`. From then on every
    // `ensurePermission()` answered false WITHOUT prompting, the per-place
    // toggle still recorded `enabled=true`, and the user waited for alerts
    // the phone would never deliver with no error and no hint to go to
    // Settings. So the request is what commits the flag — but only once it
    // RETURNS: a prompt that answers, grant or refusal, counts, and a prompt
    // that throws or never returns displayed nothing and is as if it never
    // happened.
    test('a prompt that never returns leaves the flag unwritten', () async {
      enabled = false;
      hangOnRequest = true;

      final hanging = NotificationService.ensurePermission();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        await NotificationService.hasAskedPermission(),
        isFalse,
        reason:
            'the prompt never came back, so nothing was ever asked; a flag '
            'written here would silence every later attempt',
      );

      // The recovery the flag being false is FOR: the next attempt asks
      // again, rather than answering false from a prompt nobody ever saw.
      hangOnRequest = false;
      grantOnRequest = true;

      expect(await NotificationService.ensurePermission(), isTrue);
      expect(
        methods().where((m) => m == 'requestNotificationsPermission'),
        hasLength(2),
        reason:
            'a prompt swallowed by the process dying mid-dialog must be '
            'asked for again on the next attempt',
      );

      // Let the outstanding request finish so it is not left dangling.
      pendingRequest!.complete(false);
      pendingRequest = null;
      expect(await hanging, isFalse);
    });

    test('a prompt that throws leaves the flag unwritten', () async {
      enabled = false;
      throwOnRequest = true;

      expect(await NotificationService.ensurePermission(), isFalse);
      expect(
        await NotificationService.hasAskedPermission(),
        isFalse,
        reason:
            'the throw put nothing on screen, so nothing was asked; recording '
            'it would spend Android\u2019s one ask per install on a prompt the '
            'user never saw, and no later attempt could ever ask again',
      );

      // The recovery the flag being false is FOR: with the failure recorded as
      // "not asked", the next attempt reaches the prompt at all.
      throwOnRequest = false;
      grantOnRequest = true;

      expect(await NotificationService.ensurePermission(), isTrue);
      expect(
        methods().where((m) => m == 'requestNotificationsPermission'),
        hasLength(2),
        reason:
            'a failure that showed nothing must not have burned the one-shot '
            'ask; the second attempt has to reach the prompt',
      );
    });
  });

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
