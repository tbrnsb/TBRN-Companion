import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/journey_provider.dart';
import 'package:flutter_application_1/providers/settings_provider.dart';
import 'package:flutter_application_1/providers/transaction_provider.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/utils/format.dart';

import 'expense_detail_screen.dart';
import 'income_detail_screen.dart';
import 'transaction_search_sheet.dart';

/// Search, as its own screen with its own field at the top.
///
/// The field used to live inline in the transaction list, which meant search
/// results appeared in the same list as the whole month: the list below the
/// field kept re-sorting and re-paginating around you, the month summary and the
/// charts stayed on screen describing figures that were not what you were
/// looking at, and there was no way to type a search without the charts
/// recalculating on every keystroke.
///
/// This screen owns the query and shows only results. The list keeps its
/// ordinary inline field OUT of the way — see [AppSearchButton] — so there is
/// one place to search, not two.
class TransactionSearchView extends StatefulWidget {
  const TransactionSearchView({super.key});

  @override
  State<TransactionSearchView> createState() => _TransactionSearchViewState();
}

class _TransactionSearchViewState extends State<TransactionSearchView> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Focused on open. A search screen whose field is not focused is a screen
    // that needs a second tap before it does anything, and on a phone the
    // keyboard covers the results anyway, so there is nothing to see first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _openFilters(
    TransactionProvider provider,
    String currencySymbol,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    // Dismiss the keyboard first: the filter sheet is a modal, and a keyboard
    // left open behind it squeezes the sheet into the top third of the screen.
    FocusScope.of(context).unfocus();
    final updated = await TransactionSearchSheet.show(context, provider.search);
    if (updated == null || !mounted) return;
    provider.search = updated;
    if (updated.text != _controller.text) {
      _controller.value = TextEditingValue(
        text: updated.text,
        selection: TextSelection.collapsed(offset: updated.text.length),
      );
    }
    // Redundant with the provider's own notification, but a sheet can also
    // change the query with no visible consequence otherwise, and a search that
    // silently changes is a search the user distrusts.
    messenger.hideCurrentSnackBar();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TransactionProvider>();
    final currencySymbol = context.select<SettingsProvider, String>(
      (s) => s.currency.symbol,
    );
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final query = provider.search;

    // ONE list of results, read once, and the SAME list the count and the empty
    // state describe. Reading `searchResults` three times would be three chances
    // for the count to disagree with the rows.
    final results = provider.searchResults;
    final narrowing = provider.hasActiveSearch;

    return Scaffold(
      appBar: AppBar(
        // The field is the title. YouTube-style: the query is what the screen
        // IS, so it belongs in the bar rather than in a card below it.
        titleSpacing: 0,
        title: TextField(
          key: const ValueKey('search-view-field'),
          controller: _controller,
          focusNode: _focus,
          textInputAction: TextInputAction.search,
          style: theme.textTheme.titleMedium,
          onChanged: (value) => provider.search = query.copyWith(text: value),
          decoration: InputDecoration(
            hintText: 'Search transactions',
            border: InputBorder.none,
            isDense: true,
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    key: const ValueKey('search-view-clear'),
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      _controller.clear();
                      provider.search = query.copyWith(text: '');
                    },
                  ),
          ),
        ),
        actions: [
          // The amount and category filters stay REACHABLE from the search
          // screen, because a screen whose only control is text cannot answer
          // "what did I spend on food over 500".
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xxs),
            child: _FilterButton(
              query: query,
              onPressed: () => _openFilters(provider, currencySymbol),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // The criteria the FIELD cannot show, in words. A filter with no
          // visible state is indistinguishable from data that has gone missing.
          if (query.activeCriteria > (query.text.trim().isEmpty ? 0 : 1))
            _CriteriaBar(
              query: query,
              resultCount: results.length,
              currencySymbol: currencySymbol,
              onClear: provider.clearSearch,
            ),
          Expanded(
            child: results.isEmpty
                ? _NoResults(narrowing: narrowing)
                : ListView.separated(
                    padding: AppSpacing.screenPadding,
                    itemCount: results.length + 1,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.xxs),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: Text(
                            '${results.length} result'
                            '${results.length == 1 ? '' : 's'}',
                            key: const ValueKey('search-result-count'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      }
                      return _SearchResultTile(
                        transaction: results[index - 1],
                        currencySymbol: currencySymbol,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// The tune icon, badged with the criteria the field cannot show.
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.query, required this.onPressed});

  final TransactionSearchQuery query;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hidden = query.activeCriteria - (query.text.trim().isEmpty ? 0 : 1);
    return Badge(
      isLabelVisible: hidden > 0,
      label: Text('$hidden'),
      child: IconButton(
        key: const ValueKey('search-view-filters'),
        tooltip: 'Amount and category filters',
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: hidden > 0
              ? scheme.primaryContainer
              : Colors.transparent,
          foregroundColor: hidden > 0
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant,
        ),
        icon: const Icon(Icons.tune_rounded),
      ),
    );
  }
}

