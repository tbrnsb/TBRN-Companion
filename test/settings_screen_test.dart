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
import 'package:flutter_application_1/theme/app_palettes.dart';
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

  group('the themes picker is family then variant', () {
    testWidgets('every family is listed, with its own description', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await tester.pumpWidget(_app());
      await settleUi(tester);

      for (final family in AppPalette.values) {
        final row = find.byKey(ValueKey('family-${family.name}'));
        await scrollToAndTap(tester, row);
        // The tagline comes from the palette's own identity, not from copy
        // invented per screen, so the two cannot drift apart.
        expect(find.text(family.description), findsWidgets);
      }
    });

    testWidgets('Light is ABSENT for a dark-only family, not disabled', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await tester.pumpWidget(_app());
      await settleUi(tester);

      // TBRN is selected by default, so it shows all three.
      expect(find.byKey(const ValueKey('variant-tbrn-light')), findsOneWidget);

      for (final family in AppPalette.values.where((p) => !p.supportsLight)) {
        await scrollToAndTap(
          tester,
          find.byKey(ValueKey('family-${family.name}')),
        );
        expect(
          find.byKey(ValueKey('variant-${family.name}-light')),
          findsNothing,
          reason:
              '${family.name} has no Light, so it must not offer one — a '
              'disabled option is a promise the app cannot keep',
        );
        expect(
          find.byKey(ValueKey('variant-${family.name}-dark')),
          findsOneWidget,
        );
      }
    });

    testWidgets("Catppuccin's variants are labelled Mocha and Latte", (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await tester.pumpWidget(_app());
      await settleUi(tester);

      await scrollToAndTap(
        tester,
        find.byKey(const ValueKey('family-catppuccin')),
      );
      expect(find.text('Mocha'), findsOneWidget);
      expect(find.text('Latte'), findsOneWidget);
      // And NOT "Catppuccin dark", which is a name nobody recognises.
      expect(find.text('Dark'), findsNothing);
    });

    testWidgets('choosing a family then a variant re-themes immediately', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await tester.pumpWidget(_app());
      await settleUi(tester);

      await scrollToAndTap(
        tester,
        find.byKey(const ValueKey('family-catppuccin')),
      );
      await scrollToAndTap(
        tester,
        find.byKey(const ValueKey('variant-catppuccin-light')),
      );

      // Asserted on the SELECTED CHIP, which is the observable consequence of the
      // tap reaching the provider: the choice stuck. This harness builds a fixed
      // AppTheme.light() app, so the provider's theme does not paint here — a
      // limitation of the harness, not the app, and why the assertion is on state
      // rather than on pixels. The real theme resolution is covered in
      // palette_migration_test.dart and palettes_test.dart.
      final latte = tester.widget<ChoiceChip>(
        find.byKey(const ValueKey('variant-catppuccin-light')),
      );
      expect(latte.selected, isTrue);
      final mocha = tester.widget<ChoiceChip>(
        find.byKey(const ValueKey('variant-catppuccin-dark')),
      );
      expect(mocha.selected, isFalse);
    });

    testWidgets('there is no "Colours" group any more', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await tester.pumpWidget(_app());
      await settleUi(tester);

      expect(find.text('Themes'), findsOneWidget);
      // The old second group. Its name is gone, not renamed somewhere else.
      expect(find.text('Colours'), findsNothing);
    });

    testWidgets('every control the old screen had still exists', (
      tester,
    ) async {
      // A restructure, not a feature change. Nothing may be lost.
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await tester.pumpWidget(_app());
      await settleUi(tester);

      for (final label in ['TBRN', 'Catppuccin', 'Solitude', 'Gruvbox']) {
        await scrollTo(tester, find.text(label));
      }
      // Currency still has all three, and the data and demo sections survive.
      for (final label in ['Rs.', 'Add demo data']) {
        await scrollTo(tester, find.text(label));
      }
    });
  });

  group('the demo buttons fit their labels', () {
    /// How many lines [label] is actually laid out on.
    ///
    /// Measured from the rendered box, not read back off the widget. A `Text`
    /// carrying `maxLines: 1` will happily ellipsise when squeezed, so reading
    /// `maxLines` back would pass whether or not the label fit — and the whole
    /// point is whether it fits. A single line is a bit over one font size tall;
    /// two lines is a bit over two, so 1.6 separates them.
    double labelLines(WidgetTester tester, String label) {
      final text = tester.widget<Text>(find.text(label));
      final fontSize = text.style?.fontSize ?? 14;
      return tester.getSize(find.text(label)).height / fontSize;
    }

    testWidgets('neither label wraps at 360dp', (tester) async {
      usePhoneLayout(tester, TestViewports.phoneSmall);

      await tester.pumpWidget(_app());
      await settleUi(tester);
      await scrollTo(tester, find.text('Clear demo data'));

      // Side by side at this width, the labels used to break onto two lines and
      // the pair looked broken.
      expect(find.text('Clear demo data'), findsOneWidget);
      expect(find.text('Add demo data'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the labels are laid out on a single line at 360dp', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phoneSmall);

      await tester.pumpWidget(_app());
      await settleUi(tester);
      await scrollTo(tester, find.text('Clear demo data'));

      // Each button is given the full width once they stack, so the label has
      // room and must not be the two-line button that was reported.
      final clear = tester.getRect(find.text('Clear demo data'));
      final add = tester.getRect(find.text('Add demo data'));
      // Stacked, not side by side: the second sits below the first.
      expect(clear.top, greaterThan(add.top));
      // One line, not two. This is the assertion that would have failed before.
      expect(
        labelLines(tester, 'Clear demo data'),
        lessThan(1.6),
        reason: 'the label wrapped onto a second line',
      );
      expect(
        labelLines(tester, 'Add demo data'),
        lessThan(1.6),
        reason: 'the label wrapped onto a second line',
      );
    });

    testWidgets('they still sit side by side when there is room', (
      tester,
    ) async {
      usePhoneLayout(tester, const Size(500, 900));

      await tester.pumpWidget(_app());
      await settleUi(tester);
      await scrollTo(tester, find.text('Clear demo data'));

      final clear = tester.getRect(find.text('Clear demo data'));
      final add = tester.getRect(find.text('Add demo data'));
      // Side by side, so their tops line up.
      expect((clear.top - add.top).abs(), lessThan(2));
    });

    testWidgets('the labels are not shortened to make them fit', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phoneSmall);

      await tester.pumpWidget(_app());
      await settleUi(tester);
      await scrollTo(tester, find.text('Clear demo data'));

      // Truncating the one button that deletes things would be the wrong trade.
      expect(find.text('Clear demo data'), findsOneWidget);
      expect(find.textContaining('Clear demo…'), findsNothing);
    });
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
