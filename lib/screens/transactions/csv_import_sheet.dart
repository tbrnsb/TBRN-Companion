import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/settings_provider.dart';
import 'package:flutter_application_1/providers/transaction_provider.dart';
import 'package:flutter_application_1/services/csv_document.dart';
import 'package:flutter_application_1/services/csv_import.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/utils/format.dart';
import 'package:flutter_application_1/widgets/widgets.dart';

/// Importing a CSV of transactions, as the reverse of the export.
///
/// ONE DOCUMENTED FORMAT ONLY. `date,description,amount,category,type`, exactly
/// what [CsvDocument] writes. No bank-statement layouts, no PDF, no guesswork:
/// this app does not know what your bank calls a column and pretending
/// otherwise is how people import 300 rows of column headings.
///
/// PREVIEW BEFORE WRITING, ALWAYS. The user sees every row that parsed, every row
/// that did not and why, and every row already on the phone — and can drop any of
/// them. Nothing is written until they say so, and cancelling writes nothing.
///
/// ADD-ONLY, NEVER. Nothing existing is overwritten or deleted, ever. A duplicate
/// is recognised and skipped rather than merged.
class CsvImportSheet extends StatefulWidget {
  const CsvImportSheet({super.key, required this.text, required this.fileName});

  /// The picked file's text, and its name for the preview's wording.
  ///
  /// Passed IN rather than staged on a static: the sheet is rebuilt on every
  /// keystroke of nothing and a static hand-off is one more thing that can be
  /// half-set when a second pick starts. Bytes come from the platform because on
  /// some pickers there is no path to re-open, which is also why the typed-path
  /// entry point this replaces is gone.
  final String text;
  final String fileName;

  static Future<int?> show(
    BuildContext context, {
    required String text,
    required String fileName,
  }) {
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CsvImportSheet(text: text, fileName: fileName),
    );
  }

  /// Picks a file and runs the whole flow. Returns how many rows were added.
  ///
  /// The picker is behind this rather than inline so there is ONE way into
  /// import — the same reason the typed-file-path box was removed from
  /// `trip_import_sheet.dart` once `file_picker` landed. Two entry points
  /// pointing at one sheet is one more place for them to diverge.
  static Future<int?> pickAndImport(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);

    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        withData: true,
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open the file picker: $e')),
      );
      return null;
    }

    if (picked == null || picked.files.isEmpty) return null;
    final file = picked.files.first;
    if (file.bytes == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not read that file.')),
      );
      return null;
    }

    if (!context.mounted) return null;
    return show(context, text: _decode(file), fileName: file.name);
  }

  /// Decodes picked bytes, tolerating a BOM and malformed input.
  ///
  /// A UTF-8 BOM survives as U+FEFF, which would make the first column read as
  /// '\uFEFFdate' — an unrecognised header, and then the first row mistaken for
  /// the header and silently dropped. Spreadsheets write one routinely.
  static String _decode(PlatformFile file) {
    final text = const Utf8Decoder(allowMalformed: true).convert(file.bytes!);
    return text.startsWith('\uFEFF') ? text.substring(1) : text;
  }

  @override
  State<CsvImportSheet> createState() => _CsvImportSheetState();
}

class _CsvImportSheetState extends State<CsvImportSheet> {
  CsvImportPlan? _plan;
  final Set<String> _dropped = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _analyse();
  }

  /// Builds the plan against the ledger as it actually is on this device.
  ///
  /// The duplicate check is the reason this is async and provider-driven: it has
  /// to compare against what is really stored, including trashed and trip rows
  /// the caller must not be offered.
  Future<void> _analyse() async {
    setState(() => _loading = true);
    final provider = context.read<TransactionProvider>();
    final existing = await provider.existingLedgerForImport();

    final plan = CsvImportPlan.analyse(
      text: widget.text,
      existing: existing,
      fileName: widget.fileName,
    );
    if (!mounted) return;
    setState(() {
      _plan = plan;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = _plan;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.85,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Import transactions',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('csv-import-cancel'),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (plan == null || !plan.hasContent)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: EmptyState(
                    icon: Icons.upload_file_rounded,
                    title: 'Nothing to import',
                    message:
                        'No transactions in that file. The format is one row per '
                        'transaction: date, description, amount, category, type.',
                  ),
                )
              else
                Expanded(
                  child: _PlanBody(
                    plan: plan,
                    dropped: _dropped,
                    onToggle: (key, on) => setState(() {
                      if (on) {
                        _dropped.remove(key);
                      } else {
                        _dropped.add(key);
                      }
                    }),
                  ),
                ),
              if (plan != null && plan.newRows.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const ValueKey('csv-import-confirm'),
                      onPressed: () => _confirm(plan),
                      icon: const Icon(Icons.download_done_rounded),
                      label: Text('Import ${plan.newRows.length}'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirm(CsvImportPlan plan) async {
    // Both captured before any await, so neither is a `context` read across an
    // async gap later on.
    final provider = context.read<TransactionProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // Re-check the duplicates at the moment of writing, not just at preview time.
    // Between opening the file and pressing the button the user could have
    // switched months and added a row the file also contains; this is what makes
    // "importing the same file twice changes nothing" true rather than usually
    // true.
    final existing = await provider.existingLedgerForImport();
    final known = <String>{
      for (final t in existing)
        '${t.date.toIso8601String().substring(0, 10)}|'
            '${(t.amount * 100).round()}|${t.description.trim().toLowerCase()}',
    };

    final toWrite = <Transaction>[];
    final customCategories = <String>{};
    for (final row in plan.newRows) {
      if (_dropped.contains('${row.lineNumber}')) continue;
      if (known.contains(row.dedupeKey)) continue;
      final transaction = row.toTransaction();
      if (transaction == null) continue;
      toWrite.add(transaction);

      // Custom names go through the same registry path as the "Other" screen, so
      // an imported name behaves exactly like a typed one.
      final expense = transaction;
      if (expense is Expense && expense.customCategoryName != null) {
        customCategories.add(expense.customCategoryName!);
      }
    }

    if (toWrite.isEmpty) {
      // The navigator is captured BEFORE the await above, so popping here is not
      // touching `context` across the gap. Reading `context.read` again would be.
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Nothing new to import.')),
      );
      return;
    }

    final written = await provider.addTransactionsInBulk(toWrite);
    for (final name in customCategories) {
      await provider.registerImportedCategory(name);
    }

    if (!mounted) return;
    navigator.pop(written.length);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          written.length == 1
              ? 'Imported 1 transaction.'
              : 'Imported ${written.length} transactions.',
        ),
      ),
    );
  }
}

