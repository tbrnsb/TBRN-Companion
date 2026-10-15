import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/providers/budget_provider.dart';
import 'package:daily_companion/providers/checklist_provider.dart';
import 'package:daily_companion/providers/journey_provider.dart';
import 'package:daily_companion/providers/location_provider.dart';
import 'package:daily_companion/providers/settings_provider.dart';
import 'package:daily_companion/providers/transaction_provider.dart';
import 'package:daily_companion/services/csv_export.dart';
import 'package:daily_companion/services/notification_service.dart';
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
  /// live in the Data section alone, so a change elsewhere left the "Stored on
  /// this device" numbers showing what was there before.
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
          // WHY THIS ONE LEADS, when the groups below are ordered by how often
          // people change them.
          //
          // It is not a preference, it is a precondition. When the system
          // permission is off, every alert the app can show is dropped by the
          // phone in silence: the per-place toggle says ON, the trip reminder
          // fires, and nothing arrives — with no error anywhere in the app.
          // A row that decides whether everything else here can mean anything
          // is worth seeing before everything else here.
          SettingsGroup(
            title: 'Alerts',
            footnote:
                'Shown while the app is running. The phone has to be allowed '
                'to display them.',
            children: const [_NotificationsRow()],
          ),

          const SizedBox(height: AppSpacing.lg),

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

