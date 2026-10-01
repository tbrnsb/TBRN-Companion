import 'package:flutter/material.dart';

import 'package:flutter_application_1/theme/app_chart_colors.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/utils/format.dart';
import 'package:flutter_application_1/widgets/spend_trend_cards.dart'
    show DayTotal;

/// A calendar heatmap: one cell per day, shaded by what was spent.
///
/// Answers the question none of the other charts do — "which days do I actually
/// spend" — because a bar chart of daily totals shows the *shape* of a month
/// while this shows the *texture* of it. A month with three big spikes and a lot
/// of nothing looks completely different here than it does in bars.
///
/// Pure Flutter. No fl_chart: a heatmap is a grid of coloured boxes, and a chart
/// library would add a dependency on axes, tooltips and scaling rules for
/// something that is one `Row` per week.
///
/// Colours come from the ACTIVE theme's surfaces rather than from literals, so
/// it works in every palette including the ones added later, in both
/// brightnesses.
class SpendingHeatmap extends StatelessWidget {
  const SpendingHeatmap({
    super.key,
    required this.days,
    required this.currencySymbol,
    this.highlightedDate,
  });

  final List<DayTotal> days;

  final String currencySymbol;

  /// The day the day-filter is on, outlined so the grid and the filter agree.
  final DateTime? highlightedDate;

  /// Width of a grid cell, before the per-week fit.
  ///
  /// The grid does NOT use this directly: it computes its own from the measure
  /// it is given, so a 360dp phone and a wide window both get cells that fill
  /// the row. This is only the upper bound it will not exceed.
  static const double maxCell = 15;
  static const double _gap = AppSpacing.xxs;

  /// Rows are weekdays, Monday first, matching the grid.
  static const List<String> weekdayInitials = [
    'M',
    'T',
    'W',
    'T',
    'F',
    'S',
    'S',
  ];

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final month = days.first.date.month;
    final year = days.first.date.year;
    final spendByDay = <int, double>{
      for (final day in days) day.date.day: day.expenses,
    };
    final daysInMonth = DateTime(year, month + 1, 0).day;

