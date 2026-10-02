import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/theme/app_theme.dart';

/// Picked from the "Other" screen: either a named type, or a custom name.
class OtherCategoryChoice {
  const OtherCategoryChoice.other(this.customName)
    : category = ExpenseCategory.other;

  /// A named type other than `other` — the ones revealed by the dropdown.
  const OtherCategoryChoice.named(this.category) : customName = null;

  final ExpenseCategory category;
  final String? customName;
}

/// Picks what an expense under "Other" actually is.
///
/// Reached from the add-expense sheet instead of an inline dropdown. The
/// previous control was a `DropdownButtonFormField` wedged under the category
/// chips: it had no icons, so it did not read as part of the same list, and it
/// hid the custom-name entry behind a plus button in the corner.
///
/// The screen is one flat list in the same (icon, name) hierarchy as every
/// other category list, with "Add a custom category" as the last row — the
/// same shape as the settings list rather than a different kind of control.
class OtherCategoryScreen extends StatefulWidget {
  const OtherCategoryScreen({
    super.key,
    this.currentCustomName,
    this.savedCustomNames = const [],
  });

  /// The custom name already chosen, so the list can show it as selected.
  final String? currentCustomName;

  /// Names the user has saved before, offered as ready-made choices.
  final List<String> savedCustomNames;

  /// Free-text suggestions from the provider, used to seed new names.

  /// Opens the screen and returns the choice, or null if dismissed.
  static Future<OtherCategoryChoice?> show(
    BuildContext context, {
    String? currentCustomName,
    List<String> savedCustomNames = const [],
  }) {
    return Navigator.of(context).push<OtherCategoryChoice>(
      MaterialPageRoute(
        builder: (_) => OtherCategoryScreen(
          currentCustomName: currentCustomName,
          savedCustomNames: savedCustomNames,
        ),
      ),
    );
  }

  @override
  State<OtherCategoryScreen> createState() => _OtherCategoryScreenState();
}

/// How many suggested types are shown before the list is expanded.
const _collapsedCount = 4;

class _OtherCategoryScreenState extends State<OtherCategoryScreen> {
  /// Which group is expanded. The extra types are behind a dropdown because
  /// nine rows plus a custom-name list is too long for a phone, but the choice
  /// is still one flat list — the same (icon, name) rows as everywhere else.
  bool _showMore = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    // Only names the user genuinely saved. This list used to be merged with a
    // `suggestedNames` input, and the provider filled that input with the nine
    // built-in category names — so Food, Travel and Gear appeared under "Your
    // categories" wearing the generic custom sparkle icon, as though the user
    // had created them. There is deliberately no suggestion input any more: the
    // section stays empty until the user names something themselves, which is
    // the only honest reading of the heading.
    final customNames = <String>{
      ...widget.savedCustomNames,
      if (widget.currentCustomName != null) widget.currentCustomName!,
    }.where((n) => n.trim().isNotEmpty).toList();
    final savedLower = customNames.map((n) => n.toLowerCase()).toSet();

