import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daily_companion/providers/journey_provider.dart';
import 'package:daily_companion/providers/location_provider.dart';
import 'package:daily_companion/screens/journeys/journeys_screen.dart';
import 'package:daily_companion/services/storage_service.dart';
import 'package:daily_companion/theme/app_theme.dart';

import 'test_viewports.dart';
import 'visual_smoke_test.dart' show initTestStorage;

Future<void> settleUi(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// A provider whose reminder timer is cancelled when the test ends.
///
/// [JourneyProvider.initialize] starts a one-minute periodic timer, and a
/// widget test fails on a timer still pending after the tree is disposed.
Future<JourneyProvider> _provider(WidgetTester tester) async {
  final provider = JourneyProvider();
  addTearDown(provider.dispose);
  // Awaited: runAsync is reentrant-hostile, so leaving this in flight would
  // make the test's own runAsync call fail.
  await tester.runAsync(() => provider.initialize());
  return provider;
}

Widget _app(JourneyProvider journeys) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<JourneyProvider>.value(value: journeys),
      ChangeNotifierProvider(create: (_) => LocationProvider()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const JourneysScreen(),
    ),
  );
}

/// Opens the "Start a new journey" panel.
Future<void> openStartJourney(WidgetTester tester) async {
  await tester.tap(find.text('Start a new journey'));
  await settleUi(tester);
}

void main() {
  setUpAll(() async {
    await initTestStorage();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService().clear();
  });

  group('the journey screen fits a small phone', () {
    // This was never checked at 360dp, and the month navigator overflowed by
    // 29px there — two 48dp tap targets either side of a month name. The
    // overflow only appears on a small phone, which is exactly why it survived.
    testWidgets('the month navigator does not overflow at 360dp', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phoneSmall);
      final journeys = await _provider(tester);

      await tester.pumpWidget(_app(journeys));
      await settleUi(tester);

      expect(find.text('Start a new journey'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // The month navigator and the long month name moved to the calendar in the
    // app bar, which is where that layout now lives. They are asserted in
    // calendar_screen_test.dart, at the same 360dp viewport that caught the
    // original overflow, rather than deleted — a test that moves with the code
    // it protects is still a test.
  });

  group('what you are taking is a list', () {
    testWidgets('items are added one at a time and shown back', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      final journeys = await _provider(tester);

      await tester.pumpWidget(_app(journeys));
      await settleUi(tester);
      await openStartJourney(tester);

      // No more comma ceremony in the label.
      expect(find.text('What are you taking?'), findsOneWidget);
      expect(find.textContaining('comma'), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('journey-item-entry')),
        'Boots',
      );
      await tester.tap(find.byTooltip('Add to the list'));
      await settleUi(tester);

      // What was added is visible, which the single field could never do.
      expect(find.text('Boots'), findsWidgets);
      // The entry is cleared, so the same text cannot be added twice by accident.
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Add another'))
            .controller
            ?.text,
        isEmpty,
      );
    });

    testWidgets('a pasted comma-separated list still works', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      final journeys = await _provider(tester);

      await tester.pumpWidget(_app(journeys));
      await settleUi(tester);
      await openStartJourney(tester);

      // People paste lists they already have somewhere; rejecting that would be
      // pedantic, so commas still split.
      await tester.enterText(
        find.byKey(const ValueKey('journey-item-entry')),
        'Boots, jacket, map',
      );
      await tester.tap(find.byTooltip('Add to the list'));
      await settleUi(tester);

      expect(find.text('Boots'), findsWidgets);
      expect(find.text('jacket'), findsWidgets);
      expect(find.text('map'), findsWidgets);
    });

    testWidgets('one item can be removed without retyping the rest', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      final journeys = await _provider(tester);

      await tester.pumpWidget(_app(journeys));
      await settleUi(tester);
      await openStartJourney(tester);

      await tester.enterText(
        find.byKey(const ValueKey('journey-item-entry')),
        'Boots, jacket',
      );
      await tester.tap(find.byTooltip('Add to the list'));
      await settleUi(tester);

      await tester.tap(find.byTooltip('Remove Boots'));
      await settleUi(tester);

      expect(find.text('Boots'), findsNothing);
      expect(find.text('jacket'), findsWidgets);
    });

    testWidgets('the same item is not added twice', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      final journeys = await _provider(tester);

      await tester.pumpWidget(_app(journeys));
      await settleUi(tester);
      await openStartJourney(tester);

      for (final attempt in ['Boots', 'boots', 'BOOTS']) {
        await tester.enterText(
          find.byKey(const ValueKey('journey-item-entry')),
          attempt,
        );
        await tester.tap(find.byTooltip('Add to the list'));
        await settleUi(tester);
      }

      // Case-insensitively the same thing, so one row, not three.
      expect(find.byTooltip('Remove Boots'), findsOneWidget);
    });

    test('the items are persisted with the journey', () async {
      // Deliberately not a widget test. Tapping "Start journey" writes to Hive
      // from inside the fake-async zone of a testWidgets body, and that write
      // never completes — it holds the box lock and the test hangs. So the save
      // is exercised through the provider, which is the layer that owns the
      // write, and the editor's own behaviour is covered by the widget tests
      // above.
      await StorageService().clear();
      final journeys = JourneyProvider();
      await journeys.initialize();

      await journeys.startJourney(
        origin: 'Kathmandu',
        destination: 'Pokhara',
        items: ['Boots', 'Tent'],
      );

      final reloaded = JourneyProvider();
      await reloaded.initialize();

      expect(reloaded.journeys.single.destination, 'Pokhara');
      expect(reloaded.journeys.single.items, ['Boots', 'Tent']);

      // The periodic reminder timer would otherwise outlive the test.
      journeys.dispose();
      reloaded.dispose();
    });

    testWidgets('it fits a narrow phone without overflowing', (tester) async {
      usePhoneLayout(tester, TestViewports.phoneSmall);
      final journeys = await _provider(tester);

      await tester.pumpWidget(_app(journeys));
      await settleUi(tester);
      await openStartJourney(tester);

      await tester.enterText(
        find.byKey(const ValueKey('journey-item-entry')),
        'A considerably longer item name than a phone has room for in one line',
      );
      await tester.tap(find.byTooltip('Add to the list'));
      await settleUi(tester);

      expect(tester.takeException(), isNull);
    });
  });
}
