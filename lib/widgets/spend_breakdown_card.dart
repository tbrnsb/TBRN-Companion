import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:flutter_application_1/models/expense_category_meta.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/utils/format.dart';

/// One slice of a [SpendBreakdownCard].
class BreakdownSegment {
  const BreakdownSegment({required this.meta, required this.amount});

  final CategoryMeta meta;
  final double amount;
}

/// Donut chart plus legend for one transaction type's category breakdown.
///
/// Expenses and income use the same widget but are fed different segments, so
/// an expense breakdown never shows income categories and vice versa. A type
/// with nothing recorded renders nothing rather than an empty donut.
class SpendBreakdownCard extends StatelessWidget {
  const SpendBreakdownCard({
    super.key,
    required this.title,
    required this.segments,
    required this.currencySymbol,
  });

  /// Narrowest measure at which the donut and the legend still sit side by
  /// side. Below this the legend gets too little width for a formatted amount
  /// such as "€ 1,234.50" and the row is stacked instead.
  ///
  /// The old layout was an unconditional 132px donut plus an Expanded legend.
  /// At 360dp that left the legend roughly 148dp, which is not enough for a
  /// long amount, so the two collided. A fixed guess is wrong because the card
  /// is used in a padded list; [LayoutBuilder] measures the real constraint.
  static const double sideBySideBreakpoint = 400;

  /// The donut is square, so its edge sets the height of the side-by-side row.
  static const double _donutSize = 132;

  final String title;
  final List<BreakdownSegment> segments;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    // The provider already drops non-positive totals, but fl_chart cannot lay
    // out a NaN or infinite slice, so the card refuses to draw them.
    final drawable = segments
        .where((s) => s.amount.isFinite && s.amount > 0)
        .toList(growable: false);
    if (drawable.isEmpty) return const SizedBox.shrink();

    final total = drawable.fold<double>(0, (sum, s) => sum + s.amount);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.md),
            LayoutBuilder(
              builder: (context, constraints) {
                final legend = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Every segment gets a row. There are only six categories
                    // per type, and truncating the list here would leave a
                    // donut slice the user cannot identify.
                    for (final segment in drawable)
                      _LegendRow(
                        meta: segment.meta,
                        amount: segment.amount,
                        total: total,
                        currencySymbol: currencySymbol,
                      ),
                  ],
                );

                if (constraints.maxWidth >= sideBySideBreakpoint) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        height: _donutSize,
                        width: _donutSize,
                        child: _Donut(drawable: drawable),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: legend),
                    ],
                  );
                }

                // Narrow: the donut goes above and the legend gets the whole
                // measure, so an amount is never truncated to fit beside it.
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: SizedBox(
                        height: _donutSize,
                        width: _donutSize,
                        child: _Donut(drawable: drawable),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    legend,
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Donut extends StatelessWidget {
  const _Donut({required this.drawable});

  final List<BreakdownSegment> drawable;

  @override
  Widget build(BuildContext context) {
    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 38,
        startDegreeOffset: -90,
        pieTouchData: PieTouchData(enabled: false),
        sections: [
          for (final segment in drawable)
            PieChartSectionData(
              value: segment.amount,
              color: segment.meta.color,
              radius: 20,
              showTitle: false,
            ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.meta,
    required this.amount,
    required this.total,
    required this.currencySymbol,
  });

  final CategoryMeta meta;
  final double amount;
  final double total;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final percent = total == 0 ? 0 : (amount / total * 100);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: meta.color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              meta.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          // Both figures are Flexible so a long amount shrinks the label
          // rather than overflowing the row. The amount keeps its width
          // first, because it is the number the user is here for.
          Flexible(
            child: Text(
              '${percent.toStringAsFixed(0)}%',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              AppFormat.money(amount, symbol: currencySymbol),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
