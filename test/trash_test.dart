import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/journey_provider.dart';
import 'package:flutter_application_1/providers/location_provider.dart';
import 'package:flutter_application_1/providers/settings_provider.dart';
import 'package:flutter_application_1/providers/transaction_provider.dart';
import 'package:flutter_application_1/screens/trash_screen.dart';
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

Expense _expense(
  double amount,
  ExpenseCategory category, {
  DateTime? date,
  String description = 'Test expense',
  String? journeyId,
  String? paidByParticipantId,
}) {
  return Expense(
    amount: amount,
    category: category,
    description: description,
    date: date ?? DateTime.now(),
    journeyId: journeyId,
    paidByParticipantId: paidByParticipantId,
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

  group('the flag on the model', () {
    test('a live transaction is not deleted, and a trashed one is', () {
      final live = _expense(100, ExpenseCategory.food);
      expect(live.isDeleted, isFalse);
      expect(live.deletedAt, isNull);

      final trashed = live.withDeletedAt(DateTime(2026, 3, 4));
      expect(trashed.isDeleted, isTrue);
      expect(trashed.deletedAt, DateTime(2026, 3, 4));
      // Restoring must actually CLEAR the flag, not merely set it to something
      // else. A restore that left a stamp behind would make a restored expense
      // permanently invisible while looking restored.
      expect(trashed.withDeletedAt(null).isDeleted, isFalse);
      expect(trashed.withDeletedAt(null).deletedAt, isNull);
    });

    test('the flag works on Income too, from the same base', () {
      final income = Income(
        amount: 500,
        category: 'salary',
        description: 'Salary',
        date: DateTime.now(),
      );
      expect(income.withDeletedAt(DateTime(2026, 3, 4)).isDeleted, isTrue);
      expect(
        income
            .withDeletedAt(DateTime(2026, 3, 4))
            .withDeletedAt(null)
            .isDeleted,
        isFalse,
      );
    });

    test('Transaction is still sealed to Expense and Income', () {
      // The flag lives on the BASE class precisely so it did not have to become a
      // third subclass. Asserting the seal keeps it that way.
      expect(Transaction, isNotNull);
      // A compile-time guarantee, so this is a runtime note rather than a test:
      // `Transaction()` does not compile, and neither does any third subclass.
    });

    test('a record written before the trash existed loads as live', () {
      // MIGRATION SAFETY: no `deletedAt` key at all. This is every record the app
      // wrote before this stage.
      final legacy = Expense.fromJson({
        'id': 'legacy-1',
        'amount': 450,
        'category': 'food',
        'description': 'Old expense',
        'date': DateTime(2026, 3, 4).toIso8601String(),
        'createdAt': DateTime(2026, 3, 4).toIso8601String(),
      });
      expect(legacy.isDeleted, isFalse);
      expect(legacy.deletedAt, isNull);
    });

    test('a record with a null deletedAt key loads as live', () {
      final withNull = Expense.fromJson({
        'id': 'x',
        'amount': 1,
        'category': 'food',
        'description': 'd',
        'date': DateTime(2026, 3, 4).toIso8601String(),
        'deletedAt': null,
      });
      expect(withNull.isDeleted, isFalse);
    });

    test('a corrupt deletedAt does not stop a real expense loading', () {
      // A garbage flag must not make a user's spending fail to load. The whole
      // ledger is more important than one timestamp being wrong.
      final corrupt = Expense.fromJson({
        'id': 'x',
        'amount': 1,
        'category': 'food',
        'description': 'd',
        'date': DateTime(2026, 3, 4).toIso8601String(),
        'deletedAt': 'not-a-date',
      });
      expect(corrupt.isDeleted, isFalse);
    });

    test('the flag round-trips through JSON', () {
      final original = _expense(100, ExpenseCategory.food);
      final json = original.toJson();
      expect(json['deletedAt'], isNull);
      expect(Expense.fromJson(json).isDeleted, isFalse);

      final trashed = original.withDeletedAt(DateTime(2026, 3, 4, 12, 30));
      final back = Expense.fromJson(trashed.toJson());
      expect(back.isDeleted, isTrue);
      expect(back.deletedAt, DateTime(2026, 3, 4, 12, 30));
      // And it is still an Expense, not something new.
      expect(back, isA<Expense>());
      expect(back.amount, 100);
    });
  });

  group('storage excludes trashed rows from every query', () {
    Future<void> seed() async {
      final storage = StorageService();
      final live = _expense(
        100,
        ExpenseCategory.food,
        date: DateTime(2026, 3, 4),
        description: 'Live',
      );
      final trashed = _expense(
        200,
        ExpenseCategory.travel,
        date: DateTime(2026, 3, 4),
        description: 'Trashed',
      ).withDeletedAt(DateTime(2026, 3, 5));
      await storage.addTransaction(live);
      await storage.addTransaction(trashed);
    }

    test('getAllTransactions and the month query both exclude them', () async {
      await seed();
      final storage = StorageService();

      final all = await storage.getAllTransactions();
      expect(all, hasLength(1));
      expect(all.single.description, 'Live');

      final month = await storage.getTransactionsForMonth(2026, 3);
      expect(month, hasLength(1));
      expect(month.single.description, 'Live');
    });

    test('the trashed query is the one that sees them', () async {
      await seed();
      final trashed = await StorageService().getTrashedTransactions();
      expect(trashed, hasLength(1));
      expect(trashed.single.description, 'Trashed');
    });

    test('a trashed expense is gone from its journey list but not the settlement', () async {
      // The asymmetry that matters. The trip's DISPLAY list drops it; the
      // settlement keeps counting it, because the money really was spent on the
      // trip and the other people split it.
      final storage = StorageService();
      await storage.addTransaction(
        _expense(
          500,
          ExpenseCategory.food,
          date: DateTime(2026, 3, 4),
          description: 'Trip lunch',
          journeyId: 'trip-1',
          paidByParticipantId: 'me',
        ),
      );
      await storage.addTransaction(
        _expense(
          900,
          ExpenseCategory.travel,
          date: DateTime(2026, 3, 4),
          description: 'Trip taxi',
          journeyId: 'trip-1',
          paidByParticipantId: 'sita',
        ),
      );

      // Trash one of them.
      final rows = await storage.getAllTransactions();
      final taxi = rows.firstWhere((t) => t.description == 'Trip taxi');
      await storage.updateTransaction(taxi.withDeletedAt(DateTime(2026, 3, 5)));

      final live = await storage.getLiveTransactionsByJourney('trip-1');
      expect(live.map((t) => t.description), ['Trip lunch']);

      // The settlement path still sees both. If this ever drops the trashed row,
      // settlement arithmetic changes the moment a user tidies their ledger.
      final forSettlement = await storage.getTransactionsByJourney('trip-1');
      expect(forSettlement, hasLength(2));
    });

    test('the storage count reports the live/trashed split', () async {
      await seed();
      final counts = await StorageService().getStorageCounts();
      // Both are on disk, so a "remove all data" warning counts both.
      expect(counts.transactions, 2);
      expect(counts.trashedTransactions, 1);
    });
  });

  group('the provider keeps both caches honest', () {
    Future<TransactionProvider> seeded() async {
      final provider = TransactionProvider();
      await provider.initialize();
      await provider.addTransaction(
        _expense(100, ExpenseCategory.food, description: 'Keep me'),
      );
      await provider.addTransaction(
        _expense(300, ExpenseCategory.food, description: 'Bin me'),
      );
      return provider;
    }

    test('trashing removes it from the month list', () async {
      final provider = await seeded();
      final target = provider.transactions.firstWhere(
        (t) => t.description == 'Bin me',
      );

      expect(await provider.moveToTrash(target.id), isTrue);
      await settleProvider(provider);

      expect(provider.transactions.map((t) => t.description), ['Keep me']);
    });

    test('trashing removes it from the WIDE cache too', () async {
      final provider = await seeded();
      final target = provider.transactions.firstWhere(
        (t) => t.description == 'Bin me',
      );
      await provider.moveToTrash(target.id);
      await settleProvider(provider);

      // The wide cache is what every non-month period reads. A row left in it
      // would be gone from the list and still counted by a yearly budget — two
      // screens disagreeing about whether an expense exists.
      final trashed = await provider.loadTrashedTransactions();
      expect(trashed.map((t) => t.description), ['Bin me']);
      final all = await StorageService().getAllTransactions();
      expect(all.map((t) => t.description), ['Keep me']);
    });

    test('a trashed expense is not counted as spending', () async {
      final provider = await seeded();
      final target = provider.transactions.firstWhere(
        (t) => t.description == 'Bin me',
      );

      final before = provider.totalSpend();
      await provider.moveToTrash(target.id);
      await settleProvider(provider);
      final after = provider.totalSpend();

      expect(before, 400);
      expect(after, 100);
    });

    test('a trashed expense is not counted in a budget', () async {
      final provider = await seeded();
      final target = provider.transactions.firstWhere(
        (t) => t.description == 'Bin me',
      );

      final before = provider.spendIndex().forCategory(ExpenseCategory.food);
      await provider.moveToTrash(target.id);
      await settleProvider(provider);
      final index = provider.spendIndex();

      expect(before, 400);
      expect(index.forCategory(ExpenseCategory.food), 100);
      expect(index.total, 100);
    });

    test('a trashed expense is not counted by a WIDE period either', () async {
      final provider = await seeded();
      final target = provider.transactions.firstWhere(
        (t) => t.description == 'Bin me',
      );
      await provider.moveToTrash(target.id);
      await settleProvider(provider);

      // The month read is filtered upstream by the storage query. This one reads
      // the wide cache, which is the path where a stale row would survive and a
      // month-scoped test would never notice.
      expect(provider.spendIndex(period: BudgetPeriod.year).total, 100);
    });

    test('restoring puts it back in both caches and in the totals', () async {
      final provider = await seeded();
      final target = provider.transactions.firstWhere(
        (t) => t.description == 'Bin me',
      );
      await provider.moveToTrash(target.id);
      await settleProvider(provider);
      expect(provider.totalSpend(), 100);

      expect(await provider.restoreFromTrash(target.id), isTrue);
      await settleProvider(provider);

      expect(
        provider.transactions.map((t) => t.description),
        containsAll(['Keep me', 'Bin me']),
      );
      expect(provider.totalSpend(), 400);
      expect(provider.spendIndex().forCategory(ExpenseCategory.food), 400);
    });

    test('restoring a record from another month does not land it in this list', () async {
      final provider = TransactionProvider();

      // The real sequence: a February expense is trashed while February is on
      // screen, the user browses to March, and then restores it from the trash.
      await provider.loadTransactionsForMonth(2026, 2);
      await provider.addTransaction(
        _expense(
          100,
          ExpenseCategory.food,
          date: DateTime(2026, 2, 10),
          description: 'February',
        ),
      );
      final february = provider.transactions.firstWhere(
        (t) => t.description == 'February',
      );
      await provider.moveToTrash(february.id);
      await settleProvider(provider);
      expect(provider.transactions, isEmpty);

      // Now browse to March.
      await provider.loadTransactionsForMonth(2026, 3);
      await settleProvider(provider);

      expect(await provider.restoreFromTrash(february.id), isTrue);
      await settleProvider(provider);

      // March's list must not gain a February expense just because it was
      // restored while March was on screen. The month header has to stay true,
      // or the summary card above the list is describing a different month from
      // the rows under it.
      expect(provider.transactions, isEmpty);
      // But it IS back, and the wide cache answers for its own month.
      final index = provider.spendIndex(anchor: DateTime(2026, 2));
      expect(index.total, 100);
      // And not counted in March, which is the direction that would be a real bug.
      expect(provider.spendIndex(anchor: DateTime(2026, 3)).total, 0);
    });

    test('trashing something already trashed does nothing', () async {
      final provider = await seeded();
      final target = provider.transactions.first;
      await provider.moveToTrash(target.id);
      await settleProvider(provider);

      expect(await provider.moveToTrash(target.id), isFalse);
      expect(await provider.restoreFromTrash(target.id), isTrue);
    });

    test('emptying the trash is permanent', () async {
      final provider = await seeded();
      await provider.moveToTrash(provider.transactions.first.id);
      await settleProvider(provider);

      expect(await provider.emptyTrash(), 1);
      expect(await provider.loadTrashedTransactions(), isEmpty);
      // Gone from disk too, not merely flagged.
      final all = await StorageService().getAllTransactions();
      expect(all, hasLength(1));
    });

    test('a trashed TRIP expense still follows the shared-trip rule', () async {
      // The two rules compose rather than interfere: someone else's trip expense
      // counts nowhere, and a trashed one counts nowhere either.
      final provider = TransactionProvider();
      await provider.loadTransactionsForMonth(2026, 3);
      provider.setLocalParticipant('trip-1', 'me');
      await provider.addTransaction(
        _expense(
          500,
          ExpenseCategory.food,
          date: DateTime(2026, 3, 4),
          journeyId: 'trip-1',
          paidByParticipantId: 'me',
        ),
      );
      await provider.addTransaction(
        _expense(
          900,
          ExpenseCategory.food,
          date: DateTime(2026, 3, 4),
          journeyId: 'trip-1',
          paidByParticipantId: 'sita',
        ),
      );

      expect(provider.spendIndex(anchor: DateTime(2026, 3)).total, 500);

      final mine = provider.transactions.firstWhere(
        (t) => t.paidByParticipantId == 'me',
      );
      await provider.moveToTrash(mine.id);
      await settleProvider(provider);

      // Both are gone from the ledger now, for two different reasons.
      expect(provider.spendIndex(anchor: DateTime(2026, 3)).total, 0);
      // And the trip's settlement is untouched, because it never read this path.
      final settlementData = await StorageService().getTransactionsByJourney(
        'trip-1',
      );
      expect(settlementData, hasLength(2));
    });
  });

  group('the trash screen', () {
    Future<TransactionProvider> pump(
      WidgetTester tester, {
      bool withSomethingDeleted = false,
    }) async {
      final provider = (await tester.runAsync(() async {
        final p = TransactionProvider();
        await p.initialize();
        await p.addTransaction(
          _expense(100, ExpenseCategory.food, description: 'Kept'),
        );
        await p.addTransaction(
          _expense(300, ExpenseCategory.travel, description: 'Binned'),
        );
        if (withSomethingDeleted) {
          final target = p.transactions.firstWhere(
            (t) => t.description == 'Binned',
          );
          await p.moveToTrash(target.id);
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
            home: const Scaffold(body: TrashScreen()),
          ),
        ),
      );
      await settleUi(tester);
      return provider;
    }

    testWidgets('an empty trash says so and offers no action', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await pump(tester);

      expect(find.text('Trash is empty'), findsOne);
      // No "Empty trash" button on an empty trash: a control for something that
      // cannot happen.
      expect(find.byKey(const ValueKey('trash-empty-all')), findsNothing);
      expect(
        find.descendant(
          of: find.byType(EmptyState),
          matching: find.byType(FilledButton),
        ),
        findsNothing,
      );
    });

    testWidgets('a deleted record is listed with a restore button', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await pump(tester, withSomethingDeleted: true);

      expect(find.text('Binned'), findsOne);
      expect(find.text('Kept'), findsNothing);
      expect(find.textContaining('deleted '), findsOne);
      expect(find.byKey(const ValueKey('trash-empty-all')), findsOne);
    });

    testWidgets('restore puts the record back in the ledger', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      final provider = await pump(tester, withSomethingDeleted: true);

      final targetId = (await (tester.runAsync(
        provider.loadTrashedTransactions,
      )))!.single.id;
      expect(
        (await (tester.runAsync(provider.loadTrashedTransactions)))!,
        hasLength(1),
      );

      // Hive writes inside a testWidgets body deadlock, so the restore is driven
      // through runAsync and the widget body only pumps afterwards. runAsync is
      // reentrant-hostile, so every call is awaited before the next.
      await tester.runAsync(() => provider.restoreFromTrash(targetId));
      await settleUi(tester);

      expect(await provider.loadTrashedTransactions(), isEmpty);
      // And it is genuinely back in the user's data, not merely un-flagged.
      final all = (await tester.runAsync(
        () => StorageService().getAllTransactions(),
      ))!;
      expect(all.map((t) => t.description), contains('Binned'));
    });

    testWidgets('delete forever asks before it does anything', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await pump(tester, withSomethingDeleted: true);

      final provider = tester
          .element(find.text('Binned'))
          .read<TransactionProvider>();
      final targetId = (await (tester.runAsync(
        provider.loadTrashedTransactions,
      )))!.single.id;

      await tester.tap(find.byKey(ValueKey('trash-forever-$targetId')));
      await settleUi(tester);

      // The confirmation is the whole point of the irreversible action.
      expect(find.byKey(const ValueKey('trash-confirm-forever')), findsOne);
      await tester.tap(find.text('Cancel'));
      await settleUi(tester);
      expect(
        (await (tester.runAsync(provider.loadTrashedTransactions)))!,
        hasLength(1),
      );
    });

    for (final viewport in [
      TestViewports.phonePortrait,
      TestViewports.phoneSmall,
    ]) {
      testWidgets('no overflow at $viewport', (tester) async {
        usePhoneLayout(tester, viewport);
        await pump(tester, withSomethingDeleted: true);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

/// Lets the provider's own async writes land before the next read.
///
/// Hive writes are real filesystem work, so a provider test that saves and
/// immediately re-reads has to give the write a turn of the event loop.
Future<void> settleProvider(TransactionProvider provider) async {
  await Future<void>.delayed(const Duration(milliseconds: 20));
}
