import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/providers/budget_provider.dart';
import 'package:daily_companion/services/storage_service.dart';

import 'visual_smoke_test.dart' show initTestStorage;

void main() {
  setUpAll(() async {
    await initTestStorage();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService().clear();
  });

  group('the rule itself', () {
    // THE RULE. `other` is not a category in the way Food is: tapping it opens
    // another screen to name the real one. In the middle of a list of one-step
    // choices it is a two-step action, and it makes the list longer to scan for
    // no reason.
    test('it moves the Other bucket to the end', () {
      final out = CategoryRegistry.othersLast<String>([
        'food',
        'other',
        'travel',
      ], isOther: (s) => s == 'other');
      expect(out, ['food', 'travel', 'other']);
    });

    test('it is STABLE, so a deliberate sort survives', () {
      // Everything else keeps the order it arrived in. A screen that sorted by
      // popularity or by amount meant to; only `other` moves, and it moves to
      // the end rather than taking a position of its own.
      final out = CategoryRegistry.othersLast<String>([
        'zebra',
        'other',
        'apple',
        'mango',
      ], isOther: (s) => s == 'other');
      expect(out, ['zebra', 'apple', 'mango', 'other']);
    });

    test('it copes with no Other at all, and with an empty list', () {
      expect(
        CategoryRegistry.othersLast<String>(['a', 'b'], isOther: (s) => false),
        ['a', 'b'],
      );
      expect(
        CategoryRegistry.othersLast<String>([], isOther: (s) => true),
        isEmpty,
      );
    });

    test('the declared lists already agree with it', () {
      // Belt and braces: the registry is hand-ordered, and this says so.
      for (final metas in [
        CategoryRegistry.expenseCategories(),
        CategoryRegistry.incomeCategories(),
      ]) {
        expect(metas.last.id, CategoryRegistry.otherId);
      }
    });

    test('it re-orders a popularity sort correctly', () {
      // The expense picker's actual ordering rule, applied to a list where
      // `other` does NOT naturally come last.
      final byPopularity = ['travel', 'other', 'food']..sort();
      final out = CategoryRegistry.metasOthersLast(
        byPopularity
            .map(
              (id) =>
                  CategoryRegistry.metaById(id) ??
                  CategoryRegistry.expenseCategories().first,
            )
            .toList(),
      );
      // Sorted, `other` would sit in the middle at index 1; it ends up last.
      expect(out.map((m) => m.id).toList(), ['food', 'travel', 'other']);
    });
  });

  group('budgets sort by label, and Other is still last', () {
    // The point of the helper. This list is sorted ALPHABETICALLY, so "other"
    // files itself between "apple" and "mango" and a two-step row lands in the
    // middle of a list of one-step ones.
    test('the provider puts it last', () async {
      final budgets = BudgetProvider();
      addTearDown(budgets.dispose);
      await budgets.load();
      for (final label in ['zebra', 'apple', 'mango']) {
        await budgets.setLimit(label: label, amount: 10);
      }
      await budgets.setLimit(label: CategoryRegistry.otherId, amount: 10);

      expect(budgets.budgets.map((b) => b.label).toList(), [
        'apple',
        'mango',
        'zebra',
        CategoryRegistry.otherId,
      ]);
    });

    test('a journey-level budget is not mistaken for a category', () async {
      // Journey rows are sorted with the category rows, and "Other" is a
      // CATEGORY bucket. Filing a trip row last because it happened to be
      // named similarly would be a new bug in the fix.
      final budgets = BudgetProvider();
      addTearDown(budgets.dispose);
      await budgets.load();
      await budgets.setLimit(label: 'zebra', amount: 10);
      await budgets.setLimit(label: CategoryRegistry.otherId, amount: 10);
      await budgets.setLimit(scope: 'trip-1', label: 'other', amount: 10);

      final rows = budgets.budgets;
      expect(rows.where((b) => b.label == CategoryRegistry.otherId).length, 1);
      expect(rows.last.isJourneyLevel, isFalse);
    });
  });
}
