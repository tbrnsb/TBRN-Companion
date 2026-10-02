import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/providers/transaction_provider.dart';
import 'package:daily_companion/services/storage_service.dart';
import 'package:daily_companion/theme/app_theme.dart';

/// Add, rename, recolour and re-kind the user's own categories.
///
/// ITS OWN SCREEN, not a dropdown, because there is no list to choose from here:
/// a category is not a setting you pick, it is a thing you create. A sheet
/// behind a row would say "choose one of these" and then open a blank form, and
/// a chevron that opens a form is a promise the row does not keep.
///
/// The BUILT-IN categories are listed and not editable. They are the ones the
/// app reasons about — a budget can be set against them, a transaction stores
/// their id, and the CSV export writes their names — so renaming or recolouring
/// one here would either be silently ignored or would break what is already
/// filed under it. They are shown so the list is honest about what exists, and
/// marked, rather than being hidden and leaving the user to wonder where
/// Housing went.
class CategoryManagementScreen extends StatefulWidget {
  const CategoryManagementScreen({super.key});

  @override
  State<CategoryManagementScreen> createState() =>
      _CategoryManagementScreenState();
}

class _CategoryManagementScreenState extends State<CategoryManagementScreen> {
  List<CustomCategory> _custom = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final loaded = await StorageService().getCustomCategories();
    if (!mounted) return;
    setState(() {
      _custom = loaded;
      _loading = false;
    });
  }

  /// Republishes the categories to the rest of the app.
  ///
  /// Writing to the box is not enough. The pickers read the transaction
  /// provider's cache and the registry's copy, and both are filled at startup --
  /// so a category added on this screen was invisible everywhere else until the
  /// app was restarted. One call after every write, in one place, so no path can
  /// forget it.
  Future<void> _publish() async {
    await context.read<TransactionProvider>().loadRecentCustomCategories();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _editNew,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: AppSpacing.screenPaddingWithFab,
              children: [
                const _Intro(),
                const SizedBox(height: AppSpacing.lg),
                _Group(
                  title: 'Yours',
                  // No footnote when EMPTY: the card already says "Nothing here
                  // yet", and a line under it saying "nothing added yet" was the
                  // same sentence twice. The instruction survives for the case
                  // it is actually needed -- when there ARE categories, and the
                  // footnote can remind that they can be renamed and recoloured.
                  footnote: _custom.isEmpty
                      ? null
                      : 'Tap one to rename it, change its colour or its icon, '
                            'or change whether it is money in or money out.',
                  children: [
                    for (final category in _custom)
                      _CustomRow(
                        category: category,
                        onTap: () => _edit(category),
                        onDelete: () => _confirmDelete(category),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _Group(
                  title: 'Built in',
                  footnote:
                      'These ship with the app and cannot be renamed or recoloured. '
                      'Transactions, budgets and exports all refer to them by name, '
                      'so changing one here would not change what is already filed '
                      'under it.',
                  children: const [_BuiltInList()],
                ),
              ],
            ),
    );
  }

  Future<void> _editNew() async {
    final result = await showModalBottomSheet<CustomCategory>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CategoryEditor(),
    );
    if (result == null || !mounted) return;
    await StorageService().addCustomCategory(result);
    await _publish();
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Added ${result.name}')));
  }

  Future<void> _edit(CustomCategory existing) async {
    final result = await showModalBottomSheet<CustomCategory>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CategoryEditor(existing: existing),
    );
    if (result == null || !mounted) return;
    await StorageService().updateCustomCategory(
      currentName: existing.name,
      updated: result,
    );
    await _publish();
    await _load();
  }

  Future<void> _confirmDelete(CustomCategory category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${category.name}?'),
        // Says what actually happens. The records themselves are NOT deleted:
        // a transaction filed under this category keeps its id and simply stops
        // having a category of its own, so deleting the row removes the label,
        // not the money.
        content: const Text(
          'The category is removed. Transactions already filed under it keep '
          'their amounts and fall back to Other.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await StorageService().deleteCustomCategory(category.name);
    await _publish();
    await _load();
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      'Name a category once and it is offered everywhere a category is asked '
      'for — the expense form, budgets, search, and the breakdown.',
      style: theme.textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children, this.footnote});

  final String title;
  final List<Widget> children;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
        ),
        AppSurface(
          tier: AppSurfaceTier.raised,
          child: Column(
            children: [
              if (children.isEmpty)
                // FULL WIDTH. A `Column` shrink-wraps to its widest child, so
                // the empty state was a card half the width of every card below
                // it and the list looked broken rather than empty.
                SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Text(
                      'Nothing here yet',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else
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
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _CustomRow extends StatelessWidget {
  const _CustomRow({
    required this.category,
    required this.onTap,
    required this.onDelete,
  });

  final CustomCategory category;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      key: ValueKey('custom-category-${category.id}'),
      onTap: onTap,
      leading: _Swatch(category: category),
      title: Text(category.name),
      subtitle: Text(
        category.kind.label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: IconButton(
        key: ValueKey('delete-${category.id}'),
        tooltip: 'Delete ${category.name}',
        icon: const Icon(Icons.delete_outline_rounded),
        onPressed: onDelete,
      ),
    );
  }
}

/// The row's mark: the chosen glyph in the chosen colour, tinted onto a well.
///
/// ONE element showing both choices, because the row has room for one and
/// splitting it across an icon box and a colour dot left the colour invisible --
/// the mark was the emoji, and the colour the user had picked was nowhere.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.category});

  final CustomCategory category;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: category.resolvedColor.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(AppRadii.small),
          border: Border.all(
            color: category.resolvedColor.withValues(alpha: 0.55),
          ),
        ),
        child: Icon(category.icon, size: 15, color: category.resolvedColor),
      ),
    );
  }
}