    // The suggested types, which are everything the main nine do not already
    // cover. The main nine used to be listed here again, which made this screen
    // a duplicate of the chip row above it and offered the user nothing new.
    //
    // Anything the user has already saved is dropped: "Coffee" appearing once
    // as a suggested type and again under "Your categories" is the same
    // duplication this screen was reported for, just moved.
    final namedTypes = CategoryRegistry.suggestedExpenseTypes()
        .where((m) => !savedLower.contains(m.name.toLowerCase()))
        .toList();
    // Always the first few, collapsed or not. This used to be
    // `_showMore ? namedTypes : namedTypes.take(4)`, so expanding made
    // `primary` the whole list while `overflow` still held its last four — the
    // screen then rendered those four a second time under the toggle, which is
    // where the duplicated Housing/Shopping/Health/Utilities rows came from.
    final primary = namedTypes.take(_collapsedCount).toList();
    final overflow = namedTypes.skip(_collapsedCount).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('What kind of other?')),
      body: ListView(
        padding: AppSpacing.screenPadding,
        children: [
          Text(
            'Pick the closest match, or name it yourself.',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final meta in primary)
            _CategoryRow(
              meta: meta,
              selected: false,
              onTap: () =>
                  Navigator.pop(context, OtherCategoryChoice.other(meta.name)),
            ),
          // The toggle stays put once expanded. It used to sit inside
          // `overflow.isNotEmpty`, and `overflow` is empty while expanded, so
          // expanding removed the only control that could collapse it again.
          if (overflow.isNotEmpty || _showMore) ...[
            const SizedBox(height: AppSpacing.xs),
            _MoreTypesRow(
              hiddenCount: overflow.length,
              expanded: _showMore,
              onToggle: () => setState(() => _showMore = !_showMore),
            ),
            if (_showMore) ...[
              const SizedBox(height: AppSpacing.xs),
              for (final meta in overflow)
                _CategoryRow(
                  meta: meta,
                  selected: false,
                  onTap: () => Navigator.pop(
                    context,
                    OtherCategoryChoice.other(meta.name),
                  ),
                ),
            ],
          ],
          const SizedBox(height: AppSpacing.lg),
          const Divider(),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Your categories',
            style: textTheme.titleSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (customNames.isEmpty)
            Text(
              'None saved yet.',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (final name in customNames)
              _CategoryRow(
                meta: CategoryRegistry.metaFor(
                  ExpenseCategory.other,
                  customName: name,
                ),
                selected:
                    name.toLowerCase() ==
                    widget.currentCustomName?.toLowerCase(),
                onTap: () =>
                    Navigator.pop(context, OtherCategoryChoice.other(name)),
              ),
          const SizedBox(height: AppSpacing.sm),
          // The custom entry is a row like any other, at the bottom of the
          // list, rather than a button hidden in the corner of a field.
          _CategoryRow(
            meta: const CategoryMeta(
              id: 'add-custom',
              name: 'Add a custom category',
              icon: Icons.add_circle_outline_rounded,
              color: Color(0xFF4B392F),
              popularity: 99,
            ),
            selected: false,
            onTap: () async {
              final name = await _promptForName(context);
              // Nothing typed is the same as cancelling: there is no name to
              // file the expense under, so stay on this screen.
              if (name == null || !context.mounted) return;
              // Returns immediately. Persisting the name is the caller's job:
              // awaiting a Hive write here would leave the user watching a
              // screen that does nothing while the disk catches up, and a failed
              // write would strand them on it.
              Navigator.pop(context, OtherCategoryChoice.other(name));
            },
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  Future<String?> _promptForName(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => const _NameCategoryDialog(),
    );

    // A blank name is the same as cancelling: there is nothing to file the
    // expense under.
    if (result == null || result.trim().isEmpty) return null;
    return result.trim();
  }
}

/// Asks for a name for a custom category.
///
/// Its own StatefulWidget so it owns the [TextEditingController]. Disposing the
/// controller in the caller, right after `showDialog` returns, kills it while
/// the dialog is still animating out and the TextField rebuilds — which throws
/// "A TextEditingController was used after being disposed".
class _NameCategoryDialog extends StatefulWidget {
  const _NameCategoryDialog();

  @override
  State<_NameCategoryDialog> createState() => _NameCategoryDialogState();
}

class _NameCategoryDialogState extends State<_NameCategoryDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Name this category'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          hintText: 'e.g. Coffee, Tickets, Groceries',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

/// One row in the (icon, name) hierarchy every category list uses.
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.meta,
    required this.selected,
    required this.onTap,
  });

  final CategoryMeta meta;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: BoxDecoration(
          color: meta.color.withValues(alpha: 0.16),
          borderRadius: AppRadii.smallRadius,
        ),
        child: Icon(meta.icon, size: 20, color: meta.color),
      ),
      title: Text(
        meta.name,
        style: textTheme.bodyLarge?.copyWith(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      trailing: selected
          ? Icon(Icons.check_rounded, color: colorScheme.primary)
          : const Icon(Icons.chevron_right_rounded, color: AppColors.khaki),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
    );
  }
}

/// The dropdown row that reveals the remaining named types.
class _MoreTypesRow extends StatelessWidget {
  const _MoreTypesRow({
    required this.hiddenCount,
    required this.expanded,
    required this.onToggle,
  });

  final int hiddenCount;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: AppRadii.smallRadius,
        ),
        child: Icon(Icons.more_horiz_rounded, size: 20),
      ),
      title: Text(
        expanded
            ? 'Fewer types'
            : '$hiddenCount more type${hiddenCount == 1 ? '' : 's'}',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      trailing: AnimatedRotation(
        turns: expanded ? 0.5 : 0,
        duration: AppMotion.fast,
        curve: Curves.easeOut,
        child: Icon(Icons.expand_more_rounded, color: colorScheme.primary),
      ),
      onTap: onToggle,
    );
  }
}
