import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_application_1/providers/checklist_provider.dart';
import 'package:flutter_application_1/providers/journey_provider.dart';
import 'package:flutter_application_1/providers/location_provider.dart';
import 'package:flutter_application_1/providers/transaction_provider.dart';
import 'package:flutter_application_1/screens/checklists/checklists_screen.dart';
import 'package:flutter_application_1/screens/journeys/journeys_screen.dart';
import 'package:flutter_application_1/screens/locations/locations_screen.dart';
import 'package:flutter_application_1/screens/transactions/transactions_screen.dart';
import 'package:flutter_application_1/screens/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    // Defer initialization to after first frame to avoid "setState during build" error
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeProviders();
    });
  }

  Future<void> _initializeProviders() async {
    // Initialize all providers
    if (!mounted) return;
    await context.read<ChecklistProvider>().initialize();
    if (!mounted) return;
    await context.read<JourneyProvider>().initialize();
    if (!mounted) return;
    await context.read<LocationProvider>().initialize();
    if (!mounted) return;
    await context.read<TransactionProvider>().initialize();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOutCubic,
        child: _buildBody(),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF100D0A)
              : Colors.white,
          border: Border(
            top: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
        ),
        child: NavigationBar(
          height: 68,
          backgroundColor: Colors.transparent,
          elevation: 0,
          indicatorColor: colorScheme.primaryContainer,
          selectedIndex: _selectedIndex,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.checklist_rounded),
              label: 'Pack',
            ),
            NavigationDestination(
              icon: Icon(Icons.route_rounded),
              label: 'Journey',
            ),
            // Third, ahead of Places. The dock order is Pack, Journey,
            // Transactions, Places, Settings: money is a thing you look at far
            // more often than saved places, so it sits closer to the thumb.
            NavigationDestination(
              icon: Icon(Icons.receipt_long_rounded),
              label: 'Transactions',
            ),
            NavigationDestination(
              icon: Icon(Icons.location_on_rounded),
              label: 'Places',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_rounded),
              label: 'Settings',
            ),
          ],
          onDestinationSelected: (index) {
            HapticFeedback.lightImpact();
            setState(() {
              _selectedIndex = index;
            });
          },
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return const ChecklistsScreen();
      case 1:
        return const JourneysScreen();
      case 2:
        return const TransactionsScreen();
      case 3:
        return const LocationsScreen();
      case 4:
        return const SettingsScreen();
      default:
        return const SizedBox.shrink();
    }
  }
}
