import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/services/storage_service.dart';

import 'seed_fixture.dart';
import 'visual_smoke_test.dart' show initTestStorage;

void main() {
  setUpAll(() async {
    await initTestStorage();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService().clear();
  });

  // These two are not about the fixture. They are about what a month of data
  // looks like, and a fixture is how the app's other tests get one.
  group('the seeded month is dated like a month that has been lived in', () {
    // The old code was `DateTime(y, m, now.day - n)` clamped to `1..now.day`, so
    // on the first days of a month EVERY offset clamped to 1 and seven records
    // landed on one date. The heatmap's per-day maximum was then set by a single
    // record and every other day read as nothing having happened.
    late List<Transaction> seeded;

    setUp(() async {
      await SeedFixture.seed();
      seeded = await StorageService().getAllTransactions();
    });

    test('nothing is dated in the future', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final future = seeded.where((t) => t.date.isAfter(today)).toList();
      expect(
        future,
        isEmpty,
        reason:
            'a month with spending on days that have not happened is not a '
            'month that has been lived in',
      );
    });

    test(
      'once the month has started, it has both lit and unlit days',
      () async {
        // Gated on the month being far enough along for the question to mean
        // anything -- on the 1st a month genuinely has one day and asserting
        // otherwise would be a test that lies.
        final now = DateTime.now();
        if (now.day < 10) return;

        final days = (await _currentMonth()).map((e) => e.date.day).toSet();

        expect(
          days.length,
          greaterThanOrEqualTo(6),
          reason: 'only ${days.length} days have any spending on them',
        );
        expect(
          days.length,
          lessThan(now.day),
          reason:
              'every single day has spending, which is not how a month goes',
        );
      },
    );
  });
}

/// The current month's own expenses, with the shared trip's left out: the trip
/// is dated in the past, so it would only pad the counts.
Future<List<Expense>> _currentMonth() async {
  final now = DateTime.now();
  return (await StorageService().getAllTransactions())
      .whereType<Expense>()
      .where(
        (e) =>
            e.journeyId == null &&
            e.date.year == now.year &&
            e.date.month == now.month,
      )
      .toList();
}
