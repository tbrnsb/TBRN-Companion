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
            // CENTRED, with the glyph and the label column pinned back to the
            // top by their own Aligns below.
            //
            // What this fixes: the value sat level with the row's TITLE on a row
            // that is two lines tall, so it read as part of the title -- dead
            // space under it, and nothing beside the caption. Centred, it sits on
            // the row's own axis instead, which is what makes a column of six
            // values look like a column.
            //
            // It was `start` for everything, which is what kept the icon against
            // the FIRST line of the label. A Row cannot centre one child and
            // top-align another, so the Row centres and those two are pinned back.
            //
            // Centring the value ALONE, inside a `start` Row, does nothing: such a
            // Row hands its children a LOOSE height, so a `Center` around the
            // value has no extra space to centre within and the value does not
            // move. That was built, measured on a device, and shifted by zero
            // pixels -- which is why this is at the Row and not on the Text.
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (icon != null) ...[
                // Against the FIRST line of the label, as before. The Row now
                // centres, so the glyph is pinned back up here, and the nudge
                // keeps it on the label's optical centre rather than its box top.
                Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(icon, size: 20, color: scheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                flex: 2,
                // The Row's `center` hands this a TIGHT height -- the real row
                // height -- so the value measures against what the row actually
                // is rather than against a two-line guess. `mainAxisSize.min`
                // keeps the Column to its own two lines, which is the whole point:
                // the label sits at the TOP of the row while the value sits in
                // the MIDDLE of it.
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
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
            // CENTRED, for the same reason and with the same structure as the
            // option row above: the value centres on the row's axis, the label
            // and glyph are pinned back to the top. A `start` Row hands its
            // children a loose height, so centring the value on its own would do
            // nothing at all.
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(icon, size: 20, color: scheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
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

/// A settings row that is a BINARY TOGGLE — on or off, no third state and no
/// sheet to pick one from.
///
/// WHY IT IS NOT A MODE OF [SettingsOptionRow]. That row needs a list of
/// options and opens a sheet to choose between them; a switch is two states,
/// and a sheet in front of a decision that needs no deliberation is a modal for
/// its own sake. The GEOMETRY is shared on purpose, though — the same
/// [AppSpacing.md] inset, the same label-over-caption stack — because the thing
/// that made the standalone `SwitchListTile` it replaced look wrong on the
/// place screen was precisely that it did not share it. A ListTile brings its
/// own inset and its own idea of where a trailing control goes, and on a card
/// that already had padding the two ideas disagreed with every other row in the
/// app by 16 pixels.
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.supporting,
    this.icon,
  });

  /// What this setting is called, in the section's own terms.
  final String label;

  /// Whether it is on.
  final bool value;

  /// Called with the new state. The caller persists it.
  final ValueChanged<bool> onChanged;

  /// A line under the label, so the row can say what its state MEANS — how far
  /// the arrival radius reaches, or that a feature is off here.
  final String? supporting;

  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // ONE announcement, label and state together, the way [SettingsOptionRow]
    // announces "label, currently value". A switch whose semantics are only the
    // bare role and a position ("switch, on") says what state the row is in
    // without ever saying WHICH setting that is about.
    return Semantics(
      container: true,
      button: true,
      toggled: value,
      label: '$label, currently ${value ? 'on' : 'off'}',
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(AppRadii.medium),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            // START, where the option and nav rows centre.
            //
            // The option row centres and pins its label column and glyph back
            // to the top with Aligns, so that its VALUE can sit on the row's
            // axis. Measured, those Aligns do nothing in the places the family
            // is actually used: a settings list is a ListView, so the Row's
            // cross extent is unbounded, and an Align with no room to expand
            // just shrink-wraps — what lands on the first line is the label
            // column, because it is the tallest child, and the value and the
            // chevron end up CENTRED on the block.
            //
            // Centred is right for a value, which is a fact about the whole
            // row. It is wrong for a SWITCH, which has to read as attached to
            // the label it switches: a toggle floating between a two-line label
            // and its caption belongs to neither. `start` puts the label column
            // and the switch on the same first line, with no Aligns to explain
            // and no geometry to re-derive — at this row's real height it is
            // also the half-pixel answer, since the Switch is as tall as the
            // label block, but it is the one that stays correct if the block
            // ever grows.
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                // ON THE FIRST LINE, with the nudge that keeps a 20px glyph on
                // the label's optical centre rather than its box top — the same
                // nudge the option row uses.
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(icon, size: 20, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                flex: 2,
                // THE LABEL NEVER WRAPS, and it is the wider of the two
                // columns, for the same reason as in the option row: the label
                // is what the row IS, so it gets the larger share and the
                // caption is the one that ellipsises.
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                          // ONE LINE, and ellipsised beyond it, so this row
                          // never ends up taller than the rows around it.
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
              // A real [Switch], not a tick or a chevron: the control's whole
              // affordance is that you can see and hit it, and a bespoke one
              // would be a second switch in the app to learn.
              Switch(value: value, onChanged: onChanged),
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
