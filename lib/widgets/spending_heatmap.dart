import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
        // The MONTH, derived from the data rather than written down. The card
        // said 'Which days you spend' and nothing else, so a grid of red squares
        // had no month attached to it and could be read as belonging to any.
        Text(
          'Which days you spend · ${DateFormat.yMMMM().format(DateTime(year, month))}',
          style: theme.textTheme.titleSmall,
        ),
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
            _Scale(rampLength: AppChartColors.rampLength(scheme)),
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
            // THE MONTH decides the shape, and the orientation is a calendar's:
            // seven day-columns across, week-rows down.
            final rows = rowsForMonth(year, month);
            final cell = cellFor(constraints.maxWidth);

            return Column(
              // stretch, not start: with `start` each Row sized to its content
              // and the leftover width was DISCARDED, so the grid hugged the
              // left and threw away a third of the card on a wide phone. Cells
              // now grow to fill the measure.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var row = 0; row < rows; row++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: row == rows - 1 ? 0 : _gap,
                    ),
                    child: Row(
                      // spaceBetween, NOT content-sized and NOT Expanded.
                      //
                      // Item 5 used Expanded, so the cells grew to fill the card
                      // and became ~45px squares: the grid was 315px tall and
                      // dominated the screen, which is what forced the pager up to
                      // 640. Cells are FIXED at [SpendingHeatmapShim.cell], the
                      // same constant the legend swatches use, so the two cannot
                      // drift apart.
                      //
                      // spaceBetween is NON-NEGOTIABLE and is the original
                      // left-hug fix: content-sized rows discarded the leftover
                      // width and the grid hugged the left. With fixed cells and
                      // spaceBetween the seven cells still SPAN the full card with
                      // even gutters, and the cell size stays sane.
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (var column = 0; column < columnsPerRow; column++)
                          _Cell(
                            size: cell,
                            dayNumber: _dayAt(
                              row: row,
                              column: column,
                              firstWeekday: firstWeekday,
                              daysInMonth: daysInMonth,
                            ),
                            amount: spendByDay,
                            busiest: busiest,
                            isHighlighted: _isHighlighted(row, column),
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

  bool _isHighlighted(int row, int column) {
    final target = highlightedDate;
    if (target == null) return false;
    final dayNumber = _dayAt(
      row: row,
      column: column,
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

  /// The day-of-month at [row], [column], or 0 when the cell is DEAD.
  ///
  /// Seven day-COLUMNS across and week-ROWS down, so the index runs
  /// `row * 7 + column`. Zero means "not part of this month" and paints
  /// [AppChartColors.heatmapDead] -- the shape of the month is carried entirely
  /// by which cells come back zero.
  static int _dayAt({
    required int row,
    required int column,
    required int firstWeekday,
    required int daysInMonth,
  }) {
    final day = row * 7 + column - firstWeekday + 1;
    if (day < 1 || day > daysInMonth) return 0;
    return day;
  }

  static int _firstWeekdayOf(List<DayTotal> days) =>
      DateTime(days.first.date.year, days.first.date.month, 1).weekday - 1;

  static int _daysInMonthOf(List<DayTotal> days) =>
      DateTime(days.first.date.year, days.first.date.month + 1, 0).day;

  /// DEPRECATED. The grid is transposed: seven day-columns across and 4-6
  /// week-rows down, so the shape comes from [rowsForMonth] and the column count
  /// is the constant [columnsPerRow].
  ///
  /// Kept only so a caller still compiles; it no longer describes anything. Width
  /// must not decide a calendar's shape -- a grid whose shape changes with the
  /// window is a grid that lies about the month.
  static int weeksIn(double width) => columnsPerRow;

  /// The column count a month genuinely needs.
  ///
  ///   columns = ceil((leadingDead + daysInMonth) / 7)
  ///
  /// Where `leadingDead = DateTime(y, m, 1).weekday - 1`, so a month starting on
  /// Sunday has no leading dead cells and one starting on Saturday has six.
  static int columnsForMonth(int year, int month) {
    final leadingDead = DateTime(year, month, 1).weekday - 1;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final total = leadingDead + daysInMonth;
    final columns = (total / 7).ceil();
    // A 28-day February starting on Monday needs 4; anything pathological is
    // clamped to the two real bounds rather than producing a zero- or
    // ten-column grid.
    return columns < 4 ? 4 : (columns > 6 ? 6 : columns);
  }

  /// Dead cells before the first of the month.
  static int leadingDeadForMonth(int year, int month) =>
      DateTime(year, month, 1).weekday - 1;

  /// Dead cells after the last of the month, out to the row boundary.
  static int trailingDeadForMonth(int year, int month, int rows) {
    final leading = leadingDeadForMonth(year, month);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final used = leading + daysInMonth;
    final trailing = rows * columnsPerRow - used;
    return trailing < 0 ? 0 : trailing;
  }

  /// How many day-COLUMNS the grid draws. Always seven, because a week is seven
  /// days and a calendar read left-to-right has the days across.
  ///
  /// This used to be a WEEK count and the grid was five week-columns by seven
  /// weekday rows, which is the transpose of a calendar and reads as a scatter
  /// rather than as a month.
  static const int columnsPerRow = 7;

  /// How many WEEK-ROWS a month needs.
  ///
  ///   rows = ceil((leadingDead + daysInMonth) / 7)
  ///
  /// where `leadingDead = DateTime(y, m, 1).weekday - 1`, so a month starting on
  /// Sunday has no leading dead cells and one starting on Saturday has six.
  ///
  /// Clamped to 4..6: a 4-week month gets 4, and a 6-week month gets 6. Six-week
  /// months are real (November 2026, May 2027) and truncating one loses visible
  /// days, which is the exact bug that got Stage 5 through a green suite.
  static int rowsForMonth(int year, int month) {
    final leading = leadingDeadForMonth(year, month);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final rows = ((leading + daysInMonth) / columnsPerRow).ceil();
    return rows < 4 ? 4 : (rows > 6 ? 6 : rows);
  }

  /// The cell size that fits [width] for a month of [weeks] weeks.
  ///
  /// Divides by the number of columns AND takes off the gaps. Forgetting the
  /// divide is not a subtle bug: it hands back the whole run's width as the
  /// width of one cell, so on a narrow measure every cell would be enormous.
  /// The cell size: FIXED, from the same constant the legend swatches use.
  ///
  /// No width term. The measure is handled by the row's `spaceBetween`, which
  /// spaces fixed cells across it -- so the grid SPANS the card (item 5's
  /// left-hug fix, preserved) while the cells stay small (N1's size fix). Those
  /// two only conflict through `Expanded`, and there is none here.
  ///
  /// [width] is still taken so a degenerate measure is handled rather than handed
  /// to `SizedBox.square` unchecked.
  static double cellFor(double width) =>
      width <= 0 ? SpendingHeatmapShim.cell : SpendingHeatmapShim.cell;
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
      return SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          key: const ValueKey('heat-dead-cell'),
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
      // FIXED square, from the shared cell constant. NOT an AspectRatio: sizing
      // off the measure is exactly what made cells grow to ~45px on a wide card
      // and the grid become 315px of screen. Sized from a constant, the row lays
      // them out with `spaceBetween` and the grid spans the card anyway.
      child: SizedBox.square(
        dimension: size,
        child: Container(
          // A key per day, because a Tooltip's message is not a usable handle:
          // it differs for a day with no spending, so counting by message counts
          // only the busy days.
          key: ValueKey('heat-cell-$dayNumber'),
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
      ),
    );
  }
}

/// "less" and "more", so the shading has a legend.
class _Scale extends StatelessWidget {
  const _Scale({required this.rampLength});

  /// How many swatches, including the empty cell. Passed in rather than read
  /// from a constant so the legend and the grid cannot disagree.
  final int rampLength;

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
                // The ramp's OWN length, never a literal 4. A hardcoded divisor
                // silently skips steps the moment a theme offers a different
                // number of them, and the legend then lies about the grid.
                color: i == 0
                    ? AppChartColors.heatmapEmpty(scheme)
                    : AppChartColors.spendStep(scheme, i / (rampLength - 1)),
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
