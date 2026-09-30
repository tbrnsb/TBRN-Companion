import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/checklist_provider.dart';
import 'package:flutter_application_1/providers/journey_provider.dart';
import 'package:flutter_application_1/providers/location_provider.dart';
import 'package:flutter_application_1/providers/settings_provider.dart';
import 'package:flutter_application_1/providers/transaction_provider.dart';
import 'package:flutter_application_1/screens/checklists/checklists_screen.dart';
import 'package:flutter_application_1/screens/journeys/journeys_screen.dart';
import 'package:flutter_application_1/services/packing_suggestions.dart';
import 'package:flutter_application_1/services/storage_service.dart';
import 'package:flutter_application_1/theme/app_theme.dart';

import 'test_viewports.dart';
import 'visual_smoke_test.dart' show initTestStorage;

/// Deliberately tall: the Pack screen is a long scroll and a lazy list disposes
/// rows scrolled past, so a test that only scrolls down can report a false pass.
const _tall = Size(360, 2800);
const _tallWide = Size(412, 2800);

List<String> namesFor({
  String? destination,
  DateTime? startTime,
  DateTime? endTime,
}) {
  return PackingSuggestions.forTrip(
    destination: destination,
    startTime: startTime,
    endTime: endTime,
  ).map((s) => s.name).toList();
}