    // Where the month starts. `weekday` is 1 for Monday, so subtracting one
    // gives Monday-zero, which is what the row layout below expects.
    final firstWeekday = DateTime(year, month, 1).weekday - 1;
    final totalSpend = days.fold<double>(0, (sum, d) => sum + d.expenses);
    final busiest = spendByDay.values.fold<double>(
      0,
      (max, v) => v > max ? v : max,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Which days you spend', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xxs),
        Row(
          children: [
            // Flexible, because the summary grows with the figures in it and a
            // five-figure month pushes it past the legend beside it.
            Flexible(
              child: Text(
                _summary(busiest, totalSpend),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            _Scale(),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        LayoutBuilder(
          builder: (context, constraints) {
            // One row per weekday, seven columns. Sized so the whole grid fits
            // the measure it was given: a fixed cell width overflows a 360dp
            // phone and leaves a gap on a wide one.
            // The same week-column count the weekday labels use, so the letters
            // line up with the columns they name. Fixed per width rather than
            // per month: a 5-week month drawn in 6 columns leaves one empty
            // column, which is how every calendar handles it and reads as a
            // calendar rather than as a gap in the data.
            final weeks = weeksIn(constraints.maxWidth);
            final cell = cellFor(constraints.maxWidth, weeks);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var weekday = 0; weekday < 7; weekday++)
                  Padding(
                    padding: EdgeInsets.only(bottom: weekday == 6 ? 0 : _gap),
                    child: Row(
                      children: [
                        for (var week = 0; week < weeks; week++)
                          Padding(
                            padding: EdgeInsets.only(
                              right: week == weeks - 1 ? 0 : _gap,
                            ),
                            child: _Cell(
                              size: cell,
                              dayNumber: _dayAt(
                                weekday: weekday,
                                week: week,
                                firstWeekday: firstWeekday,
                                daysInMonth: daysInMonth,
                              ),
                              amount: spendByDay,
                              busiest: busiest,
                              isHighlighted: _isHighlighted(weekday, week),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  bool _isHighlighted(int weekday, int week) {
    final target = highlightedDate;
    if (target == null) return false;
    final dayNumber = _dayAt(
      weekday: weekday,
      week: week,
      firstWeekday: _firstWeekdayOf(days),
      daysInMonth: _daysInMonthOf(days),
    );
    return target.day == dayNumber && target.month == days.first.date.month;
  }

  /// "Rs 4,200 on your heaviest day" — the one fact a grid cannot show.
  String _summary(double busiest, double total) {
    if (busiest <= 0) return 'Nothing spent this month';
    return 'Heaviest day ${AppFormat.money(busiest, symbol: currencySymbol)} · '
        '${AppFormat.money(total, symbol: currencySymbol)} total';
  }

  static int _dayAt({
    required int weekday,
    required int week,
    required int firstWeekday,
    required int daysInMonth,
  }) {
    final day = week * 7 + weekday - firstWeekday + 1;
    if (day < 1 || day > daysInMonth) return 0;
    return day;
  }

  static int _firstWeekdayOf(List<DayTotal> days) =>
      DateTime(days.first.date.year, days.first.date.month, 1).weekday - 1;

  static int _daysInMonthOf(List<DayTotal> days) =>
      DateTime(days.first.date.year, days.first.date.month + 1, 0).day;

  /// How many week-columns the grid draws at [width].
  ///
  /// Fixed per width, not per month, so the weekday labels line up with the
  /// columns they name and a 5-week month just leaves the last column empty.
  static int weeksIn(double width) => width >= 520 ? 6 : 5;

  /// The cell size that fits [width] for a month of [weeks] weeks.
  ///
  /// Divides by the number of columns AND takes off the gaps. Forgetting the
  /// divide is not a subtle bug: it hands back the whole run's width as the
  /// width of one cell, so on a narrow measure every cell would be enormous.
  static double cellFor(double width, int weeks) {
    if (weeks <= 0 || width <= 0) return maxCell;
    final available = (width - (weeks - 1) * _gap) / weeks;
    if (available <= 0) return maxCell;
    return available < maxCell ? available : maxCell;
  }
}

/// One day. Empty days are still drawn, in the recessed surface, because a
/// calendar with gaps in it is not a calendar.
class _Cell extends StatelessWidget {
  const _Cell({
    required this.size,
    required this.dayNumber,
    required this.amount,
    required this.busiest,
    required this.isHighlighted,
  });

  final double size;
  final int dayNumber;

  /// Day-of-month to what was spent.
  final Map<int, double> amount;
  final double busiest;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (dayNumber == 0) {
      // A cell OUTSIDE the month. Dead space, and deliberately a different colour
      // from an empty day: a calendar with gaps in it is still a calendar, but a
      // grid whose padding reads as a quiet week is a chart lying about its shape.
      return SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          key: ValueKey('heat-dead-cell'),
          decoration: BoxDecoration(
            color: AppChartColors.heatmapDead(scheme),
            borderRadius: BorderRadius.circular(AppSpacing.xxs),
          ),
        ),
      );
    }

    final spent = amount[dayNumber] ?? 0;
    final intensity = busiest <= 0 ? 0.0 : (spent / busiest).clamp(0.0, 1.0);

    return Tooltip(
      message: spent == 0
          ? 'Nothing spent'
          : 'Day $dayNumber · ${spent.toStringAsFixed(0)}',
      child: Container(
        // A key per day, because a Tooltip's message is not a usable handle:
        // it differs for a day with no spending, so counting by message counts
        // only the busy days.
        key: ValueKey('heat-cell-$dayNumber'),
        width: size,
        height: size,
        decoration: BoxDecoration(
          // The SPEND ramp from AppChartColors, and the empty-cell token for a
          // day with nothing on it. Not a tint of `primary`: more spending
          // ramping toward the primary reads as SELECTED rather than as cost.
          color: AppChartColors.spendStep(scheme, intensity),
          borderRadius: BorderRadius.circular(AppSpacing.xxs),
          border: isHighlighted
              ? Border.all(color: scheme.tertiary, width: 2)
              : null,
        ),
      ),
    );
  }
}

/// "less" and "more", so the shading has a legend.
class _Scale extends StatelessWidget {
  const _Scale();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'less',
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        for (var i = 0; i < 5; i++)
          Padding(
            padding: EdgeInsets.only(right: i == 4 ? 0 : 2),
            child: Container(
              width: SpendingHeatmapShim.cell,
              height: SpendingHeatmapShim.cell,
              decoration: BoxDecoration(
                // Same ramp as the grid, or the legend lies about it.
                // Same tokens as the grid, or the legend lies about it: the
                // empty cell and the ramp steps both come from AppChartColors.
                color: i == 0
                    ? AppChartColors.heatmapEmpty(scheme)
                    : AppChartColors.spendStep(scheme, i / 4),
                borderRadius: BorderRadius.circular(AppSpacing.xxs),
              ),
            ),
          ),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          'more',
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Shared cell size, so the legend swatches match the grid cells exactly.
class SpendingHeatmapShim {
  SpendingHeatmapShim._();
  static const double cell = 11;
}
