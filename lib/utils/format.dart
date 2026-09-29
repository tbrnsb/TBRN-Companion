import 'package:intl/intl.dart';

class AppFormat {
  AppFormat._();

  static final NumberFormat _money = NumberFormat('#,##0.##');

  static String money(double value, {String currency = 'Rs.'}) {
    return '$currency ${_money.format(value)}';
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
