import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/providers/journey_provider.dart';
import 'package:daily_companion/providers/location_provider.dart';
import 'package:daily_companion/services/place_launcher.dart';
import 'package:daily_companion/theme/app_theme.dart';
import 'package:daily_companion/utils/format.dart';
import 'package:daily_companion/utils/iterable_ext.dart';

import '../screens/journeys/journey_detail_screen.dart';
import '../screens/locations/location_detail_screen.dart';

/// The place / journey / coordinates block of a transaction detail screen.
///
/// ONE widget for both directions. The expense screen grew these rows by hand
/// and the income screen never got them at all, which is how a payment ended up
/// with no way to say where it arrived even after income learned to record a
/// position. Sharing the block is what makes "applies equally to expense and
/// income" true by construction rather than by remembering.
///
/// Every value here is TAPPABLE, and that is the other half of the point. A
/// place name that is only text is a dead end: the user is looking at the screen
/// that knows exactly where they were, and the place they were has its own
/// screen with everything recorded there. Tapping the name has to be the way
/// there — otherwise the cross-link exists in the model and nowhere else.
class TransactionLocationBlock extends StatelessWidget {
  const TransactionLocationBlock({super.key, required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context) {
    final locations = context.watch<LocationProvider>().locations;
    final location = transaction.locationId == null
        ? null
        : locations.where((l) => l.id == transaction.locationId).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // WHERE IT HAPPENED, and whether that is a place the user named.
        //
        // `linked` rather than "has coordinates": a transaction can carry a
        // position and no name, which is the common case, and hiding the row
        // would be hiding the only evidence the app has.
        if (location != null)
          TransactionDetailRow(
            icon: Icons.place_rounded,
            label: 'Place',
            value: location.name,
            // Opens the place's own screen: what was recorded there, how much,
            // and the full history.
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => LocationDetailScreen(location: location),
              ),
            ),
          ),

        if (transaction.journeyId != null)
          TransactionJourneyRow(journeyId: transaction.journeyId!),

        if (transaction.locationCapturedAt != null)
          TransactionDetailRow(
            icon: Icons.my_location_rounded,
            label: 'Location captured',
            value: AppFormat.dateTime(transaction.locationCapturedAt!),
          ),

        if (transaction.hasCoordinates)
          TransactionDetailRow(
            icon: Icons.pin_drop_outlined,
            label: 'Coordinates',
            value:
                '${transaction.latitude!.toStringAsFixed(5)}, '
                '${transaction.longitude!.toStringAsFixed(5)}',
            // Opens the point in a maps app, on the same launcher the saved-place
            // row uses, so there is one way to open a location in the app.
            trailing: TextButton.icon(
              key: const ValueKey('transaction-open-in-maps'),
              onPressed: () => PlaceLauncher.openOrExplain(
                context,
                PlaceLink(
                  latitude: transaction.latitude!,
                  longitude: transaction.longitude!,
                  // The saved place's name when there is one, so the pin is
                  // labelled with something recognisable; otherwise what the
                  // transaction was described as. An empty description leaves
                  // the label off entirely, which the launcher handles.
                  name: location?.name ?? transaction.description,
                ),
              ),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Maps'),
            ),
          ),
      ],
    );
  }
}

/// A row whose value opens something rather than only being read.
class TransactionJourneyRow extends StatelessWidget {
  const TransactionJourneyRow({super.key, required this.journeyId});

  final String journeyId;

  @override
  Widget build(BuildContext context) {
    final journey = context.read<JourneyProvider>().getJourneyById(journeyId);
    // A dangling id — a trip deleted after the expense was logged — resolves to
    // nothing, and showing an empty row would be worse than showing none.
    if (journey == null) return const SizedBox.shrink();
    return TransactionDetailRow(
      icon: Icons.route_rounded,
      label: 'Journey',
      value: journey.title,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => JourneyDetailScreen(journey: journey),
        ),
      ),
    );
  }
}

/// One label/value line, optionally tappable, optionally with an action.
class TransactionDetailRow extends StatelessWidget {
  const TransactionDetailRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? iconColor;

  /// Navigates somewhere. Makes the row a button and says so.
  final VoidCallback? onTap;

  /// An action on the right of the row — for the one value the user can DO with
  /// rather than only read.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tappable = onTap != null;

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 20,
            color: iconColor ?? colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                // A link LOOKS like one. Same accent as everything else that
                // navigates, so "this goes somewhere" is a property of how it is
                // drawn rather than something only the code knows.
                Text(
                  value,
                  style: tappable
                      ? textTheme.bodyLarge?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        )
                      : textTheme.bodyLarge,
                ),
              ],
            ),
          ),
          // Centred on the row rather than pinned to its top, so the action
          // lines up with the label above the value instead of floating beside
          // the gap above it.
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Center(child: trailing!),
          ],
          if (tappable)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.xs, top: 2),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );

    if (!tappable) return row;
    // A whole-row target, because the value is the thing being read and a 20px
    // icon-sized target next to it is not what anyone aims at on a phone.
    return Semantics(
      button: true,
      label: '$label, $value',
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.smallRadius,
        child: row,
      ),
    );
  }
}
