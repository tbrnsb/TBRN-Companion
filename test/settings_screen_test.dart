import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daily_companion/providers/checklist_provider.dart';
import 'package:daily_companion/providers/journey_provider.dart';
import 'package:daily_companion/providers/location_provider.dart';
import 'package:daily_companion/providers/budget_provider.dart';
import 'package:daily_companion/providers/settings_provider.dart';
import 'package:daily_companion/screens/budgets/budgets_screen.dart';
import 'package:daily_companion/screens/locations/locations_screen.dart';
import 'package:daily_companion/widgets/app_gear.dart';
import 'package:daily_companion/providers/transaction_provider.dart';
import 'package:daily_companion/screens/settings_screen.dart';
import 'package:daily_companion/services/notification_service.dart';
import 'package:daily_companion/services/storage_service.dart';
import 'package:daily_companion/theme/app_theme.dart';
import 'package:daily_companion/widgets/settings_controls.dart';

import 'test_viewports.dart';
import 'visual_smoke_test.dart' show initTestStorage;

Future<void> settleUi(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Scrolls the settings list until [finder] is built, then taps it.
///
/// The settings screen is a lazy ListView and the lower sections are its last
/// children, so they simply do not exist in the tree until the list is
/// scrolled down. Tapping a target that is clipped at the fold edge is
/// unreliable for the same reason.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    120,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 60,
  );
  await settleUi(tester);
}

Future<void> scrollToAndTap(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    120,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 60,
  );
  await settleUi(tester);
  await tester.tap(finder);
  await settleUi(tester);
}

Widget _app([Widget? home]) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ChecklistProvider()),
      ChangeNotifierProvider(create: (_) => JourneyProvider()),
      ChangeNotifierProvider(create: (_) => LocationProvider()),
      ChangeNotifierProvider(create: (_) => TransactionProvider()),
      ChangeNotifierProvider(create: (_) => SettingsProvider()),
      // The Budgets row reads the provider to summarise what is set, and
      // BudgetsScreen needs it to open. The app provides it at the root, so a
      // harness that omits it is not a screen the app can actually show.
      ChangeNotifierProvider(create: (_) => BudgetProvider()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: home ?? const SettingsScreen(),
    ),
  );
}

