import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/journey_provider.dart';
import 'package:flutter_application_1/providers/settings_provider.dart';
import 'package:flutter_application_1/screens/journeys/trip_import_sheet.dart';
import 'package:flutter_application_1/services/trip_snapshot_export.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/utils/format.dart';
import 'package:flutter_application_1/widgets/widgets.dart';

/// The payoff screen: what the trip cost, and the shortest list of payments that
/// clears it.
///
/// The settlement is recomputed from the trip's expenses every time this opens.
/// It is not stored, because a stored settlement would have to be recomputed
/// anyway the moment somebody added an expense, and a stale stored one is worse
/// than no settlement at all. What IS stored is which payments have been ticked
/// off, as keys that survive the recompute.
class TripSummaryScreen extends StatelessWidget {
  const TripSummaryScreen({super.key, required this.journeyId});

  final String journeyId;

  @override
  Widget build(BuildContext context) {
    final journey = context.watch<JourneyProvider>().getJourneyById(journeyId);

    if (journey == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Trip summary')),
        body: const Center(child: Text('That trip is no longer here.')),
      );
    }

    // One settlement, computed once and handed to both halves.
    //
    // The body needs it for the numbers and the action bar needs it to know
    // whether anything is still outstanding — and two separate reads could
    // disagree, which is how a screen ends up saying "everyone is even" above a
    // button that offers to settle a payment that still exists.
    return FutureBuilder<TripSettlement>(
      future: context.read<JourneyProvider>().tripSettlement(journeyId),
      builder: (context, snapshot) {
        final settlement = snapshot.data;
        return Scaffold(
          appBar: AppBar(title: const Text('Trip summary')),
          body: settlement == null
              ? const Center(child: CircularProgressIndicator())
              : _SummaryBody(journey: journey, settlement: settlement),
          bottomNavigationBar: settlement == null
              ? null
              : _SummaryActions(journey: journey, settlement: settlement),
        );
      },
    );
  }
}

class _SummaryBody extends StatelessWidget {
  const _SummaryBody({required this.journey, required this.settlement});

  final Journey journey;
  final TripSettlement settlement;

  @override
  Widget build(BuildContext context) {
    if (!journey.isShared) {
      return const _NotSharedNotice();
    }

    return ListView(
      padding: AppSpacing.screenPadding,
      children: [
        _Headline(settlement: settlement),
        const SizedBox(height: AppSpacing.md),
        _Explanation(settlement: settlement, journey: journey),
        const SizedBox(height: AppSpacing.md),
        _Balances(settlement: settlement, journey: journey),
        const SizedBox(height: AppSpacing.md),
        SectionHeader(
          settlement.transfers.isEmpty ? 'Nothing to settle' : 'Payments',
          trailing: Text(
            '${settlement.transfers.length} '
            '${settlement.transfers.length == 1 ? 'payment' : 'payments'}',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        if (settlement.transfers.isEmpty)
          const _AllSquareNotice()
        else
          _TransferList(settlement: settlement, journey: journey),
        const SizedBox(height: AppSpacing.md),
        const _LimitationsNotice(),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          key: const ValueKey('import-trip-file'),
          onPressed: () => TripImportSheet.show(context),
          icon: const Icon(Icons.file_download_rounded, size: 18),
          label: const Text('Import someone else\'s file'),
        ),
      ],
    );
  }
}

/// "Rs 13,900 spent · 3 people"
class _Headline extends StatelessWidget {
  const _Headline({required this.settlement});

  final TripSettlement settlement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencySymbol = context.select<SettingsProvider, String>(
      (s) => s.currency.symbol,
    );

    return AppSurface(
      tier: AppSurfaceTier.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            // The TRIP's cost, not the attributed part of it. The journey page
            // shows this same figure, and two screens about one trip quoting two
            // totals would be a bug, not a rounding curiosity.
            AppFormat.money(settlement.tripTotal, symbol: currencySymbol),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'spent · ${settlement.participantCount} people',
            style: theme.textTheme.bodyMedium,
          ),
          if (settlement.hasUnattributed) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Including ${AppFormat.money(settlement.unattributed, symbol: currencySymbol)} '
              'nobody has been recorded as paying, so it is not split below.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The settlement in words.
///
/// A list of payments is arithmetic; "Sita owes you Rs 867, and Rs 767 of it
/// goes to Raj, so two payments and everyone is even" is an answer. The person
/// reading this is usually holding the phone across a table and about to pay
/// somebody, so the sentence leads with them.
class _Explanation extends StatelessWidget {
  const _Explanation({required this.settlement, required this.journey});

  final TripSettlement settlement;
  final Journey journey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencySymbol = context.select<SettingsProvider, String>(
      (s) => s.currency.symbol,
    );
    String money(int paise) =>
        AppFormat.money(paise / 100, symbol: currencySymbol);

