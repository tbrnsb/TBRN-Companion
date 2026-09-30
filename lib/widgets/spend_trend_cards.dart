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
  });

  final List<DayTotal> days;
  final String currencySymbol;

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
              gridData: const FlGridData(show: false),
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
                        _rod(context, days[i].income, colorScheme.primary),
                      if (days[i].expenses > 0)
                        _rod(context, days[i].expenses, colorScheme.tertiary),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  BarChartRodData _rod(BuildContext context, double value, Color color) {
    return BarChartRodData(
      toY: value,
      width: 7,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
      color: color,
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
              titlesData: const FlTitlesData(show: false),
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
