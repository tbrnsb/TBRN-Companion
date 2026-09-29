import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/journey_provider.dart';
import 'package:flutter_application_1/providers/location_provider.dart';
import 'package:flutter_application_1/providers/settings_provider.dart';
import 'package:flutter_application_1/providers/transaction_provider.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/utils/format.dart';
import 'package:flutter_application_1/utils/iterable_ext.dart';

import 'add_expense_sheet.dart';

class ExpenseDetailScreen extends StatelessWidget {
  const ExpenseDetailScreen({super.key, required this.expense});

  final Expense expense;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    final current =
        context
            .watch<TransactionProvider>()
            .transactions
            .where((t) => t.id == expense.id)
            .whereType<Expense>()
            .firstOrNull ??
        expense;

    final meta = current.categoryMeta;
    final location = current.locationId == null
        ? null
        : context.read<LocationProvider>().getLocationById(current.locationId!);
    final journey = current.journeyId == null
        ? null
        : context.read<JourneyProvider>().getJourneyById(current.journeyId!);

    return Scaffold(
      appBar: AppBar(
        title: Text(meta.name),
        actions: [
          IconButton(
            tooltip: 'Edit expense',
            icon: const Icon(Icons.edit_rounded),
            onPressed: () => AddExpenseSheet.show(context, existing: current),
          ),
          IconButton(
            tooltip: 'Delete expense',
            icon: Icon(Icons.delete_outline_rounded, color: colorScheme.error),
            onPressed: () => _confirmDelete(context, current),
          ),
        ],
      ),
      body: ListView(
        padding: AppSpacing.screenPadding,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: meta.color.withValues(alpha: 0.12),
              borderRadius: AppRadii.mediumRadius,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: meta.color.withValues(alpha: 0.2),
                        borderRadius: AppRadii.smallRadius,
                      ),
                      child: Icon(meta.icon, color: meta.color),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        current.description.isEmpty
                            ? meta.name
                            : current.description,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  AppFormat.signedMoney(
                    current.amount,
                    isExpense: true,
                    symbol: context.select<SettingsProvider, String>(
                      (s) => s.currency.symbol,
                    ),
                  ),
                  style: textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  AppFormat.relativeDay(current.date),
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          _DetailRow(
            icon: meta.icon,
            iconColor: meta.color,
            label: 'Category',
            value: current.effectiveCategoryName,
          ),
          if (location != null)
            _DetailRow(
              icon: Icons.place_rounded,
              label: 'Place',
              value: location.name,
            ),
          if (journey != null)
            _DetailRow(
              icon: Icons.route_rounded,
              label: 'Journey',
              value: journey.title,
            ),
          if (current.locationCapturedAt != null)
            _DetailRow(
              icon: Icons.my_location_rounded,
              label: 'Location captured',
              value: AppFormat.dateTime(current.locationCapturedAt!),
            ),
          if (current.hasCoordinates)
            _DetailRow(
              icon: Icons.pin_drop_outlined,
              label: 'Coordinates',
              value:
                  '${current.latitude!.toStringAsFixed(5)}, ${current.longitude!.toStringAsFixed(5)}',
            ),
          const SizedBox(height: AppSpacing.lg),

          OutlinedButton.icon(
            onPressed: () => AddExpenseSheet.show(context, existing: current),
            icon: const Icon(Icons.edit_rounded),
            label: const Text('Edit expense'),
          ),
          const SizedBox(height: AppSpacing.xs),
          OutlinedButton.icon(
            onPressed: () => _confirmDelete(context, current),
            icon: Icon(Icons.delete_outline_rounded, color: colorScheme.error),
            label: Text(
              'Delete expense',
              style: TextStyle(color: colorScheme.error),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: colorScheme.error.withValues(alpha: 0.4)),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, Expense expense) {
    final provider = context.read<TransactionProvider>();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete expense?'),
        content: Text('Remove "${expense.description}" from your records?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await provider.deleteTransaction(expense.id);
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              if (!context.mounted) return;
              Navigator.pop(context);
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

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
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
                Text(value, style: textTheme.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
