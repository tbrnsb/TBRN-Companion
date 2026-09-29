import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/location_provider.dart';
import 'package:flutter_application_1/providers/settings_provider.dart';
import 'package:flutter_application_1/providers/transaction_provider.dart';
import 'package:flutter_application_1/screens/transactions/add_transaction_sheet.dart';
import 'package:flutter_application_1/screens/transactions/expense_detail_screen.dart';
import 'package:flutter_application_1/screens/transactions/income_detail_screen.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/utils/format.dart';
import 'package:flutter_application_1/widgets/widgets.dart';

class TransactionsScreen extends StatelessWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Spend')),
      body: Consumer<TransactionProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (provider.error != null) {
            return _ErrorState(
              message: provider.error!,
              onRetry: () => provider.goToCurrentMonth(),
            );
          }

          final currentMonth = provider.currentMonth ?? DateTime.now();
          final transactions = provider.filteredTransactions;
          final totalIncome = provider.totalIncome;
          final totalExpenses = provider.totalExpenses;
          final balance = provider.balance;
          final currencySymbol = context.select<SettingsProvider, String>(
            (s) => s.currency.symbol,
          );
          // Built once: these walk the month's transactions and resolve
          // metadata for every entry.
          final expenseSegments = _expenseSegments(provider);
          final incomeSegments = _incomeSegments(provider);

          return RefreshIndicator(
            onRefresh: () => provider.loadTransactionsForMonth(
              currentMonth.year,
              currentMonth.month,
            ),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: AppSpacing.screenPadding,
              children: [
                _MonthSummaryCard(
                  month: currentMonth,
                  totalIncome: totalIncome,
                  totalExpenses: totalExpenses,
                  balance: balance,
                  currencySymbol: currencySymbol,
                  count: provider.transactions.length,
                  onPrevious: provider.previousMonth,
                  onNext: provider.nextMonth,
                ),
                const SizedBox(height: AppSpacing.md),
                _FilterButtons(
                  filter: provider.filter,
                  onFilterChanged: (filter) => provider.filter = filter,
                ),
                if (expenseSegments.isNotEmpty &&
                    provider.filter != TransactionFilter.income) ...[
                  const SizedBox(height: AppSpacing.md),
                  SpendBreakdownCard(
                    title: 'Spending by category',
                    segments: expenseSegments,
                    currencySymbol: currencySymbol,
                  ),
                ],
                if (incomeSegments.isNotEmpty &&
                    provider.filter != TransactionFilter.expenses) ...[
                  const SizedBox(height: AppSpacing.md),
                  SpendBreakdownCard(
                    title: 'Income by category',
                    segments: incomeSegments,
                    currencySymbol: currencySymbol,
                  ),
                ],
                if (transactions.isEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  EmptyState(
                    icon: Icons.receipt_long_rounded,
                    title: provider.filter == TransactionFilter.income
                        ? 'No income recorded'
                        : 'No transactions yet',
                    message: provider.filter == TransactionFilter.income
                        ? 'Add income to see it here.'
                        : 'Log your first expense for ${DateFormat.yMMMM().format(currentMonth)} — it takes a few seconds.',
                    // The action always opens the Expense/Income chooser now,
                    // so the label must not promise a single type.
                    actionLabel: 'Add transaction',
                    onAction: () => AddTransactionSheet.show(context),
                  ),
                ] else ...[
                  const SizedBox(height: AppSpacing.md),
                  SectionHeader(
                    'Recent ${provider.filter == TransactionFilter.income
                        ? 'income'
                        : provider.filter == TransactionFilter.expenses
                        ? 'expenses'
                        : 'transactions'}',
                    trailing: Text(
                      '${transactions.length} this month',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  ..._groupTransactions(transactions),
                ],
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          HapticFeedback.lightImpact();
          AddTransactionSheet.show(context);
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      ),
    );
  }

  /// Expense breakdown, resolved to real expense categories.
  ///
  /// `ExpenseCategory.other` rows can carry a custom name ("Coffee"), so the
  /// first custom name in the month is preferred over the generic "Other" —
  /// otherwise the chart would disagree with the transaction tiles.
  List<BreakdownSegment> _expenseSegments(TransactionProvider provider) {
    final customNameForOther = provider.transactions
        .whereType<Expense>()
        .where((e) => e.category == ExpenseCategory.other)
        .map((e) => e.customCategoryName)
        .firstWhere(
          (name) => name != null && name.isNotEmpty,
          orElse: () => null,
        );

    return provider.getSpendingBreakdown().map((entry) {
      final meta = entry.key == ExpenseCategory.other
          ? CategoryRegistry.metaFor(
              ExpenseCategory.other,
              customName: customNameForOther,
            )
          : CategoryRegistry.metaFor(entry.key);
      return BreakdownSegment(meta: meta, amount: entry.value);
    }).toList();
  }

  /// Income breakdown, keyed by income category id so metadata resolves.
  List<BreakdownSegment> _incomeSegments(TransactionProvider provider) {
    return provider.getIncomeBreakdown().map((entry) {
      return BreakdownSegment(
        meta: CategoryRegistry.metaForIncome(entry.key),
        amount: entry.value,
      );
    }).toList();
  }

  List<Widget> _groupTransactions(List<Transaction> transactions) {
    final sorted = [...transactions]..sort((a, b) => b.date.compareTo(a.date));
    final widgets = <Widget>[];
    DateTime? lastDay;

    for (final transaction in sorted) {
      final day = DateTime(
        transaction.date.year,
        transaction.date.month,
        transaction.date.day,
      );
      if (day != lastDay) {
        lastDay = day;
        widgets.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xxs,
              AppSpacing.sm,
              0,
              AppSpacing.xxs,
            ),
            child: Text(
              _dayLabel(day),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        );
      }
      widgets.add(_TransactionTile(transaction: transaction));
    }
    return widgets;
  }

  String _dayLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat.yMMMd().format(day);
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: AppSpacing.screenPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: colorScheme.error,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Something went wrong',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Your expenses could not be loaded. Please try again.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthSummaryCard extends StatelessWidget {
  const _MonthSummaryCard({
    required this.month,
    required this.totalIncome,
    required this.totalExpenses,
    required this.balance,
    required this.currencySymbol,
    required this.count,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime month;
  final double totalIncome;
  final double totalExpenses;
  final double balance;
  final String currencySymbol;
  final int count;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: AppRadii.mediumRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                tooltip: 'Previous month',
                onPressed: onPrevious,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Text(
                DateFormat.yMMMM().format(month),
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('Balance', style: textTheme.labelLarge),
          Text(
            AppFormat.money(balance, symbol: currencySymbol),
            style: textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '$count transactions',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Income',
                    style: textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    AppFormat.money(totalIncome, symbol: currencySymbol),
                    style: textTheme.bodyLarge,
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Expenses',
                    style: textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    AppFormat.money(totalExpenses, symbol: currencySymbol),
                    style: textTheme.bodyLarge,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterButtons extends StatelessWidget {
  const _FilterButtons({required this.filter, required this.onFilterChanged});

  final TransactionFilter filter;
  final ValueChanged<TransactionFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      children: [
        _FilterButton(
          label: 'All',
          selected: filter == TransactionFilter.all,
          onTap: () => onFilterChanged(TransactionFilter.all),
        ),
        _FilterButton(
          label: 'Expenses',
          selected: filter == TransactionFilter.expenses,
          onTap: () => onFilterChanged(TransactionFilter.expenses),
        ),
        _FilterButton(
          label: 'Income',
          selected: filter == TransactionFilter.income,
          onTap: () => onFilterChanged(TransactionFilter.income),
        ),
      ],
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: colorScheme.primary.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
      ),
      side: BorderSide(
        color: selected ? colorScheme.primary : colorScheme.outline,
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final meta = transaction.categoryMeta;
    final locationName = transaction.locationId == null
        ? null
        : context
              .read<LocationProvider>()
              .getLocationById(transaction.locationId!)
              ?.name;

    final isExpense = transaction.isExpense;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2,
      ),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: meta.color.withValues(alpha: 0.15),
          borderRadius: AppRadii.smallRadius,
        ),
        child: Icon(meta.icon, color: meta.color, size: 20),
      ),
      title: Text(
        transaction.description,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        [
          transaction.effectiveCategoryName,
          AppFormat.time(transaction.date),
          if (locationName != null) '📍 $locationName',
        ].join(' · '),
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Text(
        AppFormat.signedMoney(
          transaction.amount,
          isExpense: isExpense,
          symbol: context.select<SettingsProvider, String>(
            (s) => s.currency.symbol,
          ),
        ),
        style: textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: isExpense ? colorScheme.onSurface : AppColors.success,
        ),
      ),
      onTap: () {
        if (transaction.isExpense) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  ExpenseDetailScreen(expense: transaction as Expense),
            ),
          );
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => IncomeDetailScreen(income: transaction as Income),
            ),
          );
        }
      },
    );
  }
}
