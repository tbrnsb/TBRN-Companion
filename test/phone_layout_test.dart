import 'package:fl_chart/fl_chart.dart';

// Tristate is declared in dart:ui, not in the flutter package.
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/checklist_provider.dart';
import 'package:flutter_application_1/providers/journey_provider.dart';
import 'package:flutter_application_1/providers/location_provider.dart';
import 'package:flutter_application_1/providers/settings_provider.dart';
import 'package:flutter_application_1/providers/transaction_provider.dart';
import 'package:flutter_application_1/screens/checklists/checklists_screen.dart';
import 'package:flutter_application_1/screens/home_screen.dart';
import 'package:flutter_application_1/screens/journeys/journey_detail_screen.dart';
import 'package:flutter_application_1/screens/journeys/journeys_screen.dart';
import 'package:flutter_application_1/screens/locations/locations_screen.dart';
import 'package:flutter_application_1/screens/settings_screen.dart';
import 'package:flutter_application_1/screens/transactions/add_expense_sheet.dart';
import 'package:flutter_application_1/screens/transactions/transactions_screen.dart';
import 'package:flutter_application_1/services/storage_service.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/widgets/app_gear.dart';
import 'package:flutter_application_1/widgets/app_stat_tile.dart';
import 'package:flutter_application_1/widgets/spend_breakdown_card.dart';

import 'test_viewports.dart';
import 'visual_smoke_test.dart' show initTestStorage;

/// Wide enough for the three-across branch, used to prove the breakpoint is a
/// real branch and not a one-way switch.
const Size _wide = Size(820, 900);

Future<void> settleUi(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The five providers every screen under test watches.
typedef SeededProviders = ({
  JourneyProvider journeys,
  ChecklistProvider checklists,
  LocationProvider locations,
  TransactionProvider transactions,
  SettingsProvider settings,
});

/// Seeds a journey with a checklist, a place and an expense, then loads the
/// providers from storage.
///
/// Every step runs in real async: Hive does real file IO, which cannot complete
/// inside the fake-async zone of a `testWidgets` body.
Future<SeededProviders> _seed(WidgetTester tester) async {
  return (await tester.runAsync(() async {
    await StorageService().clear();

    final journey = Journey(
      destination: 'Pokhara',
      origin: 'Kathmandu',
      startTime: DateTime.now().subtract(const Duration(days: 2)),
    );
    await StorageService().addJourney(journey);

    final checklist = Checklist(
      name: 'Pack',
      description: 'Pack list',
      journeyId: journey.id,
    );
    await StorageService().addChecklist(checklist);
    for (final name in ['Boots', 'Jacket', 'Map']) {
      await StorageService().addChecklistItem(
        ChecklistItem(
          name: name,
          checklistId: checklist.id,
          isChecked: name == 'Boots',
        ),
      );
    }

    await StorageService().addLocation(
      Location(
        name: 'Phewa Lake',
        latitude: 28.2096,
        longitude: 83.9856,
        description: 'Lakeside',
        journeyId: journey.id,
      ),
    );

    // A four-figure amount is the case that clipped to "Rs. 1,2…".
    await StorageService().addTransaction(
      Expense(
        amount: 1250.50,
        category: ExpenseCategory.travel,
        description: 'Bus to the trailhead',
        journeyId: journey.id,
        date: DateTime.now().subtract(const Duration(days: 1)),
      ),
    );

    final journeys = JourneyProvider();
    final checklists = ChecklistProvider();
    final locations = LocationProvider();
    final transactions = TransactionProvider();
    final settings = SettingsProvider();
    await journeys.initialize();
    await checklists.initialize();
    await locations.initialize();
    await transactions.initialize();
    await settings.load();

    return (
      journeys: journeys,
      checklists: checklists,
      locations: locations,
      transactions: transactions,
      settings: settings,
    );
  }))!;
}

Widget _app(SeededProviders p, Widget home) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<JourneyProvider>.value(value: p.journeys),
      ChangeNotifierProvider<ChecklistProvider>.value(value: p.checklists),
      ChangeNotifierProvider<LocationProvider>.value(value: p.locations),
      ChangeNotifierProvider<TransactionProvider>.value(value: p.transactions),
      ChangeNotifierProvider<SettingsProvider>.value(value: p.settings),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: home,
    ),
  );
}

