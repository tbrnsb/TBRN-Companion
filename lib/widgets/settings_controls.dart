import 'package:flutter/material.dart';

import 'package:daily_companion/theme/app_theme.dart';

/// A settings row that opens a sheet of choices — a dropdown, in the sense
/// people mean when they ask for one.
///
/// WHY A SHEET AND NOT AN INLINE EXPANDED LIST. The screen this replaced put
/// every option on the page: four theme families with a tagline and a swatch
/// strip each, then a variant control, then three currency rows. That is a
/// screen whose length is decided by how many options it has, so adding a
/// currency pushed the data section further down and the thing most people
/// change most often — how their money looks — was below a theme gallery. One
/// row per setting, whatever the number of options, and the page stops being a
/// list of the implementation.
///
/// WHY A SHEET AND NOT A REAL `DropdownButton`. A dropdown's menu is sized to
/// its widest item and laid out in one column, so an option with a swatch strip
/// or a two-line label does not fit, and a native menu cannot show a live
/// preview of a theme. The sheet is the same gesture and the same affordance
/// with room to put the option on more than one line.
class SettingsOptionRow<T> extends StatelessWidget {
  const SettingsOptionRow({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onSelected,
    this.supporting,
    this.icon,
    this.titleOf,
    this.subtitleOf,
  });

  /// What this setting is called, in the section's own terms.
  final String label;

  /// The option currently in force, shown on the row.
  final String value;

  /// Everything that can be chosen.
  final List<T> options;

  /// Called with the chosen option. The caller persists it.
  final void Function(T) onSelected;

  /// A line under the label, so a section header can say what the group is for.
  final String? supporting;

  final IconData? icon;

  /// The headline for one option in the sheet.
  final String Function(T)? titleOf;

  /// The second line for one option, when it needs one.
  final String? Function(T)? subtitleOf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      button: true,
      label: '$label, currently $value',
      child: InkWell(
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(AppRadii.medium),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            // TOP-ALIGNED, not centred. A `Row` centres its children by default,
            // so on a row whose supporting text wrapped to three lines the icon
            // floated in the middle of the row, level with the second line of
            // the label rather than with the label itself. Every row in a list
            // wants its glyph against the FIRST line of its text.
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                // Nudged down a hair so it sits on the label's optical centre
                // rather than its box top.
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(icon, size: 20, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // THE LABEL NEVER WRAPS, and it is the wider of the two
                    // columns.
                    //
                    // Both the label and the value are in a flex, and a value
                    // like "15 built in, 0 yours" is long enough that a 50/50
                    // split left "Categories" a column so narrow it broke over
                    // two lines -- which is the row being taller than its
                    // neighbours, again. The label is what the row IS, so it
                    // gets the larger share and never wraps; the value is the
                    // detail, so it is the one that ellipsises.
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge,
                    ),
                    if (supporting != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          supporting!,
                          // TWO LINES AT MOST, and ellipsised beyond that. These
                          // lines are there to say what a setting is FOR, and a
                          // three-line explanation under a one-word label makes
                          // the row taller than the thing it is describing. The
                          // ones that need more room say it in a group's
                          // footnote instead, below the card.
                          // ONE LINE. A caption that wraps is what made
                          // these rows taller than the rows above them, so the
                          // Settings page had three different row heights in a
                          // list that is otherwise uniform. It ellipsises, which
                          // is the right failure: a trimmed caption still reads,
                          // and a two-line one changes the shape of the page.
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.25,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // The value in the accent, so the row reads as "this is what you
              // have" rather than as another label.
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.expand_more_rounded,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final chosen = await showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _OptionSheet<T>(
        label: label,
        options: options,
        selected: options.firstWhere(
          (o) => (titleOf?.call(o) ?? '$o') == value,
          orElse: () => options.first,
        ),
        titleOf: titleOf,
        subtitleOf: subtitleOf,
      ),
    );
    if (chosen != null) onSelected(chosen);
  }
}

/// The list of choices, at the height its content wants.
class _OptionSheet<T> extends StatelessWidget {
  const _OptionSheet({
    required this.label,
    required this.options,
    required this.selected,
    this.titleOf,
    this.subtitleOf,
  });

  final String label;
  final List<T> options;
  final T selected;
  final String Function(T)? titleOf;
  final String? Function(T)? subtitleOf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SafeArea(
      child: ConstrainedBox(
        // Tall enough for a list, never taller than the screen, and scrolling
        // past that. A fixed height would either clip a long list or leave a
        // short one floating in an empty sheet.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, i) {
                  final option = options[i];
                  final title = titleOf?.call(option) ?? '$option';
                  final subtitle = subtitleOf?.call(option);
                  final isSelected =
                      title == (titleOf?.call(selected) ?? '$selected');
                  return ListTile(
                    key: ValueKey('settings-option-$title'),
                    title: Text(title),
                    subtitle: subtitle == null ? null : Text(subtitle),
                    trailing: isSelected
                        ? Icon(Icons.check_rounded, color: scheme.primary)
                        : null,
                    selected: isSelected,
                    onTap: () => Navigator.of(context).pop(option),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
        ),
      ),
    );
  }
}

/// A settings row that opens a SCREEN — not a sheet.
///
/// For the two settings that are not a choice from a list: categories and
/// budgets both have their own screen's worth of behaviour, and putting them
/// behind a chevron says "there is more here" where a dropdown would say "pick
/// one of these". A chevron and a sheet are different promises and the row has
/// to keep them apart.
class SettingsNavRow extends StatelessWidget {
  const SettingsNavRow({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.supporting,
    this.icon,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final String? supporting;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      button: true,
      label: '$label, $value',
      child: InkWell(
        key: ValueKey('settings-nav-$label'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(icon, size: 20, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // THE LABEL NEVER WRAPS, and it is the wider of the two
                    // columns.
                    //
                    // Both the label and the value are in a flex, and a value
                    // like "15 built in, 0 yours" is long enough that a 50/50
                    // split left "Categories" a column so narrow it broke over
                    // two lines -- which is the row being taller than its
                    // neighbours, again. The label is what the row IS, so it
                    // gets the larger share and never wraps; the value is the
                    // detail, so it is the one that ellipsises.
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge,
                    ),
                    if (supporting != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          supporting!,
                          // ONE LINE. A caption that wraps is what made
                          // these rows taller than the rows above them, so the
                          // Settings page had three different row heights in a
                          // list that is otherwise uniform. It ellipsises, which
                          // is the right failure: a trimmed caption still reads,
                          // and a two-line one changes the shape of the page.
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.25,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One labelled group of rows, on the raised tier.
///
/// A card, not a bare heading plus loose rows: the groups are what make the page
/// readable as a set of related things rather than as a queue, and the card edge
/// is what shows where one ends.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.title,
    required this.children,
    this.footnote,
  });

  final String title;
  final List<Widget> children;

  /// A line under the group, for the consequence of the setting rather than the
  /// setting itself.
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            bottom: AppSpacing.xs,
          ),
          child: Text(
            title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
        ),
        AppSurface(
          tier: AppSurfaceTier.raised,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: AppSpacing.md),
                children[i],
              ],
            ],
          ),
        ),
        if (footnote != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs,
              AppSpacing.xs,
              AppSpacing.xs,
              0,
            ),
            child: Text(
              footnote!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
