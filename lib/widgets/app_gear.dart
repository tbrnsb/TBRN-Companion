import 'package:flutter/material.dart';

import 'package:flutter_application_1/screens/settings_screen.dart';

/// The gear that opens Settings.
///
/// Settings used to be a fifth dock destination, which made it something you
/// browse to rather than something you open: a permanent slot on the bar
/// competing with Pack and Journey for attention, on a screen that is visited
/// rarely and changed even less often. It is a drawer, not a destination, so it
/// moves to the app bar.
///
/// One widget, not four copies: every screen's `AppBar.actions` uses this, so
/// there is a single place that decides the icon, the tooltip, the route and
/// the key a test looks for.
class AppGearButton extends StatelessWidget {
  const AppGearButton({super.key});

  /// Key for tests. `find.byIcon` would also match the gear drawn inside any
  /// dialog, and `find.bySemanticsLabel` does not resolve reliably inside a
  /// pushed route, so the widget carries an explicit key.
  static const Key buttonKey = ValueKey('settings-gear');

  /// Pushes Settings onto the current route.
  ///
  /// A push rather than a swap, so the back gesture returns to whatever tab the
  /// user was on. Deep links, CSV export, the wipe and demo data all keep
  /// working exactly as before — only the way in changed.
  static Future<void> open(BuildContext context) {
    return Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: buttonKey,
      tooltip: 'Settings',
      icon: const Icon(Icons.settings_rounded),
      onPressed: () => open(context),
    );
  }
}
