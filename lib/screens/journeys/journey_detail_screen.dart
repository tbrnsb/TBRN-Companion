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
import 'package:flutter_application_1/screens/transactions/add_transaction_sheet.dart';
import 'package:flutter_application_1/screens/transactions/expense_detail_screen.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/utils/format.dart';
import 'package:flutter_application_1/widgets/widgets.dart';

/// Journey detail — the hub that connects packing, places, and spending
/// for one journey.
class JourneyDetailScreen extends StatelessWidget {
  const JourneyDetailScreen({super.key, required this.journey});

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
          FutureBuilder<List<Transaction>>(
            future: transactions.getTransactionsByJourney(current.id),
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
                  Row(
                    children: [
                      Expanded(
                        child: AppStatTile(
                          icon: Icons.backpack_rounded,
                          label: 'Packed',
                          value: totalItems == 0 ? '—' : '$packed/$totalItems',
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: AppStatTile(
                          icon: Icons.place_rounded,
                          label: 'Places',
                          value: '${places.length}',
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: AppStatTile(
                          icon: Icons.payments_rounded,
                          label: 'Spent',
                          value: AppFormat.money(spent, symbol: currencySymbol),
                        ),
                      ),
                    ],
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
          if (checklists.isEmpty)
            _InlineHint(
              icon: Icons.checklist_rounded,
              text: 'No packing list for this journey yet.',
            )
          else
            ...checklists.map((c) => _ChecklistRow(checklist: c)),

          const SizedBox(height: AppSpacing.lg),
          const SectionHeader('Places'),
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
