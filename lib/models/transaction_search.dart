import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

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
    if (needle.isNotEmpty && !_matchesText(transaction, needle)) {
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

  /// The free-text search, over every field the result row SHOWS.
  ///
  /// It used to check [Transaction.description] and nothing else, so typing a
  /// category name returned nothing while the list underneath plainly displayed
  /// that category on every matching row. The search was not broken, it was
  /// searching less than it was showing — and the user's evidence that it was
  /// broken was the row directly below the field.
  ///
  /// Fields searched are exactly the ones a result row displays: the
  /// description, the category AS LABELLED, the amount, and the date. Anything
  /// not displayed is not searched, because a hit the user cannot see is a
  /// result they cannot explain.
  bool _matchesText(Transaction transaction, String needle) {
    // The CATEGORY AS LABELLED, not the enum name. `effectiveCategoryName` is
    // what the row shows, and it differs from `category.name` for a custom
    // category and for a raw stored id, so searching the enum would miss the
    // exact word the user read off the screen.
    if (transaction.effectiveCategoryName.toLowerCase().contains(needle)) {
      return true;
    }
    if (transaction.description.toLowerCase().contains(needle)) return true;
    // An amount, so "450" finds the row showing Rs 450. Matched against the
    // digits of the amount rather than the formatted string, so it does not
    // depend on the currency symbol or on thousands separators.
    if (_digitsOnly(transaction.amount.toString()).contains(needle)) {
      if (needle.isNotEmpty && _isAllDigits(needle)) return true;
    }
    // The date as it is shown, and as digits, so both "4 oct" and "10/04"
    // reach the row.
    final formatted = DateFormat.yMMMd().format(transaction.date).toLowerCase();
    if (formatted.contains(needle)) return true;
    final iso = DateFormat('yyyy-MM-dd').format(transaction.date);
    if (iso.contains(needle)) return true;
    return false;
  }

  /// Digits only, so a formatted amount and a typed number compare alike.
  static String _digitsOnly(String value) =>
      value.replaceAll(RegExp(r'[^0-9]'), '');

  static bool _isAllDigits(String value) => RegExp(r'^[0-9]+$').hasMatch(value);

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

/// What the day picker means.
///
/// A SENTINEL, not null. `showModalBottomSheet` resolves to null both when the
/// user taps "Whole month" and when the sheet is swiped away, and the two are
/// not the same intention: one clears the day filter and one changes nothing at
/// all. Treating a dismiss as "clear the filter" means selecting a day and then
/// dismissing the sheet changes the view without being asked to, which is the
/// wrong result on a very common gesture.
enum DayPickResult {
  /// The sheet was swiped away, or the back button pressed. CHANGE NOTHING.
  dismissed,

  /// "Whole month": drop the day filter.
  wholeMonth,

  /// A specific day was tapped.
  day,
}

/// The picker's outcome, with the day when there is one.
///
/// Three states rather than a nullable date, because the information the caller
/// needs is not "is there a date" but "what did the user MEAN".
class DayPick {
  const DayPick._(this.result, this.day);

  const DayPick.dismissed() : this._(DayPickResult.dismissed, null);

  const DayPick.wholeMonth() : this._(DayPickResult.wholeMonth, null);

  const DayPick.day(DateTime value) : this._(DayPickResult.day, value);

  final DayPickResult result;

  /// Non-null only when [result] is [DayPickResult.day].
  final DateTime? day;

  bool get isDismissed => result == DayPickResult.dismissed;
}
