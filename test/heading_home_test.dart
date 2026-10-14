import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/providers/checklist_provider.dart';
import 'package:daily_companion/providers/journey_provider.dart';
import 'package:daily_companion/screens/journeys/heading_home_sheet.dart';
import 'package:daily_companion/services/storage_service.dart';
import 'package:daily_companion/theme/app_theme.dart';

import 'test_viewports.dart';
import 'visual_smoke_test.dart' show initTestStorage;

/// "Heading home?" — the end of a trip.
///
/// The request was a button that reminds you of everything you packed, lets you
/// tick it off, and ends the trip with what you took, what you brought back and
/// how long it took.
///
/// Two rules these pin, both easy to get wrong:
///
///  1. The LIST is shown, not a count. A reminder of what to look for is only a
///     reminder if it says what to look for.
///  2. The trip cannot be ended with unticked items by accident. Someone who
///     packed eight of ten chose the other two; someone who ticked nothing has
///     not looked. The override is explicit and visible, never silent.
///
/// EVERY storage read here runs in `setUp`, on the real clock. A real storage
/// read inside a `testWidgets` body deadlocks on the box lock while the fake
/// clock is in force — the same trap that cost `category_icons_test.dart` two
/// ten-minute attempts before it was written down there. Only the widget tree
/// is faked; the providers are already live by the time the test body runs, so
/// ticking a box in the sheet exercises the real provider path.
void main() {
  setUpAll(() async {
    await initTestStorage();
  });

  late JourneyProvider journeys;
  late ChecklistProvider checklists;
  late Journey journey;

  /// Builds a running trip whose checklist holds [items].
  Future<void> seed(List<String> items) async {
    await StorageService().clear();
    journeys = JourneyProvider();
    checklists = ChecklistProvider();
    await journeys.initialize();
    await checklists.initialize();
    addTearDown(journeys.dispose);
    addTearDown(checklists.dispose);

    journey = await journeys.startJourney(
      destination: 'SmatErr',
      origin: 'Home',
      items: items,
      checklists: checklists,
    );
  }

  Widget sheet() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<JourneyProvider>.value(value: journeys),
        ChangeNotifierProvider<ChecklistProvider>.value(value: checklists),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: Scaffold(body: HeadingHomeSheet(journey: journey)),
      ),
    );
  }

  /// Awaits every pump. A bare `tester.pump` in a loop trips the guarded-function
  /// conflict, because the second call lands before the first returns.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  group('with a packing list', () {
    setUp(() => seed(['Boots', 'Jacket', 'Passport']));

    testWidgets('it shows every item, not just a count', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await tester.pumpWidget(sheet());
      await settle(tester);

      expect(find.text('Heading home?'), findsOneWidget);
      expect(find.text('Boots'), findsOneWidget);
      expect(find.text('Jacket'), findsOneWidget);
      expect(find.text('Passport'), findsOneWidget);
    });

    testWidgets('ticking writes through to the provider', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await tester.pumpWidget(sheet());
      await settle(tester);

      expect(checklists.packProgressFor(journey.id)?.packed, 0);

      // The provider is toggled directly rather than through a tap. A tap would
      // fire the same call from inside the widget's onChanged, where the Hive
      // write runs against the fake clock and deadlocks -- the same trap the
      // setUp note describes. `runAsync` is the way through it, and what is
      // under test here is that the SHEET reads the provider rather than
      // holding a copy of its own.
      await tester.runAsync(() async {
        final item = checklists
            .getChecklistsForJourney(journey.id)
            .single
            .items
            .firstWhere((i) => i.name == 'Boots');
        await checklists.toggleItem(item.id);
      });
      await settle(tester);

      expect(
        checklists.packProgressFor(journey.id)?.packed,
        1,
        reason: 'the sheet must write through, not hold its own copy',
      );
    });

    testWidgets('the trip cannot be ended with unticked items by accident', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await tester.pumpWidget(sheet());
      await settle(tester);

      final endButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'End trip'),
      );
      expect(
        endButton.onPressed,
        isNull,
        reason: 'three unticked items must block the end',
      );
    });

    testWidgets('the override is explicit and offered', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await tester.pumpWidget(sheet());
      await settle(tester);

      expect(find.text('End anyway'), findsOneWidget);

      await tester.tap(find.text('End anyway'));
      await settle(tester);

      final endButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'End trip'),
      );
      expect(endButton.onPressed, isNotNull);
    });

    testWidgets('everything packed means the button is live', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await tester.pumpWidget(sheet());
      await settle(tester);

      await tester.runAsync(() async {
        for (final item
            in checklists.getChecklistsForJourney(journey.id).single.items) {
          await checklists.toggleItem(item.id);
        }
      });
      await settle(tester);

      final endButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'End trip'),
      );
      expect(endButton.onPressed, isNotNull);
    });

    testWidgets('ending the trip stamps the end time', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await tester.pumpWidget(sheet());
      await settle(tester);

      await tester.runAsync(() async {
        for (final item
            in checklists.getChecklistsForJourney(journey.id).single.items) {
          await checklists.toggleItem(item.id);
        }
      });
      await settle(tester);

      final before = DateTime.now();
      await tester.runAsync(() => journeys.completeJourney(journey.id));
      await settle(tester);
      final after = DateTime.now();

      final stored = journeys.getJourneyById(journey.id)!;
      expect(stored.completed, isTrue);
      expect(stored.endTime, isNotNull);
      expect(
        stored.endTime!.isBefore(before.subtract(const Duration(seconds: 1))),
        isFalse,
        reason: 'the end cannot predate the tap',
      );
      expect(
        stored.endTime!.isAfter(after.add(const Duration(seconds: 1))),
        isFalse,
        reason: 'the end cannot postdate the tap',
      );
      expect(stored.isRunning, isFalse);
      expect(stored.durationText, isNot('Just started'));
    });

    testWidgets('the running duration is on screen while the trip is open', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await tester.pumpWidget(sheet());
      await settle(tester);

      expect(find.textContaining('so far'), findsOneWidget);
      expect(find.textContaining('of 3 packed'), findsOneWidget);
    });

    testWidgets('the count follows the ticks', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await tester.pumpWidget(sheet());
      await settle(tester);

      expect(find.textContaining('0 of 3 packed'), findsOneWidget);

      await tester.runAsync(() async {
        final item = checklists
            .getChecklistsForJourney(journey.id)
            .single
            .items
            .firstWhere((i) => i.name == 'Boots');
        await checklists.toggleItem(item.id);
      });
      await settle(tester);

      expect(find.textContaining('0 of 3 packed'), findsNothing);
      expect(find.textContaining('1 of 3 packed'), findsOneWidget);
    });
  });

  group('with nothing packed', () {
    // "Nothing to pack" is a different fact from "nothing packed", and the
    // sheet must not block a trip that simply had no list.
    setUp(() => seed(const []));

    testWidgets('it says so, and the trip can still be ended', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await tester.pumpWidget(sheet());
      await settle(tester);

      expect(find.text('Nothing was packed for this trip.'), findsOneWidget);
      expect(find.text('End anyway'), findsNothing);

      final endButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'End trip'),
      );
      expect(endButton.onPressed, isNotNull);
    });
  });
}
