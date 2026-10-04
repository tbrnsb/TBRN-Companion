import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/providers/journey_provider.dart';
import 'package:daily_companion/providers/location_provider.dart';
import 'package:daily_companion/providers/settings_provider.dart';
import 'package:daily_companion/providers/transaction_provider.dart';
import 'package:daily_companion/screens/transactions/expense_detail_screen.dart';
import 'package:daily_companion/screens/transactions/income_detail_screen.dart';
import 'package:daily_companion/screens/transactions/transaction_search_view.dart';
import 'package:daily_companion/screens/transactions/transactions_screen.dart';
import 'package:daily_companion/services/storage_service.dart';
import 'package:daily_companion/theme/app_theme.dart';
import 'package:daily_companion/widgets/app_search.dart';

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

/// Opens the dedicated search view over the same provider.
///
/// A push rather than a rebuild, so these tests exercise the real route the app
/// bar button takes — including that the field arrives focused.
Future<TransactionProvider> openSearchView(WidgetTester tester) async {
  await tester.tap(find.byKey(AppSearchButton.buttonKey));
  await settleUi(tester);
  final context = tester.element(find.byType(TransactionSearchView));
  return Provider.of<TransactionProvider>(context, listen: false);
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

  group('what free text looks at', () {
    // THE CAUSE OF "search finds nothing", and it was not the provider.
    //
    // `searchResults` already read `myLedger` and already checked the active
    // filter; both were correct. `TransactionSearchQuery.matches` tested the
    // DESCRIPTION and nothing else, so typing a category name returned nothing
    // while the list displayed that category on every matching row. The search
    // was not broken — it was searching less than it was showing, and the user's
    // evidence that it was broken was the row directly under the field.
    test('a category name finds rows labelled with that category', () {
      final food = sampleMonth(DateTime.now())
          .firstWhere((t) => t.effectiveCategoryName.toLowerCase() == 'food');
      final query = const TransactionSearchQuery(text: 'food');

      expect(
        query.matches(food),
        isTrue,
        reason: 'the word is on the row, so searching for it must find the row',
      );
    });

    test('a description still matches', () {
      final coffee = sampleMonth(DateTime.now())
          .firstWhere((t) => t.description.toLowerCase().contains('coffee'));
      expect(
        const TransactionSearchQuery(text: 'coffee').matches(coffee),
        isTrue,
      );
    });

    test('a number on the row finds that row', () {
      final item = sampleMonth(DateTime.now()).first;
      final digits = item.amount.toStringAsFixed(0);
      expect(
        const TransactionSearchQuery(text: '450').matches(item),
        isTrue,
        reason: 'the amount is displayed, so it must be searchable',
      );
      expect(digits.isNotEmpty, isTrue);
    });

    test('a word that is on no row finds nothing', () {
      final item = sampleMonth(DateTime.now()).first;
      expect(
        const TransactionSearchQuery(text: 'zzzznothing').matches(item),
        isFalse,
      );
    });

    test('an empty query matches everything', () {
      final item = sampleMonth(DateTime.now()).first;
      expect(const TransactionSearchQuery().matches(item), isTrue);
    });
  });

  group('the search view', () {
    // THE FIELD MOVED OUT OF THE LIST. It used to sit inline above the month
    // summary and the charts, so typing in it re-sorted the list under you and
    // made every chart on the screen recalculate for a query the charts do not
    // answer. Search now has one home.
    testWidgets('there is ONE search field, and the list has none', (
      tester,
    ) async {
      usePhoneLayout(tester, _tallEnoughToBuildEveryRow);
      await pumpSpendScreen(tester);

      // The list no longer carries a field of its own. Two fields writing the
      // same query is the bug this branch exists to remove.
      expect(
        find.byKey(const ValueKey('transaction-search-field')),
        findsNothing,
      );
      expect(find.byType(TextField), findsNothing);

      // And the way in is the app bar button, which is keyed rather than found by
      // icon — the search VIEW is full of search icons.
      expect(find.byKey(AppSearchButton.buttonKey), findsOne);
    });

    testWidgets('it opens from the app bar with the field already focused', (
      tester,
    ) async {
      usePhoneLayout(tester, _tallEnoughToBuildEveryRow);
      await pumpSpendScreen(tester);

      final provider = await openSearchView(tester);

      expect(find.byType(TransactionSearchView), findsOne);
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('search-view-field')),
      );
      expect(
        field.focusNode!.hasFocus,
        isTrue,
        reason:
            'a search screen that '
            'needs a second tap before it does anything is a screen nobody types '
            'into',
      );
      // Idle: no criteria bar, because nothing is narrowed yet.
      expect(find.byKey(const ValueKey('search-view-criteria')), findsNothing);
      expect(provider.hasActiveSearch, isFalse);
    });

    testWidgets('typing narrows the results, live', (tester) async {
      usePhoneLayout(tester, _tallEnoughToBuildEveryRow);
      await pumpSpendScreen(tester);
      // The call opens the view; nothing here reads the provider back.
      await openSearchView(tester);

      await tester.enterText(
        find.byKey(const ValueKey('search-view-field')),
        'coffee',
      );
      await settleUi(tester);

      // Asserted on what the SCREEN shows, not on `provider.hasActiveSearch`.
      // The query lives in the view's own state now, and that is the point:
      // a search is scoped to the screen that asked it.
      expect(visibleDescriptions(tester), ['Coffee with Priya']);
      expect(find.byKey(const ValueKey('search-result-count')), findsOne);
    });

    testWidgets('a result row shows title, category, date and amount', (
      tester,
    ) async {
      // Every field a row SHOWS is a field the search LOOKS at. That is the rule
      // that stops this screen asking the user to search for something it will
      // not show them.
      usePhoneLayout(tester, _tallEnoughToBuildEveryRow);
      await pumpSpendScreen(tester);
      await openSearchView(tester);

      await tester.enterText(
        find.byKey(const ValueKey('search-view-field')),
        'coffee',
      );
      await settleUi(tester);

      final tile = tester.widget<ListTile>(find.byType(ListTile).first);
      expect((tile.title! as Text).data, 'Coffee with Priya');
      // The category AS LABELLED, which is what the row shows and therefore what
      // the search must look at.
      final subtitle = (tile.subtitle! as Text).data!;
      expect(subtitle, contains('Food'));
      // The row's OWN date, not today's: the date is displayed, so it must be
      // read off the tile rather than recomputed, or this asserts nothing.
      expect(
        subtitle,
        contains(
          DateFormat.yMMMd().format(
            sampleMonth(DateTime.now())
                .firstWhere((t) => t.description == 'Coffee with Priya')
                .date,
          ),
        ),
      );
      // The amount off the transaction, not a literal. A hardcoded figure here
      // would keep asserting 450 after the fixture's amount changed, and would
      // then be testing the fixture rather than the row.
      expect(
        (tile.trailing! as Text).data,
        contains(
          sampleMonth(DateTime.now())
              .firstWhere((t) => t.description == 'Coffee with Priya')
              .amount
              .toStringAsFixed(0),
        ),
      );
    });

    testWidgets('a search with no hits says so, and says WHY', (tester) async {
      usePhoneLayout(tester, _tallEnoughToBuildEveryRow);
      await pumpSpendScreen(tester);
      await openSearchView(tester);

      await tester.enterText(
        find.byKey(const ValueKey('search-view-field')),
        'zzzznothing',
      );
      await settleUi(tester);

      // "No results" and "no data" must not look the same: the first means the
      // app has plenty and your query excluded it.
      expect(find.byKey(const ValueKey('search-view-empty-title')), findsOne);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('search-view-empty-title')))
            .data,
        'Nothing matches that search',
      );
      expect(
        find.byKey(const ValueKey('active-search-banner')),
        findsNothing,
        reason: 'the banner belongs to the list, not to this screen',
      );
    });

    testWidgets('clearing brings every row back', (tester) async {
      usePhoneLayout(tester, _tallEnoughToBuildEveryRow);
      await pumpSpendScreen(tester);
      await openSearchView(tester);
      final all = visibleDescriptions(tester).length;

      await tester.enterText(
        find.byKey(const ValueKey('search-view-field')),
        'coffee',
      );
      await settleUi(tester);
      expect(visibleDescriptions(tester), hasLength(1));

      await tester.tap(find.byKey(const ValueKey('search-view-clear')));
      await settleUi(tester);

      expect(visibleDescriptions(tester).length, greaterThanOrEqualTo(all));
      expect(find.byKey(const ValueKey('search-view-criteria')), findsNothing);
    });

    testWidgets('an income result opens the INCOME detail', (tester) async {
      // Routed by the transaction's own kind, so an income row can never open
      // the expense editor and silently offer to edit the wrong record.
      usePhoneLayout(tester, _tallEnoughToBuildEveryRow);
      await pumpSpendScreen(tester);
      await openSearchView(tester);

      await tester.enterText(
        find.byKey(const ValueKey('search-view-field')),
        'Salary',
      );
      await settleUi(tester);
      expect(visibleDescriptions(tester), isNotEmpty);

      await tester.tap(find.byType(ListTile).first);
      await settleUi(tester);

      expect(find.byType(IncomeDetailScreen), findsOne);
      expect(find.byType(ExpenseDetailScreen), findsNothing);
    });

    testWidgets('an expense result opens the EXPENSE detail', (tester) async {
      usePhoneLayout(tester, _tallEnoughToBuildEveryRow);
      await pumpSpendScreen(tester);
      await openSearchView(tester);

      await tester.enterText(
        find.byKey(const ValueKey('search-view-field')),
        'coffee',
      );
      await settleUi(tester);

      await tester.tap(find.byType(ListTile).first);
      await settleUi(tester);

      expect(find.byType(ExpenseDetailScreen), findsOne);
      expect(find.byType(IncomeDetailScreen), findsNothing);
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

      await openSearchView(tester);
      await tester.enterText(
        find.byKey(const ValueKey('search-view-field')),
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
      await openSearchView(tester);
      await tester.enterText(
        find.byKey(const ValueKey('search-view-field')),
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
      await pumpSpendScreen(tester);

      await openSearchView(tester);
      await tester.tap(find.byKey(const ValueKey('search-view-filters')));
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

      // The criteria are read off the visible results and the criteria bar,
      // not off the provider: the query is the view's own state now.
      final shown = visibleDescriptions(tester);
      expect(shown, contains('Groceries at the market'));
      expect(shown, contains('Bus fare to the coast'));
      expect(shown, isNot(contains('Coffee with Priya')));
      // The summary names the range in words, so a narrowed search is never
      // mistaken for missing data.
      expect(find.byKey(const ValueKey('search-view-criteria')), findsOne);
    });

    testWidgets('a category chip narrows to that category', (tester) async {
      usePhoneLayout(tester, _tallEnoughToBuildEveryRow);
      await pumpSpendScreen(tester);

      await openSearchView(tester);
      await tester.tap(find.byKey(const ValueKey('search-view-filters')));
      await settleUi(tester);
      // `travel.name` is not a const expression, so the key is built at runtime
      // rather than written as a literal that could drift from the enum.
      await tester.tap(
        find.byKey(ValueKey('search-cat-${ExpenseCategory.travel.name}')),
      );
      await tester.tap(find.byKey(const ValueKey('search-apply-filters')));
      await settleUi(tester);

      expect(visibleDescriptions(tester), ['Bus fare to the coast']);
    });

    testWidgets('a min above max says so instead of matching nothing quietly', (
      tester,
    ) async {
      usePhoneLayout(tester, _tallEnoughToBuildEveryRow);
      await pumpSpendScreen(tester);
      await openSearchView(tester);

      await tester.tap(find.byKey(const ValueKey('search-view-filters')));
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
      await pumpSpendScreen(tester);
      await openSearchView(tester);
      // The rows BEFORE the sheet, so "changes nothing" is checked against what
      // the screen actually shows rather than against provider state the view no
      // longer touches.
      final before = visibleDescriptions(tester);

      await tester.tap(find.byKey(const ValueKey('search-view-filters')));
      await settleUi(tester);
      await tester.enterText(
        find.byKey(const ValueKey('search-min-amount')),
        '500',
      );
      await tester.tap(find.text('Cancel'));
      await settleUi(tester);

      // A dismissed sheet is a cancel, not an apply. Treating the two the same
      // is the bug the day picker had. A cancelled sheet that narrowed to the
      // rows over 500 would look exactly like a working filter.
      expect(visibleDescriptions(tester), before);
      expect(find.byKey(const ValueKey('search-view-criteria')), findsNothing);
    });
  });

  group('search does not follow you out of the search screen', () {
    // The bug this group exists for, reported from the field: type something
    // that matches nothing, go back, and the whole month is gone from the
    // list, showing "nothing matched" with no way back to the transactions.
    //
    // The cause is that the search view writes the query into the SHARED
    // provider (`provider.search`) and never clears it, while the transaction
    // list switches its entire body to the search result set whenever
    // `hasActiveSearch` is true. Leaving search therefore left the list
    // rendering the search's results permanently.
    //
    // A search is a question asked on one screen. It must not survive the
    // screen that asked it.
    testWidgets(
      'going back from a search that matched nothing restores the list',
      (tester) async {
        usePhoneLayout(tester, _tallEnoughToBuildEveryRow);
        final provider = await pumpSpendScreen(tester);
        final monthTotal = provider.filteredTransactions.length;
        expect(
          monthTotal,
          greaterThan(0),
          reason: 'the fixture month has rows',
        );

        await openSearchView(tester);
        await tester.enterText(
          find.byKey(const ValueKey('search-view-field')),
          'zzzznothing',
        );
        await settleUi(tester);
        expect(visibleDescriptions(tester), isEmpty);

        // Leave, the way a user does: the system back gesture.
        await tester.binding.handlePopRoute();
        await settleUi(tester);

        // The transaction list is showing again, with the month, not the query.
        expect(
          provider.hasActiveSearch,
          isFalse,
          reason:
              'leaving search must clear the shared query, or the list '
              'keeps rendering search results after search is gone',
        );
        expect(visibleDescriptions(tester).length, greaterThan(0));
      },
    );

    testWidgets('a search that DID match still does not leak back', (
      tester,
    ) async {
      usePhoneLayout(tester, _tallEnoughToBuildEveryRow);
      final provider = await pumpSpendScreen(tester);

      await openSearchView(tester);
      await tester.enterText(
        find.byKey(const ValueKey('search-view-field')),
        'coffee',
      );
      await settleUi(tester);

      await tester.binding.handlePopRoute();
      await settleUi(tester);

      // A leaking "coffee" filter would be less alarming than "nothing matched"
      // but just as wrong: the list would show a subset and call it the month.
      expect(provider.hasActiveSearch, isFalse);
      expect(
        visibleDescriptions(tester).length,
        provider.filteredTransactions.length,
      );
    });

    testWidgets('reopening search does not resurrect the old query', (
      tester,
    ) async {
      usePhoneLayout(tester, _tallEnoughToBuildEveryRow);
      await pumpSpendScreen(tester);

      await openSearchView(tester);
      await tester.enterText(
        find.byKey(const ValueKey('search-view-field')),
        'coffee',
      );
      await settleUi(tester);
      await tester.binding.handlePopRoute();
      await settleUi(tester);

      await openSearchView(tester);

      // A fresh search screen starts empty. Carrying the last query forward
      // means the second search silently inherits the first one's filter.
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('search-view-field')))
            .controller!
            .text,
        isEmpty,
      );
      expect(visibleDescriptions(tester).length, greaterThan(1));
    });

    testWidgets('the list no longer offers a search mode of its own', (
      tester,
    ) async {
      usePhoneLayout(tester, _tallEnoughToBuildEveryRow);
      final provider = await pumpSpendScreen(tester);

      // If a search is active, the list must NOT be showing search results.
      // This is the invariant, stated directly, so a future change that routes
      // the query back into the list fails here rather than on a device.
      provider.search = TransactionSearchQuery(text: 'coffee');
      await settleUi(tester);

      expect(
        find.byKey(const ValueKey('active-search-banner')),
        findsNothing,
        reason: 'the list is not a search surface; the banner must not exist',
      );
      expect(
        visibleDescriptions(tester).length,
        provider.filteredTransactions.length,
      );
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
        await pumpSpendScreen(tester);
        await openSearchView(tester);

        // Force the widest case, on the screen that now owns the query: field
        // text plus a range plus a category all at once, which is the
        // criteria bar's worst realistic layout. Setting `provider.search`
        // used to be how this was reached, which is exactly the coupling the
        // leak fix removed — the query is set here the way a user sets it.
        await tester.enterText(
          find.byKey(const ValueKey('search-view-field')),
          'a long enough phrase to fill the field',
        );
        await settleUi(tester);
        await tester.tap(find.byKey(const ValueKey('search-view-filters')));
        await settleUi(tester);
        await tester.enterText(
          find.byKey(const ValueKey('search-min-amount')),
          '1000',
        );
        await tester.enterText(
          find.byKey(const ValueKey('search-max-amount')),
          '20000',
        );
        await settleUi(tester);
        await tester.tap(
          find.byKey(ValueKey('search-cat-${ExpenseCategory.food.name}')),
        );
        await tester.tap(find.byKey(const ValueKey('search-apply-filters')));
        await settleUi(tester);

        // All three criteria are showing at once, which is the case that
        // would overflow.
        expect(find.byKey(const ValueKey('search-view-criteria')), findsOne);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
