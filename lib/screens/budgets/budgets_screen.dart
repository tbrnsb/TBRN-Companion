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
  /// The primary control. A limit belongs to a period, so the period decides
  /// which limit you are looking at and which spending it is measured against;
  /// it is not a filter over a list of every category at once.
  BudgetPeriod _period = BudgetPeriod.month;

  /// The secondary control, and the ONLY category control on this screen.
  ///
  /// One budget is judged at a time because a limit is a question about one
  /// category — "am I near my food limit" — and nine rows of bars answering nine
  /// questions at once makes the one that matters impossible to find. The earlier
  /// version listed every category with a bar and no way to tell which was the
  /// subject, which is a dashboard, not a budget.
  ExpenseCategory _category = ExpenseCategory.food;

  /// Whether the trip budgets are open. Closed by default: they are secondary,
  /// and a list of trips above the fold pushes the primary reading off it.
  bool _tripsOpen = false;

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
          // THE PRIMARY CONTROL. Full width, above the fold, with the range it
          // resolves to underneath so "This week" is never a label the user has
          // to interpret. The range comes from [BudgetPeriodX.window] and is not
          // recomputed here: a second window implementation is a second answer
          // to "which days is this".
          SegmentedButton<BudgetPeriod>(
            key: const ValueKey('budget-period-control'),
            segments: [
              for (final period in BudgetPeriod.values)
                ButtonSegment<BudgetPeriod>(
                  value: period,
                  label: Text(period.shortLabel),
                ),
            ],
            selected: {_period},
            onSelectionChanged: (selection) {
              // Change the period, not the category: the category was the
              // subject and the period is the lens. Keeping the selection means
              // switching month to week re-reads the SAME food budget, which is
              // the comparison a user makes.
              setState(() => _period = selection.first);
            },
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _rangeLabel(window.start, window.end, _period),
            key: const ValueKey('budget-range-label'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // THE ONE SECONDARY SELECTOR. A dropdown, not chips AND not a list of
          // every category: two category controls is one too many, and a chip
          // row for ~18 categories wraps to three lines and buries the reading.
          DropdownButtonFormField<ExpenseCategory>(
            key: const ValueKey('budget-category-select'),
            initialValue: _category,
            decoration: InputDecoration(
              labelText: 'Category',
              prefixIcon: Icon(
                CategoryRegistry.metaFor(_category).icon,
                size: 18,
              ),
            ),
            items: [
              for (final category in budgetableCategories())
                DropdownMenuItem<ExpenseCategory>(
                  value: category,
                  child: Text(CategoryRegistry.metaFor(category).name),
                ),
            ],
            onChanged: (category) {
              if (category == null) return;
              setState(() => _category = category);
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          _CategoryBudget(
            index: index,
            period: _period,
            category: _category,
            currencySymbol: currency,
          ),
          const SizedBox(height: AppSpacing.sm),
          // The total stays, because it is the context for the one reading above
          // it: a food limit of 2000 means little without knowing the month total.
          Text(
            '${AppFormat.money(index.total, symbol: currency)} spent in total',
            key: const ValueKey('budget-total-line'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Trips stay REACHABLE and period-aware, but secondary: behind a
          // disclosure, because a trip's costs are the trip's and they never sum
          // into a category reading.
          _TripsDisclosure(
            open: _tripsOpen,
            onToggle: () => setState(() => _tripsOpen = !_tripsOpen),
          ),
          if (_tripsOpen) ...[
            const SizedBox(height: AppSpacing.sm),
            _JourneyBudgets(
              index: index,
              period: _period,
              journeyLabels: journeyLabels,
              currencySymbol: currency,
            ),
          ],
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

/// One app-level category budget: the subject of the screen.
///
/// A single reading rather than a list of every category, and it takes the
/// PERIOD's own limit for that category, so switching week/month/year re-reads
/// the same subject through a different lens instead of silently showing another
/// category's number.
class _CategoryBudget extends StatelessWidget {
  const _CategoryBudget({
    required this.index,
    required this.period,
    required this.category,
    required this.currencySymbol,
  });

  final BudgetSpendIndex index;
  final BudgetPeriod period;
  final ExpenseCategory category;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final budgets = context.watch<BudgetProvider>();
    final meta = CategoryRegistry.metaFor(category);
    final key = BudgetKey.forCategory(category.name, period).raw;

    return _BudgetRow(
      storageKey: key,
      icon: meta.icon,
      colour: meta.color,
      title: meta.name,
      limit: budgets.limitFor(label: category.name, period: period),
      hasLimit: budgets.hasLimit(label: category.name, period: period),
      spent: index.forCategory(category),
      period: period,
      currencySymbol: currencySymbol,
      onChanged: (amount) async {
        await budgets.setLimit(
          label: category.name,
          amount: amount,
          period: period,
        );
      },
    );
  }
}

/// Trips, collapsed.
///
/// A disclosure rather than a section, so the primary reading stays above the
/// fold. It carries the count so a collapsed section is not indistinguishable
/// from an empty one.
class _TripsDisclosure extends StatelessWidget {
  const _TripsDisclosure({required this.open, required this.onToggle});

  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final journeys = context.watch<JourneyProvider>();
    final theme = Theme.of(context);
    final count = journeys.journeys.length;

    return AppSurface(
      tier: AppSurfaceTier.flat,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      child: Row(
        children: [
          Icon(
            Icons.luggage_rounded,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              count == 0 ? 'Trip budgets' : 'Trip budgets ($count)',
              style: theme.textTheme.titleSmall,
            ),
          ),
          IconButton(
            key: const ValueKey('budget-trips-toggle'),
            tooltip: open ? 'Hide trip budgets' : 'Show trip budgets',
            onPressed: onToggle,
            icon: Icon(
              open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            ),
          ),
        ],
      ),
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
            storageKey: BudgetKey.forJourney(journey.id, period).raw,
            icon: Icons.luggage_rounded,
            colour: Theme.of(context).colorScheme.primary,
            title: journey.title,
            limit: budgets.limitFor(
              scope: journey.id,
              label: journey.id,
              period: period,
            ),
            hasLimit: budgets.hasLimit(
              scope: journey.id,
              label: journey.id,
              period: period,
            ),
            spent: index.forJourney(journey.id),
            period: period,
            currencySymbol: currencySymbol,
            onChanged: (amount) async {
              await budgets.setLimit(
                scope: journey.id,
                label: journey.id,
                amount: amount,
                period: period,
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
