import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/providers/budget_provider.dart';
import 'package:daily_companion/providers/checklist_provider.dart';
import 'package:daily_companion/providers/journey_provider.dart';
import 'package:daily_companion/providers/location_provider.dart';
import 'package:daily_companion/providers/settings_provider.dart';
import 'package:daily_companion/providers/transaction_provider.dart';
import 'package:daily_companion/services/csv_export.dart';
import 'package:daily_companion/screens/transactions/csv_import_sheet.dart';
import 'package:daily_companion/screens/budgets/budgets_screen.dart';
import 'package:daily_companion/screens/settings/category_management_screen.dart';
import 'package:daily_companion/screens/trash_screen.dart';
import 'package:daily_companion/services/storage_service.dart';
import 'package:daily_companion/theme/app_palettes.dart';
import 'package:daily_companion/theme/app_theme.dart';
import 'package:daily_companion/utils/number_style.dart';
import 'package:daily_companion/widgets/app_gear.dart';
import 'package:daily_companion/widgets/settings_controls.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  StorageCounts? _counts;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  /// Pushes [screen], then re-reads the counts.
  ///
  /// The counts are read ONCE in initState, so a category added or deleted on
  /// the Categories screen left this page saying "1 yours" after the only one
  /// had been deleted -- the number was true when it was read and wrong by the
  /// time it was on screen again.
  ///
  /// AWAITED and reloaded on the way back, rather than reloading in
  /// [didChangeDependencies]: that fires on every provider tick, and the count
  /// only changes when one of the two screens this page pushes has been used.
  ///
  /// The route keeps a name under [AppGearButton.settingsRoutePrefix] so the
  /// gear still knows it is inside Settings and hides itself. A screen opened
  /// from here is reached by the back arrow, and a gear offering to re-open the
  /// page you came from is the thing that change exists to prevent.
  Future<void> _pushThenReload(String name, Widget screen) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: RouteSettings(
          name: '${AppGearButton.settingsRoutePrefix}/$name',
        ),
        builder: (_) => screen,
      ),
    );
    await _loadCounts();
    if (mounted) setState(() {});
  }

  Future<void> _loadCounts() async {
    try {
      final counts = await StorageService().getStorageCounts();
      if (!mounted) return;
      setState(() => _counts = counts);
    } catch (e) {
      // A count that cannot be read is not worth failing the screen over; the
      // section falls back to its "checking" copy.
      if (!mounted) return;
      setState(() => _counts = null);
    }
  }

  /// Reloads every provider that caches records, then the counts.
  ///
  /// Both matter after any change made straight to storage. The counts used to
  /// live in the Data section alone, so adding or clearing demo data left the
  /// "Stored on this device" numbers showing what was there before.
  Future<void> _reloadEverything() async {
    final providers = _DataProviders.read(context);
    await providers.reload();
    await _loadCounts();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: AppSpacing.screenPadding,
        children: [
          // HOW IT IS ARRANGED, and why.
          //
          // One row per setting, whatever the number of options behind it, and
          // the groups in the order people change things: how the app looks, how
          // their money is written, what they track money against, and finally
          // the destructive and rare things at the bottom.
          //
          // The screen this replaced led with a theme GALLERY -- four families
          // with a tagline and a four-swatch preview each, then a variant
          // control, then three currency rows -- so the page was as long as the
          // implementation and grew every time a currency was added. Nine
          // currencies as inline rows would have been worse still. Choosing is
          // now a sheet behind a row, which is why adding the other six
          // currencies cost this screen no height at all.
          SettingsGroup(
            title: 'Appearance',
            footnote: 'Number format applies everywhere an amount is shown.',
            children: [
              SettingsOptionRow<AppPalette>(
                key: const ValueKey('settings-row-theme'),
                label: 'Theme',
                icon: Icons.palette_rounded,
                supporting: 'Colours',
                options: AppPalette.values,
                value: settings.palette.label,
                titleOf: (p) => p.label,
                subtitleOf: (p) =>
                    '${p.description} · '
                            '${settings.palette.labelForVariant(settings.palette.variants.first)}'
                        .trim(),
                onSelected: settings.setPalette,
              ),
              SettingsOptionRow<ThemeVariant>(
                key: const ValueKey('settings-row-brightness'),
                label: 'Brightness',
                icon: Icons.brightness_6_rounded,
                supporting: 'Light, dark or system',
                // Only the variants THIS family offers. A dark-only family
                // offering "Light" is a promise the app cannot keep, and being
                // snapped back is worse than never offering it.
                options: settings.palette.variants,
                value: settings.palette.labelForVariant(settings.variant),
                titleOf: (v) => settings.palette.labelForVariant(v),
                onSelected: settings.setVariant,
              ),
              SettingsOptionRow<NumberStyle>(
                key: const ValueKey('settings-row-number-style'),
                label: 'Number format',
                icon: Icons.pin_rounded,
                supporting: 'Grouping',
                options: NumberStyle.values,
                value: settings.numberStyle.label,
                titleOf: (s) => s.label,
                subtitleOf: (s) => s.title,
                onSelected: settings.setNumberStyle,
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.lg),

          SettingsGroup(
            title: 'Money',
            children: [
              SettingsOptionRow<Currency>(
                key: const ValueKey('settings-row-currency'),
                label: 'Currency',
                icon: Icons.payments_rounded,
                supporting: 'The amount symbol',
                options: Currency.values,
                value: settings.currency.name,
                titleOf: (c) => '${c.name}  ${c.title}',
                subtitleOf: (c) => c.code,
                onSelected: settings.setCurrency,
              ),
              SettingsNavRow(
                label: 'Budgets',
                icon: Icons.donut_large_rounded,
                supporting: 'A limit per category',
                value: _budgetSummary(context),
                onTap: () => _pushThenReload('budgets', const BudgetsScreen()),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.lg),

          SettingsGroup(
            title: 'Categories',
            children: [
              SettingsNavRow(
                label: 'Categories',
                icon: Icons.category_rounded,
                supporting: 'Name, colour, icon',
                value: _categorySummary(context),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    settings: const RouteSettings(
                      name: '${AppGearButton.settingsRoutePrefix}/categories',
                    ),
                    builder: (_) => const CategoryManagementScreen(),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.lg),

          _DataSection(counts: _counts, onReload: _reloadEverything),

          const SizedBox(height: AppSpacing.lg),

          // The trash entry is HIDDEN when empty, rather than present and leading
          // to a screen with nothing on it. An entry that leads to an empty screen
          // teaches people the screen is not worth opening, which is exactly
          // when it starts being worth opening.
          if ((_counts?.trashedTransactions ?? 0) > 0) ...[
            _TrashSection(count: _counts!.trashedTransactions),
            const SizedBox(height: AppSpacing.lg),
          ],

          _DemoSection(onReload: _reloadEverything),
        ],
      ),
    );
  }

  /// What the Budgets row says on the right, or a nudge if none is set.
  String _budgetSummary(BuildContext context) {
    final budgets = context.watch<BudgetProvider>().budgets.where(
      (b) => b.limit != null,
    );
    final count = budgets.length;
    if (count == 0) return 'None set';
    return '$count set';
  }

  /// How many categories are in play, counting the ones the user added.
  ///
  /// From the storage counts rather than from the provider, because the counts
  /// are already loaded for the Data section and a second read of the box would
  /// be a second thing that can disagree with the number printed below it.
  String _categorySummary(BuildContext context) {
    final builtIn =
        CategoryRegistry.expenseCategories().length +
        CategoryRegistry.incomeCategories().length;
    final custom = _counts?.customCategories;
    return custom == null
        ? '$builtIn built in'
        : '$builtIn built in, $custom yours';
  }
}

/// The section wrapper the Data, Trash and Demo groups still use.
///
/// Kept rather than folded into `SettingsGroup`, because those three predate it
/// and each has its own footnote behaviour; the groups on the new screen use
/// `SettingsGroup` directly.
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppSurface(tier: AppSurfaceTier.raised, child: child),
      ],
    );
  }
}

