import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/journey_provider.dart';
import 'package:flutter_application_1/providers/location_provider.dart';
import 'package:flutter_application_1/providers/settings_provider.dart';
import 'package:flutter_application_1/providers/transaction_provider.dart';
import 'package:flutter_application_1/screens/transactions/add_expense_sheet.dart';
import 'package:flutter_application_1/screens/transactions/income_detail_screen.dart';
import 'package:flutter_application_1/screens/transactions/transactions_screen.dart';
import 'package:flutter_application_1/services/storage_service.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/widgets/spend_breakdown_card.dart';

import 'visual_smoke_test.dart' show initTestStorage;
import 'test_viewports.dart';

/// Advances frames in bounded steps.
///
/// `pumpAndSettle` cannot be used here: both add sheets autofocus their amount
/// field, so the blinking text cursor schedules frames forever and
/// `pumpAndSettle` would never return.
Future<void> settleUi(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Scrolls the primary scrollable until [finder] is built and on screen.
///
/// At phone sizes the transaction rows sit below the fold, so a bare
/// `find.text` fails on layout position rather than on the behaviour under
/// test. Scrolling is what a user does to reach them, and the assertion that
/// follows is unchanged.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    150,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 60,
  );
  await settleUi(tester);
}

/// Hive writes hit the real filesystem, and a `testWidgets` body runs in a
/// fake-async zone where that never completes. Every mutation therefore has to
/// be driven through [tester.runAsync]; the widget body only reads.
Future<TransactionProvider> seedProvider(
  WidgetTester tester,
  List<Transaction> items,
) async {
  return (await tester.runAsync(() async {
    final provider = TransactionProvider();
    await provider.initialize();
    for (final item in items) {
      await provider.addTransaction(item);
    }
    return provider;
  }))!;
}

Future<SettingsProvider> seededSettings(
  WidgetTester tester, {
  Currency? currency,
}) async {
  return (await tester.runAsync(() async {
    final settings = SettingsProvider();
    await settings.load();
    if (currency != null) {
      await settings.setCurrency(currency);
    }
    return settings;
  }))!;
}

/// Scopes a finder to the open chooser bottom sheet.
///
/// The filter row on the screen underneath also labels a chip "Expense" and a
/// chip "Income", so a bare `find.text` is ambiguous once the chooser is up.
Finder inChooser(String text) =>
    find.descendant(of: find.byType(BottomSheet), matching: find.text(text));

Expense _expense(double amount, ExpenseCategory category, String description) {
  return Expense(
    amount: amount,
    category: category,
    description: description,
    date: DateTime.now(),
  );
}

Income _income(double amount, String category, String description) {
  return Income(
    amount: amount,
    category: category,
    description: description,
    date: DateTime.now(),
  );
}

