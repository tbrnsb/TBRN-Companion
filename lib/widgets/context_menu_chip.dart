import 'package:flutter/material.dart';

import 'package:daily_companion/theme/app_theme.dart';

/// A chip that opens a menu of related choices — a place, a trip, a payer.
///
/// SHARED BY BOTH add sheets, because it used to be private to the expense one.
/// That is how income ended up with no place chip at all: the control was not
/// missing, it was just unreachable from the other sheet. A rule one direction
/// can reach and the other cannot is a rule that will drift, so the control lives
/// somewhere both can use it.
class ContextMenuChip<T> extends StatelessWidget {
  const ContextMenuChip({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final IconData icon;

  /// The placeholder shown when nothing is chosen yet.
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T> onChanged;

  /// Widest a context chip is allowed to become.
  ///
  /// [DropdownMenu] sizes itself to its longest entry, so a long journey or
  /// place title made the chip claim the whole width available inside the
  /// sheet (measured at 312dp on a 360dp phone) and pushed its siblings onto
  /// their own lines. The chip caps itself instead.
  static const double maxChipWidth = 220;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: maxChipWidth),
      child: DropdownMenu<T>(
        initialSelection: value,
        onSelected: (v) => onChanged(v as T),
        dropdownMenuEntries: items
            .map(
              (item) => DropdownMenuEntry<T>(
                value: item.value as T,
                label: (item.child as Text).data ?? '',
              ),
            )
            .toList(),
        // Without a cap the selected value is drawn at its natural width,
        // which is what let the menu claim the whole row.
        maxLines: 1,
        inputDecorationTheme: const InputDecorationTheme(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 0,
          ),
        ),
        leadingIcon: Icon(icon, size: 18),
        hintText: label,
        textStyle: Theme.of(context).textTheme.labelLarge,
        menuStyle: MenuStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppRadii.smallRadius),
          ),
          // The open menu gets the same cap, so a long entry scrolls inside a
          // popup rather than producing a popup wider than the screen.
          maximumSize: WidgetStatePropertyAll(
            const Size(maxChipWidth, double.infinity),
          ),
        ),
      ),
    );
  }
}
