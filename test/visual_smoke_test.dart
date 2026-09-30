import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/providers/checklist_provider.dart';
import 'package:flutter_application_1/providers/journey_provider.dart';
import 'package:flutter_application_1/providers/location_provider.dart';
import 'package:flutter_application_1/providers/settings_provider.dart';
import 'package:flutter_application_1/providers/transaction_provider.dart';
import 'package:flutter_application_1/services/storage_service.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/screens/home_screen.dart';

import 'test_viewports.dart';

Future<void> initTestStorage() async {
  final dir = Directory.systemTemp.createTempSync('hive_test');
  await StorageService().initialize(hivePath: dir.path);
}

Widget _testApp() {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ChecklistProvider()),
      ChangeNotifierProvider(create: (_) => JourneyProvider()),
      ChangeNotifierProvider(create: (_) => LocationProvider()),
      ChangeNotifierProvider(create: (_) => TransactionProvider()),
      ChangeNotifierProvider<SettingsProvider>(
        create: (_) => SettingsProvider(),
      ),
    ],
    child: MaterialApp(
      title: 'Daily Context Companion',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const HomeScreen(),
    ),
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await initTestStorage();
  });

  testWidgets('main app shows home screen without debug banner', (
    tester,
  ) async {
    usePhoneLayout(tester, TestViewports.phonePortrait);

    await tester.pumpWidget(_testApp());
    await tester.pump();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(Scaffold), findsWidgets);

    // Debug banner must not be visible.
    expect(find.text('debug'), findsNothing);
  });

  testWidgets('navigation taps work', (tester) async {
    usePhoneLayout(tester, TestViewports.phonePortrait);

    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    // Scoped to the nav bar. "Transactions" is also the app bar title of that
    // screen, so a bare find.text would match twice once the tab is open and
    // tester.tap would throw on the ambiguity.
    Finder tab(String label) => find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(label),
    );

    // The dock order, which is the thing worth asserting: Transactions sits
    // third, ahead of Places.
    for (final label in [
      'Pack',
      'Journey',
      'Transactions',
      'Places',
      'Settings',
    ]) {
      expect(tab(label), findsOneWidget, reason: 'no "$label" tab');
      await tester.tap(tab(label));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
    }
  });

  testWidgets('the dock is Pack, Journey, Transactions, Places, Settings', (
    tester,
  ) async {
    usePhoneLayout(tester, TestViewports.phonePortrait);

    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    final labels = tester
        .widget<NavigationBar>(find.byType(NavigationBar))
        .destinations
        // destinations is List<Widget>; every entry here is a
        // NavigationDestination, which is where the label actually lives.
        .map((d) => (d as NavigationDestination).label)
        .toList();

    expect(labels, ['Pack', 'Journey', 'Transactions', 'Places', 'Settings']);
  });
}
