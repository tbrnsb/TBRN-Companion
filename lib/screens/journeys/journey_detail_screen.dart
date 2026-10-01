import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/checklist_provider.dart';
import 'package:flutter_application_1/providers/journey_provider.dart';
import 'package:flutter_application_1/providers/location_provider.dart';
import 'package:flutter_application_1/providers/settings_provider.dart';
import 'package:flutter_application_1/providers/transaction_provider.dart';
import 'package:flutter_application_1/screens/checklists/add_checklist_screen.dart';
import 'package:flutter_application_1/screens/checklists/checklist_detail_screen.dart';
import 'package:flutter_application_1/screens/journeys/trip_shared_section.dart';
import 'package:flutter_application_1/screens/transactions/add_transaction_sheet.dart';
import 'package:flutter_application_1/services/packing_suggestions.dart';
import 'package:flutter_application_1/screens/transactions/expense_detail_screen.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/utils/format.dart';
import 'package:flutter_application_1/widgets/widgets.dart';

/// Journey detail — the hub that connects packing, places, and spending
/// for one journey.
class JourneyDetailScreen extends StatelessWidget {
  const JourneyDetailScreen({super.key, required this.journey});

  /// Widest content measure at which three stat tiles still fit an amount
  /// without clipping. Below it the row becomes two-plus-one.
  static const double _threeTileBreakpoint = 600;

  final Journey journey;

