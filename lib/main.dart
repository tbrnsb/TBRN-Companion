import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_application_1/providers/budget_provider.dart';
import 'package:flutter_application_1/providers/checklist_provider.dart';
import 'package:flutter_application_1/providers/journey_provider.dart';
import 'package:flutter_application_1/providers/location_provider.dart';
import 'package:flutter_application_1/providers/transaction_provider.dart';
import 'package:flutter_application_1/providers/settings_provider.dart';
import 'package:flutter_application_1/services/storage_service.dart';
import 'package:flutter_application_1/services/notification_service.dart';
import 'package:flutter_application_1/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService().initialize();
  await NotificationService.initialize();
  // Awaited before the first frame so the app never renders with default
  // currency/theme and then flashes to the persisted values.
  final settings = SettingsProvider();
  await settings.load();
  // Budgets are limits the user set, loaded before the first frame for the same
  // reason the currency is: a budget bar that renders unset and then snaps to
  // the real limit is a flash of a wrong number.
  final budgets = BudgetProvider();
  await budgets.load();
  runApp(MainApp(settings: settings, budgets: budgets));
}

class MainApp extends StatelessWidget {
  const MainApp({super.key, required this.settings, required this.budgets});

  final SettingsProvider settings;
  final BudgetProvider budgets;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ChecklistProvider()),
        ChangeNotifierProvider(create: (_) => JourneyProvider()),
        ChangeNotifierProvider(create: (_) => LocationProvider()),
        ChangeNotifierProvider(create: (_) => TransactionProvider()),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: budgets),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return MaterialApp(
            title: 'TBRN',
            debugShowCheckedModeBanner: false,
            themeMode: settings.themeMode,
            theme: settings.lightTheme,
            darkTheme: settings.darkTheme,
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
