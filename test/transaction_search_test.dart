import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/journey_provider.dart';
import 'package:flutter_application_1/providers/location_provider.dart';
import 'package:flutter_application_1/providers/settings_provider.dart';
import 'package:flutter_application_1/providers/transaction_provider.dart';
import 'package:flutter_application_1/screens/transactions/transactions_screen.dart';
import 'package:flutter_application_1/services/storage_service.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/widgets/empty_state.dart';

import 'test_viewports.dart';
import 'visual_smoke_test.dart' show initTestStorage;

/// Advances frames in bounded steps.
///
/// The search field takes focus on tap, and a blinking cursor schedules frames
/// forever, so `pumpAndSettle` would never return. Same reason as the spend
/// screen's `settleUi`.
Future<void> settleUi(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// A month with a spread of amounts, categories and descriptions.
///
/// Built from [now] so nothing here hardcodes a month name or a date, and the
/// search assertions can talk about "this month" without a calendar value.
List<Transaction> sampleMonth(DateTime now) {
  final month = DateTime(now.year, now.month);
  DateTime on(int day) => month.add(Duration(days: day - 1));

  return [
    Expense(
      amount: 450,
      category: ExpenseCategory.food,
      description: 'Groceries at the market',
      date: on(2),
    ),
    Expense(
      amount: 1200,
      category: ExpenseCategory.travel,
      description: 'Bus fare to the coast',
      date: on(5),
    ),
    Expense(
      amount: 300,
      category: ExpenseCategory.food,
      description: 'Coffee with Priya',
      date: on(9),
    ),
    Income(
      amount: 9000,
      category: 'salary',
      description: 'March salary',
      date: on(1),
    ),
  ];
}

/// Seeds a provider and builds the screen around it.
///
/// Hive writes hit the real filesystem, and a `testWidgets` body runs in a
/// fake-async zone where that never completes. Every write therefore goes
/// through [tester.runAsync]; the widget body only reads and taps.
Future<TransactionProvider> pumpSpendScreen(
  WidgetTester tester, {
  List<Transaction>? items,
}) async {
  final provider = (await tester.runAsync(() async {
    final p = TransactionProvider();
    await p.initialize();
    for (final item in items ?? sampleMonth(DateTime.now())) {
      await p.addTransaction(item);
    }
    return p;
  }))!;

  final settings = (await tester.runAsync(() async {
    final s = SettingsProvider();
    await s.load();
    return s;
  }))!;

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<TransactionProvider>.value(value: provider),
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider(create: (_) => JourneyProvider()),
        ChangeNotifierProvider(create: (_) => LocationProvider()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: const Scaffold(body: TransactionsScreen()),
      ),
    ),
  );
  await settleUi(tester);
  return provider;
}

/// The transaction descriptions currently on screen, in order.
///
/// The list lives below the summary card, the two donuts and a four-page chart
/// pager, so at any phone viewport the rows start off-screen. A `ListView` is
/// lazy and disposes rows scrolled past, so this reads only what is built RIGHT
/// NOW after the caller has scrolled — never "everything, eventually", which
/// would report a false pass whenever a row happened to be laid out.
List<String> visibleDescriptions(WidgetTester tester) {
  return tester
      .widgetList<ListTile>(find.byType(ListTile))
      .map((tile) {
        final title = tile.title;
        return title is Text ? (title.data ?? '') : '';
      })
      .where((text) => text.isNotEmpty)
      .toList();
}

/// A viewport tall enough that the whole screen is laid out at once.
///
/// The transaction rows sit below the summary card, a donut and a four-page
/// chart pager, so on a real phone they start off-screen and a lazy `ListView`
/// has not built them. Scrolling to them works, but it has a trap: a `ListView`
/// DISPOSES rows scrolled past, so a test that scrolls down and then asserts on
/// a row near the top reports a false pass or a confusing failure depending on
/// the viewport. A deliberately tall viewport removes the scroll entirely, which
/// is what the handoff's "a test that only scrolls downwards can report a false
/// pass" note is about.
///
/// This is NOT a substitute for the real viewports. Overflow is only ever
/// asserted at [TestViewports.phonePortrait] and [TestViewports.phoneSmall] —
/// see the `layout` group — and nothing here claims a phone was measured.
const Size _tallEnoughToBuildEveryRow = Size(412, 2600);

