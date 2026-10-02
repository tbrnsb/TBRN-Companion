import 'package:flutter/material.dart';

import 'package:daily_companion/screens/settings_screen.dart';

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
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: routeName),
        builder: (_) => const SettingsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // A gear that opens the screen you are already on. The back arrow in the
    // corner already does the leaving, so the button had exactly one possible
    // effect -- push Settings on top of Settings -- and offered it.
    if (AppGearButton.isSettingsOpen(context)) return const SizedBox.shrink();

    return IconButton(
      key: buttonKey,
      tooltip: 'Settings',
      icon: const Icon(Icons.settings_rounded),
      onPressed: () => open(context),
    );
  }

  /// Whether the current screen is Settings, or one reached from it.
  ///
  /// MATCHED ON THE ROUTE NAME, with a prefix rather than an equality, so a
  /// screen opened from Settings -- Budgets, Categories -- also counts as being
  /// inside it. Comparing route names rather than a flag is what makes this
  /// correct without every screen having to remember to set one: a flag would be
  /// wrong the moment a screen forgot, and the failure is a gear that opens the
  /// screen you are already on.
  static bool isSettingsOpen(BuildContext context) {
    final route = ModalRoute.of<Object?>(context);
    final name = route?.settings.name;
    return name != null && name.startsWith(settingsRoutePrefix);
  }

  /// The prefix every route inside Settings carries.
  static const String settingsRoutePrefix = '/settings';

  /// The route Settings itself pushes.
  static const String routeName = settingsRoutePrefix;
}
