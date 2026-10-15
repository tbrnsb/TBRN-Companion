import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/providers/journey_provider.dart';
import 'package:daily_companion/providers/location_provider.dart';
import 'package:daily_companion/providers/settings_provider.dart';
import 'package:daily_companion/providers/transaction_provider.dart';
import 'package:daily_companion/screens/locations/location_detail_screen.dart';
import 'package:daily_companion/services/storage_service.dart';
import 'package:daily_companion/theme/app_theme.dart';
import 'package:daily_companion/widgets/settings_controls.dart';

import 'test_viewports.dart';
import 'visual_smoke_test.dart' show initTestStorage;

/// The place screen's "Notify when I arrive" row, as GEOMETRY rather than as
/// copy.
///
/// The row shipped as the app's one and only `SwitchListTile`, and it looked
/// wrong in a way a copy test cannot see: its label started 16 pixels to the
/// left of every other label/value row in the app, and its Switch sat on the
/// middle of a two-line block instead of on the label it switches. Both are
/// pixel facts, so they are locked here as pixel facts — measured against a
/// real settings row, and against the label's own first line.
void main() {
  setUpAll(() async {
    await initTestStorage();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService().clear();
  });

  Location place({bool notificationsEnabled = true}) => Location(
    id: 'home',
    name: 'Home',
    latitude: 27.7100,
    longitude: 85.3000,
    description: 'Where I live',
    icon: 'home',
    notificationsEnabled: notificationsEnabled,
  );

  /// The place screen on its own.
  ///
  /// The place is written through STORAGE first, so the provider reads what it
  /// draws rather than a list the test filled in by hand.
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
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    return locations;
  }

  /// The same screen, with a REAL settings row standing above it.
  ///
  /// The claim under test is that the arrival row shares the geometry of the
  /// app's other label/value rows — [SettingsOptionRow] and [SettingsNavRow].
  /// The place screen has no row from that family on it (its neighbours are stat
  /// cards and breakdown rows, which are laid out by their own code), so the
  /// neighbour is one of the family's own, built by the settings page's own
  /// recipe: screen padding, then a [SettingsGroup] card, then the row's own
  /// [AppSpacing.md]. Same viewport, same screen, so their left edges are
  /// directly comparable.
  Future<void> pumpPlaceBesideSettingsRow(WidgetTester tester) async {
    final locations = (await tester.runAsync(() async {
      await StorageService().addLocation(place());
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
          home: Scaffold(
            body: Column(
              children: [
                Padding(
                  padding: AppSpacing.screenPadding,
                  child: SettingsGroup(
                    title: 'Money',
                    children: const [
                      SettingsOptionRow<String>(
                        label: 'Currency',
                        value: 'Rs.',
                        options: ['Rs.'],
                        onSelected: _ignore,
                      ),
                    ],
                  ),
                ),
                Expanded(child: LocationDetailScreen(location: place())),
              ],
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('the arrival row shares the geometry of the app\'s other rows', () {
    testWidgets('its label starts on the same left edge as a settings row', (
      tester,
    ) async {
      // 360 is the app's smallest supported phone width (see
      // TestViewports.phoneSmall); the extra height only buys room for the
      // reference row above the place screen without pushing anything past the
      // fold, which would leave the labels unbuilt in a lazy list.
      usePhoneLayout(
        tester,
        Size(
          TestViewports.phoneSmall.width,
          TestViewports.phonePortrait.height,
        ),
      );
      await pumpPlaceBesideSettingsRow(tester);

      final arrivalLeft = tester
          .getTopLeft(find.text('Notify when I arrive'))
          .dx;
      final settingsLeft = tester.getTopLeft(find.text('Currency')).dx;
      final drift = (arrivalLeft - settingsLeft).abs();

      expect(
        arrivalLeft,
        closeTo(settingsLeft, 0.01),
        reason:
            '"Notify when I arrive" starts ${arrivalLeft}px from the left '
            'edge; the settings-family row beside it starts at ${settingsLeft}px '
            '— a ${drift.toStringAsFixed(1)}px drift. This row is the only one '
            'in the app built by anything other than SettingsOptionRow / '
            'SettingsNavRow, and a drift here is the row visibly stepping out '
            'of line with every other row.',
      );
    });

    testWidgets('the switch is on the label\'s FIRST line, and the caption '
        'says what the state means', (tester) async {
      usePhoneLayout(
        tester,
        Size(
          TestViewports.phoneSmall.width,
          TestViewports.phonePortrait.height,
        ),
      );
      await pumpPlace(tester, place());

      // --- GEOMETRY -------------------------------------------------------
      //
      // Measured, not eyeballed: the Switch's TOP against the label's TOP, and
      // the Switch's centre against the height of the label's first line.
      // "Aligned to the first line" is the first; the second is what separates
      // it from the fault, which was a Switch centred on the whole label
      // block — 28px below the label it belongs to, and belonging to neither
      // line of a two-line row.
      void expectSwitchOnFirstLine(String state) {
        final labelTop = tester
            .getTopLeft(find.text('Notify when I arrive'))
            .dy;
        final labelHeight = tester
            .getSize(find.text('Notify when I arrive'))
            .height;
        final switchRect = tester.getRect(find.byType(Switch));
        final drop = switchRect.top - labelTop;

        expect(
          drop.abs(),
          lessThanOrEqualTo(2),
          reason:
              'the Switch top is ${switchRect.top}px and the label\'s first '
              'line starts at ${labelTop}px, so the switch is '
              '${drop.abs().toStringAsFixed(1)}px off it ($state). A switch '
              'belongs on the line of the label it switches, not on the '
              'middle of the label block.',
        );

        final centreDrop = switchRect.center.dy - labelTop;
        expect(
          centreDrop,
          lessThanOrEqualTo(labelHeight + 2),
          reason:
              'the Switch\'s centre is ${centreDrop.toStringAsFixed(1)}px '
              'below the label\'s first line, which is only ${labelHeight}px '
              'tall ($state) — so it is centred on the whole two-line block '
              'rather than sitting on the label.',
        );
      }

      // --- COPY, enabled --------------------------------------------------
      expect(find.text('Notify when I arrive'), findsOneWidget);
      expect(
        find.text('Within 1.0 km, while the app is running'),
        findsOneWidget,
        reason:
            'the enabled caption says when the alert fires, including that it '
            'needs the app running — that limit is the honest part',
      );
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expectSwitchOnFirstLine('enabled');

      // --- ACCESSIBILITY ---------------------------------------------------
      //
      // ONE announcement, label and state together — the pattern
      // [SettingsOptionRow] uses ("$label, currently $value"). A switch whose
      // semantics are only a role and a position says what state the row is in
      // without ever saying which setting that is about. Read off the row's own
      // Semantics widget, so the assertion is on what the row ASKS to be
      // announced rather than on how a reader happens to assemble it.
      Semantics arrivalSemantics() => tester.widget<Semantics>(
        find.descendant(
          of: find.byKey(const ValueKey('place-notifications-toggle')),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label != null,
          ),
          matchRoot: true,
        ),
      );

      void expectAnnouncement(String state) {
        expect(
          arrivalSemantics().properties.label,
          'Notify when I arrive, currently $state',
          reason:
              'the row must announce which setting it is AND its state, as '
              'one thing, the way every other settings row does',
        );
        expect(arrivalSemantics().properties.toggled, state == 'on');
      }

      expectAnnouncement('on');

      // --- COPY, disabled -------------------------------------------------
      //
      // The tap is wrapped in `runAsync` for the same reason the other place
      // tests wrap it: the write goes to storage and the permission read
      // crosses a method channel, neither of which a fake-async pump alone
      // drives to completion.
      await tester.runAsync(() async {
        await tester.tap(
          find.byKey(const ValueKey('place-notifications-toggle')),
        );
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('Turned off for this place'), findsOneWidget);
      expect(find.textContaining('while the app is running'), findsNothing);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      // The caption is one line now instead of two, so the block changed
      // height under the switch — it still has to sit on the label.
      expectSwitchOnFirstLine('disabled');
      expectAnnouncement('off');
    });
  });
}

/// An option the reference row never opens.
void _ignore(String _) {}