void main() {
  setUpAll(() async {
    await initTestStorage();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService().clear();
  });

  group('search over the month', () {
    testWidgets('the field is on screen with no interaction at all', (
      tester,
    ) async {
      usePhoneLayout(tester, _tallEnoughToBuildEveryRow);
      await pumpSpendScreen(tester);

      expect(find.byKey(const ValueKey('transaction-search-field')), findsOne);
      // Idle state: no summary line, because nothing is narrowed yet.
      expect(find.byKey(const ValueKey('search-summary')), findsNothing);
    });

    testWidgets('typing narrows the list to matching descriptions', (
      tester,
    ) async {
      usePhoneLayout(tester, _tallEnoughToBuildEveryRow);
      final provider = await pumpSpendScreen(tester);

      await tester.enterText(
        find.byKey(const ValueKey('transaction-search-field')),
        'coffee',
      );
      await settleUi(tester);

      expect(provider.hasActiveSearch, isTrue);
      expect(visibleDescriptions(tester), ['Coffee with Priya']);
      expect(find.text('Search results'), findsOne);
    });

    testWidgets(
      'a search with no hits says so and offers no second add button',
      (tester) async {
        usePhoneLayout(tester, _tallEnoughToBuildEveryRow);
        await pumpSpendScreen(tester);

        await tester.enterText(
          find.byKey(const ValueKey('transaction-search-field')),
          'zzzznothing',
        );
        await settleUi(tester);

        expect(find.text('Nothing matches'), findsOne);
        // The empty-results state must not grow its own add affordance: the FAB is
        // already on screen, and two of them is the bug this asserts against.
        // Counted by TYPE, so a label change cannot make this pass while two
        // buttons remain.
        expect(
          find.descendant(
            of: find.byType(EmptyState),
            matching: find.byType(FilledButton),
          ),
          findsNothing,
        );
        expect(find.byType(FloatingActionButton), findsOne);
      },
    );

    testWidgets('clearing the search restores the whole month', (tester) async {
      usePhoneLayout(tester, _tallEnoughToBuildEveryRow);
      await pumpSpendScreen(tester);
      final all = visibleDescriptions(tester).length;

      await tester.enterText(
        find.byKey(const ValueKey('transaction-search-field')),
        'coffee',
      );
      await settleUi(tester);
      expect(visibleDescriptions(tester), hasLength(1));

      await tester.tap(find.byKey(const ValueKey('search-clear-all')));
      await settleUi(tester);

      expect(visibleDescriptions(tester), hasLength(all));
      expect(find.byKey(const ValueKey('search-summary')), findsNothing);
    });
  });

  group('search composes with the rest of the view', () {
    testWidgets('a day filter does not hide what a search should find', (
      tester,
    ) async {
      usePhoneLayout(tester, _tallEnoughToBuildEveryRow);
      final provider = await pumpSpendScreen(tester);

      // Pin the view to a day that has no 'Groceries' on it.
      final groceries = sampleMonth(DateTime.now()).first.date;
      provider.setSelectedDay(groceries);
      await settleUi(tester);

      await tester.enterText(
        find.byKey(const ValueKey('transaction-search-field')),
        'bus fare',
      );
      await settleUi(tester);

      // Search reads the month, not the day-narrowed view. Reading the narrowed
      // view is what makes a search look broken: the row exists, the month
      // holds it, and the day toggle is unrelated to the question being asked.
      expect(visibleDescriptions(tester), ['Bus fare to the coast']);
    });

    testWidgets('the expense/income chips still narrow the results', (
      tester,
    ) async {
      usePhoneLayout(tester, _tallEnoughToBuildEveryRow);
      final provider = await pumpSpendScreen(tester);

      // A term every row shares, so only the chip can be what is filtering.
      await tester.enterText(
        find.byKey(const ValueKey('transaction-search-field')),
        'a',
      );
      await settleUi(tester);
      final beforeChip = visibleDescriptions(tester).length;

      provider.filter = TransactionFilter.income;
      await settleUi(tester);

      expect(visibleDescriptions(tester).length, lessThan(beforeChip));
      for (final description in visibleDescriptions(tester)) {
        expect(description.toLowerCase(), contains('salary'));
      }
    });
  });

  group('search filters', () {
    testWidgets('an amount range is applied and reported in words', (
      tester,
    ) async {
      usePhoneLayout(tester, _tallEnoughToBuildEveryRow);
      final provider = await pumpSpendScreen(tester);

      await tester.tap(find.byKey(const ValueKey('search-open-filters')));
      await settleUi(tester);
      await tester.enterText(
        find.byKey(const ValueKey('search-min-amount')),
        '400',
      );
      await tester.enterText(
        find.byKey(const ValueKey('search-max-amount')),
        '1500',
      );
      await tester.tap(find.byKey(const ValueKey('search-apply-filters')));
      await settleUi(tester);

      expect(provider.search.minAmount, 400);
      expect(provider.search.maxAmount, 1500);
      final shown = visibleDescriptions(tester);
      expect(shown, contains('Groceries at the market'));
      expect(shown, contains('Bus fare to the coast'));
      expect(shown, isNot(contains('Coffee with Priya')));
      // The summary names the range in words, so a narrowed search is never
      // mistaken for missing data.
      expect(find.byKey(const ValueKey('search-summary')), findsOne);
    });

    testWidgets('a category chip narrows to that category', (tester) async {
      usePhoneLayout(tester, _tallEnoughToBuildEveryRow);
      final provider = await pumpSpendScreen(tester);

      await tester.tap(find.byKey(const ValueKey('search-open-filters')));
      await settleUi(tester);
      // `travel.name` is not a const expression, so the key is built at runtime
      // rather than written as a literal that could drift from the enum.
      await tester.tap(
        find.byKey(ValueKey('search-cat-${ExpenseCategory.travel.name}')),
      );
      await tester.tap(find.byKey(const ValueKey('search-apply-filters')));
      await settleUi(tester);

      expect(provider.search.categories, {ExpenseCategory.travel.name});
      expect(visibleDescriptions(tester), ['Bus fare to the coast']);
    });

    testWidgets('a min above max says so instead of matching nothing quietly', (
      tester,
    ) async {
      usePhoneLayout(tester, _tallEnoughToBuildEveryRow);
      await pumpSpendScreen(tester);

      await tester.tap(find.byKey(const ValueKey('search-open-filters')));
      await settleUi(tester);
      await tester.enterText(
        find.byKey(const ValueKey('search-min-amount')),
        '900',
      );
      await tester.enterText(
        find.byKey(const ValueKey('search-max-amount')),
        '100',
      );
      await settleUi(tester);

      // An impossible range has to explain itself on the control, not return a
      // silent empty result that reads as a fault.
      expect(find.byKey(const ValueKey('search-range-warning')), findsOne);
    });

    testWidgets('cancelling the sheet changes nothing', (tester) async {
      usePhoneLayout(tester, _tallEnoughToBuildEveryRow);
      final provider = await pumpSpendScreen(tester);
      final before = provider.search;

      await tester.tap(find.byKey(const ValueKey('search-open-filters')));
      await settleUi(tester);
      await tester.enterText(
        find.byKey(const ValueKey('search-min-amount')),
        '500',
      );
      await tester.tap(find.text('Cancel'));
      await settleUi(tester);

      // A dismissed sheet is a cancel, not an apply. Treating the two the same
      // is the bug the day picker had.
      expect(provider.search, before);
    });
  });

  group('layout', () {
    for (final viewport in [
      TestViewports.phonePortrait,
      TestViewports.phoneSmall,
    ]) {
      testWidgets('the search bar fits and no card overflows at $viewport', (
        tester,
      ) async {
        usePhoneLayout(tester, viewport);
        final provider = await pumpSpendScreen(tester);

        // Force the widest case: field text, a range and a category all at
        // once, which is the row's worst realistic layout.
        provider.search = TransactionSearchQuery(
          text: 'a long enough phrase to fill the field',
          minAmount: 1000,
          maxAmount: 20000,
          categories: const {'food', 'travel'},
        );
        await settleUi(tester);

        expect(tester.takeException(), isNull);
      });
    }
  });
}