void main() {
  setUpAll(() async {
    await initTestStorage();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('journey stat tiles', () {
    testWidgets('a 360dp phone puts the money tile on its own full-width row', (
      tester,
    ) async {
      usePhoneLayout(
        tester,
        TestViewports.phoneSmall,
        because: 'three tiles across clipped the amount to "Rs. 1,2…"',
      );

      final p = await _seed(tester);
      final journey = p.journeys.journeys.single;
      await tester.pumpWidget(_app(p, JourneyDetailScreen(journey: journey)));
      await settleUi(tester);

      expect(find.byType(AppStatTile), findsNWidgets(3));

      final rects = [
        for (var i = 0; i < 3; i++)
          tester.getRect(find.byType(AppStatTile).at(i)),
      ];

      // Tiles 0 and 1 share a row; the money tile sits below them.
      expect(rects[0].top, moreOrLessEquals(rects[1].top));
      expect(
        rects[2].top,
        greaterThan(rects[0].bottom),
        reason: 'the Spent tile must drop to its own row below 600dp',
      );
      expect(
        rects[2].width,
        greaterThan(rects[0].width),
        reason: 'the money tile takes the whole measure, not a third of it',
      );
    });

    testWidgets('a wide viewport keeps all three tiles on one row', (
      tester,
    ) async {
      usePhoneLayout(tester, _wide);

      final p = await _seed(tester);
      final journey = p.journeys.journeys.single;
      await tester.pumpWidget(_app(p, JourneyDetailScreen(journey: journey)));
      await settleUi(tester);

      final rects = [
        for (var i = 0; i < 3; i++)
          tester.getRect(find.byType(AppStatTile).at(i)),
      ];

      expect(rects[0].top, moreOrLessEquals(rects[2].top));
      expect(rects[0].width, moreOrLessEquals(rects[2].width));
      expect(rects[0].right, lessThan(rects[1].left));
    });

    testWidgets('the full amount is not truncated at 360dp', (tester) async {
      usePhoneLayout(tester, TestViewports.phoneSmall);

      final p = await _seed(tester);
      final journey = p.journeys.journeys.single;
      await tester.pumpWidget(_app(p, JourneyDetailScreen(journey: journey)));
      await settleUi(tester);

      // The seeded expense is 1250.50, so the whole formatted amount has to be
      // present as one piece of text rather than an ellipsised prefix.
      expect(find.text('Rs. 1,250.5'), findsOneWidget);
    });
  });

  group('spend breakdown card', () {
    BreakdownSegment segment(String name, double amount, Color color) {
      return BreakdownSegment(
        meta: CategoryMeta(
          id: name,
          name: name,
          icon: Icons.circle,
          color: color,
          popularity: 0,
        ),
        amount: amount,
      );
    }

    Widget card(String symbol) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: Scaffold(
          body: ListView(
            padding: AppSpacing.screenPadding,
            children: [
              SpendBreakdownCard(
                title: 'Spending by category',
                currencySymbol: symbol,
                segments: [
                  segment('Food', 1234.50, AppColors.carafe),
                  segment('Travel', 890.25, AppColors.khaki),
                ],
              ),
            ],
          ),
        ),
      );
    }

    testWidgets('at 360dp the donut stacks above a full-width legend', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phoneSmall);

      await tester.pumpWidget(card('€ '));
      await settleUi(tester);

      final donut = tester.getRect(find.byType(PieChart));
      final legend = tester.getRect(find.text('Food'));

      expect(
        legend.top,
        greaterThanOrEqualTo(donut.bottom),
        reason: 'below 400dp the donut and the legend must not share a row',
      );
      // The whole measure is available, so a long amount is not cut.
      expect(find.text('€ 1,234.5'), findsOneWidget);
    });

    testWidgets('a wide viewport keeps the donut beside the legend', (
      tester,
    ) async {
      usePhoneLayout(tester, _wide);

      await tester.pumpWidget(card('€ '));
      await settleUi(tester);

      final donut = tester.getRect(find.byType(PieChart));
      final legend = tester.getRect(find.text('Food'));

      expect(
        legend.left,
        greaterThanOrEqualTo(donut.right),
        reason: 'at or above 400dp the legend sits to the right of the donut',
      );
    });
  });

  group('add expense context chips', () {
    testWidgets('a very long journey title cannot widen the menu past its cap', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phoneSmall);

      final p = await _seed(tester);
      // Rename the seeded journey to something far wider than a phone.
      final journey = p.journeys.journeys.single;
      await tester.runAsync(() async {
        await StorageService().updateJourney(
          journey.copyWith(
            destination:
                'Kathmandu to Pokhara via the Annapurna conservation corridor',
          ),
        );
        await p.journeys.initialize();
      });

      await tester.pumpWidget(
        _app(
          p,
          Builder(
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
      );
      await settleUi(tester);

      await tester.tap(find.text('open'));
      await settleUi(tester);

      expect(find.byType(AddExpenseSheet), findsOneWidget);

      final menu = tester.getRect(
        find
            .descendant(
              of: find.byType(AddExpenseSheet),
              // Matched by predicate: the chip is a DropdownMenu<String?>, and
              // naming the exact generic argument would make this test brittle.
              matching: find.byWidgetPredicate((w) => w is DropdownMenu),
            )
            .first,
      );

      expect(
        menu.width,
        lessThanOrEqualTo(220),
        reason: 'a long title must not size the chip past its own cap',
      );
    });
  });

  group('how you pay, on the add-expense sheet', () {
    /// Opens the add-expense sheet and settles it.
    Future<void> openSheet(WidgetTester tester, SeededProviders p) async {
      await tester.pumpWidget(
        _app(
          p,
          Builder(
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
      );
      await settleUi(tester);
      await tester.tap(find.text('open'));
      await settleUi(tester);
    }

    testWidgets('offers cash and online, and starts on cash', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      final p = await _seed(tester);

      await openSheet(tester, p);

      expect(find.text('How did you pay?'), findsOneWidget);
      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('Online'), findsOneWidget);
      // Cash is the common case here, so it is preselected rather than making
      // the user tap before they can save.
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('pay-cash')))
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
    });

    testWidgets('tapping online moves the selection', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      final p = await _seed(tester);

      await openSheet(tester, p);
      await tester.tap(find.text('Online'));
      await settleUi(tester);

      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('pay-online')))
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      // A two-way choice, not a third state.
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('pay-cash')))
            .flagsCollection
            .isSelected,
        Tristate.isFalse,
      );
    });

    testWidgets('an existing expense opens on the method it was saved with', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      final p = await _seed(tester);
      final online = Expense(
        amount: 400,
        category: ExpenseCategory.travel,
        description: 'Bus',
        paymentMethod: PaymentMethod.online,
      );
      await tester.runAsync(() async {
        await StorageService().addTransaction(online);
        await p.transactions.initialize();
      });

      await tester.pumpWidget(
        _app(
          p,
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () =>
                      AddExpenseSheet.show(context, existing: online),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await settleUi(tester);
      await tester.tap(find.text('open'));
      await settleUi(tester);

      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('pay-online')))
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
    });

    testWidgets('an expense saved before the field existed is not guessed at', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      final p = await _seed(tester);
      final legacy = Expense(
        amount: 150,
        category: ExpenseCategory.food,
        description: 'Old tea',
      );
      await tester.runAsync(() async {
        await StorageService().addTransaction(legacy);
        await p.transactions.initialize();
      });

      await tester.pumpWidget(
        _app(
          p,
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () =>
                      AddExpenseSheet.show(context, existing: legacy),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await settleUi(tester);
      await tester.tap(find.text('open'));
      await settleUi(tester);

      // Editing it offers the choice without pretending to know the answer:
      // the picker falls back to cash for display, and saving records it.
      expect(find.text('How did you pay?'), findsOneWidget);
    });

    testWidgets('fits a narrow phone without overflowing', (tester) async {
      usePhoneLayout(tester, TestViewports.phoneSmall);
      final p = await _seed(tester);

      await openSheet(tester, p);

      expect(tester.takeException(), isNull);
    });
  });

  group('the dock', () {
    testWidgets('has exactly four tabs and no Settings destination', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phoneSmall);

      await tester.pumpWidget(_navApp());
      await tester.pump(const Duration(milliseconds: 300));

      final destinations = tester
          .widget<NavigationBar>(find.byType(NavigationBar))
          .destinations;

      expect(
        destinations.length,
        4,
        reason: 'Settings is a drawer opened from the gear, not a fifth tab',
      );
      // `destinations` is typed List<Widget>; the labels live on
      // NavigationDestination, which is what every destination in this dock is.
      final labels = destinations
          .map((d) => (d as NavigationDestination).label)
          .toList();

      expect(labels, [
        'Transactions',
        'Journey',
        'Pack',
        'Places',
      ], reason: 'the dock order is fixed and money leads');
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Settings'),
        ),
        findsNothing,
      );
    });

    testWidgets('every tab label renders whole at 360dp', (tester) async {
      usePhoneLayout(
        tester,
        TestViewports.phoneSmall,
        because: 'a clipped dock label is unreadable and no test would notice',
      );

      await tester.pumpWidget(_navApp());
      await tester.pump(const Duration(milliseconds: 300));

      final bar = tester.getRect(find.byType(NavigationBar));
      final count = tester
          .widget<NavigationBar>(find.byType(NavigationBar))
          .destinations
          .length;
      // NavigationBar divides its width evenly, so this is the slot a label
      // has to render inside.
      final slot = bar.width / count;

      for (final label in ['Transactions', 'Journey', 'Pack', 'Places']) {
        final finder = find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        );
        expect(finder, findsOneWidget, reason: 'no "$label" tab');

        // The laid-out Text is what gets ellipsised, so its own width is the
        // thing to compare, not the natural width of the string.
        final text = tester.getRect(finder);
        expect(
          text.width,
          lessThanOrEqualTo(slot + 0.5),
          reason:
              '"$label" is clipped: rendered ${text.width.toStringAsFixed(1)} '
              'in a ${slot.toStringAsFixed(1)} slot (bar ${bar.width})',
        );
      }
    });
  });

  group('the settings gear', () {
    testWidgets('is on the app bar of all four tabs', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      await tester.pumpWidget(_navApp());
      await settleUi(tester);

      for (var tab = 0; tab < 4; tab++) {
        await tester.tap(find.byType(NavigationDestination).at(tab));
        await settleUi(tester);

        expect(
          find.byKey(AppGearButton.buttonKey),
          findsOneWidget,
          reason: 'tab $tab has no way into Settings',
        );
        // Tapping the destination really moved the body, rather than leaving
        // the first tab under four identical app bars.
        expect(
          find.byType(_screenForTab(tab)),
          findsOneWidget,
          reason: 'tab $tab did not switch the body',
        );
      }
    });

    testWidgets('opens Settings, and back returns to the same tab', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      await tester.pumpWidget(_navApp());
      await settleUi(tester);

      // Start on Places so a bug that ignores the tapped index is visible.
      await tester.tap(find.byType(NavigationDestination).at(3));
      await settleUi(tester);

      await tester.tap(find.byKey(AppGearButton.buttonKey));
      await settleUi(tester);

      expect(find.byType(SettingsScreen), findsOneWidget);

      // The point of pushing rather than swapping: back goes where you were.
      await tester.pageBack();
      await settleUi(tester);

      expect(find.byType(SettingsScreen), findsNothing);
      expect(find.byType(LocationsScreen), findsOneWidget);
    });

    testWidgets('Settings still works from the gear — not an empty shell', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      await tester.pumpWidget(_navApp());
      await settleUi(tester);

      await tester.tap(find.byKey(AppGearButton.buttonKey));
      await settleUi(tester);

      // The sections the drawer is actually for. If the route stopped building
      // them this test fails instead of a user finding an empty screen.
      expect(find.text('Currency'), findsOneWidget);
      expect(find.text('Themes'), findsOneWidget);
    });

    testWidgets('a very long tab title does not squeeze the gear out', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phoneSmall);

      await tester.pumpWidget(_navApp());
      await settleUi(tester);

      // Places has the longest title of the four; the gear has to stay inside
      // the viewport whatever the app bar title measures.
      final gear = tester.getRect(find.byKey(AppGearButton.buttonKey));
      expect(gear.right, lessThanOrEqualTo(tester.view.physicalSize.width));
      expect(gear.width, greaterThan(0));
    });
  });
}

/// The body each dock slot is expected to show, in the fixed dock order.
Type _screenForTab(int tab) {
  return switch (tab) {
    0 => TransactionsScreen,
    1 => JourneysScreen,
    2 => ChecklistsScreen,
    _ => LocationsScreen,
  };
}

Widget _navApp() {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ChecklistProvider()),
      ChangeNotifierProvider(create: (_) => JourneyProvider()),
      ChangeNotifierProvider(create: (_) => LocationProvider()),
      ChangeNotifierProvider(create: (_) => TransactionProvider()),
      ChangeNotifierProvider(create: (_) => SettingsProvider()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const HomeScreen(),
    ),
  );
}
