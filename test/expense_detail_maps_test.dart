import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/providers/journey_provider.dart';
import 'package:daily_companion/providers/location_provider.dart';
import 'package:daily_companion/providers/settings_provider.dart';
import 'package:daily_companion/providers/transaction_provider.dart';
import 'package:daily_companion/screens/transactions/expense_detail_screen.dart';
import 'package:daily_companion/services/storage_service.dart';
import 'package:daily_companion/theme/app_theme.dart';

import 'visual_smoke_test.dart' show initTestStorage;

/// Records what was launched instead of leaving the app.
class _RecordingLauncher extends UrlLauncherPlatform {
  final List<Uri> launched = [];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(Uri.parse(url));
    return true;
  }
}

/// Where the expense in this file was spent.
///
/// Deliberately a real location, because the request this pins is "I spent 500 on
/// food HERE, and the detail screen should be able to take me there".
const _here = (latitude: 27.7172, longitude: 85.3240);

Expense _expenseAt({required double lat, required double lng, String? name}) =>
    Expense(
      amount: 500,
      category: ExpenseCategory.food,
      description: name ?? 'Dinner',
      latitude: lat,
      longitude: lng,
      date: DateTime.now(),
    );

void main() {
  late _RecordingLauncher platform;

  setUpAll(() async {
    await initTestStorage();
  });

  setUp(() async {
    platform = _RecordingLauncher();
    UrlLauncherPlatform.instance = platform;
    // The mock store is process-wide, so a currency saved by one test would
    // otherwise leak into the next.
    SharedPreferences.setMockInitialValues({});
    await StorageService().clear();
  });

  /// Seeds [expense] and pumps its detail screen.
  ///
  /// `runAsync` because Hive writes deadlock inside a `testWidgets` body; the
  /// widget tree below only reads. The provider is the one the SCREEN watches,
  /// so the screen sees the same record storage holds.
  Future<TransactionProvider> pumpDetail(
    WidgetTester tester,
    Expense expense,
  ) async {
    final provider = (await tester.runAsync(() async {
      final p = TransactionProvider();
      await p.initialize();
      await p.addTransaction(expense);
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
          ChangeNotifierProvider(create: (_) => LocationProvider()),
          ChangeNotifierProvider(create: (_) => JourneyProvider()),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: ExpenseDetailScreen(expense: expense),
        ),
      ),
    );
    // Bounded pumps: this screen has no autofocused field, but settleUi keeps
    // the pattern uniform with the rest of the suite.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return provider;
  }

  group('an expense recorded at a place can be opened in maps', () {
    // Reported from the field: spend 500 on food somewhere, open the
    // transaction, and there is no way to get to the place. The coordinates were
    // on the screen as READ-ONLY TEXT -- a number to read and nothing to do
    // with, on the one screen that knows exactly where the money was spent.
    testWidgets('the detail screen offers a maps action', (tester) async {
      await pumpDetail(
        tester,
        _expenseAt(lat: _here.latitude, lng: _here.longitude),
      );

      // The coordinates were always shown; what was missing is the action.
      expect(find.text('Coordinates'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('transaction-open-in-maps')),
        findsOneWidget,
      );
    });

    testWidgets('it opens the exact coordinates, not a search', (tester) async {
      await pumpDetail(
        tester,
        _expenseAt(lat: _here.latitude, lng: _here.longitude),
      );

      await tester.tap(find.byKey(const ValueKey('transaction-open-in-maps')));
      await tester.pumpAndSettle();

      expect(platform.launched, hasLength(1));
      final uri = platform.launched.single;
      expect(uri.scheme, 'geo');
      // The POINT, in the path -- which is what drops a pin on it. Not a text
      // search that might resolve somewhere else entirely.
      expect(uri.path, '${_here.latitude},${_here.longitude}');
    });

    testWidgets('it labels the pin with what the expense was', (tester) async {
      await pumpDetail(
        tester,
        _expenseAt(
          lat: _here.latitude,
          lng: _here.longitude,
          name: 'Dinner by the lake',
        ),
      );

      await tester.tap(find.byKey(const ValueKey('transaction-open-in-maps')));
      await tester.pumpAndSettle();

      expect(
        platform.launched.single.queryParameters['q'],
        contains('Dinner by the lake'),
      );
    });
  });

  group('an expense with no location does not offer it', () {
    // The action is on the coordinates row, and that row is gated on there
    // being coordinates. A button that opens a map at 0,0 for an expense logged
    // with no location would be worse than no button.
    testWidgets('there is no maps action', (tester) async {
      await pumpDetail(
        tester,
        Expense(
          amount: 500,
          category: ExpenseCategory.food,
          description: 'Dinner',
          date: DateTime.now(),
        ),
      );

      expect(find.text('Coordinates'), findsNothing);
      expect(
        find.byKey(const ValueKey('transaction-open-in-maps')),
        findsNothing,
      );
    });
  });
}
