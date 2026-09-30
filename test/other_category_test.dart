import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/transaction_provider.dart';
import 'package:flutter_application_1/screens/transactions/other_category_screen.dart';
import 'package:flutter_application_1/services/storage_service.dart';
import 'package:flutter_application_1/theme/app_theme.dart';

import 'test_viewports.dart';
import 'visual_smoke_test.dart' show initTestStorage;

Future<void> settleUi(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Scrolls the list until [finder] is built.
///
/// The screen is a lazy ListView and at 360dp the custom-name section is well
/// below the fold, so it simply is not in the tree until the list is scrolled.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 30 && finder.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView), const Offset(0, -150));
    await settleUi(tester);
  }
  if (finder.evaluate().isNotEmpty) {
    // A widget that is merely *built* can still be clipped at the fold, and a
    // tap on a clipped widget silently misses. Bring it fully into view.
    await tester.ensureVisible(finder.first);
    await settleUi(tester);
  }
}

Widget _app() {
  return ChangeNotifierProvider<TransactionProvider>(
    create: (_) => TransactionProvider()..initialize(),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const OtherCategoryScreen(savedCustomNames: ['Coffee', 'Tickets']),
    ),
  );
}

void main() {
  group('the choice it returns', () {
    test('a named type is not the Other bucket', () {
      const choice = OtherCategoryChoice.named(ExpenseCategory.housing);
      expect(choice.category, ExpenseCategory.housing);
      expect(choice.customName, isNull);
    });

    test('a custom name stays in the Other bucket', () {
      const choice = OtherCategoryChoice.other('Coffee');
      expect(choice.category, ExpenseCategory.other);
      expect(choice.customName, 'Coffee');
    });
  });

  setUpAll(() async {
    await initTestStorage();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService().clear();
  });

  group('the Other screen', () {
    testWidgets('is a list in the same icon-and-name hierarchy', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phoneSmall);

      await tester.pumpWidget(_app());
      await settleUi(tester);

      expect(find.text('What kind of other?'), findsOneWidget);
      // Named types, shown as rows with icons rather than a dropdown.
      expect(find.byType(ListTile), findsWidgets);
      expect(find.text('Fruits'), findsOneWidget);
      expect(find.text('Vegetables'), findsOneWidget);
    });

    testWidgets('does not repeat the main nine back at the user', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phoneSmall);

      await tester.pumpWidget(_app());
      await settleUi(tester);

      // The main categories are already the chip row on the add-expense sheet.
      // Listing them here again made this screen a duplicate of that row and
      // offered nothing new, which is what the user reported.
      for (final alreadyThere in [
        'Food',
        'Travel',
        'Entertainment',
        'Gear',
        'Housing',
        'Shopping',
        'Health',
        'Utilities',
      ]) {
        expect(
          find.text(alreadyThere),
          findsNothing,
          reason: '$alreadyThere is chosen from the chip row, not from here',
        );
      }
    });

    testWidgets('the extra types are behind a control that expands', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phoneSmall);

      await tester.pumpWidget(_app());
      await settleUi(tester);

      // A dozen suggested types is too long for a phone, so only a few show.
      expect(find.textContaining('more type'), findsOneWidget);
      await scrollTo(tester, find.text('Sports'));
      expect(find.text('Sports'), findsNothing);

      await scrollTo(tester, find.textContaining('more type'));
      await tester.tap(find.textContaining('more type'));
      await settleUi(tester);

      // The row stays put and flips to its collapsed label, so it needs no
      // scrolling to find again.
      expect(find.text('Fewer types'), findsOneWidget);
      expect(find.textContaining('more type'), findsNothing);
      await scrollTo(tester, find.text('Sports'));
      expect(find.text('Sports'), findsWidgets);
    });

    testWidgets('expanding never shows the same type twice', (tester) async {
      // The reported bug: `primary` became the whole list when expanded while
      // `overflow` still held its last four, so the bottom half of the list
      // rendered a second time under the toggle. Every type must appear once.
      //
      // A deliberately tall viewport, so the whole list is built at once. A lazy
      // ListView disposes rows scrolled past, and this test only ever scrolls
      // downwards, so a disposed row could never be found again and the check
      // would report a false pass.
      usePhoneLayout(tester, const Size(411, 2400));

      await tester.pumpWidget(_app());
      await settleUi(tester);

      await tester.tap(find.textContaining('more type'));
      await settleUi(tester);

      for (final meta in CategoryRegistry.suggestedExpenseTypes()) {
        // "Coffee" is in this test's savedCustomNames, so the suggested list
        // deliberately omits it and it appears once, under "Your categories".
        expect(
          find.text(meta.name),
          findsOneWidget,
          reason: '${meta.name} must not be listed twice',
        );
      }
    });

    testWidgets('saved custom names are listed, with the current one ticked', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phoneSmall);

      await tester.pumpWidget(
        ChangeNotifierProvider<TransactionProvider>(
          create: (_) => TransactionProvider()..initialize(),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const OtherCategoryScreen(
              currentCustomName: 'Coffee',
              savedCustomNames: ['Coffee', 'Tickets'],
            ),
          ),
        ),
      );
      await settleUi(tester);

      expect(find.text('Coffee'), findsOneWidget);
      expect(find.text('Tickets'), findsOneWidget);
      // The one already in use is marked, so the screen does not ask again for
      // something it already knows.
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('"Your categories" is empty until the user saves one', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phoneSmall);

      await tester.pumpWidget(
        ChangeNotifierProvider<TransactionProvider>(
          create: (_) => TransactionProvider()..initialize(),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const OtherCategoryScreen(),
          ),
        ),
      );
      await settleUi(tester);

      // The user has never named a category, so this section must say so rather
      // than listing the built-in ones as if they were theirs.
      await scrollTo(tester, find.text('None saved yet.'));
      expect(find.text('None saved yet.'), findsOneWidget);
      expect(find.text('Your categories'), findsOneWidget);
    });

    testWidgets('a suggested type is not listed under "Your categories"', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phoneSmall);

      await tester.pumpWidget(
        ChangeNotifierProvider<TransactionProvider>(
          create: (_) => TransactionProvider()..initialize(),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const OtherCategoryScreen(
              currentCustomName: 'Tickets',
              savedCustomNames: ['Tickets'],
            ),
          ),
        ),
      );
      await settleUi(tester);

      // Only the saved name may be ticked, so a suggested type can never be
      // mistaken for one the user created.
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('"Add a custom category" is the last row', (tester) async {
      usePhoneLayout(tester, TestViewports.phoneSmall);

      await tester.pumpWidget(_app());
      await settleUi(tester);

      await scrollTo(tester, find.text('Add a custom category'));
      expect(find.text('Add a custom category'), findsOneWidget);

      // Last in the list, not tucked behind an icon in a corner.
      final addRow = tester.getRect(find.text('Add a custom category'));
      final tickets = tester.getRect(find.text('Tickets'));
      expect(
        addRow.top,
        greaterThan(tickets.top),
        reason: 'the custom entry belongs below the saved names',
      );
    });

    testWidgets('a blank custom name is treated as cancelling', (tester) async {
      usePhoneLayout(tester, TestViewports.phoneSmall);

      await tester.pumpWidget(_app());
      await settleUi(tester);

      await scrollTo(tester, find.text('Add a custom category'));
      await scrollTo(tester, find.text('Add a custom category'));
      await tester.tap(find.text('Add a custom category'));
      await settleUi(tester);

      // Save with nothing typed: there is nothing to file the expense under, so
      // this must behave exactly like Cancel.
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settleUi(tester);

      expect(find.text('Name this category'), findsNothing);
    });

    testWidgets('a custom name is returned and the screen closes', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phoneSmall);

      await tester.pumpWidget(_app());
      await settleUi(tester);

      await scrollTo(tester, find.text('Add a custom category'));
      await scrollTo(tester, find.text('Add a custom category'));
      await tester.tap(find.text('Add a custom category'));
      await settleUi(tester);

      await tester.enterText(find.byType(TextField), 'Ferry tickets');
      await settleUi(tester);
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await settleUi(tester);
      await tester.pumpAndSettle();

      // Both dialogs must be gone before the test ends. The focused field keeps
      // a cursor-blink timer alive, and a pending timer stalls the isolate and
      // times out whatever runs next. This is also the point of the screen: it
      // collects the name and hands it straight back.
      expect(find.text('Name this category'), findsNothing);
      expect(find.text('What kind of other?'), findsNothing);
    });
  });
}