    final body = _explain(
      localId: journey.localParticipantId,
      localName: journey.localParticipant?.name,
      money: money,
    );

    return AppSurface(
      tier: AppSurfaceTier.raised,
      child: Text(body, style: theme.textTheme.bodyLarge),
    );
  }

  String _explain({
    required String? localId,
    required String? localName,
    required String Function(int) money,
  }) {
    if (settlement.transfers.isEmpty) {
      return 'Nothing is owed. Everyone on this trip is even.';
    }

    final count = settlement.transfers.length;
    final paymentWord = '$count ${count == 1 ? 'payment' : 'payments'}';
    final settleTail =
        '$paymentWord '
        '${count == 1 ? 'settles' : 'settle'} everything.';

    if (localId == null || localName == null) {
      return 'Tell the app which one you are and it will say what you owe. '
          'For now: $settleTail';
    }

    final balance = settlement.balanceFor(localId)!;
    final mine = settlement.transfers
        .where((t) => t.toId == localId || t.fromId == localId)
        .toList();

    if (mine.isEmpty) {
      return 'You are even. $settleTail';
    }

    final youGet = mine
        .where((t) => t.toId == localId)
        .fold<int>(0, (sum, t) => sum + t.amountInPaise);
    final youPay = mine
        .where((t) => t.fromId == localId)
        .fold<int>(0, (sum, t) => sum + t.amountInPaise);

    final parts = <String>[];
    if (youGet > 0) {
      final others = mine
          .where((t) => t.toId == localId)
          .map((t) => '${t.fromName} owes you ${money(t.amountInPaise)}')
          .toList();
      parts.add(others.join(' and '));
    }
    if (youPay > 0) {
      final others = mine
          .where((t) => t.fromId == localId)
          .map((t) => 'you owe ${t.toName} ${money(t.amountInPaise)}')
          .toList();
      parts.add(others.join(' and '));
    }

    final head = balance.netInPaise > 0
        ? 'You are owed ${money(youGet)} in total.'
        : balance.netInPaise < 0
        ? 'You owe ${money(youPay)} in total.'
        : 'You are even.';

    return '$head ${_sentence(parts)}. $settleTail';
  }

  /// Joins clauses into a sentence, so the text reads as one thought rather than
  /// as a list with commas in it.
  String _sentence(List<String> parts) {
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first;
    final last = parts.removeLast();
    return '${parts.join(', ')} and $last';
  }
}

class _Balances extends StatelessWidget {
  const _Balances({required this.settlement, required this.journey});

  final TripSettlement settlement;
  final Journey journey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencySymbol = context.select<SettingsProvider, String>(
      (s) => s.currency.symbol,
    );