class _TrashSection extends StatelessWidget {
  const _TrashSection({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return _SettingsSection(
      title: 'Deleted',
      child: ListTile(
        key: const ValueKey('settings-trash-entry'),
        // No leading icon and no container: this is a row in a section, not a
        // card, and the count is the thing worth reading.
        contentPadding: EdgeInsets.zero,
        title: Text(count == 1 ? '1 deleted record' : '$count deleted records'),
        subtitle: const Text('Restore anything you deleted by mistake'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () async {
          await Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const TrashScreen()));
          // Coming back, the trash may be empty now. The counts are the only
          // thing that decides whether this entry exists, so they have to be
          // re-read or a section that should have vanished stays on screen.
          if (!context.mounted) return;
          final state = context.findAncestorStateOfType<_SettingsScreenState>();
          await state?._loadCounts();
        },
      ),
    );
  }
}

/// One palette in the "Colours" group.
///
/// Shows a LIVE swatch strip from the palette's own ladder rather than a named
/// hex, so what a user taps is exactly what they will get — and a palette whose
/// ladder is broken is visible as a broken strip in Settings instead of only on
/// the screens behind it.
class _DataSection extends StatefulWidget {
  const _DataSection({required this.counts, required this.onReload});

  final StorageCounts? counts;

  /// Re-reads every provider and the counts. Called after any change made
  /// straight to storage.
  final Future<void> Function() onReload;

