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
            // Money first. The dock order is Transactions, Journey, Pack,
            // Places: a spending ledger is something you look at daily, a trip
            // and a packing list are tied to a date, and saved places are looked
            // up rather than browsed. Putting the two most-frequent things on
            // the thumb's natural arc beats keeping the original order, where
            // the two you open most were the second and third slots.
            NavigationDestination(
              icon: Icon(Icons.receipt_long_rounded),
              label: 'Transactions',
            ),
            NavigationDestination(
              icon: Icon(Icons.route_rounded),
              label: 'Journey',
            ),
            NavigationDestination(
              icon: Icon(Icons.checklist_rounded),
              label: 'Pack',
            ),
            NavigationDestination(
              icon: Icon(Icons.location_on_rounded),
              label: 'Places',
            ),
            // Settings is not a destination. It is a gear in each screen's app
            // bar, because it is a drawer you open rather than a place you
            // browse.
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
    // Indexed to match `destinations` above. Kept adjacent to it deliberately:
    // these two lists have to stay in the same order, and when they drifted the
    // dock showed one label while the body showed another.
    switch (_selectedIndex) {
      case 0:
        return const TransactionsScreen();
      case 1:
        return const JourneysScreen();
      case 2:
        return const ChecklistsScreen();
      case 3:
        return const LocationsScreen();
      default:
        return const SizedBox.shrink();
    }
  }
}
