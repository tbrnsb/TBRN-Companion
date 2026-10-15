import 'package:flutter/material.dart';
import 'package:daily_companion/theme/app_theme.dart';

/// Flat summary tile: icon + label + value on a tonal surface.
/// Replaces the various gradient/glass/grey stat boxes.
class AppStatTile extends StatelessWidget {
  const AppStatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        // A RADIUS, from the radii scale. This was `circular(12)`, which is
        // `AppSpacing.sm` — a spacing constant used as a corner radius, so these
        // tiles had visibly different corners from the cards they sit among.
        borderRadius: AppRadii.mediumRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(height: 8),
          Text(
            label,
            style: textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