  @override
  State<_DataSection> createState() => _DataSectionState();
}

class _DataSectionState extends State<_DataSection> {
  bool _busy = false;

  /// Empties every box, then reloads each provider.
  ///
  /// Without the reload the wipe would leave the app showing the records it
  /// just deleted until something else happened to trigger a refresh.
  ///
  /// The busy flag is cleared in a `finally`. If the clear itself throws, the
  /// section would otherwise stay disabled for the life of the screen, with no
  /// way to retry and no message saying what went wrong.
  Future<void> _removeAllData() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await StorageService().clear();
      await widget.onReload();
      messenger.showSnackBar(
        const SnackBar(content: Text('All data removed.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not remove all data: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmRemoveAll() async {
    final counts = widget.counts;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove all data?'),
        content: Text(
          counts == null
              ? 'This permanently deletes every record this app stores: '
                    'all checklists and their items, all places and location '
                    'logs, all transactions, all journeys, and your saved '
                    'custom expense categories. It cannot be undone.'
              : 'This permanently deletes everything this app stores:\n\n'
                    '• ${counts.checklists} checklists '
                    '(${counts.checklistItems} items)\n'
                    '• ${counts.locations} places '
                    '(${counts.locationLogs} location logs)\n'
                    '• ${counts.transactions} transactions\n'
                    '• ${counts.journeys} journeys\n'
                    '• ${counts.customCategories} custom categories\n\n'
                    'It cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Remove everything'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _removeAllData();
  }

  Future<void> _exportCsv() async {
    setState(() => _busy = true);
    // Read before the async gap for the same reason as the wipe above.
    final provider = context.read<TransactionProvider>();
    final message = await _exportMessageFor(provider);

    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _importCsv() async {
    // The picker is a platform channel, so it is reached through the sheet's own
    // static helper and this method only reports what came back. `mounted` is
    // checked after every await because a picker can take arbitrarily long and
    // the user may have left the screen while it was open.
    final imported = await CsvImportSheet.pickAndImport(context);
    if (!mounted) return;
    if (imported == null) return;
    if (imported == 0) return;

    // Every cached provider is re-read: an import can add records in months the
    // user is not browsing, so a screen still quoting the old numbers would be
    // wrong in a way nothing else would correct.
    await widget.onReload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          imported == 1
              ? 'Imported 1 transaction.'
              : 'Imported $imported transactions.',
        ),
      ),
    );
  }

  /// What to tell the user, whether the export worked, had nothing to do, or
  /// failed. A share sheet is a platform channel, so the failure has to become
  /// a sentence rather than an unhandled error.
  Future<String> _exportMessageFor(TransactionProvider provider) async {
    try {
      final result = await CsvExport.shareCurrentMonth(provider);
      return result.shared
          ? 'Shared ${result.fileName}.'
          : 'No transactions recorded this month.';
    } catch (e) {
      return 'Could not export: $e';
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final counts = widget.counts;
    final nothingStored = counts?.isEmpty ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Data',
          style: textTheme.titleMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppSurface(
          tier: AppSurfaceTier.raised,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                counts == null
                    ? 'Checking what is stored\u2026'
                    : 'Stored on this device:',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              if (counts != null) ...[
                _CountLine(label: 'Checklists', value: counts.checklists),
                _CountLine(
                  label: 'Checklist items',
                  value: counts.checklistItems,
                ),
                _CountLine(label: 'Places', value: counts.locations),
                _CountLine(label: 'Location logs', value: counts.locationLogs),
                _CountLine(label: 'Transactions', value: counts.transactions),
                _CountLine(label: 'Journeys', value: counts.journeys),
                _CountLine(
                  label: 'Custom categories',
                  value: counts.customCategories,
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              // The three actions are a MENU, not three buttons.
              //
              // A full-width button each put "Remove all data" on the screen at
              // the same weight and the same size as "Export this month as CSV",
              // and the destructive one is the one a thumb reaches for by
              // accident. Behind a menu the wipe is one deliberate tap further
              // away than the other two, which is the whole difference between
              // an action and a hazard.
              //
              // Export and import stay adjacent and in that order, because they
              // are the same format in opposite directions: separating them
              // invites somebody to change one and not the other, and the round
              // trip is the thing that has to keep working.
              SizedBox(
                width: double.infinity,
                child: MenuAnchor(
                  builder: (menuContext, controller, _) => OutlinedButton.icon(
                    key: const ValueKey('settings-data-menu'),
                    onPressed: _busy
                        ? null
                        : () => controller.isOpen
                              ? controller.close()
                              : controller.open(),
                    icon: const Icon(Icons.more_horiz_rounded),
                    label: const Text('Data actions'),
                  ),
                  menuChildren: [
                    MenuItemButton(
                      key: const ValueKey('settings-export-csv'),
                      onPressed: _busy ? null : _exportCsv,
                      leadingIcon: const Icon(Icons.ios_share_rounded),
                      child: const Text('Export this month as CSV'),
                    ),
                    MenuItemButton(
                      key: const ValueKey('settings-import-csv'),
                      onPressed: _busy ? null : _importCsv,
                      leadingIcon: const Icon(Icons.upload_file_rounded),
                      child: const Text('Import transactions from CSV'),
                    ),
                    const PopupMenuDivider(),
                    MenuItemButton(
                      key: const ValueKey('settings-remove-all'),
                      // Disabled when nothing is stored, rather than offering a
                      // wipe that has nothing to do.
                      onPressed: _busy || nothingStored
                          ? null
                          : _confirmRemoveAll,
                      leadingIcon: Icon(
                        Icons.delete_forever_rounded,
                        color: _busy || nothingStored
                            ? null
                            : colorScheme.error,
                      ),
                      child: Text(
                        'Remove all data',
                        style: TextStyle(
                          color: _busy || nothingStored
                              ? null
                              : colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CountLine extends StatelessWidget {
  const _CountLine({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: textTheme.bodySmall),
          Text(
            '$value',
            style: textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: value == 0 ? colorScheme.onSurfaceVariant : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoSection extends StatefulWidget {
  const _DemoSection({required this.onReload});

  /// Re-reads every provider and the storage counts after demo data is added or
  /// cleared.
  final Future<void> Function() onReload;

  @override
  State<_DemoSection> createState() => _DemoSectionState();
}

class _DemoSectionState extends State<_DemoSection> {
  bool _loading = false;

  Future<void> _addDemo() async {
    setState(() => _loading = true);
    await showDialog(
      context: context,
      builder: (context) => _AddDemoDialog(onReload: widget.onReload),
    );
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _clearDemo() async {
    await showDialog(
      context: context,
      builder: (context) => _ClearDemoDialog(onReload: widget.onReload),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Demo Data',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppSurface(
          tier: AppSurfaceTier.raised,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sample records for trying the app out. Every demo record is '
                'labelled "[Demo]" so you can tell them apart from your own.',
              ),
              const SizedBox(height: AppSpacing.sm),
              // A MENU, for the same reason the Data actions are one.
              //
              // Two side-by-side buttons needed a measured 380dp before either
              // label stopped wrapping, so most phones stacked them and the pair
              // looked broken. One row plus a menu has no width to get wrong,
              // and the destructive action stops being a button a thumb lands on
              // while looking for the other one.
              SizedBox(
                width: double.infinity,
                child: MenuAnchor(
                  builder: (menuContext, controller, _) => OutlinedButton.icon(
                    key: const ValueKey('settings-demo-menu'),
                    onPressed: _loading
                        ? null
                        : () => controller.isOpen
                              ? controller.close()
                              : controller.open(),
                    icon: const Icon(Icons.science_outlined),
                    label: const Text('Demo data actions'),
                  ),
                  menuChildren: [
                    MenuItemButton(
                      key: const ValueKey('settings-add-demo'),
                      onPressed: _loading ? null : _addDemo,
                      leadingIcon: const Icon(Icons.add_rounded),
                      child: const Text('Add demo data'),
                    ),
                    MenuItemButton(
                      key: const ValueKey('settings-clear-demo'),
                      onPressed: _loading ? null : _clearDemo,
                      leadingIcon: const Icon(Icons.delete_outline_rounded),
                      child: const Text('Clear demo data'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AddDemoDialog extends StatelessWidget {
  const _AddDemoDialog({required this.onReload});

  final Future<void> Function() onReload;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add demo data?'),
      content: const Text(
        'This adds sample checklists, journeys, places, expenses and income '
        'for the current month. Every record is labelled "[Demo]" so you can '
        'tell it from your own, and "Clear demo data" removes all of it again.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            final providers = _DataProviders.read(context);
            await providers.transactions.addDemoData();
            // Reloads the providers and the storage counts together; the counts
            // used to go stale here because they were owned by the Data section
            // rather than the screen.
            await onReload();
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Add demo data'),
        ),
      ],
    );
  }
}

class _ClearDemoDialog extends StatelessWidget {
  const _ClearDemoDialog({required this.onReload});

  final Future<void> Function() onReload;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Clear demo data?'),
      content: const Text(
        'This removes only the records created by "Add demo data", across every '
        'section and every month. Anything you added yourself is left alone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            final providers = _DataProviders.read(context);
            await providers.transactions.clearDemoData();
            await onReload();
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Clear demo data'),
        ),
      ],
    );
  }
}

/// The providers that cache records from storage.
///
/// Captured before an await so no BuildContext is read across an async gap,
/// which is what the `use_build_context_synchronously` lint exists to catch.
class _DataProviders {
  const _DataProviders(
    this.checklists,
    this.journeys,
    this.locations,
    this.transactions,
  );

  final ChecklistProvider checklists;
  final JourneyProvider journeys;
  final LocationProvider locations;
  final TransactionProvider transactions;

  static _DataProviders read(BuildContext context) => _DataProviders(
    context.read<ChecklistProvider>(),
    context.read<JourneyProvider>(),
    context.read<LocationProvider>(),
    context.read<TransactionProvider>(),
  );

  /// Re-reads every box-backed list. Needed after any change made straight to
  /// storage, otherwise the UI keeps showing what was there before.
  Future<void> reload() => Future.wait([
    checklists.loadChecklists(),
    journeys.loadJourneys(),
    locations.loadLocations(),
    // Reloads the month on screen, which is where a deleted transaction
    // would otherwise linger.
    transactions.goToCurrentMonth(),
  ]);
}
