import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/providers/journey_provider.dart';
import 'package:daily_companion/providers/location_provider.dart';
import 'package:daily_companion/providers/settings_provider.dart';
import 'package:daily_companion/providers/transaction_provider.dart';
import 'package:daily_companion/screens/transactions/add_expense_sheet.dart';
import 'package:daily_companion/services/storage_service.dart';
import 'package:daily_companion/theme/app_theme.dart';

import 'test_viewports.dart';
import 'visual_smoke_test.dart' show initTestStorage;

/// The expense form must never be offered an income category — and the income
/// form must never be offered an expense one.
///
/// The device had an entire income (Rs. 570) filed under a custom category
/// named "Random", and "Random" appeared in the EXPENSE picker's "Recent" row.
/// Not a cosmetic leak: a row filed that way lands on the wrong half of the
/// ledger, so the balance, the charts and every budget read wrong while looking
/// right.
///
/// Two halves of the same fault, so two tests:
///
///  - the history-derived lists (`recentCategories`, `popularCategories`)
///    walked the whole ledger, income included;
///  - the picker accepted ANY id starting with `custom:`, so a custom income id
///    passed its filter even when handed one directly.
/// The provider handed the picker a leaky list, which is exactly what the
/// history-derived getter used to do. Filtering at the provider would not
/// save this, so the picker has to refuse on its own.
class _LeakyTransactionProvider extends TransactionProvider {
  @override
  List<CategoryMeta> get recentCategories => [
    const CategoryMeta(
      id: 'custom:random',
      name: 'Random',
      icon: Icons.auto_awesome_rounded,
      color: Color(0xFF7A6A9E),
      popularity: 99,
    ),
    const CategoryMeta(
      id: 'custom:temple entry',
      name: 'Temple Entry',
      icon: Icons.auto_awesome_rounded,
      color: Color(0xFF7A6A9E),
      popularity: 98,
    ),
  ];
}

