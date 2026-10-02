import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:daily_companion/theme/app_theme.dart';

import 'add_expense_sheet.dart';
import 'income_detail_screen.dart';

/// The single entry point for recording a transaction.
///
/// The user has to pick a direction first, because expenses and income are
/// different records with different fields: an expense carries a category, a
/// place, a journey and a checkpoint flow, while income carries a centralised
/// [IncomeCategory] and nothing else. Presenting one blank form for both meant
/// income could not be created from the UI at all.
///
/// Callers should use this rather than reaching for [AddExpenseSheet] or
/// [IncomeEditSheet] directly, so the choice stays explicit.
class AddTransactionSheet {
  const AddTransactionSheet._();

  /// Shows the Expense / Income chooser, then opens the sheet for the choice.
  ///
  /// [initialJourneyId] is applied to a new expense; income has no journey
  /// field, so it is ignored on that path.
  static Future<void> show(BuildContext context, {String? initialJourneyId}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _AddTransactionChooser(
        onExpenseSelected: () {
          Navigator.of(sheetContext).pop();
          AddExpenseSheet.show(context, initialJourneyId: initialJourneyId);
        },
        onIncomeSelected: () {
          Navigator.of(sheetContext).pop();
          IncomeEditSheet.show(context: context);
        },
      ),
    );
  }
}

class _AddTransactionChooser extends StatelessWidget {
  const _AddTransactionChooser({
    required this.onExpenseSelected,
    required this.onIncomeSelected,
  });

  final VoidCallback onExpenseSelected;
  final VoidCallback onIncomeSelected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add transaction',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Money out or money in?',
              style: textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _TypeOption(
              icon: Icons.trending_down_rounded,
              label: 'Expense',
              description: 'Food, travel, gear and other spending',
              onTap: onExpenseSelected,
            ),
            const SizedBox(height: AppSpacing.sm),
            _TypeOption(
              icon: Icons.trending_up_rounded,
              label: 'Income',
              description: 'Salary, freelance, investment and other earnings',
              onTap: onIncomeSelected,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Amounts are stored as entered and shown with the currency '
              'from Settings.',
              style: textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeOption extends StatelessWidget {
  const _TypeOption({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      label: 'Add $label. $description',
      child: Material(
        color: colorScheme.surface,
        borderRadius: AppRadii.smallRadius,
        child: InkWell(
          borderRadius: AppRadii.smallRadius,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: AppRadii.smallRadius,
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: AppRadii.smallRadius,
                    ),
                    child: Icon(icon, size: 22, color: colorScheme.onSurface),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          description,
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