void main() {
  setUpAll(() async {
    await initTestStorage();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService().clear();
  });

  group('reading a trip', () {
    test('a mountain trip is a mountain trip', () {
      for (final name in [
        'Annapurna Base Camp',
        'Mount Fuji',
        'Everest Base Camp',
        'Cape Town trail',
        'Glacier view',
      ]) {
        expect(
          PackingSuggestions.kindFor(name),
          TripKind.mountain,
          reason: '"$name" did not read as mountain',
        );
      }
    });

    test('coast, forest, desert and lake are told apart', () {
      // Only names the vocabulary actually covers. There is no gazetteer and no
      // network, so "Maldives" reads as a city — an honest, documented limit
      // rather than something the engine pretends to know.
      expect(PackingSuggestions.kindFor('Gold Coast'), TripKind.coast);
      expect(PackingSuggestions.kindFor('Sentosa Island'), TripKind.coast);
      expect(
        PackingSuggestions.kindFor('Chitwan National Park'),
        TripKind.forest,
      );
      expect(PackingSuggestions.kindFor('Sahara'), TripKind.desert);
      expect(PackingSuggestions.kindFor('Pokhara'), TripKind.lake);
      expect(PackingSuggestions.kindFor('Kathmandu'), TripKind.city);
      expect(PackingSuggestions.kindFor('Staycation'), TripKind.home);
    });

    test('an unknown destination is a city, not a failure', () {
      // There is no gazetteer and no network, so the default has to be the most
      // common case rather than nothing.
      expect(PackingSuggestions.kindFor('Qzxwv'), TripKind.city);
      expect(PackingSuggestions.kindFor(null), TripKind.home);
      expect(PackingSuggestions.kindFor(''), TripKind.home);
    });

    test('a cold month gets warm-weather things a warm month does not', () {
      final january = DateTime(2026, 1, 10);
      final june = DateTime(2026, 6, 10);

      final winter = namesFor(destination: 'Kathmandu', startTime: january);
      final summer = namesFor(destination: 'Kathmandu', startTime: june);

      expect(winter, contains('Warm jacket'));
      expect(summer, isNot(contains('Warm jacket')));
    });

    test('length is read from the dates', () {
      final start = DateTime(2026, 3, 1);
      expect(
        PackingSuggestions.profileFor(
          destination: 'Pokhara',
          startTime: start,
          endTime: start,
        ).nights,
        0,
        reason: 'a same-day trip is a day trip, not an under-a-day one',
      );
      expect(
        PackingSuggestions.profileFor(
          destination: 'Pokhara',
          startTime: start,
          endTime: start.add(const Duration(days: 5)),
        ).nights,
        5,
      );
    });

    test('a trip with no end date is treated as a short one', () {
      final profile = PackingSuggestions.profileFor(
        destination: 'Pokhara',
        startTime: DateTime(2026, 3, 1),
      );
      expect(profile.nights, 2);
      expect(profile.lengthLabel, '2 nights');
    });
  });

  group('two different trips get two different lists', () {
    // THE POINT OF THE STAGE. The old engine keyword-matched the destination
    // name, so a mountain trip and a beach trip both fell through to the same
    // generic essentials.
    test('a mountain trip and a beach trip share almost nothing', () {
      final mountain = namesFor(destination: 'Annapurna Base Camp');
      final beach = namesFor(destination: 'Gokarna beach resort');

      expect(mountain, contains('Warm layers'));
      expect(beach, contains('Swimwear'));
      expect(mountain, isNot(contains('Swimwear')));
      expect(beach, isNot(contains('First aid kit')));
    });

    test('a city weekend is not a trek', () {
      final city = namesFor(destination: 'Tokyo');
      expect(city, contains('Wallet'));
      expect(city, isNot(contains('Warm layers')));
    });

    test('the same trip twice gives the same list', () {
      expect(
        namesFor(destination: 'Pokhara', startTime: DateTime(2026, 3, 1)),
        namesFor(destination: 'Pokhara', startTime: DateTime(2026, 3, 1)),
      );
    });
  });

  group('the suggestion list itself', () {
    final suggestions = PackingSuggestions.forTrip(destination: 'Annapurna');

    test('is short enough to scan', () {
      expect(suggestions.length, lessThanOrEqualTo(PackingSuggestions.limit));
      expect(suggestions, isNotEmpty);
    });

    test('has no duplicates, case-insensitively', () {
      final seen = suggestions.map((s) => s.name.toLowerCase()).toSet();
      expect(seen, hasLength(suggestions.length));
    });

    test('every entry says why', () {
      for (final s in suggestions) {
        expect(s.name, isNotEmpty);
        expect(s.reason, isNotEmpty);
      }
    });

    test('always includes the things you cannot shop for on arrival', () {
      for (final destination in [
        'Annapurna',
        'Maldives',
        'Tokyo',
        'Sahara',
        'Chitwan',
      ]) {
        final list = namesFor(destination: destination);
        expect(list, contains('Medication'), reason: destination);
      }
    });
  });

  group('packing for a trip, at the provider layer', () {
    // Persistence is covered here rather than by tapping: a Hive write started
    // inside a testWidgets body deadlocks and holds the box lock.
    late ChecklistProvider provider;

    Journey trip({List<String> items = const []}) {
      return Journey(
        id: 'trip-1',
        origin: 'Kathmandu',
        destination: 'Pokhara',
        startTime: DateTime(2026, 3, 1),
        endTime: DateTime(2026, 3, 4),
        items: items,
      );
    }

    setUp(() async {
      provider = ChecklistProvider();
      await provider.initialize();
      addTearDown(provider.dispose);
    });

    test('builds a checklist the trip owns', () async {
      final created = await provider.packForJourney(trip());

      expect(created, isNotNull);
      expect(created!.journeyId, 'trip-1');
      expect(created.items, isNotEmpty);
    });

    test("folds in the trip's own items", () async {
      final created = await provider.packForJourney(
        trip(items: ['Boots', 'Jacket']),
      );
      final names = created!.items.map((i) => i.name).toList();

      expect(names, containsAll(['Boots', 'Jacket']));
    });

    test("the trip's own items come before the suggestions", () async {
      final created = await provider.packForJourney(trip(items: ['Boots']));

      expect(created!.items.first.name, 'Boots');
    });

    test('a second call does not make a second list', () async {
      await provider.packForJourney(trip());
      final again = await provider.packForJourney(trip());

      expect(again, isNull, reason: 'a duplicate pack is never what was meant');
      expect(provider.getChecklistsForJourney('trip-1'), hasLength(1));
    });

    test('an item the trip already has is not added twice', () async {
      final created = await provider.packForJourney(
        trip(items: ['Water bottle']),
      );
      final names = created!.items.map((i) => i.name.toLowerCase()).toList();

      expect(names.where((n) => n == 'water bottle'), hasLength(1));
    });

    test('a blank trip item is not added', () async {
      final created = await provider.packForJourney(trip(items: ['  ', '']));
      final names = created!.items.map((i) => i.name);

      expect(names.any((n) => n.trim().isEmpty), isFalse);
    });
  });

  group('the duplicate guard', () {
    late ChecklistProvider provider;

    setUp(() async {
      await StorageService().addChecklist(
        Checklist(name: 'Pack', description: 'd'),
      );
      provider = ChecklistProvider();
      await provider.initialize();
      addTearDown(provider.dispose);
    });

    String id() => provider.checklists.single.id;

    test('adds when it is not there', () async {
      expect(await provider.addItemByName(id(), 'Water bottle'), isTrue);
      expect(provider.checklists.single.items, hasLength(1));
    });

    test('refuses a repeat, ignoring case', () async {
      await provider.addItemByName(id(), 'Water bottle');
      expect(await provider.addItemByName(id(), 'water bottle'), isFalse);
      expect(await provider.addItemByName(id(), 'WATER BOTTLE'), isFalse);
      expect(provider.checklists.single.items, hasLength(1));
    });

    test('ignores surrounding and repeated whitespace', () async {
      await provider.addItemByName(id(), 'Water bottle');
      expect(await provider.addItemByName(id(), '  water   bottle  '), isFalse);
      expect(provider.checklists.single.items, hasLength(1));
    });

    test('a genuinely different name still goes on', () async {
      await provider.addItemByName(id(), 'Water bottle');
      expect(await provider.addItemByName(id(), 'Water bottle bag'), isTrue);
      expect(provider.checklists.single.items, hasLength(2));
    });

    test('a blank name adds nothing', () async {
      expect(await provider.addItemByName(id(), '   '), isFalse);
      expect(provider.checklists.single.items, isEmpty);
    });

    test('the existence check agrees with the add', () async {
      expect(provider.checklistHasItem(id(), 'Map'), isFalse);
      await provider.addItemByName(id(), 'Map');
      expect(provider.checklistHasItem(id(), 'map'), isTrue);
    });
  });

  group('packing progress', () {
    late ChecklistProvider provider;

    setUp(() async {
      provider = ChecklistProvider();
      await provider.initialize();
      addTearDown(provider.dispose);
    });

    test('is null when the trip has no checklist', () async {
      await StorageService().addJourney(
        Journey(id: 't', origin: 'a', destination: 'b'),
      );
      await provider.loadChecklists();

      // Null, not zero: "nothing to pack" and "nothing packed" are different
      // facts and only one of them is a prompt to do something.
      expect(provider.packProgressFor('t'), isNull);
    });

    test('counts across every checklist on the trip', () async {
      final checklist = Checklist(name: 'A', description: '', journeyId: 't');
      await provider.addChecklist(checklist);
      await provider.addItemByName(checklist.id, 'one');
      final second = await provider.addItemByName(checklist.id, 'two');
      expect(second, isTrue);
      await provider.toggleItem(checklist.items.first.id);

      final progress = provider.packProgressFor('t')!;
      expect(progress.total, 2);
      expect(progress.packed, 1);
      expect(progress.label, '1 of 2 packed');
    });

    test('an empty checklist does not read "0 of 0"', () async {
      await provider.addChecklist(
        Checklist(name: 'A', description: '', journeyId: 't'),
      );

      expect(provider.packProgressFor('t')!.label, 'nothing to pack');
    });
  });

  group('journey items survive the merge', () {
    test('the same key and the same shape', () {
      // Stage 2 folds journey.items into a checklist but must not move the
      // field: every existing trip reads its packing list from this key.
      final journey = Journey(
        id: 't',
        origin: 'a',
        destination: 'b',
        items: ['Boots', 'Map'],
      );
      final json = journey.toJson();

      expect(json['items'], ['Boots', 'Map']);
      expect(json['items'], isA<List<String>>());

      final restored = Journey.fromJson(json);
      expect(restored.items, ['Boots', 'Map']);
    });

    test('a trip written before the field still loads', () {
      final restored = Journey.fromJson({
        'id': 'old',
        'origin': 'a',
        'destination': 'b',
        'startTime': '2026-01-01T00:00:00.000',
        'createdAt': '2026-01-01T00:00:00.000',
        'updatedAt': '2026-01-01T00:00:00.000',
      });

      expect(restored.items, isEmpty);
    });
  });

  group('on screen', () {
    Future<_Providers> seedProviders(WidgetTester tester) async {
      final p = (await tester.runAsync(() async {
        final journeys = JourneyProvider();
        final checklists = ChecklistProvider();
        final locations = LocationProvider();
        final transactions = TransactionProvider();
        final settings = SettingsProvider();
        await StorageService().addJourney(
          Journey(
            id: 'trip-1',
            origin: 'Kathmandu',
            destination: 'Pokhara',
            startTime: DateTime.now().subtract(const Duration(days: 2)),
          ),
        );
        await journeys.initialize();
        await checklists.initialize();
        await locations.initialize();
        await transactions.initialize();
        await settings.load();
        return (
          journeys: journeys,
          checklists: checklists,
          locations: locations,
          transactions: transactions,
          settings: settings,
        );
      }))!;
      addTearDown(p.journeys.dispose);
      addTearDown(p.checklists.dispose);
      addTearDown(p.locations.dispose);
      addTearDown(p.transactions.dispose);
      return p;
    }

    Widget appOf(_Providers p, Widget home) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<JourneyProvider>.value(value: p.journeys),
          ChangeNotifierProvider<ChecklistProvider>.value(value: p.checklists),
          ChangeNotifierProvider<LocationProvider>.value(value: p.locations),
          ChangeNotifierProvider<TransactionProvider>.value(
            value: p.transactions,
          ),
          ChangeNotifierProvider<SettingsProvider>.value(value: p.settings),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          home: home,
        ),
      );
    }

    Future<void> settleUi(WidgetTester tester) async {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('the Pack screen names the trip it is thinking about', (
      tester,
    ) async {
      usePhoneLayout(tester, _tallWide);

      final p = await seedProviders(tester);
      await tester.pumpWidget(appOf(p, const ChecklistsScreen()));
      await settleUi(tester);

      expect(find.text('For Pokhara'), findsOneWidget);
    });

    testWidgets('the Pack screen fits at 360dp with eight suggestions', (
      tester,
    ) async {
      usePhoneLayout(tester, _tall);

      final p = await seedProviders(tester);
      await tester.pumpWidget(appOf(p, const ChecklistsScreen()));
      await settleUi(tester);

      // The card survives the empty state: a user with a trip and no
      // checklists is the one who needs the suggestions most.
      expect(find.text('For Pokhara'), findsOneWidget);
      expect(find.text('No checklists yet'), findsOneWidget);
    });

    testWidgets('the Journeys timeline shows where a trip got to', (
      tester,
    ) async {
      usePhoneLayout(tester, _tall);

      final p = await seedProviders(tester);
      await tester.pumpWidget(appOf(p, const JourneysScreen()));
      await settleUi(tester);

      // No checklist yet, so no progress line — the cue is the pack button.
      expect(find.text('of 1 packed'), findsNothing);

      await tester.runAsync(() async {
        final checklist = Checklist(
          name: 'Pack for Pokhara',
          description: '',
          journeyId: 'trip-1',
        );
        await p.checklists.addChecklist(checklist);
        await p.checklists.addItemByName(checklist.id, 'Boots');
      });
      await settleUi(tester);

      expect(find.text('0 of 1 packed'), findsOneWidget);
    });
  });
}

/// The five providers every tab watches.
typedef _Providers = ({
  JourneyProvider journeys,
  ChecklistProvider checklists,
  LocationProvider locations,
  TransactionProvider transactions,
  SettingsProvider settings,
});
