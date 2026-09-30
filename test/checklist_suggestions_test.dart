import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/checklist_provider.dart';
import 'package:flutter_application_1/services/packing_suggestions.dart';
import 'package:flutter_application_1/providers/journey_provider.dart';
import 'package:flutter_application_1/providers/location_provider.dart';
import 'package:flutter_application_1/screens/checklists/checklists_screen.dart';
import 'package:flutter_application_1/services/storage_service.dart';
import 'package:flutter_application_1/theme/app_theme.dart';

import 'test_viewports.dart';
import 'visual_smoke_test.dart' show initTestStorage;

Future<void> settleUi(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<ChecklistProvider> _seed(WidgetTester tester) async {
  return (await tester.runAsync(() async {
    await StorageService().clear();

    // An active journey is what makes the suggestion card appear at all.
    await StorageService().addJourney(
      Journey(
        destination: 'Pokhara',
        origin: 'Kathmandu',
        startTime: DateTime.now().subtract(const Duration(days: 1)),
      ),
    );

    final weekend = Checklist(name: 'Weekend pack', description: '');
    final backup = Checklist(name: 'Backup list', description: '');
    await StorageService().addChecklist(weekend);
    await StorageService().addChecklist(backup);
    await StorageService().addChecklistItem(
      ChecklistItem(name: 'Tent', checklistId: weekend.id, isChecked: true),
    );

    final provider = ChecklistProvider();
    await provider.initialize();
    return provider;
  }))!;
}

Widget _app(ChecklistProvider checklists) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ChecklistProvider>.value(value: checklists),
      ChangeNotifierProvider(create: (_) => JourneyProvider()..initialize()),
      ChangeNotifierProvider(create: (_) => LocationProvider()..initialize()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const ChecklistsScreen(),
    ),
  );
}

void main() {
  setUpAll(() async {
    await initTestStorage();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('one way to create a checklist', () {
    testWidgets('the empty state offers exactly one call to action', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      final empty = (await tester.runAsync(() async {
        await StorageService().clear();
        final provider = ChecklistProvider();
        await provider.initialize();
        return provider;
      }))!;
      await settleUi(tester);

      await tester.pumpWidget(_app(empty));
      await settleUi(tester);

      expect(find.text('No checklists yet'), findsOneWidget);
      // The empty state's own button.
      expect(find.text('Create Checklist'), findsOneWidget);
      // And no FAB saying "New Checklist" underneath it. Two buttons doing the
      // same thing, worded differently, on the same screen.
      expect(find.text('New Checklist'), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('the FAB comes back once there is a checklist', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      final withOne = (await tester.runAsync(() async {
        await StorageService().clear();
        final provider = ChecklistProvider();
        await provider.initialize();
        await provider.addChecklist(
          Checklist(name: 'Weekend', description: ''),
        );
        return provider;
      }))!;
      await settleUi(tester);

      await tester.pumpWidget(_app(withOne));
      await settleUi(tester);

      expect(find.text('No checklists yet'), findsNothing);
      expect(find.text('New Checklist'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });
  });

  group('trip suggestions are actionable', () {
    // The suggestions are now read from the trip itself rather than matched
    // against its name, so these tests take them from the engine directly and
    // assert on what the screen shows.
    List<String> suggestionsFor(String destination) {
      return PackingSuggestions.forTrip(destination: destination)
          .map((s) => s.name)
          .toList();
    }

    testWidgets('suggestions are buttons, not inert chips', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final provider = await _seed(tester);
      await tester.pumpWidget(_app(provider));
      await settleUi(tester);

      // The card names the trip it is thinking about.
      expect(find.text('For Pokhara'), findsOneWidget);
      expect(
        find.text('Based on where you are going and when.'),
        findsOneWidget,
      );

      final suggestions = suggestionsFor('Pokhara');
      expect(suggestions, isNotEmpty);
      for (final item in suggestions) {
        expect(
          find.byKey(ValueKey('add-suggestion-$item')),
          findsOneWidget,
          reason: '"$item" has no add button, so it cannot be acted on',
        );
      }
    });

    testWidgets('every suggestion says why it is on the list', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final provider = await _seed(tester);
      await tester.pumpWidget(_app(provider));
      await settleUi(tester);

      // A bare list of guesses is what this replaced. The reason is the
      // difference between a suggestion and an instruction.
      //
      // Counted, not matched against a literal. The reason text is a function of
      // the month — 'it turns cool by evening' in the cold season, 'for the boat
      // ride in the evening' otherwise — so asserting one specific string made
      // this test fail the day the season changed, for no change in the code.
      final suggestions = PackingSuggestions.forTrip(destination: 'Pokhara');
      expect(suggestions, isNotEmpty);
      for (final suggestion in suggestions) {
        expect(suggestion.reason, isNotEmpty);
      }
      // Asserted on a reason that does not vary with the month. Several of these
      // do — 'it turns cool by evening' in the cold season, something else
      // otherwise — so a literal here would have failed the day the season
      // turned, for no change in the code.
      expect(
        find.text('you will be out on the water all day'),
        findsOneWidget,
        reason: 'the sun hat must explain itself',
      );
      // And every suggestion got a row, which is the thing the reasons hang off.
      for (final suggestion in suggestions) {
        expect(
          find.byKey(ValueKey('add-suggestion-${suggestion.name}')),
          findsOneWidget,
        );
      }
    });

    testWidgets('tapping a suggestion asks which checklist to add it to', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final provider = await _seed(tester);
      await tester.pumpWidget(_app(provider));
      await settleUi(tester);

      final suggestion = suggestionsFor('Pokhara').first;

      await tester.tap(find.byKey(ValueKey('add-suggestion-$suggestion')));
      await settleUi(tester);

      // The picker offers the real checklists, so the suggestion has somewhere
      // to go. Previously the chip did nothing at all.
      expect(find.text('Add to which checklist?'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Weekend pack'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Backup list'), findsOneWidget);
    });

    testWidgets('a single checklist skips the picker', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final provider = await _seed(tester);
      await tester.runAsync(() async {
        await StorageService().deleteChecklist(provider.checklists.last.id);
        await provider.loadChecklists();
      });

      await tester.pumpWidget(_app(provider));
      await settleUi(tester);

      expect(provider.checklists, hasLength(1));

      final suggestion = suggestionsFor('Pokhara').first;

      await tester.tap(find.byKey(ValueKey('add-suggestion-$suggestion')));
      await settleUi(tester);

      expect(find.text('Add to which checklist?'), findsNothing);
    });
  });
}