void main() {
  setUpAll(() async {
    await initTestStorage();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService().clear();
  });

  Future<void> settleUi(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// "Random", the custom category the device had, on the side it belongs to.
  Future<void> seedLedger(TransactionProvider provider) async {
    await StorageService().addCustomCategory(
      const CustomCategory(name: 'Random', kind: CategoryKind.income),
    );
    await StorageService().addCustomCategory(
      const CustomCategory(name: 'Temple Entry'),
    );
    await provider.loadRecentCustomCategories();

    await provider.addTransaction(
      Income(
        amount: 570,
        category: 'custom:random',
        description: 'Side gig',
        date: DateTime.now(),
      ),
    );
    await provider.addTransaction(
      Expense(
        amount: 40,
        category: ExpenseCategory.other,
        customCategoryName: 'Temple Entry',
        description: 'Entry fee',
        date: DateTime.now(),
      ),
    );
  }

  group('the expense form is never offered an income category', () {
    test('the history-derived Recent row reads expense rows only', () async {
      final provider = TransactionProvider();
      await provider.initialize();
      addTearDown(provider.dispose);

      await seedLedger(provider);

      final ids = provider.recentCategories.map((m) => m.id).toList();

      expect(
        ids,
        isNot(contains('custom:random')),
        reason: 'an income category reached the expense picker through history',
      );
      expect(
        ids,
        contains('custom:temple entry'),
        reason: "the user's own EXPENSE category must still be offered",
      );
    });

    test('the history-derived Popular row reads expense rows only', () async {
      final provider = TransactionProvider();
      await provider.initialize();
      addTearDown(provider.dispose);

      await seedLedger(provider);

      final ids = provider.popularCategories.map((m) => m.id).toList();

      expect(
        ids,
        isNot(contains('custom:random')),
        reason: 'the Popular row is the same leak in a different position',
      );
    });

    testWidgets('the sheet does not draw an income category anywhere', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final transactions = (await tester.runAsync(() async {
        final p = TransactionProvider();
        await p.initialize();
        await seedLedger(p);
        return p;
      }))!;
      addTearDown(transactions.dispose);

      final settings = (await tester.runAsync(() async {
        final s = SettingsProvider();
        await s.load();
        return s;
      }))!;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TransactionProvider>.value(
              value: transactions,
            ),
            ChangeNotifierProvider(create: (_) => LocationProvider()),
            ChangeNotifierProvider(create: (_) => JourneyProvider()),
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => AddExpenseSheet.show(context),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await settleUi(tester);

      await tester.tap(find.text('open'));
      await settleUi(tester);

      expect(find.byType(AddExpenseSheet), findsOneWidget);
      // Neither the Recent chip nor the prefilled default may name it.
      expect(
        find.text('Random'),
        findsNothing,
        reason: 'the expense form is offering an income category',
      );
      expect(find.text('Temple Entry'), findsWidgets);
    });
  });

  group('the picker filter itself', () {
    const expenseCustomNames = ['Temple Entry'];

    CategoryMeta customMeta(String name) => CategoryMeta(
      id: 'custom:${name.toLowerCase()}',
      name: name,
      icon: Icons.auto_awesome_rounded,
      color: const Color(0xFF7A6A9E),
      popularity: 99,
    );

    test('it refuses a custom id the expense side has not saved', () {
      // The exact fault: "Random" exists, but only as an INCOME category, so
      // its name is absent from this list and the prefix alone cannot vouch
      // for it.
      expect(
        offeredOnExpenseForm(
          customMeta('Random'),
          expenseCustomNames: expenseCustomNames,
        ),
        isFalse,
      );
    });

    test('it accepts a custom id the expense side has saved', () {
      expect(
        offeredOnExpenseForm(
          customMeta('Temple Entry'),
          expenseCustomNames: expenseCustomNames,
        ),
        isTrue,
      );
    });

    test('the comparison ignores how either side was capitalised', () {
      expect(
        offeredOnExpenseForm(
          customMeta('temple entry'),
          expenseCustomNames: expenseCustomNames,
        ),
        isTrue,
      );
    });

    test('it accepts the nine built-ins and refuses income ones', () {
      for (final meta in CategoryRegistry.expenseCategories()) {
        expect(
          offeredOnExpenseForm(meta, expenseCustomNames: const []),
          isTrue,
          reason: '"${meta.name}" is an expense category',
        );
      }
      for (final meta in CategoryRegistry.incomeCategories()) {
        // "Other" is shared by both halves, so it is the one income id this
        // predicate may accept. Every other income category is a category the
        // expense form must not offer.
        final isSharedOther = meta.id == 'other';
        expect(
          offeredOnExpenseForm(meta, expenseCustomNames: const []),
          isSharedOther,
          reason: '"${meta.name}" is an income category, not an expense one',
        );
      }
    });

    test('it refuses a suggested type, as the old filter did', () {
      expect(
        offeredOnExpenseForm(
          CategoryRegistry.metaFor(ExpenseCategory.other, customName: 'Fruits'),
          expenseCustomNames: const ['Fruits'],
        ),
        isFalse,
        reason: 'the picker has no row for a suggested type',
      );
    });

    testWidgets('a custom income id handed straight to it is dropped', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final transactions = _LeakyTransactionProvider();
      addTearDown(transactions.dispose);
      // The names the EXPENSE side has saved. "Random" is an income category,
      // so it is deliberately absent; "Temple Entry" is an expense one.
      await tester.runAsync(() async {
        await StorageService().addCustomCategory(
          const CustomCategory(name: 'Temple Entry'),
        );
        await transactions.loadRecentCustomCategories();
      });

      final settings = (await tester.runAsync(() async {
        final s = SettingsProvider();
        await s.load();
        return s;
      }))!;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TransactionProvider>.value(
              value: transactions,
            ),
            ChangeNotifierProvider(create: (_) => LocationProvider()),
            ChangeNotifierProvider(create: (_) => JourneyProvider()),
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => AddExpenseSheet.show(context),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await settleUi(tester);

      await tester.tap(find.text('open'));
      await settleUi(tester);

      expect(find.byType(AddExpenseSheet), findsOneWidget);
      expect(
        find.text('Random'),
        findsNothing,
        reason: 'the picker accepts any id starting with "custom:"',
      );
      expect(
        find.text('Temple Entry'),
        findsWidgets,
        reason: "the user's own expense category must survive the filter",
      );
    });
  });
}
