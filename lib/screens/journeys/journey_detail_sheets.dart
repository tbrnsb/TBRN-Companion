import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/providers/journey_provider.dart';
import 'package:daily_companion/providers/settings_provider.dart';
import 'package:daily_companion/providers/transaction_provider.dart';
import 'package:daily_companion/screens/journeys/journey_detail_screen.dart';
import 'package:daily_companion/theme/app_theme.dart';
import 'package:daily_companion/utils/format.dart';

/// What happened on one day, gathered from every section.
///
/// The timeline used to be a read-only calendar: a day with a dot under it told
/// you that something happened and then nothing. This turns the dot into a way
/// in.
class DayActivitySheet extends StatelessWidget {
  const DayActivitySheet({super.key, required this.day});

  final DateTime day;

  static Future<void> show(BuildContext context, DateTime day) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DayActivitySheet(day: day),
    );
  }

  @override
  Widget build(BuildContext context) {
    final journeys = context.watch<JourneyProvider>();
    final transactions = context.watch<TransactionProvider>();
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    final started = journeys.journeysStartingOn(day);
    final ended = journeys.journeysEndingOn(day);

    // Only the month on screen is in memory. A day outside it has no
    // transactions to show — but saying "nothing recorded" about a day whose
    // month was simply never loaded is a lie, and it is the kind that looks
    // exactly like the truth. It reads as "you spent nothing that day" when the
    // app means "I have not looked".
    //
    // So it says which of the two it is. The honest message is less useful and
    // much better than a confident wrong one.
    final monthLoaded =
        transactions.currentMonth?.year == day.year &&
        transactions.currentMonth?.month == day.month;
    final dayTransactions = monthLoaded
        ? transactions.getTransactionsInDateRange(day, day)
        : const <Transaction>[];

    final noJourneys = started.isEmpty && ended.isEmpty;
    final nothing = noJourneys && dayTransactions.isEmpty;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Text(_dayLabel(day), style: textTheme.titleMedium),
            ),
            Flexible(
              child: nothing
                  ? Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Text(
                        !monthLoaded && noJourneys
                            ? 'No journeys on this day. Open the month in '
                                  'Transactions to see what was spent.'
                            : 'Nothing recorded on this day.',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        0,
                        AppSpacing.lg,
                        AppSpacing.lg,
                      ),
                      children: [
                        if (started.isNotEmpty) ...[
                          _SectionLabel('Started'),
                          for (final j in started) _JourneyRow(journey: j),
                        ],
                        if (ended.isNotEmpty) ...[
                          _SectionLabel('Ended'),
                          for (final j in ended) _JourneyRow(journey: j),
                        ],
                        if (dayTransactions.isNotEmpty) ...[
                          _SectionLabel(
                            'Transactions (${dayTransactions.length})',
                          ),
                          for (final t in dayTransactions)
                            _TransactionRow(transaction: t),
                        ],
                        if (!monthLoaded && started.isEmpty && ended.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.sm),
                            child: Text(
                              'Transactions for this month are not loaded, so '
                              'spending for this day is not shown here.',
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _dayLabel(DateTime day) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${day.day} ${months[day.month - 1]} ${day.year}';
  }
}

/// A stat on the journey summary, opened for detail.
enum JourneyStat { trips, completed, averageTime, packed }

/// Explains one of the four summary numbers.
///
/// They were AppStatTiles with no tap handler, so a number that looked
/// interesting could not be followed up on.
class JourneyStatSheet extends StatelessWidget {
  const JourneyStatSheet({super.key, required this.stat});

  final JourneyStat stat;

  static Future<void> show(BuildContext context, JourneyStat stat) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => JourneyStatSheet(stat: stat),
    );
  }

  @override
  Widget build(BuildContext context) {
    final journeys = context.watch<JourneyProvider>();
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    final (title, subtitle, rows) = switch (stat) {
      JourneyStat.trips => (
        'All trips',
        '${journeys.totalJourneys} recorded, newest first',
        journeys.journeys,
      ),
      JourneyStat.completed => (
        'Completed trips',
        '${journeys.completedJourneys} of ${journeys.totalJourneys} finished',
        journeys.journeys.where((j) => j.completed).toList(),
      ),
      JourneyStat.averageTime => (
        'Average trip length',
        journeys.averageJourneyMinutes > 0
            ? 'Across finished trips only'
            : 'No finished trips yet',
        const <Journey>[],
      ),
      JourneyStat.packed => (
        'Items packed',
        '${journeys.totalPackedItems} across every trip',
        const <Journey>[],
      ),
    };

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.xs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    subtitle,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: switch (stat) {
                JourneyStat.averageTime => _AverageBreakdown(
                  journeys: journeys,
                ),
                JourneyStat.packed => _PackedBreakdown(journeys: journeys),
                _ =>
                  rows.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Text(
                            'Nothing here yet.',
                            style: textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            0,
                            AppSpacing.lg,
                            AppSpacing.lg,
                          ),
                          children: [
                            for (final j in rows) _JourneyRow(journey: j),
                          ],
                        ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AverageBreakdown extends StatelessWidget {
  const _AverageBreakdown({required this.journeys});

  final JourneyProvider journeys;

  @override
  Widget build(BuildContext context) {
    final finished = journeys.journeys.where((j) => j.completed).toList();
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    if (finished.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          'An average needs at least one finished trip.',
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      children: [
        for (final j in finished) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(j.destination.isEmpty ? 'Trip' : j.destination),
            trailing: Text(
              // durationMinutes is an int; the formatter works in doubles.
              _format(j.durationMinutes.toDouble()),
              style: textTheme.labelLarge,
            ),
          ),
          const Divider(height: 1),
        ],
      ],
    );
  }

  static String _format(double minutes) {
    if (minutes <= 0) return '0m';
    final whole = minutes.round();
    final hours = whole ~/ 60;
    final mins = whole % 60;
    return hours == 0 ? '${mins}m' : '${hours}h ${mins}m';
  }
}

