import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/providers/settings_provider.dart';
import 'package:daily_companion/providers/transaction_provider.dart';
import 'package:daily_companion/theme/app_theme.dart';
import 'package:daily_companion/utils/format.dart';
import 'package:daily_companion/widgets/widgets.dart';

/// The trash: what was deleted, and a way to get it back.
///
/// Reached from Settings, and the settings entry is hidden while the trash is
/// empty — an entry that leads to an empty screen teaches people the screen is
/// not worth opening, which is exactly when it starts being worth opening.
///
/// Restore is the primary action on every row and is one tap. "Delete forever" is
/// there, and it is permanent, but it is a separate button rather than a swipe:
/// an accidental swipe that cannot be undone is the one interaction a personal
/// finance ledger must not offer.
class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  late Future<List<Transaction>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<TransactionProvider>().loadTrashedTransactions();
  }

  void _reload() {
    setState(() {
      _future = context.read<TransactionProvider>().loadTrashedTransactions();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trash'),
        actions: const [AppGearButton()],
      ),
      body: FutureBuilder<List<Transaction>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final trashed = snapshot.data ?? const <Transaction>[];

          if (trashed.isEmpty) {
            // No action here. The route back to the ledger is the app bar, and
            // an "empty trash" button in an already-empty trash is a control for
            // something that cannot happen.
            return const EmptyState(
              icon: Icons.delete_outline_rounded,
              title: 'Trash is empty',
              message:
                  'Anything you delete lands here first, so a misfire is one tap '
                  'from being undone.',
            );
          }

          return ListView(
            padding: AppSpacing.screenPadding,
            children: [
              Text(
                '${trashed.length} deleted. Restoring puts a record back exactly '
                'where it was, including its place in every chart.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              for (final transaction in trashed)
                _TrashRow(
                  transaction: transaction,
                  onRestore: () async {
                    await context.read<TransactionProvider>().restoreFromTrash(
                      transaction.id,
                    );
                    if (!mounted) return;
                    _reload();
                  },
                  onDeleteForever: () => _confirmForever(transaction),
                ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                key: const ValueKey('trash-empty-all'),
                onPressed: () => _confirmEmptyTrash(trashed.length),
                icon: const Icon(Icons.delete_sweep_rounded),
                label: const Text('Empty trash'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmForever(Transaction transaction) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete forever?'),
        content: Text(
          '"${transaction.description}" will be gone for good. This cannot be '
          'undone — restoring it is only possible while it is in the trash.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('trash-confirm-forever'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete forever'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<TransactionProvider>().deleteForever(transaction.id);
    if (!mounted) return;
    _reload();
  }

  Future<void> _confirmEmptyTrash(int count) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete all $count?'),
        content: const Text(
          'Every deleted record will be gone for good. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('trash-confirm-empty-all'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Empty trash'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<TransactionProvider>().emptyTrash();
    if (!mounted) return;
    _reload();
  }
}

class _TrashRow extends StatelessWidget {
  const _TrashRow({
    required this.transaction,
    required this.onRestore,
    required this.onDeleteForever,
  });

  final Transaction transaction;
  final VoidCallback onRestore;
  final VoidCallback onDeleteForever;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currency = context.select<SettingsProvider, String>(
      (s) => s.currency.symbol,
    );
    final meta = transaction.categoryMeta;
    final deletedAt = transaction.deletedAt;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: AppSurface(
        tier: AppSurfaceTier.flat,
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            Icon(meta.icon, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transaction.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    // "Deleted 3 Oct" when it happened, derived from the flag —
                    // never a hardcoded month name, and never the transaction's
                    // own date, which is a different date entirely.
                    [
                      transaction.effectiveCategoryName,
                      // "Deleted 3 Oct" when it happened, derived from the flag —
                      // never a hardcoded month name, and never the
                      // transaction's own date, which is a different date
                      // entirely. The record's date is the fallback for a row
                      // with no stamp, which no live row should ever have.
                      if (deletedAt != null)
                        'deleted ${DateFormat.yMMMd().format(deletedAt)}'
                      else
                        DateFormat.yMMMd().format(transaction.date),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            // Bounded. At 360dp this row is icon + text + amount + "Restore" +
            // a delete icon, and a five-figure amount with a currency prefix is
            // not a short string — the amount escaped its own box and pushed the
            // row 2.8 pixels past the card.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 96),
              child: Text(
                AppFormat.signedMoney(
                  transaction.amount,
                  isExpense: transaction.isExpense,
                  symbol: currency,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xxs),
            // Restore is the button, not an icon in a corner: it is the action
            // that makes a trash a trash rather than a graveyard, and it is the
            // one the user came here for.
            TextButton(
              key: ValueKey('trash-restore-${transaction.id}'),
              onPressed: onRestore,
              child: const Text('Restore'),
            ),
            IconButton(
              key: ValueKey('trash-forever-${transaction.id}'),
              tooltip: 'Delete forever',
              visualDensity: VisualDensity.compact,
              onPressed: onDeleteForever,
              icon: Icon(
                Icons.delete_forever_rounded,
                size: 20,
                color: scheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
