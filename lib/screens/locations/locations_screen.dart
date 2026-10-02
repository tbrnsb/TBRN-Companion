import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/providers/location_provider.dart';
import 'package:daily_companion/widgets/widgets.dart';
import 'package:daily_companion/screens/locations/add_location_screen.dart';
import 'package:daily_companion/services/place_launcher.dart';
import 'package:daily_companion/theme/app_theme.dart';

class LocationsScreen extends StatelessWidget {
  const LocationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Location Bookmarks'),
        elevation: 0,
        actions: const [AppCalendarButton(), AppGearButton()],
      ),
      body: Consumer<LocationProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.locations.isEmpty) {
            return EmptyState(
              icon: Icons.location_on_rounded,
              title: 'No saved locations yet',
              message: 'Add a place to track geofence context and routines.',
              actionLabel: 'Add Location',
              onAction: () => _showLocationDialog(context, null),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => provider.initialize(),
            child: ListView(
              // Clears the FAB; see AppSpacing.screenPaddingWithFab.
              padding: AppSpacing.screenPaddingWithFab,
              children: [
                _SummaryCard(provider: provider),
                const SizedBox(height: 24),
                const SectionHeader('Saved places'),
                const SizedBox(height: 12),
                ...provider.locations.map(
                  (location) =>
                      _LocationTile(location: location, provider: provider),
                ),
              ],
            ),
          );
        },
      ),
      // RULE (a), the same decision as the other tabs: hidden while the list is
      // empty, back as soon as there is a row. See transactions_screen.dart for
      // why it is one rule rather than a per-call-site patch.
      floatingActionButton:
          context.select<LocationProvider, bool>((p) => p.locations.isEmpty)
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                HapticFeedback.heavyImpact();
                _showLocationDialog(context, null);
              },
              icon: const Icon(Icons.add_location_alt_rounded),
              label: const Text('Add Location'),
            ),
    );
  }

  static void _showLocationDialog(BuildContext context, Location? location) {
    AddLocationScreen.show(context, location: location);
  }

  static void _confirmDelete(
    BuildContext context,
    LocationProvider provider,
    Location location,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete location?'),
        content: Text('Remove "${location.name}" from your saved places?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              provider.deleteLocation(location.id);
              Navigator.pop(dialogContext);
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.provider});

  final LocationProvider provider;

  @override
  Widget build(BuildContext context) {
    final currentStatus = provider.currentLocationId == null
        ? 'Not in a saved zone'
        : 'Within saved zone';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: AppStatTile(
                label: 'Saved',
                value: provider.locations.length.toString(),
                icon: Icons.bookmark_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppStatTile(
                label: 'Status',
                value: currentStatus,
                icon: Icons.gps_fixed_rounded,
              ),
            ),
          ],
        ),
        if (provider.currentPosition == null) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.location_off_rounded,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  // The actual reason, and an action that matches it.
                  //
                  // The fallback used to be a fixed "Finding your location…",
                  // which the device disproved: with the permission denied the
                  // status was NOT `locating` — Retry was live — yet the screen
                  // still said it was looking. A sentence about searching, shown
                  // while nothing is searching, is the one state the user cannot
                  // act on. The message follows the status instead.
                  provider.error ?? _locationMessage(provider.status),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              TextButton(
                onPressed: provider.status == LocationStatus.locating
                    ? null
                    : () => provider.updateCurrentPosition(),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                  ),
                ),
                child: Text(
                  provider.status == LocationStatus.locating
                      ? 'Locating…'
                      : 'Retry',
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _LocationTile extends StatelessWidget {
  const _LocationTile({required this.location, required this.provider});

  final Location location;
  final LocationProvider provider;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final secondary = StringBuffer();
    secondary.write(
      '${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}',
    );
    if (provider.currentPosition != null) {
      secondary.write(
        ' · ${provider.getDistanceToLocation(location.id).toStringAsFixed(0)} m away',
      );
    }

    return Column(
      children: [
        ListTile(
          leading: CircleAvatar(
            backgroundColor: colorScheme.primaryContainer,
            // A place saved before icons existed has no icon; resolve falls
            // back to a pin, so the row never renders blank.
            child: Icon(
              PlaceIcons.resolve(location.icon),
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          title: Text(location.name),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (location.description.isNotEmpty)
                Text(
                  location.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 2),
              Text(
                secondary.toString(),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          trailing: PopupMenuButton<String>(
            itemBuilder: (context) => [
              // FIRST, and not last: a saved place's whole reason to exist is
              // being taken to. It used not to be here at all -- the app could
              // read a pasted Maps link and then had no way to open one, so the
              // coordinates were stored and otherwise inert.
              const PopupMenuItem(
                key: ValueKey('place-open-in-maps'),
                value: 'maps',
                child: Text('Open in maps'),
              ),
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
            onSelected: (value) {
              HapticFeedback.lightImpact();
              if (value == 'maps') {
                PlaceLauncher.openOrExplain(
                  context,
                  PlaceLink(
                    latitude: location.latitude,
                    longitude: location.longitude,
                    name: location.name,
                  ),
                );
              } else if (value == 'edit') {
                LocationsScreen._showLocationDialog(context, location);
              } else if (value == 'delete') {
                LocationsScreen._confirmDelete(context, provider, location);
              }
            },
          ),
          isThreeLine: location.description.isNotEmpty,
        ),
        const Divider(indent: 64, height: 1),
      ],
    );
  }
}

/// What to say when the provider has no error of its own.
///
/// Said in terms of the state, because the one thing the user must never be
/// told is that something is happening when it is not.
String _locationMessage(LocationStatus status) => switch (status) {
  LocationStatus.locating => 'Finding your location…',
  LocationStatus.ready => 'No fix yet. Tap Retry to look again.',
  LocationStatus.noFix => 'Could not get a fix. Tap Retry to try again.',
  LocationStatus.serviceDisabled =>
    'Location services are turned off on this phone.',
  LocationStatus.permissionDenied =>
    'Location permission was denied. Tap Retry to ask again.',
  LocationStatus.permissionDeniedForever =>
    'Location permission is blocked. Enable it in the phone Settings.',
  LocationStatus.unknown => 'Location is not on yet. Tap Retry to turn it on.',
};
