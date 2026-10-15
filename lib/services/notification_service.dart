import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  static Future<void> _initialize() async {
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
  /// Written AFTER the request comes back, never before — and in a `finally`,
  /// so a prompt that throws still counts as an attempt. The old ordering wrote
  /// the flag on the way out, to survive an answer that never arrives; that was
  /// the wrong trade. A process killed while the system dialog is up (OOM kill,
  /// swipe-away, a crash) never resumes, so "written first" persisted `true`
  /// for a prompt the user may never have seen, and every later
  /// [ensurePermission] then answered false WITHOUT asking: the per-place
  /// toggle recorded `enabled=true`, the user waited for alerts the phone would
  /// never show, and nothing pointed at Settings. Written last, a request that
  /// never returns leaves the flag false and the next launch simply asks again —
  /// and a repeat Android decides to swallow is harmless, because it just
  /// answers false.
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
        try {
          return await android.requestNotificationsPermission() ?? false;
        } finally {
          // AFTER the request, so a process that dies mid-prompt leaves the
          // flag false and gets asked again next launch. See
          // [_markPermissionAsked].
          await _markPermissionAsked();
        }
      }

      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        if ((await ios.checkPermissions())?.isEnabled ?? false) return true;
        if (await hasAskedPermission()) return false;
        try {
          return await ios.requestPermissions() ?? false;
        } finally {
          await _markPermissionAsked();
        }
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
}
