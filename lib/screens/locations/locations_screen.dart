import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/journey_provider.dart';
import 'package:flutter_application_1/providers/location_provider.dart';
import 'package:flutter_application_1/widgets/widgets.dart';
import 'package:flutter_application_1/theme/app_theme.dart';

class LocationsScreen extends StatelessWidget {
  const LocationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Location Bookmarks'), elevation: 0),
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
              padding: const EdgeInsets.all(AppSpacing.md),
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
      floatingActionButton: FloatingActionButton.extended(
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
    showDialog(
      context: context,
      builder: (_) => _LocationFormDialog(location: location),
    );
  }

  /// Open the place form prefilled (e.g. from a frequent-location hint).
  static void showLocationFormPrefilled(
    BuildContext context,
    Location prefill,
  ) {
    showDialog(
      context: context,
      builder: (_) => _LocationFormDialog(prefill: prefill),
    );
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
          const SizedBox(height: 8),
          Text(
            'GPS unavailable on this device — distances are hidden.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
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
            child: Text(
              (location.name.isNotEmpty ? location.name[0] : 'L').toUpperCase(),
              style: TextStyle(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
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
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
            onSelected: (value) {
              HapticFeedback.lightImpact();
              if (value == 'edit') {
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

class _LocationFormDialog extends StatefulWidget {
  const _LocationFormDialog({this.location, this.prefill});

  final Location? location;

  /// Overrides fields when saving from e.g. a frequent-location suggestion.
  final Location? prefill;

  @override
  State<_LocationFormDialog> createState() => _LocationFormDialogState();
}

class _LocationFormDialogState extends State<_LocationFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _latController;
  late final TextEditingController _lngController;
  late final TextEditingController _radiusController;
  String? _journeyId;

  @override
  void initState() {
    super.initState();
    final location = widget.location ?? widget.prefill;
    _journeyId = widget.location?.journeyId ?? widget.prefill?.journeyId;
    _nameController = TextEditingController(text: location?.name ?? '');
    _descriptionController = TextEditingController(
      text: location?.description ?? '',
    );
    _latController = TextEditingController(
      text: location == null ? '' : location.latitude.toString(),
    );
    _lngController = TextEditingController(
      text: location == null ? '' : location.longitude.toString(),
    );
    _radiusController = TextEditingController(
      text: location == null ? '100' : location.radiusMeters.toString(),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.location == null ? 'Add location' : 'Edit location';

    return AlertDialog(
      title: Text(label),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
                minLines: 2,
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.my_location_rounded, size: 18),
                  label: const Text('Use current location'),
                  onPressed: () async {
                    final provider = context.read<LocationProvider>();
                    await provider.updateCurrentPosition();
                    final pos = provider.currentPosition;
                    if (pos != null && context.mounted) {
                      setState(() {
                        _latController.text = pos.latitude.toStringAsFixed(6);
                        _lngController.text = pos.longitude.toStringAsFixed(6);
                      });
                    } else if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Location unavailable on this device.'),
                        ),
                      );
                    }
                  },
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _latController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Latitude'),
                      validator: (value) {
                        final parsed = double.tryParse(value ?? '');
                        if (parsed == null) return 'Valid number required';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _lngController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Longitude'),
                      validator: (value) {
                        final parsed = double.tryParse(value ?? '');
                        if (parsed == null) return 'Valid number required';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _radiusController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Checkpoint radius (meters)',
                  helperText:
                      'Expenses taken within this distance can be linked here.',
                ),
                validator: (value) {
                  final parsed = double.tryParse(value ?? '');
                  if (parsed == null || parsed <= 0) return 'Must be > 0';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final journeys = context.watch<JourneyProvider>().journeys;
                  if (journeys.isEmpty) return const SizedBox.shrink();
                  return DropdownButtonFormField<String?>(
                    initialValue: _journeyId,
                    decoration: const InputDecoration(
                      labelText: 'Journey (optional)',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('No journey'),
                      ),
                      ...journeys.map(
                        (j) => DropdownMenuItem<String?>(
                          value: j.id,
                          child: Text(j.title),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _journeyId = v),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;

            final provider = context.read<LocationProvider>();
            final location = Location(
              id: widget.location?.id,
              name: _nameController.text.trim(),
              description: _descriptionController.text.trim(),
              latitude: double.parse(_latController.text),
              longitude: double.parse(_lngController.text),
              radiusMeters: double.parse(_radiusController.text),
            );

            if (widget.location == null) {
              provider.addLocation(
                Location(
                  id: widget.prefill?.id,
                  name: location.name,
                  description: location.description,
                  latitude: location.latitude,
                  longitude: location.longitude,
                  radiusMeters: location.radiusMeters,
                  journeyId: _journeyId,
                ),
              );
            } else {
              provider.updateLocation(
                widget.location!.copyWith(
                  name: location.name,
                  description: location.description,
                  latitude: location.latitude,
                  longitude: location.longitude,
                  radiusMeters: location.radiusMeters,
                  journeyId: _journeyId,
                  clearJourney: _journeyId == null,
                ),
              );
            }

            Navigator.pop(context);
          },
          child: Text(widget.location == null ? 'Add' : 'Save'),
        ),
      ],
    );
  }
}
