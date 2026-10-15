import 'package:flutter/material.dart';
import 'package:daily_companion/theme/app_theme.dart';

/// Standard empty state: tonal icon circle, title, hint, optional action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// The action's icon.
  ///
  /// A parameter rather than a hardcoded `Icons.add_rounded`, because every
  /// current use happens to add something — so the first non-add action would
  /// have shipped with a plus sign on it, on the app's most-replicated
  /// component. Defaults to add, which is what it always drew.
  final IconData? actionIcon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              // On the scale. This was 20, the only off-scale `EdgeInsets` in
              // the surface layer, and it made the icon circle 80dp — a size
              // the scale does not have either.
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: colorScheme.primary),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: onAction,
                icon: Icon(actionIcon ?? Icons.add_rounded),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