class _BuiltInList extends StatelessWidget {
  const _BuiltInList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final all = [
      ...CategoryRegistry.expenseCategories(),
      ...CategoryRegistry.incomeCategories(),
    ];

    return Column(
      children: [
        for (var i = 0; i < all.length; i++) ...[
          if (i > 0) const Divider(height: 1, indent: AppSpacing.md),
          ListTile(
            dense: true,
            leading: Icon(all[i].icon, size: 20, color: all[i].color),
            title: Text(
              all[i].name,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            // Every built-in row says what it is, and says it ONCE. A trailing
            // "Other" on the row already titled "Other" was a leftover from
            // marking the bucket, and on the device it read as two labels.
            trailing: Icon(
              Icons.lock_outline_rounded,
              size: 15,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ],
      ],
    );
  }
}

/// The add/edit form, as a sheet.
class _CategoryEditor extends StatefulWidget {
  const _CategoryEditor({this.existing});

  final CustomCategory? existing;

  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  // Assigned in initState rather than in the field initialisers: a `late final`
  // field cannot read `widget` in its initialiser, and a `final` one cannot be
  // seeded from a constructor argument's default at all.
  late final TextEditingController _name;
  late CategoryKind _kind;
  late int? _colour;
  String? _iconKey;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _kind = existing?.kind ?? CategoryKind.expense;
    _colour = existing?.colorValue;
    _iconKey = existing?.iconKey;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final trimmed = _name.text.trim();
    final canSave = trimmed.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.md,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.existing == null ? 'New category' : 'Edit category',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const ValueKey('category-name-field'),
              controller: _name,
              autofocus: widget.existing == null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Coffee',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Kind', style: theme.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.xs),
            SegmentedButton<CategoryKind>(
              segments: const [
                ButtonSegment(
                  value: CategoryKind.expense,
                  label: Text('Expense'),
                  icon: Icon(Icons.trending_down_rounded),
                ),
                ButtonSegment(
                  value: CategoryKind.income,
                  label: Text('Income'),
                  icon: Icon(Icons.trending_up_rounded),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: AppSpacing.md),
            // A live preview, so the two choices below are seen TOGETHER rather
            // than assembled in the head and discovered later in a legend.
            Center(
              child: _Preview(
                icon: CategoryIcons.resolve(_iconKey),
                color: _colour == null
                    ? const Color(0xFF9C8B7A)
                    : Color(_colour!),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Text('Colour', style: theme.textTheme.labelLarge),
                const SizedBox(width: AppSpacing.xs),
                // Named, so a colour is not something the user has to compare
                // against a list to identify.
                Text(
                  _colour == null ? 'Default' : _colourName(_colour!),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final value in CategoryColours.swatches)
                  _SwatchChoice(
                    value: value,
                    selected: _colour == value,
                    onTap: () => setState(
                      () => _colour = _colour == value ? null : value,
                    ),
                  ),
                _SwatchChoice(
                  value: null,
                  selected: _colour == null,
                  onTap: () => setState(() => _colour = null),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Text('Icon', style: theme.textTheme.labelLarge),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  // The GROUP, not the key. "Icon cafe" is a name from the
                  // catalogue; "Food and drink" is something the user can read
                  // back and recognise, and it is already the heading on screen.
                  CategoryIcons.groupOf(_iconKey) ?? 'Default',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            // A GROUPED GRID, in the same idiom as the Add Location icon picker,
            // because that picker is the app's existing answer to "pick a glyph":
            // monochrome, one colour, drawn from the same `Icons.*_rounded`
            // family as every built-in category.
            //
            // Grouped rather than one flat wall of ninety, since you are looking
            // for something to do with money and "Payment" has to be findable.
            for (final group in CategoryIcons.groups.entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  group.key.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 7,
                mainAxisSpacing: AppSpacing.xxs,
                crossAxisSpacing: AppSpacing.xxs,
                children: [
                  for (final key in group.value)
                    _IconChoice(
                      iconKey: key,
                      // Drawn in the category's OWN colour, so choosing a colour
                      // and choosing an icon are visibly the same decision.
                      color: Color(_colour ?? 0xFF9C8B7A),
                      selected: _iconKey == key,
                      onTap: () => setState(
                        () => _iconKey = _iconKey == key ? null : key,
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('category-save'),
                    onPressed: canSave
                        ? () => Navigator.of(context).pop(
                            CustomCategory(
                              name: trimmed,
                              kind: _kind,
                              colorValue: _colour,
                              iconKey: _iconKey,
                            ),
                          )
                        : null,
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SwatchChoice extends StatelessWidget {
  const _SwatchChoice({
    required this.value,
    required this.selected,
    required this.onTap,
  });

  /// The packed colour, or null for "leave it to the app's default".
  final int? value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // AT FULL STRENGTH WHEN SELECTED AND MUTED WHEN NOT. Every swatch used to be
    // drawn at 55% alpha, so the whole palette looked like the same dusty shade
    // and the one you had chosen was the only vivid thing on the screen. These
    // are the colours the legend will actually be, so they are shown as they are.
    final colour = value == null ? scheme.onSurfaceVariant : Color(value!);
    return Semantics(
      key: ValueKey(value == null ? 'swatch-default' : 'swatch-$value'),
      button: true,
      selected: selected,
      label: value == null ? 'Default colour' : _colourName(value!),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.small),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: value == null ? Colors.transparent : colour,
            borderRadius: BorderRadius.circular(AppRadii.small),
            border: Border.all(
              color: selected ? scheme.onSurface : scheme.outline,
              width: selected ? 2.5 : 1,
            ),
          ),
          // The default is a DIAGONALLY STRUCK box, not a blank one: an empty
          // swatch next to twenty-four colours reads as a colour that failed to
          // load rather than as "no colour chosen".
          child: value == null
              ? Icon(
                  Icons.block_rounded,
                  size: 15,
                  color: scheme.onSurfaceVariant,
                )
              : null,
        ),
      ),
    );
  }
}

/// One glyph in the icon grid.
class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.iconKey,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String iconKey;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      key: ValueKey('category-icon-$iconKey'),
      button: true,
      selected: selected,
      label: iconKey.replaceAll('_', ' '),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.small),
        child: Container(
          decoration: BoxDecoration(
            color: selected
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadii.small),
            border: Border.all(
              color: selected ? scheme.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Icon(CategoryIcons.resolve(iconKey), size: 20, color: color),
        ),
      ),
    );
  }
}

/// The category as it will look: the glyph, in its colour, in a tinted well.
class _Preview extends StatelessWidget {
  const _Preview({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Icon(icon, size: 30, color: color),
    );
  }
}

/// A human name for a swatch, so a colour is not something to be identified by
/// comparing it against a list.
///
/// Names the HUE, not the palette: there is no "Gruvbox yellow" a person would
/// recognise without the reference, and the whole list is gruvbox-adjacent.
String _colourName(int value) {
  final hsl = HSLColor.fromColor(Color(value));
  final hue = hsl.hue;
  final light = hsl.lightness;
  final tone = light < 0.35
      ? 'dark'
      : light > 0.72
      ? 'pale'
      : '';
  String name;
  if (hue < 15 || hue >= 345) {
    name = 'red';
  } else if (hue < 40) {
    name = 'orange';
  } else if (hue < 70) {
    name = 'amber';
  } else if (hue < 160) {
    name = 'green';
  } else if (hue < 200) {
    name = 'teal';
  } else if (hue < 255) {
    name = 'blue';
  } else if (hue < 290) {
    name = 'purple';
  } else if (hue < 330) {
    name = 'pink';
  } else {
    name = 'rose';
  }
  return tone.isEmpty ? name : '$tone $name';
}