/// "Food · over Rs 500 — 3 matches" and a way to drop all of it.
class _CriteriaBar extends StatelessWidget {
  const _CriteriaBar({
    required this.query,
    required this.resultCount,
    required this.currencySymbol,
    required this.onClear,
  });

  final TransactionSearchQuery query;
  final int resultCount;
  final String currencySymbol;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final parts = <String>[];
    if (query.text.trim().isNotEmpty) parts.add('"${query.text.trim()}"');
    if (query.minAmount != null && query.maxAmount != null) {
      parts.add('${_money(query.minAmount!)} to ${_money(query.maxAmount!)}');
    } else if (query.minAmount != null) {
      parts.add('over ${_money(query.minAmount!)}');
    } else if (query.maxAmount != null) {
      parts.add('under ${_money(query.maxAmount!)}');
    }
    if (query.categories.isNotEmpty) {
      // Names, not ids. A criteria bar reading "food · 3 matches" beside rows
      // labelled "Food" is asking the user to do the translation themselves.
      final names = [
        for (final id in query.categories)
          CategoryRegistry.suggestedForName(id)?.name ?? id,
      ]..sort();
      parts.add(names.length == 1 ? names.first : '${names.length} categories');
    }

    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${parts.join(' · ')} — $resultCount match'
              '${resultCount == 1 ? '' : 'es'}',
              key: const ValueKey('search-view-criteria'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            key: const ValueKey('search-view-clear-all'),
            onPressed: onClear,
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  String _money(double value) => AppFormat.money(value, symbol: currencySymbol);
}

/// One result: what it was, what category, when, who paid, and how much.
///
/// Every field here is also a field the search looks at, which is the rule: a
/// user must not have to search for something the result row refuses to show.
class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.transaction,
    required this.currencySymbol,
  });

  final Transaction transaction;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final meta = transaction.categoryMeta;
    final isExpense = transaction.isExpense;

    // The payer, resolved to a NAME or to nothing. `paidByParticipantId` is an
    // id, and a row that shows a raw uuid is worse than a row that shows no
    // payer at all.
    final payerName = _payerName(context, transaction);

    final subtitle = [
      transaction.effectiveCategoryName,
      DateFormat.yMMMd().format(transaction.date),
      if (payerName != null) 'paid by $payerName',
    ].join(' · ');

    return ListTile(
      key: ValueKey('search-result-${transaction.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
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
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      trailing: Text(
        AppFormat.signedMoney(
          transaction.amount,
          isExpense: isExpense,
          symbol: currencySymbol,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: isExpense ? scheme.onSurface : AppColors.success,
        ),
      ),
      onTap: () => _open(context),
    );
  }

  /// The participant who paid, by name.
  ///
  /// Null rather than the raw id: an expense with no trip, no payer, or a payer
  /// no longer on the roster has no name to show, and "—" would be noise on
  /// every ordinary row.
  String? _payerName(BuildContext context, Transaction transaction) {
    if (transaction is! Expense) return null;
    final id = transaction.paidByParticipantId;
    if (id == null) return null;
    final journeys = context.read<JourneyProvider>();
    for (final journey in journeys.journeys) {
      for (final participant in journey.participants) {
        if (participant.id == id) return participant.name;
      }
    }
    return null;
  }

  /// The right detail screen for this kind of transaction.
  ///
  /// Routed by [Transaction.isExpense] rather than by the static type at the
  /// call site, so an income row can never open the expense editor.
  void _open(BuildContext context) {
    if (transaction case final Expense expense) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ExpenseDetailScreen(expense: expense),
        ),
      );
      return;
    }
    if (transaction case final Income income) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => IncomeDetailScreen(income: income)),
      );
    }
  }
}

/// The empty state, which is two different things.
///
/// "No transactions" and "no results for this search" must not look the same:
/// the first means the app has nothing, the second means the app has plenty and
/// your query excluded it. They get different words.
class _NoResults extends StatelessWidget {
  const _NoResults({required this.narrowing});

  final bool narrowing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: AppSpacing.screenPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              narrowing ? Icons.search_off_rounded : Icons.receipt_long_rounded,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              narrowing ? 'Nothing matches that search' : 'No transactions yet',
              key: const ValueKey('search-view-empty-title'),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              narrowing
                  ? 'This month has records, but none of them match what you '
                        'typed or filtered to. Clear the search to see them.'
                  : 'Anything you add will show up here.',
              key: const ValueKey('search-view-empty-message'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
