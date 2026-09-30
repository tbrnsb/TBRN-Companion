import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/utils/format.dart';

/// The search field, its clear button, and the door to the amount/category
/// filters.
///
/// Lives in the list rather than behind an app-bar icon so it is visible the
/// moment the screen opens. A search you have to discover is a search nobody
/// uses, and the one row of space it costs is worth more than the clutter a
/// collapsed affordance would save.
class TransactionSearchBar extends StatefulWidget {
  const TransactionSearchBar({
    super.key,
    required this.query,
    required this.onQueryChanged,
    required this.onOpenFilters,
  });

  final TransactionSearchQuery query;
  final ValueChanged<TransactionSearchQuery> onQueryChanged;
  final VoidCallback onOpenFilters;

  @override
  State<TransactionSearchBar> createState() => _TransactionSearchBarState();
}

class _TransactionSearchBarState extends State<TransactionSearchBar> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.query.text,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TransactionSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Two-way: the screen can change the query (the filter sheet rewrites the
    // text too, and "clear" empties it), and a controller that ignores that
    // would show the old words until the field happened to be refocused.
    if (widget.query.text != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.query.text,
        selection: TextSelection.collapsed(offset: widget.query.text.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final extraCriteria =
        widget.query.activeCriteria -
        (widget.query.text.trim().isEmpty ? 0 : 1);

    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const ValueKey('transaction-search-field'),
            controller: _controller,
            textInputAction: TextInputAction.search,
            onChanged: (value) =>
                widget.onQueryChanged(widget.query.copyWith(text: value)),
            decoration: InputDecoration(
              hintText: 'Search this month',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              isDense: true,
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      key: const ValueKey('search-clear-text'),
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _controller.clear();
                        widget.onQueryChanged(widget.query.copyWith(text: ''));
                      },
                    ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        // The badge counts the criteria the FIELD cannot show, so a user who has
        // narrowed by amount or category and then closed the sheet can still see
        // that something is hiding rows.
        //
        // Deliberately the only control beside the field. A third one — a
        // "clear everything" — put the row one control past what a 360dp phone
        // holds, so "clear all" lives on the summary line below instead, where
        // there is room to also say WHAT is being cleared.
        Badge(
          isLabelVisible: extraCriteria > 0,
          label: Text('$extraCriteria'),
          child: IconButton(
            key: const ValueKey('search-open-filters'),
            tooltip: 'Amount and category filters',
            onPressed: () {
              HapticFeedback.selectionClick();
              widget.onOpenFilters();
            },
            style: IconButton.styleFrom(
              backgroundColor: extraCriteria > 0
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHigh,
              foregroundColor: extraCriteria > 0
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
            ),
            icon: const Icon(Icons.tune_rounded),
          ),
        ),
      ],
    );
  }
}

/// "2 categories · Rs 100 to Rs 900" and a way to drop all of it.
///
/// The counterpart to [TransactionSearchBar]: when something IS narrowed, the
/// screen says so in words and offers the undo. A filter with no visible state
/// is indistinguishable from data that has gone missing.
class ActiveSearchSummary extends StatelessWidget {
  const ActiveSearchSummary({
    super.key,
    required this.query,
    required this.resultCount,
    required this.onClear,
    this.currencySymbol = 'Rs. ',
  });

  final TransactionSearchQuery query;
  final int resultCount;
  final VoidCallback onClear;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final parts = <String>[];

    final needle = query.text.trim();
    if (needle.isNotEmpty) parts.add('"$needle"');
    if (query.minAmount != null || query.maxAmount != null) {
      final lo = query.minAmount;
      final hi = query.maxAmount;
      if (lo != null && hi != null) {
        parts.add('${_money(lo)} to ${_money(hi)}');
      } else if (lo != null) {
        parts.add('over ${_money(lo)}');
      } else {
        parts.add('under ${_money(hi!)}');
      }
    }
    if (query.categories.isNotEmpty) {
      parts.add(
        query.categories.length == 1
            ? '1 category'
            : '${query.categories.length} categories',
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${parts.join(' · ')} — $resultCount match'
              '${resultCount == 1 ? '' : 'es'}',
              key: const ValueKey('search-summary'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          TextButton(
            key: const ValueKey('search-clear-all'),
            onPressed: onClear,
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  String _money(double value) => AppFormat.money(value, symbol: currencySymbol);
}
