import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/location_provider.dart';
import 'package:flutter_application_1/providers/settings_provider.dart';
import 'package:flutter_application_1/providers/transaction_provider.dart';
import 'package:flutter_application_1/screens/budgets/budgets_screen.dart';
import 'package:flutter_application_1/screens/transactions/add_transaction_sheet.dart';
import 'package:flutter_application_1/screens/transactions/expense_detail_screen.dart';
import 'package:flutter_application_1/screens/transactions/income_detail_screen.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/utils/date_window.dart';
import 'package:flutter_application_1/utils/format.dart';
import 'package:flutter_application_1/widgets/widgets.dart';

class TransactionsScreen extends StatelessWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        // Search, then calendar, then settings — the same order on every tab, so
        // the control that moves between days sits in the same place whichever
        // screen you are on.
        actions: const [
          AppSearchButton(),
          AppCalendarButton(),
          AppGearButton(),
        ],
      ),
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
          // Which list is on screen: the search result set while a search is
          // active, the ordinary filtered month otherwise. One variable, so the
          // empty state, the section header and the tiles cannot each pick a
          // different set and disagree about how many rows there are.
          final isSearching = provider.hasActiveSearch;
          final transactions = isSearching
              ? provider.searchResults
              : provider.filteredTransactions;
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
          // Feeds the by-day and running-balance charts. Empty when nothing is
          // recorded, and both cards render nothing rather than an empty frame.
          final dailyTotals = [
            for (final total in provider.dailyTotals)
              DayTotal(
                date: total.day,
                income: total.income,
                expenses: total.expenses,
              ),
          ];

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
                  averageDaily: provider.getAverageDailySpending(),
                  currencySymbol: currencySymbol,
                  count: provider.filteredTransactions.length,
                  onPrevious: provider.previousMonth,
                  onNext: provider.nextMonth,
                  // DISABLED, not hidden and not inert. A chevron that is
                  // present but does nothing is a tap that produces no change,
                  // which is indistinguishable from a tap that did not register.
                  // A disabled one says the boundary is reached; a missing one
                  // would leave a gap that looks like a layout mistake.
                  canGoPrevious: provider.canGoToPreviousMonth,
                  canGoNext: provider.canGoToNextMonth,
                  onPickDay: () => _pickDay(context, provider),
                  selectedDayLabel: provider.selectedDay == null
                      ? null
                      : DateFormat.yMMMMd().format(provider.selectedDay!),
                  // No await here, so reading `context` is safe.
                  onClearDay: () => _applyDaySelection(
                    ScaffoldMessenger.of(context),
                    provider,
                    provider.setSelectedDay(null),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _FilterButtons(
                  filter: provider.filter,
                  onFilterChanged: (filter) => provider.filter = filter,
                ),
                const SizedBox(height: AppSpacing.sm),
                // A single quiet row rather than a card. Budgets are read far
                // less often than transactions are added, so they get one line
                // here and the full screen behind the link.
                _BudgetsLink(),
                const SizedBox(height: AppSpacing.sm),
                // ONE search UI. The inline field and its summary used to live
                // here, and the dedicated view was added on top of them, which
                // meant two fields writing the same query: type in one, watch
                // the other change. Search now has one home, reached from the
                // app bar, and this list shows a month.
                //
                // Still an app-level affordance rather than nothing: when a
                // search is active the list IS the result set, and a user who
                // narrowed something needs to see that they have.
                if (isSearching)
                  _ActiveSearchBanner(currencySymbol: currencySymbol),

                // Anything still owed on a shared trip. Renders nothing when
                // there is none, which is the case on most days.
                const TripOutstandingCard(),
                // "Where did it go": the two breakdowns, stacked.
                //
                // Stacked, never side by side. At 360dp a row of two donuts is
                // about 165 pixels each and the donut alone is already 132 —
                // two of them would be unreadable rather than compact.
                if (expenseSegments.isNotEmpty ||
                    incomeSegments.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  const SectionHeader('Where did it go'),
                  const SizedBox(height: AppSpacing.xs),
                  if (expenseSegments.isNotEmpty &&
                      provider.filter != TransactionFilter.income) ...[
                    // SpendBreakdownCard carries its own raised surface, so it
                    // is not wrapped again here — that would be a card inside a
                    // card with two borders and two shadows' worth of padding.
                    SpendBreakdownCard(
                      title: 'Spending by category',
                      segments: expenseSegments,
                      currencySymbol: currencySymbol,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (incomeSegments.isNotEmpty &&
                      provider.filter != TransactionFilter.expenses)
                    SpendBreakdownCard(
                      title: 'Income by category',
                      segments: incomeSegments,
                      currencySymbol: currencySymbol,
                    ),
                ],
                // "When did it change": the three time series, one at a time.
                if (dailyTotals.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  const SectionHeader('When did it change'),
                  const SizedBox(height: AppSpacing.xs),
                  // The pager fixes its own page height internally; wrapping it
                  // in a SizedBox here would duplicate that number and go stale
                  // the moment a chart's caption changed length.
                  ChartPager(
                    labels: const ['Heatmap', 'Daily', 'Balance', 'Weekly'],
                    pages: [
                      SpendingHeatmap(
                        days: dailyTotals,
                        currencySymbol: currencySymbol,
                        // The day the filter is on, outlined, so the grid and
                        // the day filter cannot disagree about what is being
                        // looked at.
                        highlightedDate: provider.selectedDay,
                      ),
                      DailyTotalsChart(
                        days: dailyTotals,
                        currencySymbol: currencySymbol,
                        // So the chart marks the day the filter is on, instead
                        // of showing a filtered day at the same weight as the
                        // rest. On every page that has a day axis.
                        highlightedDate: provider.selectedDay,
                      ),
                      CumulativeBalanceChart(
                        days: dailyTotals,
                        currencySymbol: currencySymbol,
                      ),
                      WeeklyTotalsChart(
                        days: dailyTotals,
                        currencySymbol: currencySymbol,
                      ),
                    ],
                  ),
                ],
                if (transactions.isEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  if (isSearching)
                    // A search with no hits is not the same thing as an empty
                    // month, and the two must not share a message: "log your
                    // first expense" when the month already has thirty is
                    // simply wrong, and it is the one place a user looks after
                    // deciding they HAVE found everything.
                    //
                    // No add affordance here, deliberately. The FAB is already on
                    // screen, and the FAB is the app's one rule for adding —
                    // see the single-affordance decision in the test below.
                    EmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'Nothing matches',
                      message:
                          'No transaction in '
                          '${DateFormat.yMMMM().format(currentMonth)} '
                          'matches what you searched for.',
                    )
                  else
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
                    isSearching
                        ? 'Search results'
                        : 'Recent ${provider.filter == TransactionFilter.income
                              ? 'income'
                              : provider.filter == TransactionFilter.expenses
                              ? 'expenses'
                              : 'transactions'}',
                    trailing: Text(
                      isSearching
                          ? '${transactions.length} match'
                                '${transactions.length == 1 ? '' : 'es'}'
                          : '${transactions.length} this month',
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
      // RULE (a), applied from ONE decision and not per call site: when the list
      // is empty the EmptyState carries the action and the FAB is hidden; the
      // moment there is a row the FAB comes back.
      //
      // Both used to be on screen at once on an empty list -- the FAB
      // unconditionally, plus the empty state's own button -- so the same action
      // appeared twice in different shapes and the screen read as broken. The
      // FAB returns as soon as there is something to add to.
      floatingActionButton:
          context.select<TransactionProvider, bool>(
            (p) => p.transactions.isNotEmpty,
          )
          ? FloatingActionButton.extended(
              onPressed: () {
                HapticFeedback.lightImpact();
                AddTransactionSheet.show(context);
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add'),
            )
          : null,
    );
  }

  /// Expense breakdown, resolved to real expense categories.
  ///
  /// The provider owns the slicing: `ExpenseCategory.other` rows can each carry
  /// a different custom name ("Coffee", "Groceries"), so they arrive here as
  /// separate segments that match the transaction tiles. Picking a single name
  /// for the whole bucket is what used to make the chart disagree with them.
  List<BreakdownSegment> _expenseSegments(TransactionProvider provider) {
    return provider
        .getSpendingBreakdownSlices()
        .map(
          (slice) => BreakdownSegment(meta: slice.meta, amount: slice.amount),
        )
        .toList(growable: false);
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

  /// Opens the day picker, starting on the month on screen.
  ///
  /// NAVIGABLE, because a picker scoped to one month cannot reach any day
  /// outside it. "Jump to the 12th" and the 12th is in August while September
  /// is on screen, so the answer is to go back a month on the card first, then
  /// open this — a two-step errand for a one-step question, and the old build
  /// proved it worse than that: it drew chevrons that did nothing.
  ///
  /// Bounded by [AppDateWindow], the same floor and ceiling the month chevrons
  /// on the card use. A day filter is a view of recorded transactions, so it
  /// stops at the earliest month the app will let you record anything in and at
  /// the current month, because a future month is not a thing that has happened.
  ///
  /// Days that actually have transactions are marked, so the picker is not 30
  /// equally plausible empty cells. Only days up to today are offered: a
  /// transaction cannot have been recorded on a day that has not happened.
  Future<void> _pickDay(
    BuildContext context,
    TransactionProvider provider,
  ) async {
    // Captured before the sheet opens, so nothing reads `context` after an await.
    final messenger = ScaffoldMessenger.of(context);
    final month = provider.currentMonth ?? DateTime.now();

    final picked = await showModalBottomSheet<DayPick>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _DayPickerSheet(
        initialMonth: month,
        selectedDay: provider.selectedDay,
        daysWithData: provider.daysWithTransactions,
      ),
    );

    // A DISMISS and a "Whole month" are different intentions, and for a long
    // time they were both null. Swiping the sheet away silently cleared the day
    // filter, so selecting a day and then changing your mind about the sheet
    // changed the view anyway.
    if (picked == null || picked.isDismissed) return;
    if (picked.result == DayPickResult.wholeMonth) {
      _applyDaySelection(messenger, provider, provider.setSelectedDay(null));
      return;
    }
    _applyDaySelection(
      messenger,
      provider,
      provider.setSelectedDay(picked.day),
    );
  }

  /// Makes the outcome of a day tap VISIBLE.
  ///
  /// A tap that changes nothing must say so. Without this, selecting a day in
  /// another month, or re-tapping the day already on screen, did nothing at all
  /// and was indistinguishable from a tap that had not registered -- which is how
  /// a working control comes to look broken.
  void _applyDaySelection(
    ScaffoldMessengerState messenger,
    TransactionProvider provider,
    DaySelectionOutcome outcome,
  ) {
    final message = switch (outcome) {
      DayOutsideLoadedMonth(:final loadedMonth) =>
        'That day is in ${DateFormat.yMMMM().format(loadedMonth)}, which is not '
            'the month on screen.',
      DayInTheFuture() => 'That day has not happened yet.',
      DayAlreadySelected() => 'Already showing that day.',
      DaySelectionAlreadyWholeMonth() => 'Already showing the whole month.',
      DaySelected() || DaySelectionCleared() => null,
    };
    if (message == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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

/// The one line that gets to the budgets screen.
///
/// Carries the month's total spend, read through the provider's accessor, and
/// nothing else.
///
/// Deliberately does NOT also count the overspent budgets. It could, but that
/// means rebuilding a [BudgetStatus] per limit here — a second place the
/// near-limit and overspend thresholds live, free to drift from the budgets
/// screen's copy. The count belongs where the limits are, one tap away.
/// "Jump to a day", navigable across months.
///
/// Its own [State] because the month on screen is not the month the sheet
/// opened on: the chevrons move it. The bounds come from [AppDateWindow], the
/// same floor and ceiling the month card uses, so the picker cannot offer a day
/// in a month the rest of the app would refuse to show.
///
/// The chevrons DISABLE at a boundary rather than being hidden or left inert.
/// A control that looks live and does nothing is worse than an absent one: it
/// is the same bug as the dead chevrons this replaced.
class _DayPickerSheet extends StatefulWidget {
  const _DayPickerSheet({
    required this.initialMonth,
    required this.selectedDay,
    required this.daysWithData,
  });

  final DateTime initialMonth;
  final DateTime? selectedDay;
  final Set<DateTime> daysWithData;

  @override
  State<_DayPickerSheet> createState() => _DayPickerSheetState();
}

class _DayPickerSheetState extends State<_DayPickerSheet> {
  late DateTime _month = DateTime(
    widget.initialMonth.year,
    widget.initialMonth.month,
  );

  DateTime get _floor => AppDateWindow.monthFloor(DateTime.now());
  DateTime get _ceiling => AppDateWindow.monthCeiling(DateTime.now());

  // Strictly between, for the same reason as the calendar: the floor and the
  // ceiling are months you may BE on but not page away from. A chevron that is
  // live at a boundary is the dead-button bug this replaced.
  bool get _canGoBack => _month.isAfter(_floor);
  bool get _canGoForward => _month.isBefore(_ceiling);

  /// [value] held inside [lo]..[hi].
  ///
  /// `CalendarDatePicker` ASSERTS if `initialDate` falls outside its range, so a
  /// stored selection belonging to another month has to be pulled inside rather
  /// than trusted.
  static DateTime _clampTo(DateTime value, DateTime lo, DateTime hi) {
    if (value.isBefore(lo)) return lo;
    if (value.isAfter(hi)) return hi;
    return value;
  }

  void _step(int delta) {
    final next = AppDateWindow.clampMonth(
      DateTime(_month.year, _month.month + delta),
      DateTime.now(),
    );
    if (next == _month) return;
    setState(() => _month = next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();

    final firstOfMonth = DateTime(_month.year, _month.month, 1);
    final lastDay = DateTime(_month.year, _month.month + 1, 0).day;
    // A month that has not happened yet cannot have a transaction on it, so the
    // current month stops at today.
    final lastSelectable =
        firstOfMonth.year == now.year && firstOfMonth.month == now.month
        ? now.day
        : lastDay;

    // Clamped, because `initialDate` outside [firstDate, lastDate] asserts and
    // a stored selection from another month is exactly the case that crashed it.
    final initial = _clampTo(
      widget.selectedDay ?? firstOfMonth,
      firstOfMonth,
      DateTime(_month.year, _month.month, lastSelectable),
    );

    final highlighted = widget.daysWithData
        .where((d) => d.year == _month.year && d.month == _month.month)
        .length;

    return SafeArea(
      // Scrollable, because a month grid plus a header does not fit on a short
      // phone and an overflowing bottom sheet is both an error stripe and an
      // unreachable calendar. Constrained to most of the screen so it reads as a
      // sheet rather than as a full page.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Jump to a day',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    if (widget.selectedDay != null)
                      TextButton(
                        key: const ValueKey('day-picker-whole-month'),
                        // An EXPLICIT result, distinct from a dismiss. Both used to
                        // be null, so swiping the sheet away cleared the day filter.
                        onPressed: () =>
                            Navigator.pop(context, const DayPick.wholeMonth()),
                        child: const Text('Whole month'),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Row(
                  children: [
                    IconButton(
                      key: const ValueKey('day-picker-prev-month'),
                      tooltip: _canGoBack
                          ? 'Previous month'
                          : 'Earliest month is ${DateFormat.yMMMM().format(_floor)}',
                      onPressed: _canGoBack ? () => _step(-1) : null,
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Text(
                        DateFormat.yMMMM().format(_month),
                        key: const ValueKey('day-picker-month-label'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('day-picker-next-month'),
                      tooltip: _canGoForward
                          ? 'Next month'
                          : 'Later than this month has not happened',
                      onPressed: _canGoForward ? () => _step(1) : null,
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: CalendarDatePicker(
                  // Month-scoped, because the picker keeps its own selected date
                  // internally: navigate to an earlier month and that stale date is
                  // now AFTER this month's `lastDate`, which trips an assertion in
                  // the framework. A fresh key per month is what makes it re-read
                  // its `initialDate` instead of defending a day that is gone.
                  key: ValueKey(
                    'day-picker-calendar-${_month.year}-${_month.month}',
                  ),
                  initialDate: initial,
                  firstDate: firstOfMonth,
                  lastDate: DateTime(_month.year, _month.month, lastSelectable),
                  onDateChanged: (day) =>
                      Navigator.pop(context, DayPick.day(day)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  highlighted == 0
                      ? 'Nothing recorded in ${DateFormat.yMMMM().format(_month)}.'
                      : '$highlighted '
                            'day${highlighted == 1 ? '' : 's'} '
                            'have transactions',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
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

/// "2 matches · Search" on the list, while a search is active.
///
/// The list is showing the result set when this is on screen, and a narrowed
/// view that does not say so is indistinguishable from a month that shrank. It
/// says how many, and it offers the way back — but it does not offer a SECOND
/// field to type into, because the search screen owns that.
class _ActiveSearchBanner extends StatelessWidget {
  const _ActiveSearchBanner({required this.currencySymbol});

  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TransactionProvider>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      key: const ValueKey('active-search-banner'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: AppRadii.smallRadius,
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              '${provider.searchResults.length} match'
              '${provider.searchResults.length == 1 ? '' : 'es'} — showing '
              'search results',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            key: const ValueKey('search-open-view'),
            onPressed: () => AppSearchButton.open(context),
            child: const Text('Search'),
          ),
          TextButton(
            key: const ValueKey('search-clear-all'),
            onPressed: provider.clearSearch,
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

class _BudgetsLink extends StatelessWidget {
  const _BudgetsLink();

  @override
  Widget build(BuildContext context) {
    final transactions = context.watch<TransactionProvider>();
    final currency = context.select<SettingsProvider, String>(
      (s) => s.currency.symbol,
    );
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final anchor = transactions.currentMonth ?? DateTime.now();
    final index = transactions.spendIndex(anchor: anchor);

    return InkWell(
      key: const ValueKey('budgets-link'),
      borderRadius: AppRadii.smallRadius,
      onTap: () =>
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const BudgetsScreen())),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Row(
          children: [
            Icon(Icons.donut_small_rounded, size: 18, color: scheme.primary),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                'Budgets · '
                '${AppFormat.money(index.total, symbol: currency)} this month',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: scheme.primary),
          ],
        ),
      ),
    );
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
    required this.averageDaily,
    required this.currencySymbol,
    required this.count,
    required this.onPrevious,
    required this.onNext,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.onPickDay,
    required this.selectedDayLabel,
    required this.onClearDay,
  });

  final DateTime month;
  final double totalIncome;
  final double totalExpenses;
  final double balance;
  final double averageDaily;
  final String currencySymbol;
  final int count;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  /// Whether each chevron has somewhere to go. False disables it rather than
  /// hiding it, so the boundary is visible instead of mysterious.
  final bool canGoPrevious;
  final bool canGoNext;

  /// Opens the day picker.
  final VoidCallback onPickDay;

  /// Non-null when the view is narrowed to a single day; shown as a chip the
  /// user can dismiss to get the whole month back.
  final String? selectedDayLabel;
  final VoidCallback onClearDay;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    // The month summary is the single most important element on this screen, so
    // it is the screen's one accent surface. Everything below it is raised or
    // flat, which is what makes it read as the headline.
    return AppSurface(
      tier: AppSurfaceTier.accent,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Fixed-width rather than a bare IconButton. A Material IconButton
              // claims 48x48 minimum, which is 96 of the 296 available at 360dp
              // before the month name gets anything — and it overflowed the row
              // by a pixel, which no test caught because no test ever rendered
              // this screen at 360dp. The month label itself is the big tap
              // target; these are just affordances either side of it.
              SizedBox(
                width: AppSpacing.xl + AppSpacing.sm,
                height: AppSpacing.xl + AppSpacing.sm,
                child: IconButton(
                  key: const ValueKey('month-previous'),
                  tooltip: canGoPrevious ? 'Previous month' : 'Earliest month',
                  onPressed: canGoPrevious ? onPrevious : null,
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
              ),
              // Tappable, because the month header is the natural place to reach
              // for a day. It used to be a plain Text.
              Expanded(
                child: TextButton(
                  onPressed: onPickDay,
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.onPrimaryContainer,
                    // A zero minimum width, and no horizontal padding. Without
                    // this Material gives the button an intrinsic width the row
                    // cannot shrink past, and at 360dp the month name is pushed
                    // out by exactly one pixel.
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Row(
                    // NOT mainAxisSize.min. A min-size Row asks for its
                    // children's full intrinsic width and has no free space to
                    // hand out, which makes the Flexible below a no-op — the
                    // month name escapes at its natural width, the button
                    // cannot shrink, and the row overflows at 360dp. Letting it
                    // fill and shrinking the Flexible is what makes the
                    // ellipsis work.
                    children: [
                      const Icon(Icons.calendar_today_rounded, size: 16),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          DateFormat.yMMMM().format(month),
                          // Its own key, so a test can read WHICH month is on
                          // screen. Asserting on a formatted string built the same
                          // way the widget builds it proves only that intl works.
                          key: const ValueKey('month-label'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: AppSpacing.xl + AppSpacing.sm,
                height: AppSpacing.xl + AppSpacing.sm,
                child: IconButton(
                  key: const ValueKey('month-next'),
                  tooltip: canGoNext ? 'Next month' : 'Latest month',
                  onPressed: canGoNext ? onNext : null,
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('Balance', style: textTheme.titleSmall),
          // The one number this screen is about, so it is the one number
          // allowed to be large. Everything else on the screen steps down from
          // it.
          Text(
            AppFormat.money(balance, symbol: currencySymbol),
            style: textTheme.displayMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '$count transactions',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (selectedDayLabel != null) ...[
            const SizedBox(height: AppSpacing.xs),
            // The escape hatch from a day view. Without it there is no way back
            // to the month except the calendar.
            Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                avatar: const Icon(Icons.event_rounded, size: 18),
                label: Text(selectedDayLabel!),
                onDeleted: onClearDay,
                deleteButtonTooltipMessage: 'Show the whole month',
                onPressed: onPickDay,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              // Both halves flex. Two unconstrained Columns with
              // `spaceBetween` is the one layout here that cannot give: it asks
              // for both figures at their natural width and has no room to
              // distribute, so a four-figure income and a four-figure expense
              // side by side overflow the row at 360dp — one pixel, which no test
              // caught because no test had ever rendered this screen at 360dp.
              Expanded(
                child: Column(
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          // Pass 2 replaced this line's slot with the currency parameter and
          // dropped the figure entirely, leaving getAverageDailySpending() with
          // no UI caller at all.
          Text(
            'Avg. ${AppFormat.money(averageDaily, symbol: currencySymbol)} / day',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
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
        // Ellipsis, like the title. A long place name plus a category plus a
        // time is more than a 360dp row can hold, and an unbounded Text here
        // pushed the row one pixel past its own width.
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Text(
        // Bounded for the same reason as the subtitle: a five-figure amount
        // with a currency prefix is not a short string.
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
