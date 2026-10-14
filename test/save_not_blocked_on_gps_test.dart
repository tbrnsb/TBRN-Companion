import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Adding a transaction must not wait on the satellite.
///
/// The save read: capture a GPS fix (up to a 10s hard timeout), ask whether to
/// link a nearby place, and only then write the row. So the one action the user
/// had already decided on -- recording a coffee -- was queued behind a network
/// round trip and a satellite lock, and on a bad signal it took ten seconds to
/// reach storage. The complaint was "it takes ages when adding a transaction".
///
/// The rule these tests pin, for both forms: the WRITE is issued before
/// `capturePosition`, so `notifyListeners` fires inside `addTransaction` and the
/// ledger updates while any position work happens behind it. The coordinates are
/// backfilled afterwards by a second write, and skipped entirely when there is
/// nothing new to add.
///
/// A source scan rather than a timing test on purpose. A wall-clock assertion
/// would be flaky, would need a fake Geolocator behind a static, and would pass
/// on a machine with a warm fix while the real device waited ten seconds. What
/// actually regressed is the ORDER of two calls in a function, and that is what
/// is asserted here.
void main() {
  const expenseSheet = 'lib/screens/transactions/add_expense_sheet.dart';
  const incomeSheet = 'lib/screens/transactions/income_detail_screen.dart';

  int orderIn(String path, String first, String second) {
    final source = File(path).readAsStringSync();
    final write = source.indexOf(first);
    final capture = source.indexOf(second);
    if (write < 0) fail('$path: no "$first" found');
    if (capture < 0) fail('$path: no "$second" found');
    return write < capture ? -1 : 1;
  }

  group('the expense sheet writes before it reads the position', () {
    test('addTransaction is issued before capturePosition', () {
      expect(
        orderIn(
          expenseSheet,
          'provider.addTransaction(row)',
          'TransactionLocationService.capturePosition()',
        ),
        -1,
        reason: 'the ledger must see the row before any GPS work is attempted',
      );
    });

    test('the position is backfilled with a second write, not the first', () {
      final source = File(expenseSheet).readAsStringSync();
      final firstWrite = source.indexOf('provider.addTransaction(row)');
      final backfill = source.indexOf(
        'provider.updateTransaction(',
        firstWrite,
      );

      expect(backfill, greaterThan(0), reason: 'there is a backfill write');
      expect(
        backfill,
        greaterThan(firstWrite),
        reason: 'the backfill comes after the row exists',
      );
    });

    test('the backfill only happens when there is something new to add', () {
      final source = File(expenseSheet).readAsStringSync();
      final backfill = source.indexOf('if (hasNewPosition) {');
      expect(
        backfill,
        greaterThan(0),
        reason: 'a manual place with no fix costs no second write at all',
      );
    });

    test('the row carries a position only if one is already known', () {
      final source = File(expenseSheet).readAsStringSync();
      final row = source.substring(
        source.indexOf('final row = Expense('),
        source.indexOf('final written ='),
      );
      expect(
        row,
        contains('latitude: _latitude'),
        reason: 'the first write must not block on a fix it does not have yet',
      );
    });
  });

  group('the income sheet does the same', () {
    test('addTransaction is issued before capturePosition', () {
      expect(
        orderIn(
          incomeSheet,
          'provider.addTransaction(row)',
          'TransactionLocationService.capturePosition()',
        ),
        -1,
        reason: 'income is money too, and it should not feel slower',
      );
    });
  });

  group('the GPS read is bounded, and tightly', () {
    test('the fix and hard timeouts are seconds, not tens of seconds', () {
      final source = File('lib/services/transaction_location_service.dart')
          .readAsStringSync();
      final fix = RegExp(r'_fixTimeout\s*=\s*Duration\(seconds:\s*(\d+)\)')
          .firstMatch(source);
      final hard = RegExp(r'_hardTimeout\s*=\s*Duration\(seconds:\s*(\d+)\)')
          .firstMatch(source);

      expect(fix, isNotNull, reason: '_fixTimeout is declared');
      expect(hard, isNotNull, reason: '_hardTimeout is declared');

      final fixSeconds = int.parse(fix!.group(1)!);
      final hardSeconds = int.parse(hard!.group(1)!);

      // The bound no longer sits between the user pressing Save and their money
      // being recorded, so it only decides whether a pin gets attached. A pin
      // nobody asked for is not worth eight seconds of patience.
      expect(fixSeconds, lessThanOrEqualTo(4));
      expect(hardSeconds, lessThanOrEqualTo(5));
    });
  });
}
