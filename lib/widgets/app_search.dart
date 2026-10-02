import 'package:flutter/material.dart';

import 'package:daily_companion/screens/transactions/transaction_search_view.dart';

/// The search affordance for an app bar.
///
/// The same shape as [AppGearButton] and for the same reasons: it carries an
/// explicit key, because `find.byIcon` also matches a search icon drawn inside
/// any dialog and a search VIEW is full of them, and `find.bySemanticsLabel`
/// does not resolve reliably inside a pushed route.
///
/// A push rather than a swap, so the back gesture returns to whatever tab the
/// user was on, and the search field is left behind rather than scrolled away.
class AppSearchButton extends StatelessWidget {
  const AppSearchButton({super.key});

  /// Key for tests.
  static const Key buttonKey = ValueKey('app-search-button');

  /// Pushes the search view onto the current route.
  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const TransactionSearchView()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: buttonKey,
      tooltip: 'Search',
      icon: const Icon(Icons.search_rounded),
      onPressed: () => open(context),
    );
  }
}
