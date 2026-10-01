import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/journey_provider.dart';
import 'package:flutter_application_1/providers/transaction_provider.dart';
import 'package:flutter_application_1/screens/journeys/journey_detail_sheets.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/utils/date_window.dart';
import 'package:flutter_application_1/widgets/section_header.dart';
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
        journey.add(DateTime(stamp.year, stamp.month, stamp.day));
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

  /// Takes the user to that day in the ledger, which is the whole point.
  Future<void> _openDay(DateTime day) async {
    HapticFeedback.lightImpact();
    final transactions = context.read<TransactionProvider>();
    final navigator = Navigator.of(context);

    // Load FIRST, then narrow: the day belongs to the month that has to be in
    // memory before the filter can mean anything.
    await transactions.loadTransactionsForMonth(day.year, day.month);
    transactions.setSelectedDay(day);
    if (!mounted) return;
    navigator.pop();
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
                onTap: () => _openDay(date),
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
          Text(
            'Tap a day to open it in Transactions.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
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
  });

  final DateTime date;
  final bool hasSpending;
  final bool hasJourney;
  final VoidCallback onTap;

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
          '${hasJourney ? ', journey' : ''}',
      child: InkWell(
        key: CalendarScreen.dayKey(date.day),
        borderRadius: BorderRadius.circular(AppRadii.small),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: hasSpending ? scheme.primary : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppRadii.small),
            border: hasJourney && !hasSpending
                ? Border.all(color: scheme.tertiary, width: 2)
                : isToday
                ? Border.all(color: scheme.onSurface, width: 1.5)
                : null,
          ),
          alignment: Alignment.center,
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
