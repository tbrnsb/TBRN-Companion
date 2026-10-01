import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_application_1/providers/checklist_provider.dart';
import 'package:flutter_application_1/providers/journey_provider.dart';
import 'package:flutter_application_1/providers/location_provider.dart';
import 'package:flutter_application_1/providers/settings_provider.dart';
import 'package:flutter_application_1/providers/transaction_provider.dart';
import 'package:flutter_application_1/services/csv_export.dart';
import 'package:flutter_application_1/screens/transactions/csv_import_sheet.dart';
import 'package:flutter_application_1/screens/trash_screen.dart';
import 'package:flutter_application_1/services/storage_service.dart';
import 'package:flutter_application_1/theme/app_palettes.dart';
import 'package:flutter_application_1/theme/app_theme.dart';

/// The width at which "Add demo data" and "Clear demo data" sit side by side
/// without either label wrapping.
///
/// Measured, not guessed: each button needs its icon, the internal gap, its own
/// horizontal padding and its label, so two of them plus the gap between them
/// is what has to fit. Below this they stack.
const _sideBySideWidth = 380.0;

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
          // APPEARANCE FIRST. The old screen led with Currency and had the theme
          // split across two groups that had to be reconciled with each other, so
          // it read as a settings dump rather than as something with an order.
          // One "Themes" group, two levels deep: a family, then a variant of it.
          _ThemesSection(
            palette: settings.palette,
            variant: settings.variant,
            onPalette: settings.setPalette,
            onVariant: settings.setVariant,
          ),

          const SizedBox(height: AppSpacing.lg),

          _SettingsSection(
            title: 'Currency',
            child: Column(
              children: [
                _CurrencyOption(
                  currency: Currency.rs,
                  selected: settings.currency,
                  onSelect: (currency) => settings.setCurrency(currency),
                ),
                _CurrencyOption(
                  currency: Currency.usd,
                  selected: settings.currency,
                  onSelect: (currency) => settings.setCurrency(currency),
                ),
                _CurrencyOption(
                  currency: Currency.eur,
                  selected: settings.currency,
                  onSelect: (currency) => settings.setCurrency(currency),
                ),
              ],
            ),
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
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppSurface(tier: AppSurfaceTier.raised, child: child),
      ],
    );
  }
}

class _CurrencyOption extends StatelessWidget {
  const _CurrencyOption({
    required this.currency,
    required this.selected,
    required this.onSelect,
  });

  final Currency currency;
  final Currency selected;
  final ValueChanged<Currency> onSelect;

  @override
  Widget build(BuildContext context) {
    final isSelected = currency == selected;
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(Icons.money_rounded, color: colorScheme.primary),
      title: Text(currency.name),
      trailing: isSelected
          ? Icon(Icons.check, color: colorScheme.primary)
          : null,
      onTap: () => onSelect(currency),
    );
  }
}

/// The "Themes" section: a FAMILY, then a VARIANT of it.
///
/// Two levels because that is how a colour scheme is actually chosen — "I want
/// the warm one", and then "in the dark". The previous screen had a Theme group
/// and a separate Colours group, and a user who picked Gruvbox still had to work
/// out which of the two answered their question.
///
/// Live preview: choosing a family or a variant re-themes the app immediately,
/// because the only honest way to choose a colour scheme is to look at it. A
/// picker that applies on "Save" makes the user memorise swatches and guess.
class _ThemesSection extends StatelessWidget {
  const _ThemesSection({
    required this.palette,
    required this.variant,
    required this.onPalette,
    required this.onVariant,
  });

