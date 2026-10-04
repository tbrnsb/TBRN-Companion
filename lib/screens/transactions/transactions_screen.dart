import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/providers/location_provider.dart';
import 'package:daily_companion/providers/settings_provider.dart';
import 'package:daily_companion/providers/transaction_provider.dart';
import 'package:daily_companion/screens/transactions/add_transaction_sheet.dart';
import 'package:daily_companion/screens/transactions/expense_detail_screen.dart';
import 'package:daily_companion/screens/transactions/income_detail_screen.dart';
import 'package:daily_companion/theme/app_theme.dart';
import 'package:daily_companion/utils/date_window.dart';
import 'package:daily_companion/utils/format.dart';
import 'package:daily_companion/widgets/widgets.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  /// Whether the "Add" FAB is on screen right now.
  ///
  /// A floating action button is painted ON TOP of the list, so it covers
  /// whatever the user has scrolled underneath it. On the device it sat squarely
  /// on the heatmap's colour scale and hid two of its five swatches -- a chart
  /// that cannot be read because of a button that is not even its subject.
  ///
  /// Bottom padding cannot fix that. [AppSpacing.screenPaddingWithFab] only
  /// guarantees the LAST row can be scrolled clear, and the heatmap sits in the
  /// middle of a long screen. So the button gets out of the way while the user
  /// is reading, and comes back the moment they scroll up or return to the top.
  bool _fabVisible = true;

  double _lastScrollPixels = 0;

  /// Hides the FAB on the way down and brings it back on the way up.
  ///
  /// Always shown again at the top, so it is never missing from a screen someone
  /// has just landed on.
  bool _onScroll(ScrollUpdateNotification note) {
    final pixels = note.metrics.pixels;
    final atTop = pixels <= 0;
    final movingDown = pixels > _lastScrollPixels;
    _lastScrollPixels = pixels;
    final shouldShow = atTop || !movingDown;
    if (shouldShow != _fabVisible) {
      setState(() => _fabVisible = shouldShow);
    }
    return false;
  }

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
          // The list is the month, always. It used to switch to the search
          // result set whenever the provider said a search was active, which
          // meant leaving the search screen could leave you here looking at a
          // search you had already closed.
          final transactions = provider.filteredTransactions;
          final totalIncome = provider.totalIncome;
          final totalExpenses = provider.totalExpenses;
          final balance = provider.balance;
          final currencySymbol = context.select<SettingsProvider, String>(
            (s) => s.currency.symbol,
          );
          // The two category breakdowns, as swipeable pages. Built once: each
          // walks the month's transactions and resolves metadata for every entry.
          final breakdownPages = _breakdownPages(
            provider,
            currencySymbol: currencySymbol,
          );

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
            child: NotificationListener<ScrollUpdateNotification>(
              onNotification: _onScroll,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                // Clears the FAB, which otherwise covers the count, the
                // pager's page label and the last row of the list.
                padding: AppSpacing.screenPaddingWithFab,
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
                  // ONE search UI, in the app bar. The inline field used to live
                  // here too, and the dedicated view was added on top of it,
                  // which meant two fields writing the same query.
                  //
                  // This list is not a search surface. It renders the month and
                  // nothing else: the search screen owns the query, and when it
                  // used to write that query into shared state the list followed
                  // it out — leave search with nothing matching and the month was
                  // replaced by "nothing matched", with no way back. A screen
                  // that cannot be narrowed must not pretend it can be.

                  // Anything still owed on a shared trip. Renders nothing when
                  // there is none, which is the case on most days.
                  const TripOutstandingCard(),
                  // "Where did it go": the two breakdowns, stacked.
                  //
                  // Stacked, never side by side. At 360dp a row of two donuts is
                  // about 165 pixels each and the donut alone is already 132 —
                  // two of them would be unreadable rather than compact.
                  if (breakdownPages.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    const SectionHeader('Where did it go'),
                    const SizedBox(height: AppSpacing.xs),
                    // ONE card at a time, swiped.
                    //
                    // Stacked, the two breakdowns ate a screen and a half before
                    // the ledger began, and the spending chart was pushed far
                    // enough down that a month with eight spending categories
                    // never showed one. Side by side is not an option either: at
                    // 360dp a row of two donuts leaves about 165 pixels each and
                    // the donut alone is already 132.
                    //
                    // A fixed-height pager cannot hold these two either. The card
                    // measures 216 pixels plus 22 per category, so it needs 260
                    // for a two-category month and 414 for all nine; one number
                    // either clips a rich month or pads a poor one with two
                    // hundred pixels of empty card. `SwipePages` takes its height
                    // from the page it is showing, so neither can happen.
                    SwipePages(
                      labels: [for (final page in breakdownPages) page.$1],
                      pages: [for (final page in breakdownPages) page.$2],
                      // THE COUNT LABEL GETS OUT OF THE FAB'S WAY.
                      //
                      // The Add button floats bottom-RIGHT on a phone, and so
                      // did "1 of 2 . Spending". The button comes BACK on a
                      // scroll-up -- the moment the user is looking at the row --
                      // and landed on it, hiding which page they were on. On the
                      // left there is nothing floating.
                      countOnTheLeft: true,
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
                    // There is no "nothing matched" state HERE, and its absence
                    // is the fix. This screen cannot be narrowed by a search any
                    // more, so an empty list means the month really is empty,
                    // and the one message that is true is the one below. Search
                    // keeps its own "nothing matched" explanation, where the
                    // search is visible and can be undone.
                    EmptyState(
                      icon: Icons.receipt_long_rounded,
                      // A DAY IS A DIFFERENT QUESTION.
                      //
                      // The device opened this by tapping a day in the
                      // calendar, choosing one with nothing on it, and being
                      // told "No transactions yet — log your first expense for
                      // October 2026". The user has thirty in that month. The
                      // day filter chip was right above it saying the same
                      // thing, so the empty state was arguing with the screen
                      // it was on: the answer was about a day, not a month.
                      title: provider.selectedDay != null
                          ? 'Nothing on ${DateFormat.MMMd().format(provider.selectedDay!)}'
                          : provider.filter == TransactionFilter.income
                          ? 'No income recorded'
                          : 'No transactions yet',
                      message: provider.selectedDay != null
                          ? 'That day is clear. Take the filter off to see the rest of ${DateFormat.yMMMM().format(currentMonth)}.'
                          : provider.filter == TransactionFilter.income
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
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    ..._groupTransactions(transactions),
                  ],
                ],
              ),
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
          _fabVisible &&
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

  /// The breakdown cards worth showing, as (label, card) pairs.
  ///
  /// A type the user has filtered OUT is not offered as a page, so the pager
  /// never has a page that is present but permanently empty — and with one type
  /// left there is nothing to swipe to, so [SwipePages] simply shows it.
  ///
  /// Each card carries its own raised surface and is deliberately NOT wrapped in
  /// another: that would be a card inside a card, with two borders and two
  /// shadows' worth of padding.
  List<(String, Widget)> _breakdownPages(
    TransactionProvider provider, {
    required String currencySymbol,
  }) => [
    if (_expenseSegments(provider).isNotEmpty &&
        provider.filter != TransactionFilter.income)
      (
        'Spending',
        SpendBreakdownCard(
          title: 'Spending by category',
          segments: _expenseSegments(provider),
          currencySymbol: currencySymbol,
        ),
      ),
    if (_incomeSegments(provider).isNotEmpty &&
        provider.filter != TransactionFilter.expenses)
      (
        'Income',
        SpendBreakdownCard(
          title: 'Income by category',
          segments: _incomeSegments(provider),
          currencySymbol: currencySymbol,
        ),
      ),
  ];

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

    final picked = await showModalBottomSheet<DayPick>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _DayPickerSheet(
        initialMonth: provider.currentMonth ?? DateTime.now(),
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
    // The day may be in a month the ledger is not showing — the picker spans the
    // whole [AppDateWindow] precisely so that it can. `setSelectedDay` REFUSES a
    // day outside the loaded month, which is right: it cannot show a day whose
    // transactions it has not read. So the month is loaded first, and the two
    // steps cannot be separated or the tap silently does nothing — which is the
    // symptom this was reported as.
    final day = picked.day;
    // Non-null only for [DayPickResult.day], which is the only branch left here.
    if (day == null) return;
    final loaded = provider.currentMonth;
    if (loaded != null &&
        (day.year != loaded.year || day.month != loaded.month)) {
      await provider.loadTransactionsForMonth(day.year, day.month);
    }
    if (!context.mounted) return;
    _applyDaySelection(messenger, provider, provider.setSelectedDay(day));
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
/// The picker's OWN header does the navigating: [CalendarDatePicker] renders a
/// month label with working chevrons, and it drives them from [firstDate] and
/// [lastDate]. The first version of this sheet added a SECOND row of chevrons
/// above the picker and left the built-in one underneath, so the device showed
/// two month navigators, one of which could not move. One row, driven by the
/// range, is both fewer controls and the framework's own — which means the
/// chevrons disable themselves at the ends for free.
///
/// So the range IS the fix. [firstDate] is the floor and [lastDate] is today,
/// both from [AppDateWindow] — the same window the month chevrons on the card
/// use. A picker scoped to the month already on screen could not reach any day
/// outside it: "jump to the 12th", with the 12th in another month, was
/// unanswerable, and the build before that drew chevrons that did nothing at
/// all.
class _DayPickerSheet extends StatefulWidget {
  const _DayPickerSheet({
    required this.initialMonth,
    required this.selectedDay,
    required this.daysWithData,
  });

  /// The month on the card behind the sheet.
  ///
  /// This is what the picker OPENS on, and it is a different thing from the
  /// range below. Someone who paged back twice and then opens the picker is
  /// looking for a day in the month in front of them; opening on today instead
  /// would drop them somewhere they were not, which is the same mistake as
  /// scoping the range in the first place.
  final DateTime initialMonth;

  final DateTime? selectedDay;

  /// Days with something on them, so the picker is not 30 equally plausible
  /// empty cells.
  final Set<DateTime> daysWithData;

  @override
  State<_DayPickerSheet> createState() => _DayPickerSheetState();
}

class _DayPickerSheetState extends State<_DayPickerSheet> {
  /// The day tapped in the grid but not yet committed.
  ///
  /// Starts EMPTY rather than at [widget.selectedDay], so opening the sheet to
  /// change your mind and leaving it alone does not re-apply the filter you were
  /// trying to clear. The Apply button says which day it will apply, so the held
  /// value is never a secret.
  DateTime? _pending;

  @override
  Widget build(BuildContext context) {
    final initialMonth = widget.initialMonth;
    final selectedDay = widget.selectedDay;
    final daysWithData = widget.daysWithData;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();

    final first = AppDateWindow.monthFloor(now);
    // Today, not the end of the month: a transaction cannot have been recorded
    // on a day that has not happened.
    final last = now;

    // Where it OPENS: the day already chosen, else somewhere inside the month
    // the card is showing. Clamped, because `initialDate` outside
    // [firstDate, lastDate] asserts, and a month older than the floor is exactly
    // the case that reaches here.
    final initial = _clampTo(
      selectedDay ?? DateTime(initialMonth.year, initialMonth.month, 1),
      first,
      last,
    );

    final marked = daysWithData.length;

    return SafeArea(
      // Scrollable, because a month grid plus a header does not fit on a short
      // phone, and an overflowing bottom sheet is both an error stripe and an
      // unreachable calendar.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: SingleChildScrollView(
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
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Jump to a day',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    if (selectedDay != null)
                      TextButton(
                        key: const ValueKey('day-picker-whole-month'),
                        // An EXPLICIT result, distinct from a dismiss. Both used
                        // to be null, so swiping the sheet away cleared the day
                        // filter.
                        onPressed: () =>
                            Navigator.pop(context, const DayPick.wholeMonth()),
                        child: const Text('Whole month'),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: CalendarDatePicker(
                  key: const ValueKey('day-picker-calendar'),
                  initialDate: _pending ?? initial,
                  firstDate: first,
                  lastDate: last,
                  // SELECTS, DOES NOT CLOSE.
                  //
                  // `onDateChanged` used to pop the sheet, so a single tap both
                  // chose a day and dismissed the thing you choose it in -- and
                  // one stray tap on a grid of thirty cells silently narrowed
                  // the whole month. The day is now HELD, shown above, and
                  // applied by the button, so choosing is a separate act from
                  // committing and a mis-tap costs nothing.
                  onDateChanged: (day) {
                    HapticFeedback.selectionClick();
                    setState(() => _pending = day);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  0,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey('day-picker-apply'),
                    // Nothing chosen, nothing to apply. Disabled rather than
                    // applying the first of the month, which would be a
                    // different day from the one the grid is showing.
                    onPressed: _pending == null
                        ? null
                        : () => Navigator.pop(context, DayPick.day(_pending!)),
                    child: Text(
                      _pending == null
                          ? 'Pick a day'
                          : 'Show ${DateFormat.yMMMMd().format(_pending!)}',
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Text(
                  marked == 0
                      ? 'Nothing recorded in the months you can reach.'
                      : '$marked day${marked == 1 ? ' has' : 's have'} '
                            'transactions',
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

  /// [value] held inside [lo]..[hi].
  static DateTime _clampTo(DateTime value, DateTime lo, DateTime hi) {
    if (value.isBefore(lo)) return lo;
    if (value.isAfter(hi)) return hi;
    return value;
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
