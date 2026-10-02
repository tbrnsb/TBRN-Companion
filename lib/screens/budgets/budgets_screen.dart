import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/providers/budget_provider.dart';
import 'package:daily_companion/providers/journey_provider.dart';
import 'package:daily_companion/providers/settings_provider.dart';
import 'package:daily_companion/providers/transaction_provider.dart';
import 'package:daily_companion/theme/app_theme.dart';
import 'package:daily_companion/utils/format.dart';
import 'package:daily_companion/widgets/widgets.dart';

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

/// The ids of the built-in expense categories.
///
/// "Is this the user's own category?" has to have ONE answer in this file. The
/// list and the row's subtitle each decided it separately and disagreed, so a
/// Coffee budget appeared in the picker and then described itself as a stock
/// category.
///
/// NOT a `custom:` prefix test: a name the user happens to match to one the app
/// suggests is stored as `suggested:<name>`, so a prefix check silently treated
/// the user's own category as a built-in one.
Set<String> get _builtInCategoryIds => {
  for (final category in budgetableCategories())
    CategoryRegistry.metaFor(category).id,
};

/// Whether [id] is one of the app's own categories rather than the user's.
bool isBuiltInCategory(String id) => _builtInCategoryIds.contains(id);

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
  ///
  /// Held as a [CategoryMeta.id] rather than an [ExpenseCategory], because a
  /// custom category the user typed into an expense has no enum value at all —
  /// it is `ExpenseCategory.other` plus a name. Keying the control by the enum
  /// made those categories unbudgetable and invisible here.
  ///
  /// [allCategoriesKey] is the default: "All" is the honest first thing to
  /// show, because a cap on total spending in the period is what most people
  /// mean, and it used to be unreachable.
  String _categoryId = allCategoriesKey;

  /// Whether the trip budgets are open. Closed by default: they are secondary,
  /// and a list of trips above the fold pushes the primary reading off it.
  bool _tripsOpen = false;

  /// Which budgets have already raised a notification.
  ///
  /// Held here rather than in the provider because only the screen can see that
  /// a notification has gone out, and re-notifying on every rebuild would make
  /// the app nag the same overspend every time the user scrolled.
  /// The built-in expense categories, in the app's own order.
  List<CategoryMeta> get _builtInMetas => [
    for (final category in budgetableCategories())
      CategoryRegistry.metaFor(category),
  ];

  /// The custom categories worth offering, and where they come from.
  ///
  /// TWO sources, because either alone is wrong:
  ///
  ///  - What has been SPENT in this period, so a category with money in it can
  ///    never be missing from the list. This is the integration the user asked
  ///    for: anything added as a category on an expense appears here.
  ///  - What the user has RECENTLY typed, so a category they use but have not
  ///    spent this period is still reachable. Offered because it was named, not
  ///    because it has a figure, and it will read zero.
  ///
  /// Deduplicated by NAME, not by id — and it has to be. The two sources
  /// disagree about the id for the same category: spending keys it as
  /// `suggested:coffee` because the registry gives a recognised name its own
  /// icon, while the recent-typed list holds the bare name. A set of ids
  /// therefore held BOTH, and the device showed "Coffee" twice in the dropdown —
  /// two entries, two different budgets, one category.
  ///
  /// Sorted by name so the list does not reshuffle as amounts change; a control
  /// that reorders itself under the user's thumb gets tapped by accident.
  List<CategoryMeta> _customMetas(
    BudgetSpendIndex index,
    TransactionProvider transactions,
  ) {
    final byName = <String, String>{};

    // Spending first: a category with money in it is the one that must appear,
    // and its id is the one the figures are already filed under.
    for (final key in index.byCategory.keys) {
      if (isBuiltInCategory(key)) continue;
      final name = CategoryRegistry.metaById(key)?.name;
      if (name == null || name.trim().isEmpty) continue;
      byName.putIfAbsent(name.toLowerCase(), () => key);
    }
    // Then the recent names, only filling gaps.
    for (final raw in transactions.recentCustomCategories) {
      final name = raw.trim();
      if (name.isEmpty || isBuiltInCategory(name)) continue;
      if (byName.containsKey(name.toLowerCase())) continue;
      byName[name.toLowerCase()] = 'custom:${name.toLowerCase()}';
    }

    final metas = <CategoryMeta>[
      for (final id in byName.values) ?CategoryRegistry.metaById(id),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return metas;
  }

  /// Every budgetable category, in the order the dropdown shows them.
  ///
  /// The user's own categories are in the list because a category typed into an
  /// expense has to be budgetable, or the money is real and unaccountable. And
  /// [CategoryRegistry.othersLast] is applied to the COMBINED list, so Other is
  /// last overall rather than merely last among the built-ins.
  List<CategoryMeta> _orderedCategories(
    BudgetSpendIndex index,
    TransactionProvider transactions,
  ) => CategoryRegistry.othersLast([
    ..._builtInMetas,
    ..._customMetas(index, transactions),
  ], isOther: (m) => m.id == CategoryRegistry.otherId);

  /// The meta for a stored category id, including the "all" sentinel.
  ///
  /// Falls back to a neutral "all" meta rather than the last enum entry, so a
  /// limit saved against a category the app no longer offers still READS as
  /// something rather than silently becoming a different category's budget.
  CategoryMeta _metaFor(String id) {
    if (isAllCategories(id)) return _allCategoriesMeta;
    return CategoryRegistry.metaById(id) ?? _allCategoriesMeta;
  }

  static const CategoryMeta _allCategoriesMeta = CategoryMeta(
    id: allCategoriesKey,
    name: 'All categories',
    icon: Icons.pie_chart_outline_rounded,
    color: Color(0xFF8A7A66),
    popularity: 0,
  );

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

          // The label is its OWN line, not a floating `labelText`.
          //
          // A floating label rides the field's border, and with a prefix icon in
          // this decoration the device showed "Category" half-buried under the
          // top edge. A label above the control cannot collide with it at any
          // width, and it reads the same way the period range above does.
          Text(
            'Category',
            style: theme.textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          // THE ONE SECONDARY SELECTOR. A dropdown, not chips AND not a list of
          // every category: two category controls is one too many, and a chip
          // row for ~18 categories wraps to three lines and buries the reading.
          DropdownButtonFormField<String>(
            key: const ValueKey('budget-category-select'),
            initialValue: _categoryId,
            decoration: InputDecoration(
              prefixIcon: Icon(_metaFor(_categoryId).icon, size: 18),
            ),
            items: [
              // "All" first, because a limit on the period's TOTAL is the
              // honest default and a list that starts with Food is not.
              DropdownMenuItem<String>(
                value: allCategoriesKey,
                child: Text('All categories'),
              ),
              // Then ONE list, not two, so `othersLast` can do its job.
              //
              // Built-ins and the user's own categories were appended as separate
              // groups, so the Other bucket -- last of the built-ins -- ended up
              // in the MIDDLE of the whole list with a custom category after it.
              // That is the one row which leads somewhere else rather than naming
              // a thing, and it has to be the last thing in every list.
              for (final meta in _orderedCategories(index, transactions))
                DropdownMenuItem<String>(
                  value: meta.id,
                  child: Text(meta.name),
                ),
            ],
            onChanged: (id) {
              if (id == null) return;
              setState(() => _categoryId = id);
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          _CategoryBudget(
            index: index,
            period: _period,
            categoryId: _categoryId,
            currencySymbol: currency,
            meta: _metaFor(_categoryId),
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
    required this.categoryId,
    required this.currencySymbol,
    required this.meta,
  });

  final BudgetSpendIndex index;
  final BudgetPeriod period;

  /// A [CategoryMeta.id], or [allCategoriesKey].
  final String categoryId;
  final String currencySymbol;

  /// Resolved by the caller, so the dropdown's icon and the row's icon cannot be
  /// two different categories.
  final CategoryMeta meta;

  @override
  Widget build(BuildContext context) {
    final budgets = context.watch<BudgetProvider>();

    // "All" is a limit on the period's TOTAL, not a slice of it — the same
    // number the card above reports, which is what makes it the honest default.
    final all = isAllCategories(categoryId);
    final spent = all ? index.total : index.forCategoryId(categoryId);

    return _BudgetRow(
      storageKey: BudgetKey.forCategory(categoryId, period).raw,
      icon: meta.icon,
      colour: meta.color,
      title: meta.name,
      limit: budgets.limitFor(label: categoryId, period: period),
      hasLimit: budgets.hasLimit(label: categoryId, period: period),
      spent: spent,
      period: period,
      currencySymbol: currencySymbol,
      // "Your own category" for anything that is not a built-in, decided the
      // same way the list decides it. Testing the `custom:` prefix here missed
      // every suggested one, which is the same mistake the list had.
      subtitle: all
          ? 'Everything, every category'
          : !isBuiltInCategory(meta.id)
          ? 'Your own category'
          : null,
      onChanged: (amount) async {
        await budgets.setLimit(
          label: categoryId,
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
    this.subtitle,
  });

  /// An optional line under the title, for the two cases where a budget is not
  /// simply "a category": the all-categories total, and a category the user
  /// invented. Both are worth saying out loud, because neither is a stock one.
  final String? subtitle;

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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          key: const ValueKey('budget-row-subtitle'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
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
