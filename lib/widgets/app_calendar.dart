import 'package:flutter/material.dart';

import 'package:flutter_application_1/screens/calendar_screen.dart';

/// The calendar that opens the month view.
///
/// GLOBAL, like the gear. It used to be a card halfway down the Journey tab,
/// which made "what was on the 12th?" answerable only from one screen that had
/// nothing to do with it — and the four tabs are four views of the same month, so
/// the control that moves between days belongs beside the one that opens
/// Settings, on every one of them.
///
/// One widget rather than four copies, so there is a single place that decides
/// the icon, the tooltip, the route and the key a test looks for.
class AppCalendarButton extends StatelessWidget {
  const AppCalendarButton({super.key});

  /// Key for tests. NEVER `find.byIcon`: the calendar screen is full of chevrons
  /// and date glyphs, and the icon is also drawn inside it.
  static const Key buttonKey = CalendarScreen.calendarIconKey;

  /// Pushes the calendar onto the current route, so the back gesture returns to
  /// whatever tab the user was on.
  static Future<void> open(BuildContext context) =>
      CalendarScreen.open(context);

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: buttonKey,
      tooltip: 'Calendar',
      icon: const Icon(Icons.calendar_month_rounded),
      onPressed: () => open(context),
    );
  }
}
