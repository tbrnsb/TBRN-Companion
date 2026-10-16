import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Prefs key recording that the system prompt has been answered.
  ///
  /// Persisted rather than kept in memory, because "has it been asked yet" is
  /// a question about the INSTALL, not about this run. Android answers
  /// `POST_NOTIFICATIONS` at most once: a second request after a refusal is a
  /// silent no-op that never reaches the user, so a user who refused at launch
  /// and opens Settings after a restart has to be sent to system Settings
  /// rather than shown a prompt the system will swallow.
  static const String _permissionAskedKey = 'notification_permission_asked';

  /// The last answer to [hasAskedPermission]; null until it has been read.
  static bool? _permissionAsked;

  /// The clock-seeded counter behind [nextNotificationId].
  static int _lastNotificationId = 0;

  /// Forgets everything this class remembers. For tests only: the prompt flag
  /// and the id counter are both static, so without this the second test in a
  /// file would inherit the first one's answers.
  @visibleForTesting
  static void resetForTesting() {
    _permissionAsked = null;
    _lastNotificationId = 0;
  }

  /// The id for the next notification.
  ///
  /// A monotonic counter SEEDED FROM THE CLOCK, rather than the clock itself.
  /// The old id was `millisecondsSinceEpoch ~/ 1000` — one id per second — so
  /// two arrivals in the same second shared an id and the second replaced the
  /// notification the user had not read yet. Counting up from the clock makes
  /// every id unique while still starting near the present, so ids keep the
  /// rough shape of their timestamp and never run backwards if the clock is
  /// moved to an earlier date mid-run.
  @visibleForTesting
  static int nextNotificationId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now > _lastNotificationId) {
      _lastNotificationId = now;
    }
    return _lastNotificationId++;
  }

  static Future<void> initialize() async {
    if (kIsWeb) return;
    try {
      await _initialize();
    } catch (_) {
      // Notifications unavailable (e.g. in tests) — non-fatal.
    }
  }

  /// Whether the timezone database has been loaded.
  ///
  /// `tz.local` answers in UTC until it is, which would schedule every
  /// reminder hours off from the time the user picked — silently, because UTC
  /// is a perfectly valid timezone to schedule in.
  static bool _timezonesLoaded = false;

  static void _ensureTimezones() {
    if (_timezonesLoaded) return;
    try {
      tz_data.initializeTimeZones();
      _timezonesLoaded = true;
    } catch (_) {
      // Already loaded, or the data is unavailable — either way there is
      // nothing more to load.
    }
  }

  static Future<void> _initialize() async {
    // BEFORE anything schedules: `tz.local` answers in UTC until the database
    // is loaded, and every zonedSchedule goes through it.
    _ensureTimezones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const linux = LinuxInitializationSettings(defaultActionName: 'Open app');
    const settings = InitializationSettings(
      android: android,
      iOS: ios,
      linux: linux,
    );

    await _plugin.initialize(settings);
  }

  /// Whether alerts from this app are allowed to appear right now.
  ///
  /// Reads state only and never prompts: Android's request is one-shot, so the
  /// Settings row has to be able to report "Off" — and send the user to system
  /// Settings — without re-asking a question that would be ignored.
  ///
  /// Returns false when the platform could not be reached at all, rather than
  /// guessing "On": a promise that alerts will appear is the one claim nothing
  /// here was able to check.
  static Future<bool> notificationsEnabled() async {
    if (kIsWeb) return true;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        return await android.areNotificationsEnabled() ?? false;
      }

      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        return (await ios.checkPermissions())?.isEnabled ?? false;
      }

      // Linux and Windows have no runtime notification permission: nothing to
      // be missing, so nothing is blocking the alert.
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Whether the system prompt has already been answered for this install.
  ///
  /// This is the fork in the road for Settings: if it has not been asked yet,
  /// the app can still put the prompt on screen; once it has, Android swallows
  /// a second request, so the only route left is the switch in system Settings.
  ///
  /// Reads the persisted flag once and then answers from memory. If the
  /// preferences cannot be read at all, the answer is "not asked" — the worst
  /// case is one request that Android would swallow anyway.
  static Future<bool> hasAskedPermission() async {
    final cached = _permissionAsked;
    if (cached != null) return cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      _permissionAsked = prefs.getBool(_permissionAskedKey) ?? false;
    } catch (_) {
      _permissionAsked = false;
    }
    return _permissionAsked!;
  }

  /// Records that the prompt has been put on screen, in memory and in prefs.
  ///
  /// Called only once the request has RETURNED — never before it goes out, and
  /// never from a `finally`.
  ///
  /// Written BEFORE the request, a process killed while the system dialog is
  /// up (OOM kill, swipe-away, a crash) never resumed, so `true` was persisted
  /// for a prompt the user may never have seen, and every later
  /// [ensurePermission] then answered false WITHOUT asking: the per-place
  /// toggle recorded `enabled=true`, the user waited for alerts the phone would
  /// never show, and nothing pointed at Settings.
  ///
  /// Written from a `finally` after the request, a throw — a
  /// `MissingPluginException` from a plugin nothing registered, a
  /// `PlatformException` from a channel that is down — displayed NOTHING and
  /// still burned the one ask Android grants per install, so the user lost
  /// their only prompt to a failure they never saw. A throw now skips this
  /// method entirely and leaves the flag unwritten: the next attempt asks
  /// again, and a repeat Android decides to swallow is harmless, because it
  /// just answers false.
  static Future<void> _markPermissionAsked() async {
    _permissionAsked = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_permissionAskedKey, true);
    } catch (_) {
      // Best effort: this run already has the answer in memory, and losing the
      // persistent copy costs at most one swallowed request later.
    }
  }

  /// Asks for the notification permission if it has not been asked for yet,
  /// and reports whether alerts are allowed afterwards.
  ///
  /// Must be called AFTER [initialize]: the plugin requires initialization
  /// before it can ask. On Android 13+ `POST_NOTIFICATIONS` starts DENIED on a
  /// fresh install, so without this call every `showTripReminder` is dropped
  /// by the system in silence — the toggle in a place's settings says ON and
  /// nothing arrives.
  ///
  /// Never throws. A failure to reach the platform comes back as false, which
  /// is the state the caller would have read anyway; a permission already
  /// answered returns that answer without prompting again. See
  /// [hasAskedPermission].
  static Future<bool> ensurePermission() async {
    if (kIsWeb) return true;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        if (await android.areNotificationsEnabled() ?? false) return true;
        if (await hasAskedPermission()) return false;
        final answered =
            await android.requestNotificationsPermission() ?? false;
        // Only a request that CAME BACK is an attempt worth recording. A throw
        // skips this line and the flag stays unwritten, so the next call asks
        // again. See [_markPermissionAsked].
        await _markPermissionAsked();
        return answered;
      }

      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        if ((await ios.checkPermissions())?.isEnabled ?? false) return true;
        if (await hasAskedPermission()) return false;
        final answered = await ios.requestPermissions() ?? false;
        await _markPermissionAsked();
        return answered;
      }

      // No runtime permission on this platform — nothing to ask.
      return true;
    } catch (_) {
      // Non-fatal, like `initialize()` above: the alerts stay as they are and
      // the Settings row reports what it could read.
      return false;
    }
  }

  static Future<void> showTripReminder({
    required String title,
    required String body,
  }) async {
    if (kIsWeb) return;

    const androidDetails = AndroidNotificationDetails(
      'journey_reminders',
      'Journey reminders',
      importance: Importance.max,
      priority: Priority.high,
      // Foreground alerts only: arrivals are checked while the app is open
      // (see `LocationProvider._checkArrivals`), so this channel never fires
      // from a background geofence — the app does not have one.
      channelDescription:
          'Trip reminders, and arrival alerts at saved places while the app '
          'is running',
    );
    const iosDetails = DarwinNotificationDetails();
    const linuxDetails = LinuxNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      linux: linuxDetails,
    );

    await _plugin.show(nextNotificationId(), title, body, details);
  }

  /// Schedules a one-shot notification for [scheduledTime].
  ///
  /// ONE-SHOT, deliberately: the previous version passed
  /// `matchDateTimeComponents: DateTimeComponents.dateAndTime`, which tells
  /// the OS to repeat the notification EVERY DAY at that time — a "leave now"
  /// reminder for one trip that never stops firing. A journey reminder is a
  /// single fact about a single day.
  ///
  /// Answers whether the platform ACCEPTED the schedule, so the caller can
  /// report a failure instead of promising an alert that was dropped. On web
  /// there is no scheduler at all, so the answer is always false.
  static Future<bool> scheduleAt({
    required String id,
    required String title,
    required String body,
    required DateTime scheduledTime,
  }) async {
    if (kIsWeb) return false;
    _ensureTimezones();

    const androidDetails = AndroidNotificationDetails(
      'journey_reminders',
      'Journey reminders',
      importance: Importance.max,
      priority: Priority.high,
      channelDescription: 'Scheduled reminders for trips and important events',
    );
    const iosDetails = DarwinNotificationDetails();
    const linuxDetails = LinuxNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      linux: linuxDetails,
    );

    // Android 12+ refuses the `alarmClock` mode below unless the user has
    // granted "Alarms & reminders". The permission itself is declared in
    // AndroidManifest.xml — without that declaration the toggle does not even
    // exist and every schedule on a modern phone throws inside the plugin.
    // This asks ONCE, from the user's own "Remind me" tap, when the toggle is
    // still off, and gives up honestly when they decline. On Android 11 and
    // older, or on desktop, `android` is null and nothing here runs.
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        final canSchedule = await android.canScheduleExactNotifications();
        if (canSchedule == false) {
          final granted = await android.requestExactAlarmsPermission();
          if (granted != true) return false;
        }
      }
    } catch (_) {
      // No platform behind the plugin at all (unit test, older engine), the
      // permission channel is missing, or another request is in flight. Let
      // the schedule attempt below be the judge: it fails closed on 31+, and
      // succeeds where no permission gate exists.
    }

    try {
      await _plugin.zonedSchedule(
        _stableId(id),
        title,
        body,
        tz.TZDateTime.from(scheduledTime, tz.local),
        details,
        androidScheduleMode: AndroidScheduleMode.alarmClock,
      );
      return true;
    } catch (_) {
      // The plugin is missing, the platform refused, or the channel cannot be
      // created. None of those will get better by throwing at the tap handler.
      return false;
    }
  }

  /// A notification id that is the same number on every run of the app.
  ///
  /// [Object.hashCode] for strings is seeded per process: scheduling
  /// 'journey_start_reminder' on Monday and again on Tuesday produced two
  /// different ints, so the second alarm stacked next to the first instead of
  /// replacing it, and a cancel keyed on the string could never find the
  /// original. FNV-1a over the code units is boring arithmetic with one
  /// answer, kept inside a positive 32-bit int because the platform channel
  /// hands Java an `int`.
  static int _stableId(String id) {
    var hash = 0x811C9DC5; // FNV-1a 32-bit offset basis.
    for (final unit in id.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF; // FNV-1a 32-bit prime.
    }
    return hash & 0x7FFFFFFF;
  }
}
