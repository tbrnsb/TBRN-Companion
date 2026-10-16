import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/providers/checklist_provider.dart';
import 'package:daily_companion/providers/journey_provider.dart';
import 'package:daily_companion/providers/location_provider.dart';
import 'package:daily_companion/providers/settings_provider.dart';
import 'package:daily_companion/providers/transaction_provider.dart';
import 'package:daily_companion/screens/checklists/checklists_screen.dart';
import 'package:daily_companion/screens/journeys/journeys_screen.dart';
import 'package:daily_companion/services/notification_service.dart';
import 'package:daily_companion/services/storage_service.dart';
import 'package:daily_companion/theme/app_theme.dart';

import 'test_viewports.dart';
import 'visual_smoke_test.dart' show initTestStorage;

/// Presets: a checklist saved as a reusable template for future journeys.
///
/// The bugs these tests pin, each of which shipped at least once:
///
/// - `saveAsPreset` coalesced `journeyId: null` back onto the source row —
///   and converting in place detached the trip's packing list behind a
///   success snackbar. It now clones: the source stays, the preset is fresh.
/// - `regularChecklists` existed but nothing used it, so a saved preset
///   stayed in the main list — saving one looked identical to doing nothing.
/// - The journey sheet's actions were bare `TextButton`s in a `Column`, and
///   a Column CENTRES its children: both drifted to the middle of the sheet
///   while every other control sat on the left edge.
/// - `NotificationService.scheduleAt` never loaded the timezone database
///   (silent UTC scheduling) and threw out of the tap handler when no plugin
///   existed instead of reporting the failure.
///
/// As everywhere else in this suite: a Hive write inside a `testWidgets`
/// body deadlocks the box lock, so every write and every tap that starts one
/// runs inside `tester.runAsync`.
void main() {
  setUpAll(() async {
    await initTestStorage();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService().clear();
  });

  ChecklistItem item(String name) =>
      ChecklistItem(checklistId: 'c1', name: name);

  Checklist checklist({
    String id = 'c1',
    String name = 'Weekend bag',
    String? journeyId,
    bool isPreset = false,
    List<String> items = const ['Boots'],
  }) => Checklist(
    id: id,
    name: name,
    description: '',
    journeyId: journeyId,
    isPreset: isPreset,
    items: items.map(item).toList(),
  );

  group('a saved preset, at the provider layer', () {
    late ChecklistProvider provider;

    setUp(() async {
      provider = ChecklistProvider();
      await provider.initialize();
      addTearDown(provider.dispose);
    });

    test('the preset is STANDALONE — no trip of its own', () async {
      await provider.addChecklist(checklist(journeyId: 'trip-1'));
      await provider.saveAsPreset('c1');

      final saved = provider.presets.single;
      expect(saved.isPreset, isTrue);
      expect(saved.journeyId, isNull, reason: 'a preset belongs to no trip');
    });

    test(
      'the source checklist stays with its trip — a save, not a move',
      () async {
        // Converting in place emptied the trip's packing list behind a success
        // snackbar. The clone keeps the original linked and tickable, and adds
        // a second, standalone row.
        await provider.addChecklist(checklist(id: 'c1', journeyId: 'trip-1'));
        await provider.saveAsPreset('c1');

        expect(provider.presets, hasLength(1));
        final source = provider.regularChecklists.single;
        expect(source.id, 'c1');
        expect(
          source.journeyId,
          'trip-1',
          reason: "the trip's list is untouched",
        );
        expect(source.isPreset, isFalse);
      },
    );

    test('the preset copies the items, unticked and of its own', () async {
      await provider.addChecklist(
        checklist(id: 'c1', items: ['Boots', 'Jacket']),
      );
      await provider.saveAsPreset('c1');

      final preset = provider.presets.single;
      expect(preset.items.map((i) => i.name), ['Boots', 'Jacket']);
      expect(
        preset.items.every((i) => !i.isChecked && i.checklistId == preset.id),
        isTrue,
        reason: 'a template starts fresh, under its own id',
      );
    });

    test('regularChecklists leaves presets out', () async {
      await provider.addChecklist(checklist(id: 'c1', name: 'Trip pack'));
      await provider.addChecklist(
        checklist(id: 'c2', name: 'Template', isPreset: true),
      );

      expect(provider.regularChecklists.map((c) => c.id), [
        'c1',
      ], reason: 'a template is not a checklist you are packing');
      expect(provider.presets.map((c) => c.id), ['c2']);
    });

    test('a preset survives a reload', () async {
      await provider.addChecklist(checklist());
      await provider.saveAsPreset('c1');

      final reloaded = ChecklistProvider();
      await reloaded.initialize();
      addTearDown(reloaded.dispose);

      expect(reloaded.presets.single.isPreset, isTrue);
      expect(reloaded.presets.single.journeyId, isNull);
    });
  });

  /// The screen harness both widget groups share: providers seeded through
  /// `runAsync` so their Hive reads finish, then handed to the app by value.
  Future<
    ({
      ChecklistProvider checklists,
      JourneyProvider journeys,
      LocationProvider locations,
      TransactionProvider transactions,
      SettingsProvider settings,
    })
  >
  seedProviders(WidgetTester tester) async {
    final p = (await tester.runAsync(() async {
      final checklists = ChecklistProvider();
      final journeys = JourneyProvider();
      final locations = LocationProvider();
      final transactions = TransactionProvider();
      final settings = SettingsProvider();
      await checklists.initialize();
      await journeys.initialize();
      await locations.initialize();
      await transactions.initialize();
      await settings.load();
      return (
        checklists: checklists,
        journeys: journeys,
        locations: locations,
        transactions: transactions,
        settings: settings,
      );
    }))!;
    addTearDown(p.checklists.dispose);
    addTearDown(p.journeys.dispose);
    addTearDown(p.locations.dispose);
    addTearDown(p.transactions.dispose);
    return p;
  }

  Widget appOf(
    ({
      ChecklistProvider checklists,
      JourneyProvider journeys,
      LocationProvider locations,
      TransactionProvider transactions,
      SettingsProvider settings,
    })
    p,
    Widget home,
  ) => MultiProvider(
    providers: [
      ChangeNotifierProvider<ChecklistProvider>.value(value: p.checklists),
      ChangeNotifierProvider<JourneyProvider>.value(value: p.journeys),
      ChangeNotifierProvider<LocationProvider>.value(value: p.locations),
      ChangeNotifierProvider<TransactionProvider>.value(value: p.transactions),
      ChangeNotifierProvider<SettingsProvider>.value(value: p.settings),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: home,
    ),
  );

  Future<void> settleUi(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('the checklists screen splits presets from real lists', () {
    testWidgets('a preset shows under Presets, not under Your checklists', (
      tester,
    ) async {
      usePhoneLayout(tester, const Size(360, 2800));
      final p = await seedProviders(tester);
      await tester.runAsync(() async {
        await p.checklists.addChecklist(
          checklist(id: 'real', name: 'Weekend bag'),
        );
        await p.checklists.addChecklist(
          checklist(
            id: 'tpl',
            name: 'Camping template',
            isPreset: true,
            items: ['Tent', 'Stove'],
          ),
        );
      });

      await tester.pumpWidget(appOf(p, const ChecklistsScreen()));
      await settleUi(tester);

      expect(find.text('Presets'), findsOneWidget);
      expect(find.text('Camping template'), findsOneWidget);
      expect(find.text('Weekend bag'), findsOneWidget);
      expect(
        find.text('2 items — used when starting a journey'),
        findsOneWidget,
      );
    });

    testWidgets('a checklist is SAVED AS a preset — the original stays', (
      tester,
    ) async {
      usePhoneLayout(tester, const Size(360, 2800));
      final p = await seedProviders(tester);
      await tester.runAsync(() async {
        await p.checklists.addChecklist(
          checklist(id: 'c1', name: 'Weekend bag'),
        );
      });

      await tester.pumpWidget(appOf(p, const ChecklistsScreen()));
      await settleUi(tester);

      // The tap that OPENS the menu runs in a real zone (the gesture, not the
      // write), then pumps build the route; the ITEM's tap starts the provider
      // write, so that one gets runAsync again.
      await tester.runAsync(() async {
        await tester.tap(find.byType(PopupMenuButton).first);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await settleUi(tester);
      await tester.runAsync(() async {
        await tester.tap(find.text('Save as preset'));
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await settleUi(tester);

      expect(find.text('Presets'), findsOneWidget);
      expect(p.checklists.presets.single.isPreset, isTrue);
      expect(p.checklists.presets.single.journeyId, isNull);
      expect(
        p.checklists.regularChecklists.single.id,
        'c1',
        reason: 'the save is a copy, so the original list is still there',
      );
      // Both rows are on screen: the list under "Your checklists" and the
      // template under "Presets".
      expect(find.text('Weekend bag'), findsNWidgets(2));
    });
  });

  group("the journey sheet's preset and reminder controls", () {
    Future<void> openStartCard(WidgetTester tester) async {
      usePhoneLayout(tester, const Size(360, 2800));
      final p = await seedProviders(tester);
      await tester.pumpWidget(appOf(p, const JourneysScreen()));
      await settleUi(tester);
      await tester.tap(find.text('Start a new journey'));
      await settleUi(tester);
    }

    testWidgets('both actions are on the card, and sit on the LEFT edge', (
      tester,
    ) async {
      await openStartCard(tester);

      final addPreset = find.text('Add from preset');
      final remindMe = find.text('Remind me');
      expect(addPreset, findsOneWidget);
      expect(remindMe, findsOneWidget);
      // A bare TextButton in a Column CENTRES itself; these are wrapped in
      // Align(centerLeft) so they share the left edge of the fields above
      // them. The x is the widget's left — the card's content inset is the
      // same for both, so closeness to the field's edge is the alignment.
      final fieldX = tester.getTopLeft(find.byType(TextField).first).dx;
      expect(
        (tester.getTopLeft(addPreset).dx - fieldX).abs(),
        lessThan(48),
        reason: 'the action should start at the same edge as the fields',
      );
      expect((tester.getTopLeft(remindMe).dx - fieldX).abs(), lessThan(48));
    });

    testWidgets('no presets yet says so, and says where they come from', (
      tester,
    ) async {
      await openStartCard(tester);

      await tester.tap(find.text('Add from preset'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text('No presets yet — save one from a checklist’s menu first'),
        findsOneWidget,
      );
    });
  });

  group('a schedule nobody can keep', () {
    test('reports failure instead of throwing when no plugin exists', () async {
      // Widget tests have no notification plugin behind them. The old
      // scheduleAt threw out of the tap handler; the fixed one answers false,
      // and the sheet tells the user rather than promising an alert that will
      // never arrive.
      final ok = await NotificationService.scheduleAt(
        id: 'test-reminder',
        title: 'Journey reminder',
        body: 'Time to start your journey!',
        scheduledTime: DateTime.now().add(const Duration(hours: 1)),
      );

      expect(ok, isFalse);
    });
  });
}
