import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/budget_provider.dart';
import 'package:flutter_application_1/providers/journey_provider.dart';
import 'package:flutter_application_1/providers/settings_provider.dart';
import 'package:flutter_application_1/providers/transaction_provider.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/utils/format.dart';
import 'package:flutter_application_1/widgets/widgets.dart';

/// Budgets, in two scopes that never mix: an app-level limit per expense
/// category, and one optional limit per trip.
///
/// Every figure on this screen comes from [TransactionProvider.spendIndex]. The
/// screen holds no totals of its own, so adding an expense moves the bar and
/// nothing has to be recomputed here.
class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  BudgetPeriod _period = BudgetPeriod.month;

  /// Which budgets have already raised a notification.
  ///
  /// Held here rather than in the provider because only the screen can see that
  /// a notification has gone out, and re-notifying on every rebuild would make
  /// the app nag the same overspend every time the user scrolled.
  @override
  Widget build(BuildContext context) {
    final transactions = context.watch<TransactionProvider>();
    final journeys = context.watch<JourneyProvider>();
    final currency = context.select<SettingsProvider, String>(
      (s) => s.currency.symbol,
    );
    final theme = Theme.of(context);

    final index = transactions.spendIndex(period: _period);
    final journeyLabels = {
      for (final journey in journeys.journeys) journey.id: journey.title,
    };

    // Anchored on the month being browsed, not the wall clock: browsing to March
    // should judge March's limit against March's spending.
    final anchor = transactions.currentMonth ?? DateTime.now();
    final window = _period.window(DateTime(anchor.year, anchor.month));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Budgets'),
        actions: const [AppGearButton()],
      ),
      body: ListView(
        padding: AppSpacing.screenPadding,
        children: [
          Text('Period', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            children: [
              for (final period in BudgetPeriod.values)
                ChoiceChip(
                  key: ValueKey('budget-period-${period.name}'),
                  label: Text(period.shortLabel),
                  selected: _period == period,
                  onSelected: (_) => setState(() => _period = period),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${_rangeLabel(window.start, window.end, _period)} · '
            '${AppFormat.money(index.total, symbol: currency)} spent in total',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader('By category'),
          const SizedBox(height: AppSpacing.xs),
          _CategoryBudgets(
            index: index,
            period: _period,
            currencySymbol: currency,
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader('By trip'),
          const SizedBox(height: AppSpacing.xs),
          _JourneyBudgets(
            index: index,
            period: _period,
            journeyLabels: journeyLabels,
            currencySymbol: currency,
          ),
        ],
      ),
    );
  }

  String _rangeLabel(DateTime start, DateTime end, BudgetPeriod period) {
    final lastDay = end.subtract(const Duration(days: 1));
    return switch (period) {
      BudgetPeriod.month => DateFormat.yMMMM().format(start),
      BudgetPeriod.week =>
        '${DateFormat.MMMd().format(start)} – ${DateFormat.MMMd().format(lastDay)}',
      BudgetPeriod.year => DateFormat.y().format(start),
    };
  }
}

/// App-level limits, one per expense category.
class _CategoryBudgets extends StatelessWidget {
  const _CategoryBudgets({
    required this.index,
    required this.period,
    required this.currencySymbol,
  });

  final BudgetSpendIndex index;
  final BudgetPeriod period;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final budgets = context.watch<BudgetProvider>();
    final categories = budgetableCategories();

    return Column(
      children: [
        for (final category in categories)
          Builder(
            // A Builder per row so each row's limit can be its own Consumer
            // and editing one limit does not rebuild the other nine.
            builder: (context) {
              final meta = CategoryRegistry.metaFor(category);
              return _BudgetRow(
                storageKey: 'cat:${category.name}',
                icon: meta.icon,
                colour: meta.color,
                title: meta.name,
                limit: budgets.limitFor(label: category.name),
                hasLimit: budgets.hasLimit(label: category.name),
                spent: index.forCategory(category),
                period: period,
                currencySymbol: currencySymbol,
                onChanged: (amount) =>
                    budgets.setLimit(label: category.name, amount: amount),
              );
            },
          ),
      ],
    );
  }
}

/// One limit per journey, over the trip's whole cost.
///
/// A separate pool from the category budgets: the trip's expenses are counted
/// here whatever the category, and nowhere against a category limit — except
/// the ones I paid, which are my spending and do count there. Both facts are
/// true at once and the two rows showing them is what makes that visible.
class _JourneyBudgets extends StatelessWidget {
  const _JourneyBudgets({
    required this.index,
    required this.period,
    required this.journeyLabels,
    required this.currencySymbol,
  });

  final BudgetSpendIndex index;
  final BudgetPeriod period;
  final Map<String, String> journeyLabels;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final budgets = context.watch<BudgetProvider>();
    final journeys = context.watch<JourneyProvider>();

    if (journeys.journeys.isEmpty) {
      return const EmptyState(
        icon: Icons.luggage_rounded,
        title: 'No trips yet',
        message: 'A trip gets its own limit here, over its whole cost.',
      );
    }