  @override
  Widget build(BuildContext context) {
    final journeys = context.watch<JourneyProvider>();
    final current = journeys.getJourneyById(journey.id) ?? journey;
    final checklists = context
        .watch<ChecklistProvider>()
        .getChecklistsForJourney(current.id);
    final places = context.watch<LocationProvider>().getLocationsForJourney(
      current.id,
    );
    final transactions = context.watch<TransactionProvider>();
    final currencySymbol = context.select<SettingsProvider, String>(
      (s) => s.currency.symbol,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(current.title),
        actions: [
          if (!current.completed)
            TextButton.icon(
              onPressed: () async {
                await context.read<JourneyProvider>().completeJourney(
                  current.id,
                );
              },
              icon: const Icon(Icons.check_circle_outline_rounded),
              label: const Text('Complete'),
            ),
        ],
      ),
      body: ListView(
        padding: AppSpacing.screenPadding,
        children: [
          _JourneyHeader(journey: current),
          if (current.notes.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              current.notes,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),

          // Cross-system context.
          //
          // The LIVE twin of the settlement's query. A trashed trip expense is
          // gone from the user's ledger, so it must not still be adding to the
          // trip's headline spend here — while settlement keeps counting it,
          // because the other people did spend it. Two reads of one box,
          // answering two different questions, on purpose.
          FutureBuilder<List<Transaction>>(
            future: transactions.getLiveTransactionsForJourney(current.id),
            builder: (context, snapshot) {
              final transactions = snapshot.data ?? const <Transaction>[];
              final expenses = transactions.whereType<Expense>().toList();
              final spent = expenses.fold<double>(0, (s, e) => s + e.amount);
              final packed = checklists.fold<int>(
                0,
                (s, c) => s + c.items.where((i) => i.isChecked).length,
              );
              final totalItems = checklists.fold<int>(
                0,
                (s, c) => s + c.items.length,
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Three tiles across only once there is room for the money
                  // value to render whole. On a 360dp phone three across left
                  // each tile ~101dp — about 77dp of text — and the amount
                  // clipped to "Rs. 1,2…", which is worse than showing fewer tiles.
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final tiles = <Widget>[
                        AppStatTile(
                          icon: Icons.backpack_rounded,
                          label: 'Packed',
                          value: totalItems == 0 ? '—' : '$packed/$totalItems',
                        ),
                        AppStatTile(
                          icon: Icons.place_rounded,
                          label: 'Places',
                          value: '${places.length}',
                        ),
                        AppStatTile(
                          icon: Icons.payments_rounded,
                          label: 'Spent',
                          value: AppFormat.money(spent, symbol: currencySymbol),
                        ),
                      ];

                      if (constraints.maxWidth >= _threeTileBreakpoint) {
                        return Row(
                          children: [
                            for (var i = 0; i < tiles.length; i++) ...[
                              if (i > 0) const SizedBox(width: AppSpacing.sm),
                              Expanded(child: tiles[i]),
                            ],
                          ],
                        );
                      }

                      // Two across, then the money tile on its own full-width
                      // row so the amount has the whole measure to itself.
                      return Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: tiles[0]),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(child: tiles[1]),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          tiles[2],
                        ],
                      );
                    },
                  ),
                  if (expenses.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    const SectionHeader('Journey spending'),
                    const SizedBox(height: AppSpacing.xs),
                    ...expenses
                        .take(5)
                        .map(
                          (e) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              e.categoryMeta.icon,
                              size: 20,
                              color: e.categoryMeta.color,
                            ),
                            title: Text(
                              e.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(AppFormat.shortDate(e.date)),
                            trailing: Text(
                              // Expenses are outflows, so they carry the
                              // minus sign — same convention as the Spend list.
                              AppFormat.signedMoney(
                                e.amount,
                                isExpense: true,
                                symbol: currencySymbol,
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ExpenseDetailScreen(expense: e),
                              ),
                            ),
                          ),
                        ),
                  ],
                ],
              );
            },
          ),

          const SizedBox(height: AppSpacing.lg),
          SectionHeader(
            'Packing',
            trailing: checklists.isEmpty
                ? null
                : Text(
                    '${checklists.length} list${checklists.length == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (checklists.isEmpty) ...[
            _InlineHint(
              icon: Icons.checklist_rounded,
              text: 'No packing list for this journey yet.',
            ),
            const SizedBox(height: AppSpacing.xs),
            // The one-tap join between the trip's own item list and the Pack
            // tab. Without it a trip carried items nothing could tick off, and
            // the Pack tab carried checklists nothing linked to the trip.
            _PackForTripButton(journey: current),
          ] else
            ...checklists.map((c) => _ChecklistRow(checklist: c)),

          // Only renders once the trip has at least one person on it, so the
          // block cannot be a dead section on a solo trip.
          TripSharedSection(journeyId: current.id),

          const SizedBox(height: AppSpacing.lg),
          SectionHeader('Places'),
          const SizedBox(height: AppSpacing.xs),
          if (places.isEmpty)
            _InlineHint(
              icon: Icons.place_outlined,
              text: 'No saved places linked to this journey.',
            )
          else
            ...places.map(
              (p) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.place_rounded, size: 20),
                title: Text(
                  p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: p.description.isEmpty
                    ? null
                    : Text(
                        p.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
            ),

          const SizedBox(height: AppSpacing.lg),
          const SectionHeader('Quick actions'),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              ActionChip(
                avatar: const Icon(Icons.add_task_rounded, size: 18),
                label: const Text('New checklist'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AddChecklistScreen(journeyId: current.id),
                  ),
                ),
              ),
              ActionChip(
                avatar: const Icon(Icons.payments_rounded, size: 18),
                label: const Text('Add transaction'),
                onPressed: () => AddTransactionSheet.show(
                  context,
                  initialJourneyId: current.id,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _JourneyHeader extends StatelessWidget {
  const _JourneyHeader({required this.journey});

  final Journey journey;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final status = journey.status;

    final statusColor = switch (status) {
      JourneyStatus.active => AppColors.success,
      JourneyStatus.upcoming => AppColors.info,
      JourneyStatus.completed => colorScheme.onSurfaceVariant,
    };

    final start = DateFormat('MMM d').format(journey.startTime);
    final end = journey.endTime != null
        ? DateFormat('MMM d').format(journey.endTime!)
        : null;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: AppRadii.mediumRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.route_rounded,
                size: 18,
                color: colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  '${journey.origin} → ${journey.destination}',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: AppRadii.smallRadius,
                ),
                child: Text(
                  status.label,
                  style: textTheme.labelMedium?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            end == null
                ? 'Started $start · in progress'
                : '$start – $end · ${journey.durationText}',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (journey.items.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: journey.items
                  .map(
                    (item) => Chip(
                      label: Text(item),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Pack for this trip" — one tap, and the trip has a real checklist.
///
/// Builds it from two sources: whatever the trip already carried in its own
/// `items` list, plus what the trip itself implies (where, when, how long).
/// Both are the user's own data; nothing is fetched.
///
/// Offers to open the result, because creating a list the user then has to go
/// hunting for is the same as not creating it.
class _PackForTripButton extends StatelessWidget {
  const _PackForTripButton({required this.journey});

  final Journey journey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final itemCount = journey.items.where((i) => i.trim().isNotEmpty).length;
    final suggestionCount = PackingSuggestions.forTrip(
      destination: journey.destination,
      startTime: journey.startTime,
      endTime: journey.endTime,
    ).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const ValueKey('pack-for-this-trip'),
            onPressed: () async {
              final provider = context.read<ChecklistProvider>();
              final messenger = ScaffoldMessenger.of(context);
              final created = await provider.packForJourney(journey);
              if (!context.mounted) return;
              if (created == null) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Already packed for this trip')),
                );
                return;
              }
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChecklistDetailScreen(checklist: created),
                ),
              );
            },
            icon: const Icon(Icons.backpack_rounded, size: 18),
            label: const Text('Pack for this trip'),
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          itemCount > 0
              ? 'Starts with the $itemCount ${itemCount == 1 ? 'item' : 'items'} '
                    'you already listed, plus $suggestionCount more for '
                    '${journey.destination.isEmpty ? 'this trip' : journey.destination}.'
              : 'Adds $suggestionCount things worth taking for '
                    '${journey.destination.isEmpty ? 'this trip' : journey.destination}.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({required this.checklist});

  final Checklist checklist;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final packed = checklist.items.where((i) => i.isChecked).length;

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          value: checklist.items.isEmpty ? 0 : checklist.getProgress(),
          strokeWidth: 3.5,
          backgroundColor: colorScheme.surfaceContainerHighest,
        ),
      ),
      title: Text(checklist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('$packed of ${checklist.items.length} packed'),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChecklistDetailScreen(checklist: checklist),
        ),
      ),
    );
  }
}

class _InlineHint extends StatelessWidget {
  const _InlineHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
