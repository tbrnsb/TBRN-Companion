import 'package:intl/intl.dart';

import 'package:daily_companion/utils/number_style.dart';

class AppFormat {
  AppFormat._();

  /// The number shape in force, set once from the user's choice.
  ///
  /// A STATIC rather than a parameter on every call. `money` has around thirty
  /// call sites spread across screens, widgets and services, and threading a
  /// format choice through all of them means a new argument nobody can forget to
  /// pass -- and a forgotten one is a screen silently disagreeing with every
  /// other screen about how a number is written. The value is set in exactly one
  /// place, when settings load, and read everywhere else.
  ///
  /// Set BEFORE the first frame that draws an amount, which is why `load()` is
  /// awaited in `main()`.
  static NumberStyle numberStyle = NumberStyle.commaDot;

  /// Adopts [style] as [numberStyle] and returns it, for a call site that both
  /// sets and persists.
  static NumberStyle setNumberStyle(NumberStyle style) => numberStyle = style;

  /// Formats [value] with a currency prefix.
  ///
  /// [symbol] is the full prefix including its own trailing space, so the
  /// spacing is decided once by `Currency.symbol` instead of being bolted on
  /// here — `'Rs. '` → `Rs. 1,234.50`, `'$'` → `$1,234.50`, `'€ '` → `€ 1,234.50`.
  /// Appending a space unconditionally produced `Rs.  1,234.50` and
  /// `$ 1,234.50`.
  static String money(double value, {String symbol = 'Rs. '}) {
    return '$symbol${formatWith(numberStyle, value)}';
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

  /// A length of time in the largest unit that carries information.
  ///
  /// Days-aware, because the device showed an average trip of three days as
  /// "72h 0m". That is arithmetically correct and useless to read: nobody thinks
  /// in 72-hour units, and a trailing "0m" is noise on every whole hour.
  ///
  /// Only the units that say something: two days is "2d 3h", not "2d 3h 0m".
  static String duration(double minutes) {
    if (minutes <= 0) return '0m';
    final whole = minutes.round();
    final days = whole ~/ (60 * 24);
    final hours = (whole ~/ 60) % 24;
    final mins = whole % 60;
    if (days > 0) return hours > 0 ? '${days}d ${hours}h' : '${days}d';
    if (hours > 0) return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
    return '${mins}m';
  }

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