    return Column(
      children: [
        for (final journey in journeys.journeys)
          _BudgetRow(
            storageKey: 'trip:${journey.id}',
            icon: Icons.luggage_rounded,
            colour: Theme.of(context).colorScheme.primary,
            title: journey.title,
            limit: budgets.limitFor(scope: journey.id, label: journey.id),
            hasLimit: budgets.hasLimit(scope: journey.id, label: journey.id),
            spent: index.forJourney(journey.id),
            period: period,
            currencySymbol: currencySymbol,
            onChanged: (amount) async {
              await budgets.setLimit(
                scope: journey.id,
                label: journey.id,
                amount: amount,
              );
              await budgets.notifyCrossed(
                index: index,
                currencySymbol: currencySymbol,
                journeyLabels: journeyLabels,
              );
            },
          ),
      ],
    );
  }
}

/// One budget: its limit, the bar, the sentence, and the control that sets it.
class _BudgetRow extends StatelessWidget {
  const _BudgetRow({
    required this.storageKey,
    required this.icon,
    required this.colour,
    required this.title,
    required this.limit,
    required this.hasLimit,
    required this.spent,
    required this.period,
    required this.currencySymbol,
    required this.onChanged,
  });

  final String storageKey;
  final IconData icon;
  final Color colour;
  final String title;
  final double? limit;
  final bool hasLimit;
  final double spent;
  final BudgetPeriod period;
  final String currencySymbol;
  final ValueChanged<double?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = BudgetStatus(
      label: title,
      limit: limit,
      spent: spent,
      period: period,
    );

    // Overspend reads as a warning, and the bar's own colour is the message —
    // rather than a red number that has to be noticed. "Close to the limit" is
    // amber and distinct from both, so a bar at 85% never looks like a bar at
    // 120%.
    final barColour = switch ((status.isOverspent, status.isNearLimit)) {
      (true, _) => scheme.error,
      (_, true) => AppColors.warning,
      _ => scheme.primary,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: AppSurface(
        tier: AppSurfaceTier.flat,
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: colour),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Text(
                  hasLimit ? '${percentOf(spent, limit!)}%' : 'No limit',
                  key: ValueKey('budget-percent-$storageKey'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: hasLimit ? scheme.onSurfaceVariant : scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: AppSpacing.xxs),
                IconButton(
                  key: ValueKey('budget-edit-$storageKey'),
                  tooltip: hasLimit ? 'Change limit' : 'Set a limit',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _editLimit(context),
                  icon: const Icon(Icons.tune_rounded, size: 18),
                ),
              ],
            ),
            // The bar is only meaningful against a limit. With no limit there is
            // nothing to be a percentage OF, so showing an empty track would
            // imply a zero budget rather than an absent one.
            if (hasLimit) ...[
              const SizedBox(height: AppSpacing.xxs),
              ClipRRect(
                borderRadius: AppRadii.smallRadius,
                child: LinearProgressIndicator(
                  key: ValueKey('budget-bar-$storageKey'),
                  value: status.progress,
                  minHeight: AppSpacing.xxs + 2,
                  color: barColour,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xxs),
            Text(
              hasLimit
                  ? '${AppFormat.money(spent, symbol: currencySymbol)} spent · '
                        '${status.describe((v) => AppFormat.money(v, symbol: currencySymbol))}'
                  : '${AppFormat.money(spent, symbol: currencySymbol)} spent, no limit set',
              key: ValueKey('budget-caption-$storageKey'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: status.isOverspent
                    ? scheme.error
                    : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editLimit(BuildContext context) async {
    HapticFeedback.selectionClick();
    final result = await showModalBottomSheet<double?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _LimitEditor(
        title: title,
        current: limit,
        currencySymbol: currencySymbol,
        spent: spent,
      ),
    );
    if (result == null) return;
    if (result < 0) {
      // -1 is the editor's "clear" escape, which cannot be a real limit: limits
      // are positive by definition and a negative one would make a progress bar
      // read as overspent before a rupee was spent.
      onChanged(null);
      return;
    }
    onChanged(result);
  }
}

/// Sets or clears one limit.
class _LimitEditor extends StatefulWidget {
  const _LimitEditor({
    required this.title,
    required this.current,
    required this.currencySymbol,
    required this.spent,
  });

  final String title;
  final double? current;
  final String currencySymbol;
  final double spent;

  @override
  State<_LimitEditor> createState() => _LimitEditorState();
}

class _LimitEditorState extends State<_LimitEditor> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.current?.toStringAsFixed(0) ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Limit for ${widget.title}',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'You have spent ${AppFormat.money(widget.spent, symbol: widget.currencySymbol)} '
                'in this period. The period is the reset — there is no button to clear it early, '
                'because a budget you can clear on a bad day stops being a limit.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const ValueKey('limit-editor-field'),
                controller: _controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                decoration: InputDecoration(
                  labelText: 'Limit',
                  hintText: 'No limit',
                  prefixText: widget.currencySymbol,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  if (widget.current != null)
                    Expanded(
                      child: TextButton(
                        key: const ValueKey('limit-editor-clear'),
                        onPressed: () => Navigator.pop(context, -1),
                        child: const Text('Clear'),
                      ),
                    ),
                  if (widget.current != null)
                    const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('limit-editor-save'),
                      onPressed: () {
                        final parsed = double.tryParse(_controller.text.trim());
                        Navigator.pop(context, parsed);
                      },
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
