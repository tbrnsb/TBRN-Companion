import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/providers/journey_provider.dart';
import 'package:daily_companion/providers/settings_provider.dart';
import 'package:daily_companion/providers/transaction_provider.dart';
import 'package:daily_companion/services/place_launcher.dart';
import 'package:daily_companion/theme/app_theme.dart';
import 'package:daily_companion/utils/format.dart';
import 'package:daily_companion/widgets/section_header.dart';

import '../transactions/expense_detail_screen.dart';
import '../transactions/income_detail_screen.dart';
import 'add_location_screen.dart';

/// Everything recorded at one saved place.
///
/// WHY THIS EXISTS. A saved place was a row in a list with three menu items:
/// open in maps, edit, delete. There was nowhere to see what had actually
/// happened there — not how many transactions, not the total, not the history —
/// even though the data was all there and `getTransactionsByLocation` existed to
/// read it with nothing calling it. A place you have saved fifteen transactions
/// against was a place the app could not tell you anything about.
///
/// The link from a transaction to here is the other half: tapping the place name
/// on a transaction opens this, so the app has a path in both directions instead
/// of the place knowing about transactions but never being reachable from one.
class LocationDetailScreen extends StatelessWidget {
  const LocationDetailScreen({super.key, required this.location});

  final Location location;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final currency = context.select<SettingsProvider, String>(
      (s) => s.currency.symbol,
    );

    // Every transaction ever filed against this place, across all months and
    // both directions.
    final transactions =
        context
            .watch<TransactionProvider>()
            .transactionsAtLocation(location.id)
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));

    final expenses = transactions.where((t) => t.isExpense).toList();
    final income = transactions.where((t) => t.isIncome).toList();
    final spent = expenses.fold<double>(0, (sum, t) => sum + t.amount);
    final earned = income.fold<double>(0, (sum, t) => sum + t.amount);

    return Scaffold(
      appBar: AppBar(
        title: Text(location.name),
        actions: [
          IconButton(
            key: const ValueKey('location-detail-maps'),
            tooltip: 'Open in maps',
            icon: const Icon(Icons.open_in_new_rounded),
            onPressed: () => PlaceLauncher.openOrExplain(
              context,
              PlaceLink(
                latitude: location.latitude,
                longitude: location.longitude,
                name: location.name,
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('location-detail-edit'),
            tooltip: 'Edit place',
            icon: const Icon(Icons.edit_rounded),
            onPressed: () =>
                AddLocationScreen.show(context, location: location),
          ),
        ],
      ),
      body: ListView(
        padding: AppSpacing.screenPadding,
        children: [
          _Header(
            location: location,
            icon: PlaceIcons.resolve(location.icon),
            currency: currency,
          ),
          const SizedBox(height: AppSpacing.lg),

          // THE COUNTS. "15 transactions, Rs 4,200" is the answer to "is this
          // place worth keeping", and it is the thing that was impossible to get
          // before this screen existed.
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'Transactions',
                  value: '${transactions.length}',
                  icon: Icons.receipt_long_rounded,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _Stat(
                  label: 'Spent here',
                  value: expenses.isEmpty
                      ? '—'
                      : '$currency${spent.toStringAsFixed(0)}',
                  icon: Icons.trending_down_rounded,
                ),
              ),
            ],
          ),
          if (income.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _Stat(
              label: 'Received here',
              value: '$currency${earned.toStringAsFixed(0)}',
              icon: Icons.trending_up_rounded,
            ),
          ],

          const SizedBox(height: AppSpacing.lg),
          const SectionHeader('Breakdown'),
          const SizedBox(height: AppSpacing.xs),
          _Breakdown(transactions: transactions, currency: currency),

          const SizedBox(height: AppSpacing.lg),
          SectionHeader(
            transactions.isEmpty ? 'Nothing recorded yet' : 'History',
          ),
          const SizedBox(height: AppSpacing.xs),

          // An empty state that says what to do, not just that there is nothing.
          if (transactions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                'Nothing has been recorded at ${location.name} yet. '
                'Transactions logged inside its '
                '${location.radiusMeters.toStringAsFixed(0)} m radius will '
                'appear here.',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final transaction in transactions)
              _TransactionRow(transaction: transaction, currency: currency),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.location,
    required this.icon,
    required this.currency,
  });

  final Location location;
  final IconData icon;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final journey = location.journeyId == null
        ? null
        : context.read<JourneyProvider>().getJourneyById(location.journeyId!);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: AppRadii.mediumRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: AppRadii.smallRadius,
            ),
            child: Icon(icon, color: colorScheme.onPrimaryContainer),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${location.latitude.toStringAsFixed(4)}, '
                  '${location.longitude.toStringAsFixed(4)}',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                // The radius is stated because it is the rule this place applies
                // to every future transaction: inside this distance counts as
                // here, outside it does not.
                Text(
                  'Triggers within '
                  '${location.radiusMeters.toStringAsFixed(0)} m',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (location.description.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(location.description, style: textTheme.bodyMedium),
                ],
                if (journey != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'On ${journey.title}',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: AppRadii.smallRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: AppSpacing.xs),
          Text(value, style: textTheme.titleMedium),
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Spending and income at this place, split by category.
class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.transactions, required this.currency});

  final List<Transaction> transactions;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (transactions.isEmpty) {
      return Text(
        'Nothing to break down yet.',
        style: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      );
    }

    // Grouped by the category each transaction reports, so the same numbers the
    // transaction list shows are the numbers here. Expense and income are kept in
    // separate maps because they are separate facts — a donut of both at once
    // would put spending and earnings on the same scale, which is how a small
    // expense ends up looking like a large earning.
    final byCategory = <String, double>{};
    for (final t in transactions) {
      final meta = t.categoryMeta;
      byCategory[meta.name] = (byCategory[meta.name] ?? 0) + t.amount;
    }
    final rows = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                Expanded(child: Text(row.key, style: textTheme.bodyMedium)),
                Text(
                  '$currency${row.value.toStringAsFixed(0)}',
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One transaction in this place's history, and the way into it.
class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.transaction, required this.currency});

  final Transaction transaction;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final meta = transaction.categoryMeta;
    final isIncome = transaction.isIncome;

    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: meta.color.withValues(alpha: 0.15),
            child: Icon(meta.icon, size: 18, color: meta.color),
          ),
          title: Text(
            transaction.description.isEmpty
                ? meta.name
                : transaction.description,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${meta.name} · ${AppFormat.shortDate(transaction.date)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          // Income positive, expense negative — the same convention as the
          // transaction list, so a number read here means the same thing it does
          // there.
          trailing: Text(
            '${isIncome ? '+' : '−'}$currency'
            '${transaction.amount.toStringAsFixed(0)}',
            style: textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: isIncome ? AppColors.success : colorScheme.onSurface,
            ),
          ),
          // INTO the transaction, so the graph is navigable from both ends.
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => transaction.isExpense
                  ? ExpenseDetailScreen(expense: transaction as Expense)
                  : IncomeDetailScreen(income: transaction as Income),
            ),
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}
