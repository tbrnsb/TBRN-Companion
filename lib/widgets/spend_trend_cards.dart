import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/utils/format.dart';

/// One day's totals, as the charts consume them.
class DayTotal {
  const DayTotal({
    required this.date,
    required this.income,
    required this.expenses,
  });

  final DateTime date;
  final double income;
  final double expenses;

  double get net => income - expenses;
}

/// Money in and money out per day, as bars.
///
/// Only days that have something on them are plotted, and the x axis is
/// labelled by day-of-month rather than evenly spaced, so a run of empty days
/// collapses instead of being drawn as a row of zero-height bars.
class DailyTotalsChart extends StatelessWidget {
  const DailyTotalsChart({
    super.key,
    required this.days,
    required this.currencySymbol,
    this.highlightedDate,
  });

  final List<DayTotal> days;
  final String currencySymbol;

  /// The day the user has filtered to, if any. Marked in the chart so the graph
  /// and the day filter cannot disagree about what is being looked at.
  final DateTime? highlightedDate;

  bool isHighlighted(DateTime date) {
    final target = highlightedDate;
    if (target == null) return false;
    return date.year == target.year &&
        date.month == target.month &&
        date.day == target.day;
  }

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final peak = days.fold<double>(
      0,
      (m, d) => [d.income, d.expenses].reduce((a, b) => a > b ? a : b),
    );
    // Headroom so the tallest bar is not flush against the top of the frame.
    final maxY = peak <= 0 ? 1.0 : peak * 1.15;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('In and out, by day', style: textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xxs),
        Row(
          children: [
            _Key(color: colorScheme.primary, label: 'In'),
            const SizedBox(width: AppSpacing.md),
            _Key(color: colorScheme.tertiary, label: 'Out'),
            const Spacer(),
            // The scale, in words. Without it the bars are decoration: there is
            // nothing to compare a bar's height against.
            Text(
              'peak ${AppFormat.money(peak, symbol: currencySymbol)}',
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          height: 180,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxY,
              barTouchData: BarTouchData(enabled: false),
              // Horizontal rules only; vertical ones would cage every bar.
              //
              // Drawn as exactly three fixed lines rather than by setting
              // `horizontalInterval`. That property makes fl_chart walk the axis
              // in fixed steps, and when the step does not divide the range it
              // generates an unbounded number of lines — the spend screen hung
              // outright on it. Testing three known values cannot do that.
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: null,
                checkToShowHorizontalLine: (value) =>
                    _isAtFractions(value, maxY, const [0.25, 0.5, 0.75]),
                getDrawingHorizontalLine: (_) => FlLine(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 || index >= days.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xxs),
                        child: Text(
                          '${days[index].date.day}',
                          style: textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < days.length; i++)
                  BarChartGroupData(
                    x: i,
                    // Two thin bars per day rather than one, so in and out are
                    // comparable on the same baseline.
                    barsSpace: 2,
                    barRods: [
                      if (days[i].income > 0)
                        _rod(
                          context,
                          days[i].income,
                          colorScheme.primary,
                          highlighted: isHighlighted(days[i].date),
                        ),
                      if (days[i].expenses > 0)
                        _rod(
                          context,
                          days[i].expenses,
                          colorScheme.tertiary,
                          highlighted: isHighlighted(days[i].date),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  BarChartRodData _rod(
    BuildContext context,
    double value,
    Color color, {
    bool highlighted = false,
  }) {
    return BarChartRodData(
      toY: value,
      // Wider for the day the user has selected, so the chart agrees with the
      // day filter above it instead of showing a filtered day at the same
      // weight as every other.
      width: highlighted ? 10 : 7,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
      color: highlighted
          ? Color.lerp(color, Theme.of(context).colorScheme.onSurface, 0.35)
          : color,
      // The value is on the card as text, so repeating it on every bar is
      // noise. Kept for the caller's benefit via the tooltip-free design.
      rodStackItems: const [],
    );
  }
}

/// Running balance across the month.
///
/// Answers a question the daily bars cannot: not "what did I spend on the 9th"
/// but "am I ahead or behind by the end of the month, and since when".
class CumulativeBalanceChart extends StatelessWidget {
  const CumulativeBalanceChart({
    super.key,
    required this.days,
    required this.currencySymbol,
  });

  final List<DayTotal> days;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Walk the days once, accumulating.
    final running = <double>[];
    var total = 0.0;
    for (final day in days) {
      total += day.net;
      running.add(total);
    }

    final lowest = running.reduce((a, b) => a < b ? a : b);
    final highest = running.reduce((a, b) => a > b ? a : b);
    // A flat line at zero still needs a range, or the chart divides by nothing.
    final span = highest - lowest;
    final padding = span == 0 ? 1.0 : span * 0.2;
    final minY = lowest - padding;
    final maxY = highest + padding;

    final endsPositive = running.last >= 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Running balance', style: textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          endsPositive
              ? 'Up ${AppFormat.money(running.last, symbol: currencySymbol)} by the last day recorded'
              : 'Down ${AppFormat.money(running.last.abs(), symbol: currencySymbol)} by the last day recorded',
          style: textTheme.bodySmall?.copyWith(
            color: endsPositive
                ? AppColors.success
                : Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          height: 150,
          child: LineChart(
            LineChartData(
              minY: minY,
              maxY: maxY,
              lineTouchData: const LineTouchData(enabled: false),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              // Only the ends are labelled. Every day would be noise on a
              // phone, but with no dates at all there was nothing to say which
              // stretch of the month the line covered.
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 20,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      // First and last only.
                      if (index != 0 && index != running.length - 1) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xxs),
                        child: Text(
                          '${days[index].date.day}/${days[index].date.month}',
                          style: textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              // The line that matters most on a running balance: zero. Without
              // it, "up Rs 500" and "down Rs 500" are told apart only by the
              // sentence above, and the eye cannot see where the balance
              // crossed over.
              extraLinesData: ExtraLinesData(
                horizontalLines: [
                  HorizontalLine(
                    y: 0,
                    color: colorScheme.outline.withValues(alpha: 0.7),
                    strokeWidth: 1,
                    dashArray: const [4, 4],
                  ),
                ],
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (var i = 0; i < running.length; i++)
                      FlSpot(i.toDouble(), running[i]),
                  ],
                  isCurved: true,
                  // Gentle, not bouncy. A curve that overshoots would claim
                  // values the data never reached.
                  curveSmoothness: 0.18,
                  preventCurveOverShooting: true,
                  barWidth: 2.5,
                  color: colorScheme.primary,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    // Tinted toward whichever direction the month ended in.
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        colorScheme.primary.withValues(alpha: 0.22),
                        colorScheme.primary.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One ISO week of the month, as the weekly chart consumes it.
class WeekTotal {
  const WeekTotal({
    required this.weekStart,
    required this.income,
    required this.expenses,
    required this.dayCount,
  });

  final DateTime weekStart;
  final double income;
  final double expenses;

  /// How many of the month's days fall in this week.
  final int dayCount;

  double get net => income - expenses;
}

/// Spending grouped into weeks, which is how people actually think about it.
///
/// The daily chart answers "what did the 9th cost". It cannot answer "was this
/// week worse than last week", because seven bars in a row are harder to compare
/// than a handful of bars each standing for a week. Grouped, the comparison is
/// the whole point of the chart.
class WeeklyTotalsChart extends StatelessWidget {
  const WeeklyTotalsChart({
    super.key,
    required this.days,
    required this.currencySymbol,
  });

  final List<DayTotal> days;
  final String currencySymbol;

  /// Splits [days] into weeks starting on Monday.
  ///
  /// Keyed by the Monday's date rather than by a day-of-month bucket, so a week
  /// straddling a month boundary cannot be counted twice.
  static List<WeekTotal> groupByWeek(List<DayTotal> days) {
    final weeks = <DateTime, ({double income, double expenses, int days})>{};
    for (final day in days) {
      final monday = DateTime(
        day.date.year,
        day.date.month,
        day.date.day,
      ).subtract(Duration(days: day.date.weekday - 1));
      final existing = weeks[monday];
      weeks[monday] = (
        income: (existing?.income ?? 0) + day.income,
        expenses: (existing?.expenses ?? 0) + day.expenses,
        days: (existing?.days ?? 0) + 1,
      );
    }
    final keys = weeks.keys.toList()..sort();
    return [
      for (final key in keys)
        WeekTotal(
          weekStart: key,
          income: weeks[key]!.income,
          expenses: weeks[key]!.expenses,
          dayCount: weeks[key]!.days,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final weeks = groupByWeek(days);
    if (weeks.isEmpty) return const SizedBox.shrink();

    final peak = weeks.fold<double>(
      0,
      (m, w) => [w.income, w.expenses].reduce((a, b) => a > b ? a : b),
    );
    final maxY = peak <= 0 ? 1.0 : peak * 1.15;

    final heaviest = weeks.reduce((a, b) => b.expenses > a.expenses ? b : a);
    final quietest = weeks.reduce((a, b) => b.expenses < a.expenses ? b : a);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('By week', style: textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xxs),
        // The comparison in words. Seven daily bars do not reliably answer
        // "which week was worst" at a glance; a sentence does.
        Text(
          weeks.length < 2
              ? 'Only one week with anything on it so far.'
              : 'Heaviest week ${AppFormat.money(heaviest.expenses, symbol: currencySymbol)}'
                    ' · quietest ${AppFormat.money(quietest.expenses, symbol: currencySymbol)}',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          height: 150,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxY,
              barTouchData: BarTouchData(enabled: false),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                // Fixed lines, not an interval — see DailyTotalsChart.
                horizontalInterval: null,
                checkToShowHorizontalLine: (value) =>
                    _isAtFractions(value, maxY, const [0.5]),
                getDrawingHorizontalLine: (_) => FlLine(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 || index >= weeks.length) {
                        return const SizedBox.shrink();
                      }
                      final start = weeks[index].weekStart;
                      return Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xxs),
                        child: Text(
                          '${start.day}/${start.month}',
                          style: textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < weeks.length; i++)
                  BarChartGroupData(
                    x: i,
                    barsSpace: 3,
                    // A daily average rather than the raw week total, so the
                    // current part-week is not drawn as a collapse in spending.
                    barRods: [
                      if (weeks[i].income > 0)
                        _rod(
                          weeks[i].income / weeks[i].dayCount,
                          colorScheme.primary,
                        ),
                      if (weeks[i].expenses > 0)
                        _rod(
                          weeks[i].expenses / weeks[i].dayCount,
                          colorScheme.tertiary,
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'Each bar is a daily average, so a part-week is not read as a quiet '
          'week.',
          style: textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  BarChartRodData _rod(double value, Color color) {
    return BarChartRodData(
      toY: value,
      width: 10,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
      color: color,
      rodStackItems: const [],
    );
  }
}

/// Whether [value] sits on one of [fractions] of [max].
///
/// Gridlines are placed by testing a short fixed list of values rather than by
/// telling fl_chart to step by an interval. A step that does not divide the
/// range evenly makes it walk the axis in ever-smaller increments and never
/// finish — which is a hang, not a cosmetic glitch.
bool _isAtFractions(double value, double max, List<double> fractions) {
  for (final fraction in fractions) {
    if ((value - max * fraction).abs() < 0.0001) return true;
  }
  return false;
}

class _Key extends StatelessWidget {
  const _Key({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          label,
          style: textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
