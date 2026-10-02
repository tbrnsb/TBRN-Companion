import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:daily_companion/theme/app_chart_colors.dart';
import 'package:daily_companion/theme/app_theme.dart';
import 'package:daily_companion/utils/format.dart';
import 'package:daily_companion/widgets/spend_trend_cards.dart' show DayTotal;

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

  /// The gutter between cells, on both axes.
  ///
  /// Small on purpose. This is the value that decides whether the thing reads as
  /// a grid or as scattered pixels, and it is the opposite of what `spaceBetween`
  /// produced by accident.
  ///
  /// Four rather than three because three sat close enough to the 1px cell
  /// outline that a row of days read as a hatched block on the device. A gutter
  /// has to be visibly CARD between the cells, not merely non-zero, or the
  /// outline closes the seam back up.
  static const double _gap = 4;

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

    // ONE measure, resolved once at the top and handed to the grid AND the
    // legend. Resolving it in two places is how a key ends up a different size
    // from the thing it explains.
    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = SpendingHeatmap.cellFor(constraints.maxWidth);
        // THE MONTH decides the shape, and the orientation is a calendar's:
        // seven day-columns across, week-rows down.
        final rows = rowsForMonth(year, month);
        return Column(
          // `min`, not the default `max`. A Column given a bounded height
          // otherwise EXPANDS to fill it, so the card silently became as tall as
          // whatever box it was put in — which is how a page whose content needs
          // 292 pixels overflowed a 266 pixel pager slot: the card had already
          // spent the space before its own content asked for it.
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The MONTH, derived from the data rather than written down. The card
            // said 'Which days you spend' and nothing else, so a grid of red
            // squares had no month attached to it.
            Text(
              'Which days you spend '
              '${DateFormat.yMMMM().format(DateTime(year, month))}',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.xxs),
            Row(
              children: [
                // Flexible, because the summary grows with the figures in it and
                // a five-figure month pushes it past the legend beside it.
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
                _Scale(
                  rampLength: AppChartColors.rampLength(scheme),
                  cell: cell,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            // CENTRED, not stretched. Seven columns cannot both fill a 412dp
            // card and stay small: filling it means 56px cells, which is the
            // wall of squares item 5 removed. So the grid is a block in the
            // middle of the card, the way a contribution graph is. The original
            // defect was HUGGING THE LEFT, and centring fixes that without
            // bringing the size back.
            Center(
              child: Column(
                // Shrink-wrapped on purpose. With `stretch` the Column took the
                // full card width, the `Center` around it had nothing left to
                // centre, and the grid sat hard against the left edge — the very
                // defect the centring was meant to remove. A content-sized
                // Column is what makes `Center` do anything.
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var row = 0; row < rows; row++)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: row == rows - 1 ? 0 : _gap,
                      ),
                      child: Row(
                        // A FIXED gutter, with a cell already sized from the
                        // measure. This is the arrangement that reads as a grid.
                        //
                        // `Expanded` made the cells ~45px and the grid 315px
                        // tall. `spaceBetween` kept them small but spread seven
                        // 11px cells across 412dp, leaving ~56dp between them —
                        // a scatter, not a grid. A measured cell plus a small
                        // gutter gives tight columns AND a properly sized day.
                        // `min` is load-bearing. A Row defaults to taking the
                        // full width, so the cells were laid out at the START of
                        // a full-width row and the `Center` around them had
                        // nothing to centre — the grid was still hugging the
                        // left, which is the whole complaint.
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          for (
                            var column = 0;
                            column < columnsPerRow;
                            column++
                          ) ...[
                            // The SAME gutter the rows use, between columns.
                            //
                            // This was missing while `cellFor` had been
                            // subtracting six of them from the measure: the row
                            // laid its cells out edge to edge, so every vertical
                            // seam was two 1px cell borders meeting. On the
                            // device the month read as one congested hatched
                            // block rather than a grid of separate days, which
                            // is the opposite of what the gutter is for.
                            if (column > 0) const SizedBox(width: _gap),
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
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
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
    // A MONTH TOO SHORT TO HAVE A HEAVIEST DAY.
    //
    // On the 2nd of a month every record is on one day, so the busiest day IS
    // the month's total, and the caption read "Heaviest day Rs. 4,128.35 ·
    // Rs. 4,128.35 total" -- the same figure twice, which reads as a bug in the
    // arithmetic rather than a fact about the date. A grid with one lit cell
    // already says everything there is to say, so the caption just says it.
    if ((busiest - total).abs() < 0.005) {
      return 'All ${AppFormat.money(total, symbol: currencySymbol)} on one day';
    }
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
  /// The cell size for a given measure: as large as the width allows, capped.
  ///
  /// This replaces `spaceBetween`. Seven fixed 11px cells spread across a 412dp
  /// card put roughly 56dp between them, and a grid whose members are five times
  /// further apart than they are wide does not read as a grid at all — it reads
  /// as dots on a background, which is the complaint the device settled. The
  /// gutters are the defect, not the cell size.
  ///
  /// So the cell now takes the width and the gap comes out of it: the seven
  /// columns plus six small gaps fill the measure exactly, cells grow, and the
  /// grid stays a grid at any phone width. [maxCell] is the cap that stops this
  /// becoming the 45px wall of squares item 5 removed, and [minCell] keeps it
  /// legible on a narrow phone.
  static double cellFor(double width) {
    if (width <= 0) return SpendingHeatmapShim.minCell;
    final exact = (width - _gap * (columnsPerRow - 1)) / columnsPerRow;
    if (exact <= SpendingHeatmapShim.minCell) {
      return SpendingHeatmapShim.minCell;
    }
    if (exact >= SpendingHeatmapShim.maxCell) {
      return SpendingHeatmapShim.maxCell;
    }
    return exact;
  }

  /// The size the legend swatches are drawn at, so the key cannot drift from
  /// the grid it explains.
  static double legendCellFor(double width) => cellFor(width);
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

    // The outline that makes this a GRID rather than a scatter of squares.
    //
    // Every cell carries it, including the empty ones, because the empty cells
    // are what define the shape of the month — an outline is what the eye joins
    // up into rows and columns. Without it a quiet day and no day at all are
    // both just background, and the month has no rectangle.
    //
    // Derived, not a literal, so a palette edit cannot leave a grid of
    // hairlines that vanish on one background and shout on another.
    final outline = Border.all(
      color: scheme.onSurface.withValues(alpha: 0.14),
      width: 1,
    );

    if (dayNumber == 0) {
      // A cell OUTSIDE the month. Kept, and clearly de-emphasised: same outline
      // so the rectangle closes, but a fainter fill so it cannot read as a day.
      // A grid whose padding reads as a quiet week is a chart lying about its
      // own shape, and dropping the cell entirely leaves a ragged edge instead.
      return SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          key: const ValueKey('heat-dead-cell'),
          decoration: BoxDecoration(
            color: AppChartColors.heatmapDead(scheme),
            borderRadius: BorderRadius.circular(AppSpacing.xxs),
            border: outline,
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
            // The highlight REPLACES the outline rather than sitting on top of
            // it, so a selected day is not drawn with two borders of different
            // weights at once.
            border: isHighlighted
                ? Border.all(color: scheme.tertiary, width: 2)
                : outline,
          ),
        ),
      ),
    );
  }
}

/// "less" and "more", so the shading has a legend.
class _Scale extends StatelessWidget {
  const _Scale({required this.rampLength, required this.cell});

  /// How many swatches, including the empty cell. Passed in rather than read
  /// from a constant so the legend and the grid cannot disagree.
  final int rampLength;

  /// The RESOLVED cell size, so a swatch is the same shape as the day it
  /// describes. The grid sizes its cells from the measure; a legend still on the
  /// nominal constant would be a different size from the thing it explains.
  final double cell;

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
              width: cell,
              height: cell,
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

  /// The floor. Below this a cell stops being a cell.
  static const double minCell = 15;

  /// The cap that stops a wide phone turning the grid back into the wall of
  /// squares item 5 removed.
  static const double maxCell = 26;

  /// The nominal size, and what a degenerate measure falls back to.
  static const double cell = minCell;
}
