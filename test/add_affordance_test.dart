import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/budget_provider.dart';
import 'package:flutter_application_1/providers/journey_provider.dart';
import 'package:flutter_application_1/providers/location_provider.dart';
import 'package:flutter_application_1/providers/settings_provider.dart';
import 'package:flutter_application_1/providers/transaction_provider.dart';
import 'package:flutter_application_1/screens/locations/locations_screen.dart';
import 'package:flutter_application_1/screens/transactions/transactions_screen.dart';
import 'package:flutter_application_1/services/storage_service.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/widgets/empty_state.dart';

import 'test_viewports.dart';
import 'visual_smoke_test.dart' show initTestStorage;

Future<void> settleUi(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The screen's add affordances, COUNTED BY TYPE.
///
/// Never by label. A label change could make a label-based assertion pass while
/// two buttons are still on screen, which is the exact bug this is guarding.
/// `FilledButton` is what [EmptyState] renders its action as; `IconButton` is
/// counted too because a screen could plausibly offer a compact add.
int addAffordanceCount(WidgetTester tester) {
  return find.byType(FloatingActionButton).evaluate().length +
      find
          .descendant(
            of: find.byType(EmptyState),
            matching: find.byType(FilledButton),
          )
          .evaluate()
          .length +
      find
          .descendant(
            of: find.byType(EmptyState),
            matching: find.byType(IconButton),
          )
          .evaluate()
          .length;
}

/// A tall viewport so the whole screen is laid out at once.
///
/// A lazy list disposes rows scrolled past, so a test that scrolls down and then
/// asserts about the top can report a false pass. Overflow is asserted separately
/// at both real viewports.
const Size _tall = Size(412, 2600);

Widget _app(Widget home, TransactionProvider transactions) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<TransactionProvider>.value(value: transactions),
      ChangeNotifierProvider(create: (_) => LocationProvider()),
      ChangeNotifierProvider(create: (_) => JourneyProvider()),
      ChangeNotifierProvider(create: (_) => BudgetProvider()),
      ChangeNotifierProvider(create: (_) => SettingsProvider()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: home,
    ),
  );
}

Expense _expense(double amount, ExpenseCategory category, String what) {
  return Expense(
    amount: amount,
    category: category,
    description: what,
    date: DateTime.now(),
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

  group('one add affordance per screen, counted by type', () {
    // RULE (a), decided once: the FAB is hidden while the list is empty and
    // EmptyState carries the action; the FAB returns as soon as there is a row.
    //
    // Three screens had the same structural mistake -- a FAB rendered
    // unconditionally OUTSIDE the empty check, plus an EmptyState with its own
    // action. Two buttons, one action, two shapes, on an empty list.
    testWidgets('transactions: empty list', (tester) async {
      usePhoneLayout(tester, _tall);
      final provider = (await tester.runAsync(() async {
        final p = TransactionProvider();
        await p.initialize();
        return p;
      }))!;

      await tester.pumpWidget(_app(const TransactionsScreen(), provider));
      await settleUi(tester);

      expect(provider.transactions, isEmpty);
      expect(
        addAffordanceCount(tester),
        1,
        reason:
            'an empty transaction list must offer exactly one way to add, '
            'not a FAB and an empty-state button doing the same thing',
      );
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(
        find.descendant(
          of: find.byType(EmptyState),
          matching: find.byType(FilledButton),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'transactions: with a row, the FAB is back and still only one',
      (tester) async {
        usePhoneLayout(tester, _tall);
        final provider = (await tester.runAsync(() async {
          final p = TransactionProvider();
          await p.initialize();
          await p.addTransaction(
            _expense(100, ExpenseCategory.food, 'An existing expense'),
          );
          return p;
        }))!;

        await tester.pumpWidget(_app(const TransactionsScreen(), provider));
        await settleUi(tester);

        expect(find.byType(FloatingActionButton), findsOneWidget);
        expect(find.byType(EmptyState), findsNothing);
        expect(
          addAffordanceCount(tester),
          1,
          reason:
              'the FAB returns as soon as there is something to add to, and '
              'must not be joined by a second button',
        );
      },
    );

    testWidgets('locations: an empty list offers exactly one', (tester) async {
      usePhoneLayout(tester, _tall);
      await tester.pumpWidget(_app(const LocationsScreen(), await _empty()));
      await settleUi(tester);

      // One affordance. The FAB used to render unconditionally on top of the
      // empty state's own "Add Location".
      expect(
        addAffordanceCount(tester),
        1,
        reason: 'an empty location list must offer exactly one way to add',
      );
    });
  });

  group('the search empty state does not add a second button', () {
    // Stage 6's search. It is a state that only exists once the feature landed,
    // so it was not in the original bug list and had to be checked separately.
    testWidgets('a search matching nothing offers no add of its own', (
      tester,
    ) async {
      usePhoneLayout(tester, _tall);
      final provider = (await tester.runAsync(() async {
        final p = TransactionProvider();
        await p.initialize();
        await p.addTransaction(
          _expense(100, ExpenseCategory.food, 'Something'),
        );
        return p;
      }))!;

      await tester.pumpWidget(_app(const TransactionsScreen(), provider));
      await settleUi(tester);

      // Search moved to its own screen, reached from the app bar. The LIST's job
      // here is unchanged: when a search is active it shows the results and says
      // so, and it grows no add affordance of its own.
      provider.search = const TransactionSearchQuery(text: 'zzzznothing');
      await settleUi(tester);

      expect(
        find.byKey(const ValueKey('active-search-banner')),
        findsOneWidget,
      );
      expect(find.textContaining('showing search results'), findsOneWidget);
      // The month still has a row, so the FAB is present and is the only add
      // affordance. The banner deliberately carries no add button either — it is
      // a statement about what is on screen, not an offer to change it.
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('active-search-banner')),
          matching: find.byType(FilledButton),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('active-search-banner')),
          matching: find.byType(FloatingActionButton),
        ),
        findsNothing,
      );
    });
  });
}

Future<TransactionProvider> _empty() async {
  final provider = TransactionProvider();
  await provider.initialize();
  return provider;
}