/// The preview: every row, every reason, and a tick box on each.
class _PlanBody extends StatelessWidget {
  const _PlanBody({
    required this.plan,
    required this.dropped,
    required this.onToggle,
  });

  final CsvImportPlan plan;
  final Set<String> dropped;

  /// Ticking a row on or off, by its line number.
  ///
  /// A callback rather than the rows reaching up for the sheet's State: a
  /// `setState` called through `findAncestorStateOfType` is a protected member
  /// invoked from outside the class that owns it, and it breaks the moment the
  /// rows are reused anywhere else.
  final void Function(String key, bool on) onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = context.select<SettingsProvider, String>(
      (s) => s.currency.symbol,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                plan.summary,
                key: const ValueKey('csv-import-summary'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              // Said out loud, because a user who did not know duplicates were
              // detected would read "12 of 20 skipped" as a bug.
              Text(
                'Nothing already on this phone is changed or overwritten. '
                'Identical rows are skipped.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            children: [
              for (final row in plan.rows)
                _RowTile(
                  row: row,
                  plan: plan,
                  dropped: dropped,
                  currency: currency,
                  onToggle: onToggle,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({
    required this.row,
    required this.plan,
    required this.dropped,
    required this.currency,
    required this.onToggle,
  });

  final ParsedCsvRow row;
  final CsvImportPlan plan;
  final Set<String> dropped;
  final String currency;
  final void Function(String key, bool on) onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final key = '${row.lineNumber}';

    final isDuplicate = plan.duplicates.contains(row.dedupeKey);
    final isDropped = dropped.contains(key);

    // Three states, and each says so in words. A checkbox on a row that cannot be
    // ticked, with no explanation, is a control that looks broken.
    final (String stateLabel, Color stateColour) = !row.isValid
        ? ('Could not read', scheme.error)
        : isDuplicate
        ? ('Already on this phone', scheme.onSurfaceVariant)
        : isDropped
        ? ('Skipped', scheme.onSurfaceVariant)
        : ('Will import', scheme.primary);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: CheckboxListTile(
        key: ValueKey('csv-row-$key'),
        // Dense, because a twenty-row file has to be reviewable without scrolling
        // past most of it.
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: row.isValid && !isDuplicate && !isDropped,
        // A duplicate and a rejected row CANNOT be selected — there is nothing to
        // select. Disabled rather than hidden, so the user can see the row was
        // read and understand why it is not going in.
        onChanged: (!row.isValid || isDuplicate)
            ? null
            : (on) => onToggle(key, on ?? false),
        title: Text(
          row.isValid ? row.description!.trim() : 'Line ${row.lineNumber}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge,
        ),
        subtitle: Text(
          row.isValid
              ? [
                  if (row.categoryName!.trim().isNotEmpty)
                    row.categoryName!.trim(),
                  DateFormat.yMd().format(row.date!),
                  AppFormat.money(row.amount!, symbol: currency),
                  stateLabel,
                ].join(' · ')
              // The reason, verbatim. "Could not read" on its own is useless;
              // "unreadable amount" tells the user which line to fix.
              : '${row.failure} — ${row.raw}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: row.isValid ? scheme.onSurfaceVariant : scheme.error,
          ),
        ),
        secondary: Text(
          stateLabel,
          style: theme.textTheme.labelSmall?.copyWith(color: stateColour),
        ),
      ),
    );
  }
}
