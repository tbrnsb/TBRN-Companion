import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/journey_provider.dart';
import 'package:flutter_application_1/providers/transaction_provider.dart';
import 'package:flutter_application_1/services/demo_data_service.dart';
import 'package:flutter_application_1/services/storage_service.dart';

import 'visual_smoke_test.dart' show initTestStorage;

/// Prints the spending baseline Phase B item 1 is checked against.
///
/// Run it, read the numbers, then run it again after item 1 lands. Every month's
/// "other participants' trip spend" figure SHOULD disappear from the totals, and
/// nothing else should move.
///
/// Not a `_test.dart` file, so the suite does not run it: a test that merely
/// prints is not a test. The invariant it depends on — per-category totals adding
/// up to the month total — is a real assertion in `budget_test.dart`.
///
/// Derived entirely from the data. No captured constant, no fixture: re-running
/// it after any change prints the truth rather than a stale answer.
Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await initTestStorage();
  SharedPreferences.setMockInitialValues({});
  await StorageService().clear();
  await DemoDataService.seedAll();

  final provider = TransactionProvider();
  await provider.initialize();
  final journeys = JourneyProvider();
  await journeys.initialize();

  final all = await StorageService().getAllTransactions();

  // Every month that holds data, not just the current one. On the 1st of a month
  // the demo set's trip expenses fall into the PREVIOUS month — a consequence of
  // the demo data being dated on "now", which is Phase B item 2's bug — so a
  // current-month-only baseline would report a trip comparison with nothing to
  // compare against.
  final monthKeys = <String>{
    for (final t in all)
      '${t.date.year}-${t.date.month.toString().padLeft(2, '0')}',
  }.toList()..sort();

  final buffer = StringBuffer()
    ..writeln('=== SPENDING BASELINE (before item 1) ===');

  for (final key in monthKeys) {
    final parts = key.split('-');
    final month = DateTime(int.parse(parts[0]), int.parse(parts[1]));
    final index = provider.spendIndex(anchor: month);
    final others = _othersSpendIn(all, journeys, month);

    // THREE figures, because they answer three different questions and conflating
    // them is how a filter bug hides.
    //
    // - `raw` is every expense in storage for the month, other participants
    //   included. It is the DATA and item 1 must not change it.
    // - `ledger` is spendIndex: the same data after the shared-trip rule. This is
    //   what budgets have always read.
    // - `view` is totalExpenses: what the summary card reads. Item 1 makes this
    //   equal `ledger`.
    //
    // raw - others == ledger is the invariant. view == ledger is item 1.
    final raw = <String, double>{};
    for (final t in all.whereType<Expense>()) {
      if (t.date.year != month.year || t.date.month != month.month) continue;
      raw[t.category.name] = (raw[t.category.name] ?? 0) + t.amount;
    }
    final rawTotal = raw.values.fold<double>(0, (a, b) => a + b);
    final viewTotal = await provider.viewTotalForMonth(month);

    buffer
      ..writeln('')
      ..writeln('--- $key ---')
      ..writeln('raw storage total: ${rawTotal.toStringAsFixed(2)}')
      ..writeln("others' trip spend: ${others.toStringAsFixed(2)}")
      ..writeln(
        'raw - others (must equal the ledger total): '
        '${(rawTotal - others).toStringAsFixed(2)}',
      )
      ..writeln(
        'ledger total (spendIndex, budgets): ${index.total.toStringAsFixed(2)}',
      )
      ..writeln('view total (summary card): ${viewTotal.toStringAsFixed(2)}')
      ..writeln('SPLIT-BRAIN: ${(viewTotal - index.total).toStringAsFixed(2)}')
      ..writeln('per category (ledger):');
    for (final category in ExpenseCategory.values) {
      final amount = index.forCategory(category);
      if (amount == 0) continue;
      buffer.writeln('  ${category.name}: ${amount.toStringAsFixed(2)}');
    }
  }

  // ignore: avoid_print
  print(buffer);
}

/// Other participants' trip spend inside [month]'s window.
double _othersSpendIn(
  List<Transaction> all,
  JourneyProvider journeys,
  DateTime month,
) {
  final window = BudgetPeriod.month.window(month);
  var total = 0.0;
  for (final t in all.whereType<Expense>()) {
    final journeyId = t.journeyId;
    if (journeyId == null) continue;
    final payer = t.paidByParticipantId;
    if (payer == null) continue;
    if (t.date.isBefore(window.start) || !t.date.isBefore(window.end)) {
      continue;
    }
    final local = journeys.getJourneyById(journeyId)?.localParticipantId;
    if (payer == local) continue;
    total += t.amount;
  }
  return total;
}

/// A measurement seam for this script and its assertions.
///
/// It navigates the provider and reads `totalExpenses` — the same path the month
/// card takes — so comparing it against `spendIndex` is a real comparison rather
/// than one number reached twice.
///
/// It LIVES HERE, in the test, rather than in the provider: it mutates the loaded
/// month, and a library should not ship a method whose only purpose is to break a
/// provider's state for a reporting script. The permanent guard against the
/// split-brain is the provider test in `ledger_filter_test.dart` that asserts
/// `totalExpenses == spendIndex().total` directly.
extension ViewTotalForMonth on TransactionProvider {
  Future<double> viewTotalForMonth(DateTime month) async {
    await loadTransactionsForMonth(month.year, month.month);
    return totalExpenses;
  }
}
