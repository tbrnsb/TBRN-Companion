import 'package:flutter/foundation.dart';

import 'expense_category_meta.dart';
import 'transaction.dart';

/// The three things a transaction search can be narrowed by.
///
/// A value, not a widget: the same query decides what the screen shows and what
/// a test asserts about it, so the two cannot disagree. Immutable, so the
/// provider can hold one and compare rather than mutate a list in place.
@immutable
class TransactionSearchQuery {
  const TransactionSearchQuery({
    this.text = '',
    this.minAmount,
    this.maxAmount,
    this.categories = const <String>{},
  });

  /// Nothing typed, no bound set, no category picked.
  static const TransactionSearchQuery none = TransactionSearchQuery();

  /// Free text, matched against the description.
  final String text;

  /// Inclusive lower bound on the amount, or null for no lower bound.
  final double? minAmount;

  /// Inclusive upper bound on the amount, or null for no upper bound.
  final double? maxAmount;

  /// Category ids the user picked. An EMPTY set means "no category filter", not
  /// "match nothing" — otherwise opening the search and picking nothing would
  /// silently return zero results, which is the opposite of what a user who has
  /// not touched the category filter expects.
  final Set<String> categories;

  /// True when nothing has been narrowed, so the caller can skip the work and
  /// show the ordinary month.
  bool get isEmpty =>
      text.trim().isEmpty &&
      minAmount == null &&
      maxAmount == null &&
      categories.isEmpty;

  bool get isNotEmpty => !isEmpty;

  /// How many of the three criteria are in play. Drives the badge on the
  /// filters button, so a user who cannot see the sheet still knows something is
  /// hiding rows from them.
  int get activeCriteria {
    var n = 0;
    if (text.trim().isNotEmpty) n++;
    if (minAmount != null || maxAmount != null) n++;
    if (categories.isNotEmpty) n++;
    return n;
  }

  /// Whether [transaction] satisfies every criterion in play.
  ///
  /// Criteria are ANDed. A user who types a word and picks a category is
  /// asking for both, and offering either would be a filter they did not ask
  /// for.
  bool matches(Transaction transaction) {
    final needle = text.trim().toLowerCase();
    if (needle.isNotEmpty &&
        !transaction.description.toLowerCase().contains(needle)) {
      return false;
    }
    if (minAmount != null && transaction.amount < minAmount!) return false;
    if (maxAmount != null && transaction.amount > maxAmount!) return false;
    if (categories.isNotEmpty) {
      // Matched on the RESOLVED category id rather than the enum name. An
      // `other` row filed under a custom name has a different id from every
      // built-in category, so filtering on the enum would either drop those rows
      // or lump them in with a category the user never picked.
      if (!categories.contains(transaction.categoryMeta.id)) return false;
    }
    return true;
  }

  TransactionSearchQuery copyWith({
    String? text,
    double? minAmount,
    double? maxAmount,
    Set<String>? categories,
    bool clearMin = false,
    bool clearMax = false,
  }) {
    return TransactionSearchQuery(
      text: text ?? this.text,
      minAmount: clearMin ? null : (minAmount ?? this.minAmount),
      maxAmount: clearMax ? null : (maxAmount ?? this.maxAmount),
      categories: categories ?? this.categories,
    );
  }

  TransactionSearchQuery cleared() => const TransactionSearchQuery(text: '');

  @override
  bool operator ==(Object other) =>
      other is TransactionSearchQuery &&
      other.text == text &&
      other.minAmount == minAmount &&
      other.maxAmount == maxAmount &&
      setEquals(other.categories, categories);

  @override
  int get hashCode => Object.hash(
    text,
    minAmount,
    maxAmount,
    Object.hashAllUnordered(categories),
  );
}

/// A category offered in the search's category filter.
///
/// Built from the registry rather than hardcoded, so a category added later
/// appears here without touching this file.
class SearchCategoryOption {
  const SearchCategoryOption({required this.id, required this.label});

  final String id;
  final String label;
}

/// Every category a search can filter on: the nine expense categories, the
/// suggested types, and the income categories.
///
/// The expense ids are the registry's own, so a row filed under a suggested type
/// ("Coffee") and a row filed under a built-in ("Food") are separately
/// selectable — they are separately visible in the breakdown donut and so should
/// be separately findable.
List<SearchCategoryOption> searchCategoryOptions() {
  final options = <SearchCategoryOption>[
    for (final meta in CategoryRegistry.expenseCategories())
      SearchCategoryOption(id: meta.id, label: meta.name),
  ];
  return List.unmodifiable(options);
}
