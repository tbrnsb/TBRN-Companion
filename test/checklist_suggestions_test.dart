import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/checklist_provider.dart';
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
    testWidgets('suggestions are buttons, not inert chips', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final provider = await _seed(tester);
      await tester.pumpWidget(_app(provider));
      await settleUi(tester);

      // The card is on screen, which is what makes the chips reachable.
      expect(find.text('Trip suggestions'), findsOneWidget);
      expect(find.text('Weekend pack'), findsWidgets);

      // The recommendations for a trip whose destination contains neither
      // business, weekend, camp nor flight fall back to the essentials set.
      final suggestions = provider.getRecommendedItemsForTrip(
        tripType: 'Pokhara',
        notes: '',
        destination: 'Pokhara',
      );
      for (final item in suggestions) {
        expect(
          find.widgetWithText(ActionChip, item),
          findsOneWidget,
          reason: '"$item" is shown as a plain Chip, so it cannot be tapped',
        );
      }

      // A plain Chip has no onPressed and no tooltip; an ActionChip has both.
      expect(
        tester
            .widget<ActionChip>(
              find.widgetWithText(ActionChip, suggestions.first),
            )
            .tooltip,
        isNotNull,
      );
    });

    testWidgets('tapping a suggestion asks which checklist to add it to', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final provider = await _seed(tester);
      await tester.pumpWidget(_app(provider));
      await settleUi(tester);

      final suggestion = provider
          .getRecommendedItemsForTrip(
            tripType: 'Pokhara',
            notes: '',
            destination: 'Pokhara',
          )
          .first;

      expect(find.text('Tap one to add it to a checklist.'), findsOneWidget);

      await tester.tap(find.widgetWithText(ActionChip, suggestion));
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

      final suggestion = provider
          .getRecommendedItemsForTrip(
            tripType: 'Pokhara',
            notes: '',
            destination: 'Pokhara',
          )
          .first;

      await tester.tap(find.widgetWithText(ActionChip, suggestion));
      await settleUi(tester);

      expect(find.text('Add to which checklist?'), findsNothing);
    });
  });
}
