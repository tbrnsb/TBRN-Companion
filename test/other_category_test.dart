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
      home: const OtherCategoryScreen(
        savedCustomNames: ['Coffee', 'Tickets'],
        suggestedNames: ['Groceries', 'Coffee'],
      ),
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
      expect(find.text('Food'), findsOneWidget);
      expect(find.text('Travel'), findsOneWidget);
    });

    testWidgets('the extra types are behind a control that expands', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phoneSmall);

      await tester.pumpWidget(_app());
      await settleUi(tester);

      // Nine categories is too long for a phone, so only a few show first.
      expect(find.textContaining('more type'), findsOneWidget);
      expect(find.text('Utilities'), findsNothing);

      // Already visible: it sits above the custom-name section. Scrolling to
      // it only pushed it against the fold and the tap missed.
      await tester.tap(find.textContaining('more type'));
      await settleUi(tester);

      // The row stays put and flips to its collapsed label, so it needs no
      // scrolling to find again.
      // The point is that the hidden types are now reachable, so this asserts
      // presence rather than a count: a ListView keeps scrolled-past children
      // in its cache, so a second copy can legitimately be in the tree.
      expect(find.text('Fewer types'), findsOneWidget);
      expect(find.textContaining('more type'), findsNothing);
      await scrollTo(tester, find.text('Utilities'));
      expect(find.text('Utilities'), findsWidgets);
      expect(find.text('Health'), findsWidgets);
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
