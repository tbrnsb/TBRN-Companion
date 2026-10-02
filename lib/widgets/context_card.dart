import 'package:flutter/material.dart';

import 'package:daily_companion/theme/app_theme.dart';

/// Tonal context/alert card (replaces the old gradient info cards).
/// Uses ColorScheme containers so it is dark-mode safe.
class ContextCard extends StatelessWidget {
  const ContextCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.color,
    this.onColor,
  });

  final IconData icon;
  final String title;
  final Widget child;

  /// Container color (defaults to secondaryContainer).
  final Color? color;

  /// Content color (defaults to onSecondaryContainer).
  final Color? onColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveColor = color ?? colorScheme.secondaryContainer;
    final effectiveOnColor = onColor ?? colorScheme.onSecondaryContainer;

    // A context card is a tonal surface carrying its own semantic colour, so it
    // sits on the flat tier with the fill overridden rather than reaching for a
    // bare Card with a colour override.
    return AppSurface(
      tier: AppSurfaceTier.flat,
      color: effectiveColor,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: effectiveOnColor),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: effectiveOnColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          DefaultTextStyle(
            style:
                Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: effectiveOnColor) ??
                TextStyle(color: effectiveOnColor),
            child: IconTheme(
              data: IconThemeData(color: effectiveOnColor, size: 16),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
