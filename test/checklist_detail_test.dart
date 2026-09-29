import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/checklist_provider.dart';
import 'package:flutter_application_1/screens/checklists/checklist_detail_screen.dart';
import 'package:flutter_application_1/services/storage_service.dart';
import 'package:flutter_application_1/theme/app_theme.dart';

import 'test_viewports.dart';
import 'visual_smoke_test.dart' show initTestStorage;

Future<void> settleUi(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Seeds one checklist whose first item starts checked, and returns the loaded
/// provider.
Future<ChecklistProvider> _seed(
  WidgetTester tester, {
  String name = 'Pack',
}) async {
  return (await tester.runAsync(() async {
    await StorageService().clear();

    final checklist = Checklist(name: name, description: 'Pack list');
    await StorageService().addChecklist(checklist);
    for (final item in ['Boots', 'Jacket', 'Map']) {
      await StorageService().addChecklistItem(
        ChecklistItem(
          name: item,
          checklistId: checklist.id,
          isChecked: item == 'Boots',
        ),
      );
    }

    final provider = ChecklistProvider();
    await provider.initialize();
    return provider;
  }))!;
}

Widget _app(ChecklistProvider provider) {
  return ChangeNotifierProvider<ChecklistProvider>.value(
    value: provider,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: Builder(
        builder: (context) =>
            ChecklistDetailScreen(checklist: provider.checklists.single),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    await initTestStorage();
  });

  group('single source of truth', () {
    // These drive the provider directly rather than through a tap. A tap
    // dispatches in the fake-async zone, the handler's continuations then sit in
    // that zone's queue, and the Hive writes it starts are real file IO. A
    // write begun in the fake zone never completes and leaves the box write
    // lock held, which deadlocks every later test in the file. Calling the
    // provider inside runAsync keeps every Hive write in real async.

    testWidgets('a rename through the provider updates the open screen', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final provider = await _seed(tester);
      final checklist = provider.checklists.single;

      await tester.pumpWidget(_app(provider));
      await settleUi(tester);

      expect(find.text('Pack'), findsWidgets);

      await tester.runAsync(() async {
        await provider.updateChecklist(
          checklist.copyWith(name: 'Pack for winter'),
        );
      });
      await settleUi(tester);

      // The screen used to hold its own `late Checklist` taken in initState, so
      // a rename arriving from the provider left the app bar showing the old
      // name while the provider and the list underneath held the new one.
      expect(
        find.text('Pack for winter'),
        findsWidgets,
        reason: 'the screen must derive from the provider by id',
      );
    });

    testWidgets('an item added through the provider appears on the open screen', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final provider = await _seed(tester);
      final checklist = provider.checklists.single;

      await tester.pumpWidget(_app(provider));
      await settleUi(tester);

      expect(find.text('Map'), findsOneWidget);
      expect(find.text('Tent'), findsNothing);

      await tester.runAsync(() async {
        await provider.addItemToChecklist(
          checklist.id,
          ChecklistItem(checklistId: checklist.id, name: 'Tent'),
        );
      });
      await settleUi(tester);

      expect(find.text('Tent'), findsOneWidget);
      expect(find.text('1 of 4 items checked'), findsOneWidget);
    });

    testWidgets('an item deleted through the provider disappears from the open screen', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final provider = await _seed(tester);
      final checklist = provider.checklists.single;

      await tester.pumpWidget(_app(provider));
      await settleUi(tester);

      final map = checklist.items.firstWhere((i) => i.name == 'Map');

      await tester.runAsync(() async {
        await provider.deleteChecklistItem(map.id);
      });
      await settleUi(tester);

      expect(find.text('Map'), findsNothing);
      expect(find.text('Boots'), findsOneWidget);
      expect(find.text('1 of 2 items checked'), findsOneWidget);
    });

    testWidgets('a checklist cleared through the provider empties the open screen', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final provider = await _seed(tester);
      final checklist = provider.checklists.single;

      await tester.pumpWidget(_app(provider));
      await settleUi(tester);

      await tester.runAsync(() async {
        await provider.clearCompletedItems(checklist.id);
      });
      await settleUi(tester);

      // The old code also rebuilt a private copy here, so the screen and the
      // provider each held their own item list.
      expect(find.text('Boots'), findsNothing);
      expect(find.text('Jacket'), findsOneWidget);
      expect(find.text('Map'), findsOneWidget);
      expect(find.text('0 of 2 items checked'), findsOneWidget);
    });

    testWidgets('the screen survives the checklist being deleted underneath it', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final provider = await _seed(tester);
      final checklist = provider.checklists.single;

      await tester.pumpWidget(_app(provider));
      await settleUi(tester);

      await tester.runAsync(() async {
        await provider.deleteChecklist(checklist.id);
      });
      await settleUi(tester);

      // Deriving by id means there is nothing left to derive, so the screen
      // falls back to the checklist it was handed rather than reading a
      // deleted record out of the provider.
      expect(tester.takeException(), isNull);
      expect(find.byType(ChecklistDetailScreen), findsOneWidget);
    });
  });

  group('popup menu', () {
    // Only synchronous behaviour is asserted here, for the reason given above:
    // these selections would start Hive writes from the fake-async zone.

    testWidgets('offers clear-packed only when something is checked', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final provider = await _seed(tester);
      await tester.pumpWidget(_app(provider));
      await settleUi(tester);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await settleUi(tester);

      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Duplicate'), findsOneWidget);
      expect(find.text('Uncheck all'), findsOneWidget);
      // "Boots" is checked in the seed, so the action is offered.
      expect(find.text('Clear packed items'), findsOneWidget);

      // With nothing checked the action has nothing to do and is hidden.
      await tester.runAsync(() async {
        await provider.resetChecklist(provider.checklists.single.id);
      });
      await settleUi(tester);

      await tester.tapAt(const Offset(200, 300));
      await settleUi(tester);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await settleUi(tester);

      expect(find.text('Clear packed items'), findsNothing);
      expect(find.text('Uncheck all'), findsOneWidget);
    });

    testWidgets('Uncheck all opens its confirmation and nothing else', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final provider = await _seed(tester);
      await tester.pumpWidget(_app(provider));
      await settleUi(tester);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await settleUi(tester);
      await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Uncheck all'));
      await settleUi(tester);

      expect(find.text('Reset Checklist?'), findsOneWidget);
      expect(find.text('This will uncheck all items. Are you sure?'), findsOneWidget);
      // Exactly one dialog: the switch cases do not fall through. Dart inserts
      // an implicit break when a case ends in a void-returning call, which is
      // why the analyzer is silent about the missing `break`s here.
      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });
}
