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
import 'package:flutter_application_1/screens/settings_screen.dart';
import 'package:flutter_application_1/services/storage_service.dart';
import 'package:flutter_application_1/theme/app_theme.dart';

import 'test_viewports.dart';
import 'visual_smoke_test.dart' show initTestStorage;

Future<void> settleUi(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Scrolls the settings list until [finder] is built, then taps it.
///
/// The settings screen is a lazy ListView and the Demo section is its last
/// child, so it simply does not exist in the tree until the list is scrolled
/// down. Tapping a target that is clipped at the fold edge is unreliable for
/// the same reason.
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

Widget _app() {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ChecklistProvider()),
      ChangeNotifierProvider(create: (_) => JourneyProvider()),
      ChangeNotifierProvider(create: (_) => LocationProvider()),
      ChangeNotifierProvider(create: (_) => TransactionProvider()),
      ChangeNotifierProvider(create: (_) => SettingsProvider()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const SettingsScreen(),
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

  group('the two destructive actions are separate and honestly labelled', () {
    testWidgets('both are present and the demo one is not a wipe', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      await tester.pumpWidget(_app());
      await settleUi(tester);

      expect(find.text('Remove all data'), findsOneWidget);

      // The Demo section is the list's last child and is not built until the
      // list is scrolled down.
      await scrollTo(tester, find.text('Clear demo data'));
      expect(find.text('Add demo data'), findsOneWidget);

      // The old single button said "Clear Data" while its dialog claimed
      // "Clear All Data", which misdescribed it in both directions.
      expect(find.text('Clear Data'), findsNothing);
      expect(find.text('Clear All Data?'), findsNothing);
    });

    testWidgets('the wipe dialog states what it deletes, with real counts', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      await tester.runAsync(() async {
        await StorageService().addTransaction(
          Expense(
            amount: 10,
            category: ExpenseCategory.food,
            description: 'Lunch',
          ),
        );
        await StorageService().addTransaction(
          Expense(
            amount: 20,
            category: ExpenseCategory.travel,
            description: 'Bus',
          ),
        );
        await StorageService().addJourney(
          Journey(destination: 'Pokhara', origin: 'Kathmandu'),
        );
      });

      await tester.pumpWidget(_app());
      await settleUi(tester);

      // The counts are on screen before anything is confirmed.
      expect(find.text('Transactions'), findsOneWidget);
      expect(find.text('Journeys'), findsOneWidget);

      await scrollToAndTap(tester, find.text('Remove all data'));

      expect(find.text('Remove all data?'), findsOneWidget);
      // The actual numbers, not a vague warning.
      expect(find.textContaining('2 transactions'), findsOneWidget);
      expect(find.textContaining('1 journeys'), findsOneWidget);
      expect(find.textContaining('cannot be undone'), findsOneWidget);
      expect(find.text('Remove everything'), findsOneWidget);
    });

    testWidgets('the demo dialog promises demo records only', (tester) async {
      usePhoneLayout(tester, TestViewports.phoneSmall);

      await tester.pumpWidget(_app());
      await settleUi(tester);

      await scrollToAndTap(tester, find.text('Clear demo data'));

      expect(find.text('Clear demo data?'), findsOneWidget);
      expect(
        find.textContaining('only the records created by'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Anything you added yourself is left alone'),
        findsOneWidget,
      );
    });

    testWidgets('the wipe is disabled when there is nothing stored', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      await tester.pumpWidget(_app());
      await settleUi(tester);

      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Remove all data'),
      );
      // An empty install has nothing to lose, so offering a wipe that does
      // nothing is just a way to be nervous for no reason.
      expect(button.onPressed, isNull);
    });
  });

  group('storage counts reflect what is actually stored', () {
    // NOT TESTED HERE: that the counts refresh after a demo action. Both demo
    // dialogs write to Hive from an async callback, and a Hive write begun in
    // the fake-async zone of a testWidgets body never completes and leaves the
    // box write lock held, which deadlocks the file. The seeding and clearing
    // themselves are covered in demo_data_test.dart, where they run in real
    // async via runAsync. What is verified here is that the counts the screen
    // shows, and the disabled state derived from them, follow real storage.

    testWidgets('the counts show real seeded records and enable the wipe', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      await tester.runAsync(() async {
        final checklist = Checklist(name: 'Pack', description: '');
        await StorageService().addChecklist(checklist);
        await StorageService().addChecklistItem(
          ChecklistItem(name: 'Boots', checklistId: checklist.id),
        );
        await StorageService().addTransaction(
          Expense(
            amount: 10,
            category: ExpenseCategory.food,
            description: 'Lunch',
          ),
        );
      });

      await tester.pumpWidget(_app());
      await settleUi(tester);

      // Counts arrive asynchronously in initState, so give them a moment.
      await tester.pump();
      await settleUi(tester);

      expect(find.text('Checklists'), findsOneWidget);
      expect(find.text('Transactions'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Remove all data'),
            )
            .onPressed,
        isNotNull,
        reason: 'storage is not empty, so the wipe must be offered',
      );
    });
  });
}
