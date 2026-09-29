import 'package:intl/intl.dart';

class AppFormat {
  AppFormat._();

  static final NumberFormat _money = NumberFormat('#,##0.##');

  /// Formats [value] with a currency prefix.
  ///
  /// [symbol] is the full prefix including its own trailing space, so the
  /// spacing is decided once by `Currency.symbol` instead of being bolted on
  /// here — `'Rs. '` → `Rs. 1,234.50`, `'$'` → `$1,234.50`, `'€ '` → `€ 1,234.50`.
  /// Appending a space unconditionally produced `Rs.  1,234.50` and
  /// `$ 1,234.50`.
  static String money(double value, {String symbol = 'Rs. '}) {
    return '$symbol${_money.format(value)}';
  }

  /// Money with an explicit direction: expense negative, income positive.
  static String signedMoney(
    double value, {
    required bool isExpense,
    String symbol = 'Rs. ',
  }) {
    final amount = money(value.abs(), symbol: symbol);
    return isExpense ? '-$amount' : '+$amount';
  }

  static String shortDate(DateTime date) => DateFormat.yMMMd().format(date);

  static String dateTime(DateTime date) =>
      DateFormat.yMMMd().add_jm().format(date);

  static String time(DateTime date) => DateFormat.jm().format(date);

  static String relativeDay(DateTime date) {
    final now = DateTime.now();
    final day = DateTime(date.year, date.month, date.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    final time = DateFormat.jm().format(date);
    if (diff == 0) return 'Today, $time';
    if (diff == 1) return 'Yesterday, $time';
    return '${DateFormat.yMMMd().format(date)}, $time';
  }
}
