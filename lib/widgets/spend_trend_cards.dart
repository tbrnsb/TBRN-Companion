import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:daily_companion/theme/app_theme.dart';
import 'package:daily_companion/utils/format.dart';

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
      // FILL THE PAGER'S BOX, which is what stops the plot running into the
      // heading.
      //
      // These two lines fought each other, and the fight is what put bars
      // through the words on the device.
      //
      // `min` was here to centre a short page in the shared box: a Column given
      // a TIGHT height and MainAxisSize.max fills it and leaves all the slack in
      // one band under the last element, which is what made every chart read as
      // sitting too high. But `min` is wrong for a page whose plot is
      // `Expanded`, and with it in place ChartPager's `Center` was centring a
      // child TALLER than its own box -- which splits the excess above and
      // below. The top of a page is its heading, so the plot's overflow went
      // upwards, straight through "In and out, by day".
      //
      // Filling the box makes the page exactly the height of its slot, so
      // `Center` has nothing to do and cannot push anything anywhere. The plot
      // is the flexible child, so it absorbs slack AND shortage: a short page
      // grows its plot into the space, a long one shrinks it.
      mainAxisSize: MainAxisSize.max,
      children: [
        Text('In and out, by day', style: textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xxs),
        // A Wrap, not a Row. Two keys and a "peak Rs. 5,150" on one line is
        // about 250 pixels at the normal font and rather more at a large one, and
        // a `Row` with a `Spacer` cannot wrap: it overflowed the card sideways at
        // a 2x system font. A Wrap lets the scale fall to its own line, which is
        // also a better place for it -- it is a caption, not a third key.
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _Key(color: colorScheme.primary, label: 'In'),
            _Key(color: colorScheme.tertiary, label: 'Out'),
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
        // THE PLOT TAKES WHAT IS LEFT, not a fixed 180.
        //
        // A fixed height is a page that is only correct at one font size. The
        // title and the key row above it grow with the system text scale, and
        // once they pass 280 the `Column` -- which is given a TIGHT height by the
        // pager's viewport -- is clamped, and the plot is painted straight over
        // the heading. The device showed exactly that: "In and out, by day" with
        // the bars drawn through it, at a larger system font.
        //
        // `Expanded` is safe because a page is only ever used inside the pager,
        // which bounds it. It would throw in a scroll view, and a test that
        // pumps one has to say so.
        Expanded(
          child: ClipRect(
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
                      //
                      // WIDE ENOUGH TO SEE. At 2 the seam was under a pixel once
                      // the phone's text scale and the card's padding were applied,
                      // so the pair read as one solid block and there was no way to
                      // see that two series were being drawn at all.
                      barsSpace: _groupBarGap,
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
      // A highlighted bar is nudged toward the ink so it reads as "the one you
      // picked" against its own neighbours.
      //
      // NUDGED BY HOW MUCH IT NEEDS, not by a fixed 0.35. That constant was a
      // different problem from the pager dots': this is not an alpha over a
      // surface but a whole different colour, so a percentage either moved the
      // bar too far toward the ink or not far enough, depending on the category's
      // own luminance. Measured against the card it is drawn on, and moved the
      // minimum amount that clears 3:1.
      color: highlighted
          ? _nudgeTowardInk(
              color,
              Theme.of(context).colorScheme.onSurface,
              Theme.of(context).colorScheme.surface,
            )
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
      // FILL THE PAGER'S BOX, which is what stops the plot running into the
      // heading.
      //
      // These two lines fought each other, and the fight is what put bars
      // through the words on the device.
      //
      // `min` was here to centre a short page in the shared box: a Column given
      // a TIGHT height and MainAxisSize.max fills it and leaves all the slack in
      // one band under the last element, which is what made every chart read as
      // sitting too high. But `min` is wrong for a page whose plot is
      // `Expanded`, and with it in place ChartPager's `Center` was centring a
      // child TALLER than its own box -- which splits the excess above and
      // below. The top of a page is its heading, so the plot's overflow went
      // upwards, straight through "In and out, by day".
      //
      // Filling the box makes the page exactly the height of its slot, so
      // `Center` has nothing to do and cannot push anything anywhere. The plot
      // is the flexible child, so it absorbs slack AND shortage: a short page
      // grows its plot into the space, a long one shrinks it.
      mainAxisSize: MainAxisSize.max,
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
        Expanded(
          child: ClipRect(
            child: LineChart(
              LineChartData(
                minY: minY,
                maxY: maxY,
                // A DAY EITHER SIDE, so the first and last points are not ON the
                // plot's edges.
                //
                // With one recorded day there is a single spot, and an unset
                // minX/maxX makes that spot the entire domain -- so it was drawn
                // hard against the left edge and clipped in half, with its date
                // label sitting to the right of it rather than under it. Half a
                // day of air on each end puts the point where a point belongs, and
                // leaves room for the end labels inside the box.
                minX: running.length == 1 ? -0.5 : 0,
                maxX: running.length == 1
                    ? 0.5
                    : (running.length - 1).toDouble(),
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
                      // Half a step for a single point, so the axis has a stop at
                      // exactly zero in the middle of the half-day of air this
                      // one point is given.
                      //
                      // THE DEVICE SHOWED "2/10  2/10  2/10". With one spot and no
                      // minX/maxX it used to be drawn hard against the left edge
                      // and clipped, so the axis was given -0.5 to 0.5 to move it
                      // off the edge -- and then every stop on that axis is
                      // fractional. `value.toInt()` TRUNCATES towards zero, so
                      // -0.5, 0.0 and 0.5 all became index 0, all three passed
                      // "is this the first point?", and the same date was drawn
                      // three times under one dot. The extra stops are the fix:
                      // with a half-step there is a real 0.0 in the middle, and
                      // only that one is a data point.
                      interval: running.length == 1 ? 0.5 : 1,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (running.length == 1) {
                          // Only the middle stop is a data point. The two either
                          // side of it are the padding, and labelling padding
                          // would put a date under a day nothing happened.
                          if (value.abs() > 0.001) {
                            return const SizedBox.shrink();
                          }
                        } else if (index != 0 && index != running.length - 1) {
                          // First and last only.
                          return const SizedBox.shrink();
                        }
                        final isFirst = index == 0;
                        // FITTED INSIDE THE PLOT, not merely text-aligned.
                        //
                        // These two labels sit ON the first and last data points,
                        // which are hard against the chart's edges, and fl_chart
                        // centres a title widget on its axis value. A centred
                        // "2/10" at x = 0 is therefore half outside the plot and
                        // the device showed it as a bare "10" floating at the left
                        // edge with no line attached. `textAlign` cannot fix that,
                        // because the clipping happens OUTSIDE the Text — it is the
                        // parent that cuts it. `fitInside` is the API that moves
                        // the label back within the axis box.
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          space: AppSpacing.xxs,
                          fitInside: SideTitleFitInsideData.fromTitleMeta(
                            meta,
                            enabled: true,
                          ),
                          child: Text(
                            '${days[index].date.day}/${days[index].date.month}',
                            textAlign: isFirst
                                ? TextAlign.left
                                : TextAlign.right,
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
                    // NOT CURVED when there is nothing to curve between.
                    //
                    // A curve is an interpolation: it needs at least three points
                    // to have anything to say. On a freshly seeded month — one
                    // recorded day — the line had a single spot, and fl_chart
                    // built a degenerate path that painted NOTHING. The page came
                    // up as a title, a sentence and an empty box, and every widget
                    // finder still passed, because the chart was in the tree; it
                    // simply drew no line. Two points are drawn straight, which is
                    // the truth for a straight line anyway.
                    isCurved: running.length > 2,
                    // Gentle, not bouncy. A curve that overshoots would claim
                    // values the data never reached.
                    curveSmoothness: 0.18,
                    preventCurveOverShooting: true,
                    barWidth: 2.5,
                    color: colorScheme.primary,
                    // A dot stands in for the line when there is no line to draw.
                    //
                    // Without it, one or two recorded days produce a chart with
                    // literally no mark on it — the one case where the user most
                    // needs to see that their balance exists and where it stands.
                    dotData: FlDotData(
                      show: running.length < 3,
                      getDotPainter: (spot, percent, bar, index) =>
                          FlDotCirclePainter(
                            radius: 4,
                            color: colorScheme.primary,
                            strokeWidth: 0,
                          ),
                    ),
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
      // FILL THE PAGER'S BOX, which is what stops the plot running into the
      // heading.
      //
      // These two lines fought each other, and the fight is what put bars
      // through the words on the device.
      //
      // `min` was here to centre a short page in the shared box: a Column given
      // a TIGHT height and MainAxisSize.max fills it and leaves all the slack in
      // one band under the last element, which is what made every chart read as
      // sitting too high. But `min` is wrong for a page whose plot is
      // `Expanded`, and with it in place ChartPager's `Center` was centring a
      // child TALLER than its own box -- which splits the excess above and
      // below. The top of a page is its heading, so the plot's overflow went
      // upwards, straight through "In and out, by day".
      //
      // Filling the box makes the page exactly the height of its slot, so
      // `Center` has nothing to do and cannot push anything anywhere. The plot
      // is the flexible child, so it absorbs slack AND shortage: a short page
      // grows its plot into the space, a long one shrinks it.
      mainAxisSize: MainAxisSize.max,
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
        // Flexible for the same reason as the daily chart, and it matters MORE
        // here: this page carries two paragraphs -- the comparison above the plot
        // and the "daily average" note below it -- so it is the first of the
        // four to run out of room when the text grows.
        Expanded(
          child: ClipRect(
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
                      barsSpace: _groupBarGap,
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

/// The clear space between the two rods of one bar group, in logical pixels.
///
/// The In and Out rods of a day have to read as TWO series. Below about 3 the
/// seam disappears at phone text scales and the group looks like a single bar,
/// which is worse than no gap at all: it looks like one series when it is two.
const double _groupBarGap = 5;

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

/// [colour] moved toward [ink] by the least amount that clears 3:1 on [surface].
///
/// Returns [colour] unchanged when it already clears, which is the common case.
/// The direction is chosen by comparing luminance rather than by brightness,
/// because a bar can be pale or dark on a pale or dark card and only one of the
/// two directions helps.
Color _nudgeTowardInk(Color colour, Color ink, Color surface) {
  const floor = 3.0;
  if (_ratio(colour, surface) >= floor) return colour;

  final goLighter = _luminance(ink) > _luminance(colour);
  var candidate = colour;
  for (var i = 1; i <= 50; i++) {
    candidate = Color.lerp(candidate, ink, 0.04)!;
    if (_ratio(candidate, surface) >= floor) return candidate;
  }
  return goLighter ? ink : colour;
}

double _ratio(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

double _luminance(Color c) => c.computeLuminance();