  final AppPalette palette;
  final ThemeVariant variant;
  final ValueChanged<AppPalette> onPalette;
  final ValueChanged<ThemeVariant> onVariant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Themes',
          style: theme.textTheme.titleMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppSurface(
          tier: AppSurfaceTier.raised,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final family in AppPalette.values)
                _FamilyRow(
                  family: family,
                  palette: palette,
                  variant: variant,
                  onPalette: onPalette,
                  onVariant: onVariant,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One family. Its variants are shown underneath, and ONLY for the family that is
/// selected.
///
/// Collapsed, a family is one row. Expanded, it shows the variants it actually
/// has — so Light is simply ABSENT for Solitude and Gruvbox rather than present
/// and greyed out. A disabled option is a promise the app cannot keep, and
/// tapping it and being snapped back to Dark is worse than never offering it.
class _FamilyRow extends StatelessWidget {
  const _FamilyRow({
    required this.family,
    required this.palette,
    required this.variant,
    required this.onPalette,
    required this.onVariant,
  });

  final AppPalette family;
  final AppPalette palette;
  final ThemeVariant variant;
  final ValueChanged<AppPalette> onPalette;
  final ValueChanged<ThemeVariant> onVariant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isSelected = family == palette;

    // The effective variant for THIS family, not the app's. Choosing Gruvbox and
    // then switching to Catppuccin must land on a variant Catppuccin has, so the
    // stored variant is checked against the family's own list.
    final effective = family.hasVariant(variant)
        ? variant
        : family.variants.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          key: ValueKey('family-${family.name}'),
          contentPadding: EdgeInsets.zero,
          selected: isSelected,
          onTap: () => onPalette(family),
          leading: Icon(
            isSelected
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_unchecked_rounded,
            color: isSelected ? scheme.primary : scheme.outline,
          ),
          title: Text(family.label),
          subtitle: Text(
            family.description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          // The family's OWN ladder, painted from its real theme rather than from
          // a hex. A collapsed ladder shows as a flat stripe, so a broken
          // palette is visible here instead of only on the screens behind.
          trailing: _SwatchStrip(
            themes: [
              for (final v in family.variants) AppTheme.forVariant(family, v),
            ],
          ),
        ),
        if (isSelected)
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.lg,
              bottom: AppSpacing.xs,
            ),
            child: Wrap(
              spacing: AppSpacing.xs,
              children: [
                for (final v in family.variants)
                  ChoiceChip(
                    key: ValueKey('variant-${family.name}-${v.name}'),
                    label: Text(family.labelForVariant(v)),
                    selected: v == effective,
                    onSelected: (_) => onVariant(v),
                  ),
              ],
            ),
          ),
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
class _SwatchStrip extends StatelessWidget {
  const _SwatchStrip({required this.themes});

  final List<ThemeData> themes;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppSpacing.xl + AppSpacing.sm,
      height: AppSpacing.xs + AppSpacing.xxs,
      child: Row(
        children: [
          for (final themeData in themes)
            for (final colour in _ladderOf(themeData))
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(color: colour),
                  child: const SizedBox.expand(),
                ),
              ),
        ],
      ),
    );
  }

  static List<Color> _ladderOf(ThemeData themeData) {
    final scheme = themeData.colorScheme;
    return [
      scheme.surfaceContainerLowest,
      scheme.surfaceContainerLow,
      scheme.surfaceContainer,
      scheme.surfaceContainerHigh,
      scheme.surfaceContainerHighest,
    ];
  }
}

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
              // Export and import sit together and in that order, because they are
              // the same format in opposite directions. Separating them across the
              // screen would invite somebody to change one and not the other, and
              // the round trip is the thing that has to keep working.
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _exportCsv,
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('Export this month as CSV'),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const ValueKey('settings-import-csv'),
                  onPressed: _busy ? null : _importCsv,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('Import transactions from CSV'),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  // Disabled when nothing is stored, rather than offering a
                  // wipe that has nothing to do.
                  onPressed: _busy || nothingStored ? null : _confirmRemoveAll,
                  icon: Icon(
                    Icons.delete_forever_rounded,
                    color: _busy || nothingStored ? null : colorScheme.error,
                  ),
                  label: Text(
                    'Remove all data',
                    style: TextStyle(
                      color: _busy || nothingStored ? null : colorScheme.error,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: colorScheme.error.withValues(alpha: 0.4),
                    ),
                  ),
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
              // Side by side, these two labels plus their icons need more room
              // than a 360dp phone has, so each one wrapped onto two lines and
              // the pair looked broken. Below the width where they genuinely
              // fit, they stack instead. The labels are not shortened: "Clear
              // demo data" says what it does, and truncating it to "Clear demo…"
              // on the one button that deletes things is the wrong trade.
              LayoutBuilder(
                builder: (context, constraints) {
                  final sideBySide = constraints.maxWidth >= _sideBySideWidth;
                  final add = OutlinedButton.icon(
                    onPressed: _loading ? null : _addDemo,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text(
                      'Add demo data',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                  final clear = OutlinedButton.icon(
                    onPressed: _loading ? null : _clearDemo,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text(
                      'Clear demo data',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );

                  if (!sideBySide) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        add,
                        const SizedBox(height: AppSpacing.sm),
                        clear,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: add),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: clear),
                    ],
                  );
                },
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