    return AppSurface(
      tier: AppSurfaceTier.flat,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Column(
        children: [
          for (final balance in settlement.balances)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      balance.id == journey.localParticipantId
                          ? '${balance.name} (you)'
                          : balance.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    AppFormat.money(balance.paid, symbol: currencySymbol),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  SizedBox(
                    // Wide enough for a five-figure amount with its sign, so the
                    // column cannot be the one thing that clips at 360dp. Three
                    // steps of the app's own spacing scale rather than a bare
                    // number.
                    width: AppSpacing.xl + AppSpacing.lg + AppSpacing.md,
                    child: Text(
                      balance.netInPaise == 0
                          ? 'even'
                          : balance.netInPaise > 0
                          ? '+${AppFormat.money(balance.net, symbol: currencySymbol)}'
                          : '-${AppFormat.money(balance.net.abs(), symbol: currencySymbol)}',
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: balance.netInPaise > 0
                            ? AppColors.success
                            : balance.netInPaise < 0
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The transfers, each tickable.
///
/// A tick records a KEY. It does not create a transaction, and it must not: a
/// reimbursement is money coming back for money already spent, and recording one
/// as income would inflate income, the balance, the charts and every budget. The
/// expense still counts fully against the user's own spending; the split tracks
/// a receivable, nothing more.
class _TransferList extends StatelessWidget {
  const _TransferList({required this.settlement, required this.journey});

  final TripSettlement settlement;
  final Journey journey;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final transfer in settlement.transfers)
          _TransferRow(
            journeyId: journey.id,
            transfer: transfer,
            settled: journey.settledTransfers.contains(transfer.key),
            currencySymbol: context.select<SettingsProvider, String>(
              (s) => s.currency.symbol,
            ),
          ),
      ],
    );
  }
}

class _TransferRow extends StatelessWidget {
  const _TransferRow({
    required this.journeyId,
    required this.transfer,
    required this.settled,
    required this.currencySymbol,
  });

  final String journeyId;
  final Transfer transfer;
  final bool settled;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: AppSurface(
        tier: AppSurfaceTier.raised,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: InkWell(
          key: ValueKey('transfer-${transfer.key}'),
          onTap: () => _toggle(context),
          borderRadius: AppRadii.smallRadius,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
            child: Row(
              children: [
                Checkbox(
                  key: ValueKey('transfer-tick-${transfer.key}'),
                  value: settled,
                  onChanged: (_) => _toggle(context),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    '${transfer.fromName} pays ${transfer.toName}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      decoration: settled ? TextDecoration.lineThrough : null,
                      color: settled
                          ? scheme.onSurfaceVariant
                          : scheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  AppFormat.money(transfer.amount, symbol: currencySymbol),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: settled ? scheme.onSurfaceVariant : scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggle(BuildContext context) async {
    HapticFeedback.selectionClick();
    await context.read<JourneyProvider>().toggleTransferSettled(
      journeyId,
      transfer.key,
    );
  }
}

/// Export, "we're even", and the outstanding state, pinned so the buttons a
/// group reaches for are reachable without scrolling to the bottom.
class _SummaryActions extends StatelessWidget {
  const _SummaryActions({required this.journey, required this.settlement});

  final Journey journey;
  final TripSettlement settlement;

  @override
  Widget build(BuildContext context) {
    final trip = journey;
    final theme = Theme.of(context);

    // "We\'re even" only when something is actually left to settle, and
    // "Reopen" only once it has all been ticked. Deciding this from the stored
    // keys alone would show "Reopen" after a single tap on a trip with two
    // payments outstanding, which reads as though the trip were finished.
    final unsettled = settlement.transfers
        .where((t) => !trip.settledTransfers.contains(t.key))
        .length;
    final canSettle = unsettled > 0;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('share-trip-file'),
                onPressed: () => _share(context),
                icon: const Icon(Icons.ios_share_rounded, size: 18),
                label: const Text('Share'),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('mark-trip-settled'),
                onPressed: canSettle
                    ? () => _markSettled(context)
                    : () => _reopen(context),
                icon: const Icon(Icons.done_all_rounded, size: 18),
                label: Text(canSettle ? "We're even" : 'Reopen'),
                style: FilledButton.styleFrom(
                  backgroundColor: canSettle
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHighest,
                  foregroundColor: canSettle
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _share(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final journeys = context.read<JourneyProvider>();
    final trip = journey;

    try {
      final snapshot = await journeys.buildSnapshot(trip.id);
      await TripSnapshotExport.shareSnapshot(snapshot);
    } catch (e) {
      // The share sheet is a platform channel and a denied permission looks like
      // an exception. Saying so is better than appearing to have done nothing.
      messenger.showSnackBar(
        SnackBar(content: Text('Could not share that file: $e')),
      );
    }
  }

  /// "We're even" — the whole trip settled in one action.
  ///
  /// People say this over a table and move on. Without it the app nags about an
  /// outstanding balance after the group has already settled, which is worse
  /// than saying nothing.
  Future<void> _markSettled(BuildContext context) async {
    await context.read<JourneyProvider>().markWholeTripSettled(journey.id);
  }

  Future<void> _reopen(BuildContext context) async {
    final journeys = context.read<JourneyProvider>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reopen the trip?'),
        content: const Text(
          'Every ticked payment goes back to outstanding. The trip itself is '
          'not deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep as is'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Reopen'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await journeys.clearSettledTransfers(journey.id);
    }
  }
}

class _AllSquareNotice extends StatelessWidget {
  const _AllSquareNotice();

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      tier: AppSurfaceTier.raised,
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, color: AppColors.success),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'Everyone is even. Nothing left to pay.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotSharedNotice extends StatelessWidget {
  const _NotSharedNotice();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AppSpacing.screenPadding,
        child: Text(
          'This trip has nobody else on it, so there is nothing to settle. '
          'Add people from the journey page first.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

/// What this feature does not do, stated on the screen.
///
/// Not a disclaimer to cover a bug — each of these is a real limitation that
/// WILL come up on a real trip, and a wrong quiet answer is worse than a known
/// rough edge.
class _LimitationsNotice extends StatelessWidget {
  const _LimitationsNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ContextCard(
      icon: Icons.info_outline_rounded,
      title: 'Worth knowing',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '· Someone who joined late is still split across the whole trip. '
            'That is unfair, and fixing it needs a split per expense.',
            style: theme.textTheme.bodySmall,
          ),
          Text(
            '· Deletions do not travel between phones. If Raj removes an '
            'expense, it stays on your phone until he tells you.',
            style: theme.textTheme.bodySmall,
          ),
          Text(
            '· Sharing a file shares everyone\'s spending. Some people will not '
            'want their food spending visible to friends.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