class _PackedBreakdown extends StatelessWidget {
  const _PackedBreakdown({required this.journeys});

  final JourneyProvider journeys;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    if (journeys.journeys.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          'No trips yet.',
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      children: [
        for (final j in journeys.journeys) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(j.destination.isEmpty ? 'Trip' : j.destination),
            subtitle: Text(
              j.items.isEmpty
                  ? 'Nothing packed'
                  : j.items.take(4).join(', ') +
                        (j.items.length > 4 ? ' +${j.items.length - 4}' : ''),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text('${j.items.length}', style: textTheme.labelLarge),
          ),
          const Divider(height: 1),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _JourneyRow extends StatelessWidget {
  const _JourneyRow({required this.journey});

  final Journey journey;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final statusColor = journey.completed
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : AppColors.success;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        journey.completed
            ? Icons.check_circle_rounded
            : Icons.navigation_rounded,
        color: statusColor,
      ),
      title: Text(journey.destination.isEmpty ? 'Trip' : journey.destination),
      subtitle: Text(
        journey.endTime == null
            ? 'Started ${_short(journey.startTime)}'
            : '${_short(journey.startTime)} → ${_short(journey.endTime!)}',
        style: textTheme.bodySmall,
      ),
      onTap: () {
        Navigator.pop(context);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => JourneyDetailScreen(journey: journey),
          ),
        );
      },
    );
  }

  static String _short(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // The currency is a setting, so a hardcoded symbol here would quietly
    // disagree with every other amount on the screen.
    final symbol = context.select<SettingsProvider, String>(
      (s) => s.currency.symbol,
    );
    final meta = transaction.categoryMeta;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(meta.icon, color: meta.color),
      title: Text(
        transaction.description.isEmpty ? meta.name : transaction.description,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(meta.name, style: textTheme.bodySmall),
      trailing: Text(
        AppFormat.signedMoney(
          transaction.amount,
          isExpense: transaction.isExpense,
          symbol: symbol,
        ),
        style: textTheme.labelLarge?.copyWith(
          color: transaction.isExpense
              ? Theme.of(context).colorScheme.onSurface
              : AppColors.success,
        ),
      ),
    );
  }
}
