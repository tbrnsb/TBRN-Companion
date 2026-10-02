import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/providers/journey_provider.dart';
import 'package:daily_companion/providers/transaction_provider.dart';
import 'package:daily_companion/screens/journeys/journey_detail_sheets.dart';
import 'package:daily_companion/theme/app_theme.dart';
import 'package:daily_companion/utils/date_window.dart';
import 'package:daily_companion/widgets/section_header.dart';
import 'package:provider/provider.dart';

/// Every day in one month, reachable from every tab.
///
/// This used to exist as a card buried halfway down the Journey tab, which made
/// a global question — "what was on the 12th?" — answerable only from one screen
/// that had nothing to do with it. It is a button beside Settings now, and
/// Settings is on every tab.
///
/// It answers by day, and the answer is a day in the ledger: tapping a day loads
/// that month, narrows the ledger to the day, and pops back to Transactions. So
/// the calendar is a way IN, not a place that shows a summary of somewhere else.
///
/// Journeys are shown too, because a trip that starts or ends on a day is the
/// other half of "what happened", and it is already in memory, so it costs
/// nothing to mark it.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  /// Key for tests. An explicit key, never `find.byIcon`: this screen is full of
  /// chevrons and so is every icon button around it.
  static const Key calendarIconKey = ValueKey('calendar-button');

  /// The month/day/chevron keys, so a test can drive the grid without depending
  /// on layout order.
  static const Key monthLabelKey = ValueKey('calendar-month-label');
  static const Key prevMonthKey = ValueKey('calendar-prev-month');
  static const Key nextMonthKey = ValueKey('calendar-next-month');

  /// A day's key, because the day number is only known at build time.
  static Key dayKey(int day) => ValueKey('calendar-day-$day');

  /// Opens the calendar.
  static Future<void> open(BuildContext context) {
    return Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const CalendarScreen()));
  }

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  /// The day tapped but not yet opened. Null until one is.
  DateTime? _selected;

  /// Days with the user's own spending on them, month-first keys.
  Set<DateTime> _spendDays = const {};

  /// Days a journey started or ended on.
  Set<DateTime> _journeyDays = const {};

  bool _loading = false;
  int _loadToken = 0;

  DateTime get _floor => AppDateWindow.monthFloor(DateTime.now());
  DateTime get _ceiling => AppDateWindow.monthCeiling(DateTime.now());

  // Strictly between, because the floor and the ceiling are months you may BE
  // on but not page away from: from the current month there is nothing after it,
  // and from the earliest month there is nothing before it. A chevron that is
  // live there is the dead-button bug this replaced.
  bool get _canGoBack => _month.isAfter(_floor);
  bool get _canGoForward => _month.isBefore(_ceiling);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) return;
    _load();
  }

  /// Reads the month, without moving the ledger.
  ///
  /// The token guards against an older read landing after a newer one: tapping
  /// the chevron twice quickly must not let the first month's answer overwrite
  /// the second's.
  Future<void> _load() async {
    final token = ++_loadToken;
    final year = _month.year;
    final monthNumber = _month.month;
    final transactions = context.read<TransactionProvider>();
    final journeys = context.read<JourneyProvider>();

    setState(() => _loading = true);

    final results = await Future.wait([
      transactions.peekTransactionsForMonth(year, monthNumber),
      Future<List<Journey>>.value(journeys.journeys),
    ]);

    if (!mounted || token != _loadToken) return;

    final spend = <DateTime>{};
    for (final t in results[0] as List<Transaction>) {
      spend.add(DateTime(t.date.year, t.date.month, t.date.day));
    }

    final journey = <DateTime>{};
    for (final j in results[1] as List<Journey>) {
      // `endTime` is null while a journey is still running, so today stands in
      // for it: an ongoing trip IS something happening on this day.
      for (final stamp in [j.startTime, j.endTime ?? DateTime.now()]) {
        final day = DateTime(stamp.year, stamp.month, stamp.day);
        // Scoped to the month on the grid. An unscoped list put "August 18"
        // under an October calendar, which is not information — it is a
        // different month answering a question nobody asked.
        if (day.year == year && day.month == monthNumber) journey.add(day);
      }
    }

    setState(() {
      _spendDays = spend;
      _journeyDays = journey;
      _loading = false;
    });
  }

  void _step(int delta) {
    final next = AppDateWindow.clampMonth(
      DateTime(_month.year, _month.month + delta),
      DateTime.now(),
    );
    if (next == _month) return;
    HapticFeedback.selectionClick();
    setState(() => _month = next);
    _load();
  }

  /// Holds the day the user tapped, without leaving.
  ///
  /// The tap used to load, narrow AND pop, so a single touch on a month grid
  /// ended the screen. That is a cheap way to throw away a browse: the day is
  /// marked, the sheet stays, and the journey out is a deliberate second act
  /// with a button that names the day it will open.
  Future<void> _selectDay(DateTime day) async {
    HapticFeedback.selectionClick();
    final transactions = context.read<TransactionProvider>();

    // Load FIRST, then narrow: the day belongs to the month that has to be in
    // memory before the filter can mean anything.
    await transactions.loadTransactionsForMonth(day.year, day.month);
    if (!mounted) return;
    setState(() {
      _selected = day;
      // The month is reloaded above, so the list has to be asked for again.
      _load();
    });
  }

  /// Commits the held day: narrows the ledger to it and leaves.
  Future<void> _openSelectedDay() async {
    final day = _selected;
    if (day == null || !mounted) return;
    HapticFeedback.lightImpact();
    context.read<TransactionProvider>().setSelectedDay(day);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final first = DateTime(_month.year, _month.month, 1);
    final lastDay = DateTime(_month.year, _month.month + 1, 0).day;
    // A month grid starts on Sunday, so Monday is index 1. `first.weekday` is
    // already 1..7 with Sunday as 1.
    final leading = first.weekday - 1;
    final cells = ((leading + lastDay) / 7).ceil() * 7;

    const weekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    return Scaffold(
      appBar: AppBar(title: const Text('Calendar')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          // The month, with its bounds spelled out rather than enforced
          // silently: a disabled chevron with a tooltip that says why.
          Row(
            children: [
              IconButton(
                key: CalendarScreen.prevMonthKey,
                tooltip: _canGoBack
                    ? 'Previous month'
                    : 'Earliest month is ${DateFormat.yMMMM().format(_floor)}',
                onPressed: _canGoBack ? () => _step(-1) : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      DateFormat.yMMMM().format(_month),
                      key: CalendarScreen.monthLabelKey,
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      _canGoBack || _canGoForward
                          ? '${_spendDays.length} '
                                'day${_spendDays.length == 1 ? '' : 's'} '
                                'with spending'
                          : 'Only month available',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: CalendarScreen.nextMonthKey,
                tooltip: _canGoForward
                    ? 'Next month'
                    : 'Later than this month has not happened',
                onPressed: _canGoForward ? () => _step(1) : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: weekdays
                .map(
                  (d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: AppSpacing.xs),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1,
              crossAxisSpacing: AppSpacing.xxs,
              mainAxisSpacing: AppSpacing.xxs,
            ),
            itemCount: cells,
            itemBuilder: (context, index) {
              final dayNumber = index - leading + 1;
              if (dayNumber < 1 || dayNumber > lastDay) {
                return const SizedBox.shrink();
              }
              final date = DateTime(_month.year, _month.month, dayNumber);
              return _DayCell(
                date: date,
                hasSpending: _spendDays.contains(date),
                hasJourney: _journeyDays.contains(date),
                selected: _selected == date,
                onTap: () => _selectDay(date),
              );
            },
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _LegendDot(color: scheme.primary, label: 'Spending'),
              const SizedBox(width: AppSpacing.md),
              _LegendDot(color: scheme.tertiary, label: 'Journey'),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // CHOOSING IS NOT LEAVING. The hint changes to name the day that is
          // held and the button that commits it, so the two are never confused:
          // tapping a day marks it, and only the button opens it.
          if (_selected == null)
            Text(
              'Tap a day to choose it, then open it in Transactions.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${DateFormat.yMMMMd().format(_selected!)} selected',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                FilledButton(
                  key: const ValueKey('calendar-open-selected-day'),
                  onPressed: _openSelectedDay,
                  child: const Text('Open day'),
                ),
              ],
            ),
          if (_loading) ...[
            const SizedBox(height: AppSpacing.sm),
            const LinearProgressIndicator(minHeight: 2),
          ],
          // The journey day-detail sheet is still reachable from here, because it
          // knows about packing and reminders that the ledger knows nothing of.
          if (_journeyDays.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            const SectionHeader('Journey days'),
            for (final date in _journeyDays.toList()..sort())
              ListTile(
                key: ValueKey('calendar-journey-day-${date.day}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(DateFormat.yMMMMd().format(date)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => DayActivitySheet.show(context, date),
              ),
          ],
        ],
      ),
    );
  }
}

/// One day in the grid.
///
/// A day with spending is FILLED and a day with only a journey is outlined, so
/// the two are distinguishable without relying on colour alone.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.hasSpending,
    required this.hasJourney,
    required this.onTap,
    this.selected = false,
  });

  final DateTime date;
  final bool hasSpending;
  final bool hasJourney;
  final VoidCallback onTap;

  /// The day is HELD -- chosen, not yet opened.
  ///
  /// Outlined, not filled: a fill means "spending happened here" and is already
  /// spoken for. So the selection is a ring around the cell, which cannot be
  /// confused with the data the cell is reporting.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isToday = DateUtils.isSameDay(date, DateTime.now());

    return Semantics(
      button: true,
      label:
          '${date.day}'
          '${hasSpending ? ', has spending' : ''}'
          '${hasJourney ? ', journey' : ''}'
          '${selected ? ', selected' : ''}',
      selected: selected,
      child: InkWell(
        key: CalendarScreen.dayKey(date.day),
        borderRadius: BorderRadius.circular(AppRadii.small),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: hasSpending ? scheme.primary : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppRadii.small),
            border: selected
                // The selection ring is drawn OUTSIDE the cell's own edge so it
                // is never mistaken for the journey outline, which is a fill on
                // the border itself and means something else entirely.
                ? Border.all(color: scheme.primary, width: 2.5)
                : hasJourney && !hasSpending
                ? Border.all(color: scheme.tertiary, width: 2)
                : isToday
                ? Border.all(color: scheme.onSurface, width: 1.5)
                : null,
          ),
          alignment: Alignment.center,
          child: Stack(
            children: [
              Center(
                child: Text(
                  '${date.day}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: hasSpending ? scheme.onPrimary : scheme.onSurface,
                    fontWeight: hasSpending || isToday
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
              // The dot sits bottom-right so it never collides with the number,
              // and exists only when the fill has already claimed the cell. A day
              // with BOTH would otherwise show the spending and silently drop
              // the journey, which makes the key a small lie.
              if (hasJourney && hasSpending)
                Positioned(
                  right: 3,
                  bottom: 3,
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: scheme.tertiary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One entry in the key under the grid.
class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(AppSpacing.xxs),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