/// The section wrapper the Data and Trash groups still use.
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
        // Went through _SettingsSection like every other group. This header
        // hand-rolled the same structure and used `titleMedium` in mixed case,
        // so "Data" sat 170px under "CATEGORIES" rendered in a different type
        // system — one line of omission, not a decision.
        Text(
          'DATA',
          style: textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
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

    return Semantics(
      // Ten of these sit under one heading on this screen, and every other
      // row in Settings already reads as one control to a screen reader. Left
      // bare, a traversal of the Data section is ten unlabelled number pairs.
      label: '$label, $value',
      excludeSemantics: true,
      child: Padding(
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
      ),
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

/// The "can alerts appear at all?" row.
///
/// Why this exists: every alert control in the app — the per-place "Notify
/// when I arrive" switch, the trip reminders — is silently void while the
/// system permission is off, and no screen said so. The user's evidence was a
/// toggle reading ON and a phone showing nothing.
///
/// It is a row, not a nav row and not a dropdown: it opens neither an in-app
/// screen nor a sheet of choices, so it has neither a chevron nor an expand
/// caret — those two marks mean "there is more of this app behind me" on this
/// page, and this row leads out to system Settings or puts a system prompt on
/// screen.
class _NotificationsRow extends StatefulWidget {
  const _NotificationsRow();

  @override
  State<_NotificationsRow> createState() => _NotificationsRowState();
}

class _NotificationsRowState extends State<_NotificationsRow> {
  /// How long the row waits for the phone before it gives up.
  ///
  /// Long enough that a busy phone is not mistaken for a hang, short enough
  /// that "Checking…" is a moment rather than a state the row sits on. Both
  /// reads go out TOGETHER and each is bounded by this one deadline, so the
  /// row waits at most this long — not this twice over, which is what two
  /// sequential bounded reads cost.
  static const Duration _readTimeout = Duration(seconds: 4);

  /// What the phone says: the answer, or null when there is not one.
  ///
  /// Null covers two very different things and [_gaveUp] is what tells them
  /// apart. While a read is genuinely outstanding the row says "Checking…";
  /// once a read has given up the row says "Unknown" and offers the retry,
  /// because a read that never came back has read nothing and may not claim
  /// "Off" — that was the defect: an unknown painted as Off, in the error
  /// colour, with nothing able to re-read it.
  bool? _enabled;

  /// Whether the last read gave up rather than still being in flight.
  ///
  /// True exactly when [_enabled] is null after the deadline passed or the
  /// channel threw, which is what turns "Checking…" into "Unknown" and turns
  /// the tap into a re-read.
  bool _gaveUp = false;

  /// Whether the system prompt has been answered before. Decides between
  /// asking and sending the user to Settings — see
  /// [NotificationService.hasAskedPermission].
  bool _asked = false;

  bool _busy = false;

  /// Serial number of the newest read.
  ///
  /// A read started at startup that is still outstanding when the user taps
  /// would otherwise land LATER than the answer the tap just fetched and
  /// overwrite it with its own stale "Unknown". Only the newest read writes.
  int _readGeneration = 0;

  @override
  void initState() {
    super.initState();
    // Read on the way up rather than only on tap: the row's whole job is to
    // show a state the user never sees otherwise.
    _refresh();
  }

  /// One read of the phone, with a deadline on it.
  ///
  /// Every path here crosses a platform channel, and a channel that never
  /// answers — a stalled method channel, a plugin race at startup — left this
  /// row on "Checking…" for as long as the screen stayed up, with no retry and
  /// nothing on it to tap. So the wait is bounded, and what comes back when it
  /// expires is NULL, not false: false is a claim — "the permission is off" —
  /// and nothing here was able to check it. The row paints null as an honest
  /// unknown with its own way out.
  static Future<bool?> _bounded(Future<bool> read) async {
    try {
      return await read.timeout(_readTimeout);
    } catch (_) {
      // Includes the timeout itself.
      return null;
    }
  }

  Future<void> _refresh() async {
    final generation = ++_readGeneration;
    // Both reads go out together, each bounded by the SAME deadline, so
    // "Checking…" lasts [_readTimeout] at most rather than twice it. They are
    // still bounded separately: the permission history lands even when it is
    // the state read that has stalled. A false "asked" is the safe direction
    // to be wrong in — the tap then tries the prompt once more, and a request
    // Android decides to swallow simply answers false.
    final answers = await Future.wait<bool?>([
      _bounded(NotificationService.notificationsEnabled()),
      _bounded(NotificationService.hasAskedPermission()),
    ]);
    if (!mounted || generation != _readGeneration) return;
    setState(() {
      _enabled = answers[0];
      _gaveUp = answers[0] == null;
      _asked = answers[1] ?? false;
    });
  }

  /// One tap, three possible answers.
  ///
  /// Nothing could be read: this is the retry. Re-read, and only re-read —
  /// acting on a state nobody knows would mean prompting on a guess, and the
  /// prompt is one-shot.
  ///
  /// Not asked yet: the prompt can still be put on screen, so ask. Asked
  /// already: Android swallows a second request, so the switch in system
  /// Settings is the only route left — one app's page deep, since nothing in
  /// pubspec opens the notifications sub-page directly and none may be added.
  Future<void> _onTap() async {
    if (_busy) return;
    setState(() => _busy = true);
    final retry = _gaveUp;
    if (!retry) {
      try {
        // Bounded, like the read above: `_busy` is what disables this row, and
        // a call that never returns would leave it un-tappable for the rest of
        // the screen's life.
        if (_asked) {
          await Geolocator.openAppSettings().timeout(_readTimeout);
        } else {
          await NotificationService.ensurePermission().timeout(_readTimeout);
        }
      } catch (_) {
        // Neither a permission prompt nor a Settings intent is allowed to take
        // the tap down: the row keeps reporting whatever it could read.
      }
    }
    await _refresh();
    if (!mounted) return;
    setState(() => _busy = false);
  }

  /// The state word on the right.
  ///
  /// Measured against real Roboto on a 412pt phone, the value column this row
  /// shares with the ones around it is 81.3px wide, and "Off — tap to enable"
  /// is 119px: it would have ellipsised down to "Off — tap t…", dropping the
  /// hint, which is the one thing the Off state has to say. So the word is the
  /// state alone and the action lives under the label ([_supporting]), where
  /// the column is 162.7px and the sentence fits intact.
  ///
  /// Three states, and the last one is not a third spelling of Off: while the
  /// phone is still being asked, "Checking…"; when that ask gave up,
  /// "Unknown" — a resting state, which is why it is not drawn in the error
  /// colour and why the line under the label offers a re-read instead of a
  /// permission change.
  String get _state {
    final enabled = _enabled;
    if (enabled == null) return _gaveUp ? 'Unknown' : 'Checking\u2026';
    return enabled ? 'On' : 'Off';
  }

  /// The line under the label: what this row governs, or what to do while it
  /// is off. Every supporting line on this page is a short phrase ("Light,
  /// dark or system" is the longest at 112.5px) — this one started at 171.3px
  /// and was the only one that would have been trimmed by its column.
  String get _supporting {
    if (_enabled == false) return 'Tap to turn them on';
    if (_gaveUp) return 'Tap to check again';
    return 'Trip and arrival alerts';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = _enabled;

    return Semantics(
      button: true,
      label: 'Notifications, currently $_state',
      child: InkWell(
        key: const ValueKey('settings-row-notifications'),
        onTap: _busy ? null : _onTap,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            // Same structure as the option and nav rows above: the label sits
            // at the TOP of the row and the state word on its own axis, so a
            // column of values down the page lines up. A `start` Row hands its
            // children a loose height, which is why the centring is at the Row
            // and the label is pinned back to the top by its Align.
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.notifications_rounded,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // flex 2, the same share every other row on this page gives its
              // label. Without it the label column and the state word split the
              // free space evenly and the state lands ~45px off the value
              // column the rows above and below use.
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Notifications',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          _supporting,
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
                  _state,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  // The state is the value on this row, in the accent like the
                  // other rows' values — and in the error colour when it is
                  // the one state that is costing the user their alerts.
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: enabled == true
                        ? scheme.primary
                        : enabled == false
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Every other row ends with an 8px gap and a 20px caret; this one
              // has neither — it navigates nowhere, and a chevron would promise
              // a screen it does not open. The space is still reserved, so the
              // state word sits on the same x as the values around it instead
              // of drifting right by the width of a caret.
              const SizedBox(width: AppSpacing.xs + 20),
            ],
          ),
        ),
      ),
    );
  }
}
