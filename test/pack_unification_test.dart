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
import 'package:daily_companion/services/storage_service.dart';
import 'package:daily_companion/theme/app_theme.dart';

import 'test_viewports.dart';
import 'visual_smoke_test.dart' show initTestStorage;

/// Deliberately tall: the Pack screen is a long scroll and a lazy list disposes
/// rows scrolled past, so a test that only scrolls down can report a false pass.
const _tall = Size(360, 2800);

void main() {
  setUpAll(() async {
    await initTestStorage();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService().clear();
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
    });

    test('adds nothing the trip did not itself list', () async {
      // The build seeded a list from a keyword match on the destination, so a
      // trip called "SmatErr" matched nothing and got the same generic eight
      // items every other unrecognised name got. Those guesses were the first
      // thing on the Pack tab and pushed the trip's real list below the fold,
      // which read as the list not existing.
      final created = await provider.packForJourney(
        trip(items: ['Boots', 'Jacket']),
      );
      final names = created!.items.map((i) => i.name).toSet();

      expect(names, {'Boots', 'Jacket'});
    });

    test("folds in the trip's own items", () async {
      final created = await provider.packForJourney(
        trip(items: ['Boots', 'Jacket']),
      );
      final names = created!.items.map((i) => i.name).toList();

      expect(names, containsAll(['Boots', 'Jacket']));
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

  group('a journey typed with items gets a real checklist', () {
    // The reported bug: items typed while creating a journey never appeared in
    // the Pack tab, and the trip's own "Pack for this trip" button stayed on
    // screen forever. Both had the same cause -- `Journey.items` is a plain
    // `List<String>` with no ticks, no ids, and no place in the Pack tab, and
    // the button only ever checked whether a *Checklist* existed, which none
    // ever did.
    late JourneyProvider journeys;
    late ChecklistProvider checklists;

    setUp(() async {
      journeys = JourneyProvider();
      checklists = ChecklistProvider();
      await journeys.initialize();
      await checklists.initialize();
      addTearDown(journeys.dispose);
      addTearDown(checklists.dispose);
    });

    test('the items become a checklist the trip owns', () async {
      final journey = await journeys.startJourney(
        destination: 'SmatErr',
        origin: 'Home',
        items: ['Boots', 'Jacket', 'Passport'],
        checklists: checklists,
      );

      final owned = checklists.getChecklistsForJourney(journey.id);
      expect(owned, hasLength(1));
      expect(owned.single.items.map((i) => i.name).toSet(), {
        'Boots',
        'Jacket',
        'Passport',
      });
    });

    test('the pack button question is answered: the trip HAS a list', () async {
      // The button is gated on this exact condition. While it was false the
      // button stayed on screen and, tapped, reported "Already packed for this
      // trip" -- telling the user they had packed when they had never been able
      // to tick anything.
      final journey = await journeys.startJourney(
        destination: 'SmatErr',
        origin: 'Home',
        items: ['Boots'],
        checklists: checklists,
      );

      expect(checklists.getChecklistsForJourney(journey.id), isNotEmpty);
      expect(checklists.packProgressFor(journey.id), isNotNull);
    });

    test('the items are tickable, which is the whole point', () async {
      final journey = await journeys.startJourney(
        destination: 'SmatErr',
        origin: 'Home',
        items: ['Boots', 'Jacket'],
        checklists: checklists,
      );

      expect(checklists.packProgressFor(journey.id)?.total, 2);

      final boots = checklists
          .getChecklistsForJourney(journey.id)
          .single
          .items
          .firstWhere((i) => i.name == 'Boots');
      await checklists.toggleItem(boots.id);

      expect(checklists.packProgressFor(journey.id)?.packed, 1);
      expect(checklists.packProgressFor(journey.id)?.total, 2);
    });

    test('a journey with NO items still gets no empty list', () async {
      // An empty checklist is a dead screen with a tick on nothing. The trip
      // simply has nothing to pack, which is a different fact and the "Pack for
      // this trip" button is the right answer to it.
      final journey = await journeys.startJourney(
        destination: 'Somewhere',
        origin: 'Home',
        checklists: checklists,
      );

      expect(checklists.getChecklistsForJourney(journey.id), isEmpty);
      expect(checklists.packProgressFor(journey.id), isNull);
    });

    test(
      'packing for the same trip again does not make a second list',
      () async {
        final journey = await journeys.startJourney(
          destination: 'SmatErr',
          origin: 'Home',
          items: ['Boots'],
          checklists: checklists,
        );

        final again = await checklists.packForJourney(journey);

        expect(again, isNull);
        expect(checklists.getChecklistsForJourney(journey.id), hasLength(1));
      },
    );

    test('a LEGACY journey keeps its items reachable', () {
      // A journey written before this change has items in `Journey.items` and
      // no checklist. The header still shows them, or they would be visible
      // nowhere at all.
      final legacy = Journey(
        id: 'legacy',
        destination: 'Old Trip',
        origin: 'Home',
        items: ['Old Item'],
        startTime: DateTime(2026, 3, 1),
      );
      expect(legacy.items, ['Old Item']);
    });
  });

  group('a solo trip is not a shared trip nobody joined', () {
    // "There should be an option to put this as a solo journey, so there is no
    // add people to it."
    //
    // The distinction matters because they LOOK the same: a journey with no
    // participants and a journey declared solo are both lists of one. But the
    // first is a shared trip waiting for people and keeps offering the field;
    // the second is a trip the user said they did not want to share, and offers
    // only the control that turns sharing back on.
    test('the flag survives a save and reload', () async {
      final journeys = JourneyProvider();
      addTearDown(journeys.dispose);
      await journeys.initialize();

      final journey = await journeys.startJourney(
        destination: 'SmatErr',
        origin: 'Home',
        isSolo: true,
      );
      expect(journey.isSolo, isTrue);
      expect(journeys.getJourneyById(journey.id)!.isSolo, isTrue);
    });

    test('a trip with no participants and NOT solo keeps its shared section', () {
      // The default is unchanged. This is the regression the flag could cause:
      // treating "unknown" as "solo" would hide sharing on every trip.
      final shared = Journey(
        destination: 'Somewhere',
        origin: 'Here',
        startTime: DateTime(2026, 3, 1),
      );
      expect(shared.participants, isEmpty);
      expect(shared.isSolo, isFalse);
    });

    test('adding a participant takes the trip out of solo', () async {
      final journeys = JourneyProvider();
      addTearDown(journeys.dispose);
      await journeys.initialize();

      final journey = await journeys.startJourney(
        destination: 'SmatErr',
        origin: 'Home',
        isSolo: true,
      );

      await journeys.addParticipant(journey.id, 'Raj');

      // Otherwise the trip would hide the very section the user is using.
      expect(journeys.getJourneyById(journey.id)!.isSolo, isFalse);
    });

    test('a solo trip can be made shared again', () async {
      // The flag is set from the start-trip form and cleared from the trip's
      // own Shared block, so both directions have to work and neither may be
      // reachable only at creation.
      final journeys = JourneyProvider();
      addTearDown(journeys.dispose);
      await journeys.initialize();

      final journey = await journeys.startJourney(
        destination: 'SmatErr',
        origin: 'Home',
        isSolo: true,
      );

      await journeys.setSolo(journey.id, solo: false);

      expect(journeys.getJourneyById(journey.id)!.isSolo, isFalse);
    });

    test('going solo takes the people off the trip', () async {
      // THE FAULT. `setSolo` only flipped the flag. A trip that already had a
      // roster kept every one of them on the record while every screen switched
      // to the solo branch: a trip that says nobody is on it, still carrying
      // the people it used to carry, and a roster that came back the moment
      // the flag was taken off.
      final journeys = JourneyProvider();
      addTearDown(journeys.dispose);
      await journeys.initialize();

      final journey = await journeys.startJourney(
        destination: 'SmatErr',
        origin: 'Home',
      );
      await journeys.addParticipant(journey.id, 'Raj');
      await journeys.addParticipant(journey.id, 'Mina');

      await journeys.setSolo(journey.id, solo: true);

      final saved = journeys.getJourneyById(journey.id)!;
      expect(saved.isSolo, isTrue);
      expect(
        saved.participants,
        isEmpty,
        reason:
            'a solo trip has nobody on it; a roster left behind by a flag is '
            'a roster the solo screens cannot show and the trip cannot lose',
      );
    });

    test('going solo on a trip with nobody leaves it with nobody', () async {
      final journeys = JourneyProvider();
      addTearDown(journeys.dispose);
      await journeys.initialize();

      final journey = await journeys.startJourney(
        destination: 'SmatErr',
        origin: 'Home',
      );

      await journeys.setSolo(journey.id, solo: true);

      final saved = journeys.getJourneyById(journey.id)!;
      expect(saved.isSolo, isTrue);
      expect(saved.participants, isEmpty);
    });

    test('taking the solo flag back off invents no participants', () async {
      // Both directions are reachable — the flag is set at creation and taken
      // off from the trip's own Shared block — so the way back has to leave
      // the trip as empty as it found it. A trip with nobody on it is a shared
      // trip nobody has joined yet, not a trip with a roster.
      final journeys = JourneyProvider();
      addTearDown(journeys.dispose);
      await journeys.initialize();

      final journey = await journeys.startJourney(
        destination: 'SmatErr',
        origin: 'Home',
        isSolo: true,
      );
      expect(journeys.getJourneyById(journey.id)!.participants, isEmpty);

      await journeys.setSolo(journey.id, solo: false);

      final shared = journeys.getJourneyById(journey.id)!;
      expect(shared.isSolo, isFalse);
      expect(
        shared.participants,
        isEmpty,
        reason: 'un-soloing must not invent the people the trip never had',
      );
      expect(shared.isShared, isFalse);

      // And the trip can go back to solo without losing anything twice.
      await journeys.setSolo(journey.id, solo: true);
      final soloAgain = journeys.getJourneyById(journey.id)!;
      expect(soloAgain.isSolo, isTrue);
      expect(soloAgain.participants, isEmpty);
    });

    test('a journey written before the flag existed is not solo', () {
      final legacy = Journey.fromJson({
        'destination': 'Old Trip',
        'origin': 'Home',
        'startTime': DateTime(2026, 3, 1).toIso8601String(),
        'createdAt': DateTime(2026, 3, 1).toIso8601String(),
        'updatedAt': DateTime(2026, 3, 1).toIso8601String(),
      });

      // Absent means false. Reading "unknown" as "solo" would hide the shared
      // section on every journey already on the device.
      expect(legacy.isSolo, isFalse);
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

    testWidgets('the Pack screen shows no suggestion card for an active trip', (
      tester,
    ) async {
      // A trip is seeded, so the old build rendered "For Pokhara" plus eight
      // suggested items ABOVE the trip's own list. That card is gone, and the
      // empty state is what a trip with nothing packed now looks like.
      usePhoneLayout(tester, _tall);

      final p = await seedProviders(tester);
      await tester.pumpWidget(appOf(p, const ChecklistsScreen()));
      await settleUi(tester);

      expect(find.text('For Pokhara'), findsNothing);
      expect(find.text('No checklists yet'), findsOneWidget);
    });

    testWidgets("the trip's own checklist is visible without scrolling to it", (
      tester,
    ) async {
      usePhoneLayout(tester, _tall);

      final p = await seedProviders(tester);
      await tester.runAsync(() async {
        // The context card is seeded deliberately. Without one in the tree the
        // ordering cannot be observed, so the assertion below would pass even
        // with the old card-first layout -- which is exactly the bug, and it
        // means a test that only checks "the list is on screen" proves nothing.
        final essentials = Checklist(
          name: 'Everyday Essentials',
          description: '',
          isEverydayEssentials: true,
        );
        await p.checklists.addChecklist(essentials);
        await p.checklists.addItemByName(essentials.id, 'Toothbrush');

        final checklist = Checklist(
          name: 'Pack for Pokhara',
          description: '',
          journeyId: 'trip-1',
        );
        await p.checklists.addChecklist(checklist);
        await p.checklists.addItemByName(checklist.id, 'Boots');
      });
      await tester.pumpWidget(appOf(p, const ChecklistsScreen()));
      await settleUi(tester);

      expect(find.text('Your checklists'), findsOneWidget);
      expect(find.text('Pack for Pokhara'), findsOneWidget);

      // The user's own list comes FIRST, the context card second. They used to
      // be the other way round, so someone who had packed a dozen things into a
      // journey scrolled past decoration before finding their own list and
      // concluded it was missing. It was never missing; it was below the fold.
      //
      // `first` is deliberate. A reversal renders the card twice rather than
      // moving it, so `findsOneWidget` here would fail on the symptom and hide
      // the cause. Comparing positions of the FIRST match states the rule
      // directly: the user's heading is above the card, and the card is above
      // nothing that matters.
      final userHeading = tester.getTopLeft(find.text('Your checklists'));
      final packRow = tester.getTopLeft(find.text('Pack for Pokhara'));
      final contextCard = tester.getTopLeft(
        find.text('Everyday Essentials').first,
      );

      expect(
        userHeading.dy,
        lessThan(packRow.dy),
        reason: 'the heading must sit above the row it introduces',
      );
      expect(
        userHeading.dy,
        lessThan(contextCard.dy),
        reason: "the user's own list is not below a context card",
      );
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