void main() {
  setUpAll(() async {
    await initTestStorage();
  });

  setUp(() async {
    // The mock preferences store is process-wide, so a currency saved by one
    // test would otherwise leak into the next one.
    SharedPreferences.setMockInitialValues({});
    await StorageService().clear();
  });

  group('category breakdown charts', () {
    testWidgets('shows a spending chart and an income chart for both types', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final provider = await seedProvider(tester, [
        _expense(120, ExpenseCategory.food, 'Lunch'),
        _expense(30, ExpenseCategory.travel, 'Bus'),
        _income(900, 'salary', 'Payday'),
      ]);

      await tester.pumpWidget(
        _spendApp(
          transactions: provider,
          settings: await seededSettings(tester),
        ),
      );
      await settleUi(tester);

      expect(find.byType(SpendBreakdownCard), findsNWidgets(2));
      expect(find.byType(PieChart), findsNWidgets(2));
      expect(find.text('Spending by category'), findsOneWidget);
      expect(find.text('Income by category'), findsOneWidget);
      // Real category labels, not the literal "Expense"/"Income".
      expect(find.text('Food'), findsWidgets);
      expect(find.text('Salary'), findsWidgets);
    });

    testWidgets('the Expenses filter shows only the spending chart', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final provider = await seedProvider(tester, [
        _expense(120, ExpenseCategory.food, 'Lunch'),
        _income(900, 'salary', 'Payday'),
      ]);

      await tester.pumpWidget(
        _spendApp(
          transactions: provider,
          settings: await seededSettings(tester),
        ),
      );
      await settleUi(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Expenses'));
      await settleUi(tester);

      expect(find.text('Spending by category'), findsOneWidget);
      expect(find.text('Income by category'), findsNothing);
      expect(find.byType(PieChart), findsOneWidget);
    });

    testWidgets('the Income filter shows only the income chart', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final provider = await seedProvider(tester, [
        _expense(120, ExpenseCategory.food, 'Lunch'),
        _income(900, 'salary', 'Payday'),
      ]);

      await tester.pumpWidget(
        _spendApp(
          transactions: provider,
          settings: await seededSettings(tester),
        ),
      );
      await settleUi(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Income'));
      await settleUi(tester);

      expect(find.text('Income by category'), findsOneWidget);
      expect(find.text('Spending by category'), findsNothing);
    });

    testWidgets('no chart is shown when nothing is recorded', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final provider = await seedProvider(tester, const []);

      await tester.pumpWidget(
        _spendApp(
          transactions: provider,
          settings: await seededSettings(tester),
        ),
      );
      await settleUi(tester);

      expect(find.byType(SpendBreakdownCard), findsNothing);
      expect(find.byType(PieChart), findsNothing);
    });
    testWidgets(
      'custom "Other" names are not collapsed into one chart slice',
      (tester) async {
        usePhoneLayout(tester, TestViewports.phonePortrait);

        // Both rows are ExpenseCategory.other, so a breakdown keyed by the enum
        // alone sums them into a single slice and labels it with whichever
        // custom name happened to sort first. The tiles below show each name.
        final now = DateTime.now();
        final provider = await seedProvider(tester, [
          Expense(
            amount: 40,
            category: ExpenseCategory.other,
            customCategoryName: 'Coffee',
            description: 'Flat white',
            date: now,
          ),
          Expense(
            amount: 60,
            category: ExpenseCategory.other,
            customCategoryName: 'Groceries',
            description: 'Weekly shop',
            date: now,
          ),
          _expense(100, ExpenseCategory.food, 'Lunch'),
        ]);

        await tester.pumpWidget(
          _spendApp(
            transactions: provider,
            settings: await seededSettings(tester),
          ),
        );
        await settleUi(tester);

        final card = find.byType(SpendBreakdownCard);
        expect(find.descendant(of: card, matching: find.text('Coffee')), findsOneWidget);
        expect(
          find.descendant(of: card, matching: find.text('Groceries')),
          findsOneWidget,
        );
        // Each custom name keeps its own total, not a merged one.
        expect(
          find.descendant(of: card, matching: find.text('Rs. 40')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: card, matching: find.text('Rs. 60')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: card, matching: find.text('Rs. 100')),
          findsOneWidget,
          reason: 'Rs. 100 belongs to Food, not to the merged Other bucket',
        );
      },
    );

    testWidgets('the month summary keeps the average daily figure', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final provider = await seedProvider(tester, [
        _expense(300, ExpenseCategory.food, 'Lunch'),
      ]);

      await tester.pumpWidget(
        _spendApp(
          transactions: provider,
          settings: await seededSettings(tester),
        ),
      );
      await settleUi(tester);

      // Pass 2 dropped this from the summary card while wiring the currency
      // through, which left getAverageDailySpending() with no UI caller.
      expect(find.textContaining('/ day'), findsOneWidget);
    });

    testWidgets('every donut slice keeps a legend row', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      // All six expense categories, which is more than a `take(5)` legend.
      final provider = await seedProvider(tester, [
        for (final category in ExpenseCategory.values)
          _expense(20, category, category.name),
      ]);

      await tester.pumpWidget(
        _spendApp(
          transactions: provider,
          settings: await seededSettings(tester),
        ),
      );
      await settleUi(tester);

      expect(find.byType(PieChart), findsOneWidget);
      final card = find.byType(SpendBreakdownCard);
      // One legend row per category, so no slice is left unlabelled.
      for (final category in ExpenseCategory.values) {
        expect(
          find.descendant(of: card, matching: find.text(category.meta.name)),
          findsOneWidget,
          reason: '${category.name} has no legend row',
        );
      }
    });
  });

  group('add transaction entry point', () {
    testWidgets('the FAB offers an explicit Expense or Income choice', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final provider = await seedProvider(tester, const []);

      await tester.pumpWidget(
        _spendApp(
          transactions: provider,
          settings: await seededSettings(tester),
        ),
      );
      await settleUi(tester);

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Add'));
      await settleUi(tester);

      expect(inChooser('Add transaction'), findsOneWidget);
      expect(inChooser('Expense'), findsOneWidget);
      expect(inChooser('Income'), findsOneWidget);
      // Neither form is open until a type is chosen.
      expect(find.byType(AddExpenseSheet), findsNothing);
      expect(find.byType(IncomeEditSheet), findsNothing);
    });

    testWidgets(
      'choosing Income opens the income form with income categories',
      (tester) async {
        usePhoneLayout(tester, TestViewports.phonePortrait);

        final provider = await seedProvider(tester, const []);

        await tester.pumpWidget(
          _spendApp(
            transactions: provider,
            settings: await seededSettings(tester),
          ),
        );
        await settleUi(tester);

        await tester.tap(find.widgetWithText(FloatingActionButton, 'Add'));
        await settleUi(tester);
        await tester.tap(inChooser('Income'));
        await settleUi(tester);

        expect(find.byType(IncomeEditSheet), findsOneWidget);
        expect(find.text('Add income'), findsOneWidget);
        // Income shows the centralised income categories, not the expense ones.
        expect(find.text('Salary'), findsWidgets);
        expect(find.text('Freelance'), findsWidgets);
        expect(find.text('Food'), findsNothing);
        expect(find.text('Travel'), findsNothing);
      },
    );

    testWidgets(
      'choosing Expense opens the expense form with expense categories',
      (tester) async {
        usePhoneLayout(tester, TestViewports.phonePortrait);

        final provider = await seedProvider(tester, const []);

        await tester.pumpWidget(
          _spendApp(
            transactions: provider,
            settings: await seededSettings(tester),
          ),
        );
        await settleUi(tester);

        await tester.tap(find.widgetWithText(FloatingActionButton, 'Add'));
        await settleUi(tester);
        await tester.tap(inChooser('Expense'));
        await settleUi(tester);

        expect(find.byType(AddExpenseSheet), findsOneWidget);
        expect(find.text('Add expense'), findsOneWidget);
        // The expense picker offers expense categories.
        expect(find.text('Food'), findsWidgets);
        expect(find.text('Travel'), findsWidgets);
        expect(find.text('Salary'), findsNothing);
        expect(find.text('Freelance'), findsNothing);
      },
    );

    testWidgets('an amount entered as Income is persisted as Income', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final provider = await seedProvider(tester, const []);

      await tester.pumpWidget(
        _spendApp(
          transactions: provider,
          settings: await seededSettings(tester),
        ),
      );
      await settleUi(tester);

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Add'));
      await settleUi(tester);
      await tester.tap(inChooser('Income'));
      await settleUi(tester);

      await tester.enterText(find.widgetWithText(TextFormField, '0'), '450');
      await settleUi(tester);

      // Saving reaches Hive. A write initiated from the fake-async zone of a
      // `testWidgets` body never completes and leaves the box write lock held,
      // which deadlocks every later test, so the tap itself runs in real async.
      await tester.runAsync(() async {
        await tester.tap(find.text('Save income'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await settleUi(tester);

      final saved = provider.transactions.whereType<Income>().toList();
      expect(saved.length, 1);
      expect(saved.single.amount, 450);
      expect(saved.single.isIncome, isTrue);
      expect(saved.single.category, 'salary');
    });

    testWidgets('picking an income category stores the category id', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final provider = await seedProvider(tester, const []);

      await tester.pumpWidget(
        _spendApp(
          transactions: provider,
          settings: await seededSettings(tester),
        ),
      );
      await settleUi(tester);

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Add'));
      await settleUi(tester);
      await tester.tap(inChooser('Income'));
      await settleUi(tester);

      expect(find.text('Freelance'), findsOneWidget);
      await tester.tap(find.text('Freelance'));
      await settleUi(tester);

      // The default selection is 'salary', so tapping Freelance must move the
      // selection rather than leaving nothing highlighted.
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Freelance'))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Salary'))
            .selected,
        isFalse,
      );

      await tester.enterText(find.widgetWithText(TextFormField, '0'), '250');
      await settleUi(tester);
      await tester.runAsync(() async {
        await tester.tap(find.text('Save income'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await settleUi(tester);

      final saved = provider.transactions.whereType<Income>().toList();
      expect(saved.length, 1);
      expect(saved.single.category, 'freelance');
    });
  });

  group('currency', () {
    testWidgets('amounts render with the rupee symbol by default', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final provider = await seedProvider(tester, [
        _expense(120, ExpenseCategory.food, 'Lunch'),
      ]);

      await tester.pumpWidget(
        _spendApp(
          transactions: provider,
          settings: await seededSettings(tester),
        ),
      );
      await settleUi(tester);

      expect(find.textContaining('Rs. '), findsWidgets);
      // Expense is negative, income positive.
      expect(find.text('-Rs. 120'), findsOneWidget);
      expect(find.textContaining('Rs.  '), findsNothing); // no double space
    });

    testWidgets('switching currency changes what is rendered', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final provider = await seedProvider(tester, [
        _expense(120, ExpenseCategory.food, 'Lunch'),
      ]);

      await tester.pumpWidget(
        _spendApp(
          transactions: provider,
          settings: await seededSettings(tester, currency: Currency.eur),
        ),
      );
      await settleUi(tester);

      expect(find.textContaining('€ '), findsWidgets);
      expect(find.text('-€ 120'), findsOneWidget);
      expect(find.textContaining('Rs.'), findsNothing);
    });
  });

  group('sign convention', () {
    testWidgets('expenses render negative and income positive', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final provider = await seedProvider(tester, [
        _expense(120, ExpenseCategory.food, 'Lunch'),
        _income(900, 'salary', 'Payday'),
      ]);

      await tester.pumpWidget(
        _spendApp(
          transactions: provider,
          settings: await seededSettings(tester),
        ),
      );
      await settleUi(tester);

      await scrollTo(tester, find.text('-Rs. 120'));
      expect(find.text('-Rs. 120'), findsOneWidget);
      expect(find.text('+Rs. 900'), findsOneWidget);
    });
  });
}

Widget _spendApp({
  required TransactionProvider transactions,
  required SettingsProvider settings,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<TransactionProvider>.value(value: transactions),
      ChangeNotifierProvider(create: (_) => LocationProvider()),
      ChangeNotifierProvider(create: (_) => JourneyProvider()),
      ChangeNotifierProvider<SettingsProvider>.value(value: settings),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const TransactionsScreen(),
    ),
  );
}
