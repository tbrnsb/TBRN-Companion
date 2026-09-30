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

    buffer
      ..writeln('')
      ..writeln('--- $key ---')
      ..writeln('total spend: ${index.total.toStringAsFixed(2)}')
      ..writeln('per category:');
    for (final category in ExpenseCategory.values) {
      final amount = index.forCategory(category);
      if (amount == 0) continue;
      buffer.writeln('  ${category.name}: ${amount.toStringAsFixed(2)}');
    }
    buffer
      ..writeln(
        "other participants' trip spend, which must vanish in item 1: "
        '${others.toStringAsFixed(2)}',
      )
      ..writeln(
        'expected total after item 1: '
        '${(index.total - others).toStringAsFixed(2)}',
      );
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