void main() {
  setUpAll(() async {
    await initTestStorage();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService().clear();
  });

  group('the screen is organised, not a list of options', () {
    // The complaint the redesign answers: the page was as long as the
    // implementation. Four theme families with a tagline and a swatch strip
    // each, then a variant control, then three currency rows -- and nine
    // currencies as rows would have been worse. One row per setting means the
    // page stops being a list of how many options it has.
    testWidgets('every setting is ONE row, whatever it offers', (tester) async {
      usePhoneLayout(tester, const Size(412, 2600));
      await tester.pumpWidget(_app());
      await settleUi(tester);

      for (final key in [
        'settings-row-theme',
        'settings-row-brightness',
        'settings-row-number-style',
        'settings-row-currency',
      ]) {
        expect(
          find.byKey(ValueKey(key)),
          findsOneWidget,
          reason: '$key is not on the screen as a single row',
        );
      }
    });

    testWidgets('a dropdown opens a sheet listing the choices', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await tester.pumpWidget(_app());
      await settleUi(tester);

      await tester.tap(find.byKey(const ValueKey('settings-row-currency')));
      await settleUi(tester);

      // Nine currencies, all reachable, and none of them a row on the page.
      for (final currency in Currency.values) {
        expect(
          find.textContaining(currency.title),
          findsWidgets,
          reason: '${currency.title} is not offered',
        );
      }
      expect(find.text('2,350.00'), findsNothing);
    });

    testWidgets('choosing a currency applies it immediately', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await tester.pumpWidget(_app());
      await settleUi(tester);

      await tester.tap(find.byKey(const ValueKey('settings-row-currency')));
      await settleUi(tester);
      // Tapped by its visible text rather than by the row's composed key, so the
      // test does not break when a label gains a space or a currency is added.
      await tester.tap(find.text('₹  Indian Rupee'));
      await settleUi(tester);

      // The row now reports the choice, which is the whole point of the row: you
      // can see what is selected without opening the sheet again. The row shows
      // the SHORT mark -- the full name lives in the sheet, and a row that
      // spelled out "₹ Indian Rupee" would be a paragraph.
      expect(find.text('₹'), findsOneWidget);
    });

    testWidgets('a dark-only family does not offer Light', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await tester.pumpWidget(_app());
      await settleUi(tester);

      await tester.tap(find.byKey(const ValueKey('settings-row-theme')));
      await settleUi(tester);
      await tester.tap(find.byKey(const ValueKey('settings-option-Gruvbox')));
      await settleUi(tester);

      await tester.tap(find.byKey(const ValueKey('settings-row-brightness')));
      await settleUi(tester);

      // ABSENT, not disabled. A "Light" a dark-only family cannot honour is a
      // promise the app cannot keep, and being snapped back to dark is worse
      // than never offering it.
      expect(find.text('Light'), findsNothing);
      expect(find.text('Dark'), findsWidgets);
    });
  });

  group('the two things that open a SCREEN say so with a chevron', () {
    testWidgets('categories and budgets are rows, not dropdowns', (
      tester,
    ) async {
      usePhoneLayout(tester, const Size(412, 2600));
      await tester.pumpWidget(_app());
      await settleUi(tester);

      // A chevron and a sheet are different promises: a chevron says "there is
      // more here", a dropdown says "pick one of these". Categories and budgets
      // both open a screen's worth of behaviour, so they must not look like a
      // choice from a list.
      expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(2));
      expect(find.byIcon(Icons.expand_more_rounded), findsNWidgets(4));
    });

    testWidgets('categories opens its own screen with a way back', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await tester.pumpWidget(_app());
      await settleUi(tester);

      await scrollToAndTap(
        tester,
        find.byKey(const ValueKey('settings-nav-Categories')),
      );

      expect(find.text('Categories'), findsWidgets);
      expect(find.byType(BackButton), findsOneWidget);
    });

    testWidgets('budgets opens the budgets screen', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await tester.pumpWidget(_app());
      await settleUi(tester);

      await scrollToAndTap(
        tester,
        find.byKey(const ValueKey('settings-nav-Budgets')),
      );

      expect(find.byType(BudgetsScreen), findsOneWidget);
    });
  });

  group('the gear is not offered on the screen it opens', () {
    testWidgets('the gear is gone inside Settings', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      // PUSHED, the way the app reaches it. Asked from the route rather than a
      // flag, so the answer is a property of WHERE the screen is and not
      // something a screen has to remember to set -- and so it is still true for
      // a screen opened from Settings.
      await tester.pumpWidget(_app(const LocationsScreen()));
      await settleUi(tester);
      expect(
        AppGearButton.isSettingsOpen(
          tester.element(find.byType(LocationsScreen)),
        ),
        isFalse,
        reason: 'the gear must be there on an ordinary screen',
      );

      // NOT awaited: `open` resolves when the pushed route is POPPED, so
      // awaiting it here would wait forever.
      unawaited(
        AppGearButton.open(tester.element(find.byType(LocationsScreen))),
      );
      await settleUi(tester);

      expect(
        AppGearButton.isSettingsOpen(tester.element(find.text('Settings'))),
        isTrue,
      );
    });
  });

  group('the destructive actions live in a menu', () {
    // A full-width button each put "Remove all data" on screen at the same
    // weight and size as "Export this month as CSV", and the destructive one is
    // the one a thumb reaches for by accident.
    testWidgets('they are not on the page at all', (tester) async {
      usePhoneLayout(tester, const Size(412, 2600));
      await tester.pumpWidget(_app());
      await settleUi(tester);

      expect(find.text('Remove all data'), findsNothing);
      expect(find.text('Export this month as CSV'), findsNothing);
      expect(find.byKey(const ValueKey('settings-data-menu')), findsOneWidget);
    });

    testWidgets('the menu offers all three, export before import', (
      tester,
    ) async {
      usePhoneLayout(tester, const Size(412, 2600));
      await tester.pumpWidget(_app());
      await settleUi(tester);

      await tester.tap(find.byKey(const ValueKey('settings-data-menu')));
      await settleUi(tester);

      expect(find.text('Export this month as CSV'), findsOneWidget);
      expect(find.text('Import transactions from CSV'), findsOneWidget);
      expect(find.text('Remove all data'), findsOneWidget);
    });
  });

  group('no Settings row text wraps', () {
    // THE DEVICE: "Manage categories" wrapped onto two lines, as did "Grouping
    // and decimals" and "Name, colour and icon", so the Appearance and Money
    // groups had rows of three different heights in a list that is otherwise
    // uniform -- and a page of uneven rows reads as broken even when every row
    // is correct.
    //
    // Asserted on the RENDERED height rather than on a row height, because a row
    // height comparison fails for reasons that have nothing to do with wrapping:
    // an option row and a nav row are different heights to begin with, so no two
    // of them are ever equal to each other.
    testWidgets('no text in a settings row is more than one line tall', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await tester.pumpWidget(_app());
      await settleUi(tester);

      final texts = <({String text, double height, double fontSize})>[];
      for (final rowType in [SettingsNavRow, SettingsOptionRow]) {
        final finder = find.descendant(
          of: find.byType(rowType),
          matching: find.byType(Text),
        );
        // The widget and its OWN element, paired by index.
        //
        // Re-finding by the text -- `find.text(data).first` -- measures whichever
        // matching Text comes first in the whole tree, and "Categories" is both a
        // row label and the group header above it. That reported the header's
        // height against the row's font size and called a one-line row two-line.
        final widgets = tester.widgetList<Text>(finder).toList();
        final elements = finder.evaluate().toList();
        expect(widgets.length, elements.length);

        for (var i = 0; i < widgets.length; i++) {
          final text = widgets[i];
          final size = text.style?.fontSize;
          if (size == null || size == 0 || text.data == null) continue;
          texts.add((
            text: text.data!,
            height: tester
                .getSize(find.byElementPredicate((e) => e == elements[i]))
                .height,
            fontSize: size,
          ));
        }
      }

      expect(texts, isNotEmpty, reason: 'the page rendered no row text');

      for (final t in texts) {
        // A single line is the font size times its height multiplier, which is
        // at most about 1.3 in this theme. A second line roughly doubles it, so
        // 1.75x separates the two cases with room to spare.
        expect(
          t.height,
          lessThan(t.fontSize * 1.75),
          reason:
              '"${t.text}" is ${t.height.toStringAsFixed(1)}px tall at a '
              '${t.fontSize.toStringAsFixed(1)}px font, so it is on two lines -- '
              'and that is what makes this row taller than the rows around it',
        );
      }
    });
  });

  // The row that answers the question the rest of the app never asked: CAN the
  // phone show an alert at all? Everything else here — the per-place toggle,
  // the trip reminders — is silently void while that permission is off, and
  // until this row existed no screen said so.
  group('the alerts row reports what the phone will actually do', () {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final calls = <MethodCall>[];

    /// What `areNotificationsEnabled` will say.
    var enabled = true;

    /// Whether it never says anything at all — a platform channel that has
    /// stalled, which is how the row used to sit on "Checking…" forever.
    var hang = false;

    /// What the permission prompt will answer.
    var grantOnRequest = true;

    setUpAll(() {
      // The plugin resolves its implementation from the target platform, and
      // nothing registers a plugin in a test: the Android implementation has
      // to be installed by hand.
      FlutterLocalNotificationsPlatform.instance =
          AndroidFlutterLocalNotificationsPlugin();
    });

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      NotificationService.resetForTesting();
      calls.clear();
      enabled = true;
      hang = false;
      grantOnRequest = true;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            switch (call.method) {
              case 'areNotificationsEnabled':
                if (hang) {
                  // Never answered: the row's read is now waiting on a
                  // platform that is not going to reply.
                  return Completer<dynamic>().future;
                }
                return enabled;
              case 'requestNotificationsPermission':
                // Answering the prompt is what changes the state the row
                // then reads back, so the grant has to move the switch.
                enabled = grantOnRequest;
                return grantOnRequest;
              default:
                return null;
            }
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    /// Runs [body] as if it were running on Android.
    ///
    /// The plugin resolves its implementation from the target platform and
    /// this machine reports linux — a platform with nothing to ask — so the
    /// override has to be on while the row is built and tapped. It must be
    /// OFF again before the test body ends: flutter_test checks every
    /// foundation debug variable before `tearDown` runs, and a leftover
    /// override fails the test as "changed by the test".
    Future<void> onAndroid(Future<void> Function() body) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    testWidgets('it says On when the phone will show alerts', (tester) {
      return onAndroid(() async {
        usePhoneLayout(tester, const Size(412, 2600));
        await tester.pumpWidget(_app());
        await settleUi(tester);

        final row = find.byKey(const ValueKey('settings-row-notifications'));
        expect(row, findsOneWidget);
        expect(find.text('On'), findsOneWidget);
        expect(find.text('Off'), findsNothing);
        expect(find.text('Trip and arrival alerts'), findsOneWidget);
      });
    });

    testWidgets('it says Off, and the tap asks for the permission', (tester) {
      return onAndroid(() async {
        usePhoneLayout(tester, const Size(412, 2600));
        enabled = false;
        await tester.pumpWidget(_app());
        await settleUi(tester);

        expect(find.text('Off'), findsOneWidget);
        // The tap hint lives under the label: the value column is 81.3px and
        // "Off — tap to enable" is 119px of Roboto, so it would arrive trimmed
        // to "Off — tap t…" — the hint, gone.
        expect(find.text('Tap to turn them on'), findsOneWidget);
        expect(find.text('Trip and arrival alerts'), findsNothing);

        await tester.tap(
          find.byKey(const ValueKey('settings-row-notifications')),
        );
        await settleUi(tester);

        expect(
          calls.map((c) => c.method),
          contains('requestNotificationsPermission'),
          reason:
              'a permission that was never asked for must be asked for on the '
              'tap that offers to enable it',
        );
        // The prompt was granted, and the row reports the new state rather
        // than sitting on the one it read at startup.
        expect(find.text('On'), findsOneWidget);
      });
    });

    testWidgets('once the prompt has been answered, a tap goes to Settings', (
      tester,
    ) {
      return onAndroid(() async {
        usePhoneLayout(tester, const Size(412, 2600));
        // Android answers the prompt at most once, so a second attempt is a
        // dialog nobody sees — the only route left is system Settings. The
        // geolocator settings intent has no plugin behind it in a test, which
        // is fine: what this asserts is that the tap does NOT ask again and
        // does not blow up on the way.
        SharedPreferences.setMockInitialValues({
          'notification_permission_asked': true,
        });
        NotificationService.resetForTesting();
        enabled = false;
        await tester.pumpWidget(_app());
        await settleUi(tester);

        expect(find.text('Off'), findsOneWidget);
        expect(find.text('Tap to turn them on'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey('settings-row-notifications')),
        );
        await settleUi(tester);

        expect(
          calls.where((c) => c.method == 'requestNotificationsPermission'),
          isEmpty,
          reason: 'the prompt has been used up; asking again is a no-op',
        );
        expect(tester.takeException(), isNull);

        // The intent never comes back here, and the tap path is bounded for
        // the same reason the read is: a Settings call that never returns
        // would leave `_busy` set and this row un-tappable for the rest of the
        // screen's life. Wait out the deadline and it is live again.
        await tester.pump(const Duration(seconds: 5));
        await settleUi(tester);
        expect(
          tester
              .widget<InkWell>(
                find.byKey(const ValueKey('settings-row-notifications')),
              )
              .onTap,
          isNotNull,
          reason: 'the row recovers its tap once the bounded wait is over',
        );
      });
    });

    testWidgets('a phone that never answers lands on Off, not on '
        'Checking…', (tester) {
      return onAndroid(() async {
        usePhoneLayout(tester, const Size(412, 2600));
        // THE FAULT. `_refresh` ran once, on the way up, and `_enabled` only
        // left null when `areNotificationsEnabled` came back. A channel that
        // stalls leaves it waiting forever: the row showed "Checking…", with
        // no timeout and no retry, and there was nothing on it to tap.
        hang = true;
        await tester.pumpWidget(_app());
        await settleUi(tester);

        // Honest while it waits — the read really is still outstanding.
        expect(find.text('Checking\u2026'), findsOneWidget);

        // And bounded: app-time is advanced in slices until the row settles,
        // and it is given a few seconds' worth of clock and no more.
        for (
          var i = 0;
          i < 20 && find.text('Checking\u2026').evaluate().isNotEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 500));
        }

        expect(
          find.text('Checking\u2026'),
          findsNothing,
          reason:
              'a hung read must resolve to a definite state; "Checking…" is a '
              'moment, not a place the row can sit',
        );
        expect(
          find.text('Off'),
          findsOneWidget,
          reason:
              'the state nothing was able to check is "not allowed", which is '
              'what the service already reports for an unreachable platform',
        );
        expect(find.text('Tap to turn them on'), findsOneWidget);
      });
    });
  });
}
