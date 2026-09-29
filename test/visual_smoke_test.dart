import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter_application_1/providers/checklist_provider.dart';
import 'package:flutter_application_1/providers/journey_provider.dart';
import 'package:flutter_application_1/providers/location_provider.dart';
import 'package:flutter_application_1/providers/transaction_provider.dart';
import 'package:flutter_application_1/services/storage_service.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/screens/home_screen.dart';

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
    await initTestStorage();
  });

  testWidgets('main app shows home screen without debug banner', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    await tester.pumpWidget(_testApp());
    await tester.pump();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(Scaffold), findsWidgets);

    // Debug banner must not be visible.
    expect(find.text('debug'), findsNothing);
  });

  testWidgets('navigation taps work', (tester) async {
    tester.view.physicalSize = const Size(1280, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    for (final label in ['Pack', 'Journey', 'Places', 'Spend']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
    }
  });
}
