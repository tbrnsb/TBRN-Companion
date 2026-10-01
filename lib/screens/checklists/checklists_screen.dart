import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/checklist_provider.dart';
import 'package:flutter_application_1/providers/journey_provider.dart';
import 'package:flutter_application_1/providers/location_provider.dart';
import 'package:flutter_application_1/services/packing_suggestions.dart';
import 'package:flutter_application_1/screens/checklists/checklist_detail_screen.dart';
import 'package:flutter_application_1/screens/checklists/add_checklist_screen.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/widgets/widgets.dart';

class ChecklistsScreen extends StatefulWidget {
  const ChecklistsScreen({super.key});

  @override
  State<ChecklistsScreen> createState() => _ChecklistsScreenState();
}

class _ChecklistsScreenState extends State<ChecklistsScreen> {
  @override
  Widget build(BuildContext context) {
    // Watched here, outside the Consumer below, because the FAB decision needs
    // the same "is it empty" answer the empty state is built from.
    final isEmpty = context.watch<ChecklistProvider>().checklists.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Packing'),
        actions: const [AppCalendarButton(), AppGearButton()],
      ),
      body: Consumer3<ChecklistProvider, LocationProvider, JourneyProvider>(
        builder:
            (context, checklistProvider, locationProvider, journeyProvider, _) {
              if (checklistProvider.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              final activeJourney = journeyProvider.activeJourney;
              // Read from the trip itself — where, when, how long — rather than
              // keyword-matching the destination. Two unrelated trips used to get
              // the same six generic suggestions because neither name matched a
              // keyword.
              final suggestions = activeJourney == null
                  ? const <PackingSuggestion>[]
                  : PackingSuggestions.forTrip(
                      destination: activeJourney.destination,
                      startTime: activeJourney.startTime,
                      endTime: activeJourney.endTime,
                    );

              final locationLinkedChecklists = checklistProvider.checklists
                  .where(
                    (c) =>
                        c.linkedLocationId != null &&
                        c.linkedLocationId ==
                            locationProvider.currentLocationId,
                  )
                  .toList();

              final isEmpty = checklistProvider.checklists.isEmpty;

              return ListView(
                padding: AppSpacing.screenPadding,
                children: [
                  if (suggestions.isNotEmpty)
                    _buildTripSuggestionCard(
                      context,
                      activeJourney!,
                      suggestions,
                    ),
                  if (locationLinkedChecklists.isNotEmpty)
                    _buildLocationReminderCard(
                      context,
                      locationLinkedChecklists,
                    ),
                  if (checklistProvider.everydayEssentials != null) ...[
                    _buildEverydayEssentialsCard(
                      context,
                      checklistProvider.everydayEssentials!,
                    ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  if (isEmpty)
                    // The suggestions above stay on screen here on purpose. The
                    // old empty state short-circuited the whole list, so the
                    // card was invisible to anyone with no checklists — which is
                    // exactly the person with a trip and nothing packed for it.
                    EmptyState(
                      icon: Icons.checklist_rounded,
                      title: 'No checklists yet',
                      message:
                          'Create your first checklist, or pack for the trip '
                          'above',
                      actionLabel: 'Create Checklist',
                      onAction: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AddChecklistScreen(),
                          ),
                        );
                      },
                    )
                  else ...[
                    const SectionHeader('All Checklists'),
                    const SizedBox(height: AppSpacing.sm),
                    ..._buildChecklistCards(context, checklistProvider),
                  ],
                ],
              );
            },
      ),
      // Hidden while the list is empty. The empty state already offers
      // "Create Checklist" in the middle of the screen, and a FAB saying
      // "New Checklist" underneath it gave the user two buttons doing the same
      // thing, worded differently, on the same screen. The empty state's
      // action is the one call to action; the FAB returns once there is
      // something to add to.
      floatingActionButton: isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                HapticFeedback.heavyImpact();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AddChecklistScreen()),
                );
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('New Checklist'),
            ),
    );
  }

  Widget _buildTripSuggestionCard(
    BuildContext context,
    Journey journey,
    List<PackingSuggestion> suggestions,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final checklists = context.read<ChecklistProvider>().checklists;
    final tripChecklist = context
        .read<ChecklistProvider>()
        .getChecklistsForJourney(journey.id)
        .firstOrNull;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ContextCard(
        icon: Icons.auto_awesome_rounded,
        title: 'For ${journey.title.isEmpty ? 'this trip' : journey.title}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Based on where you are going and when.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            // Each suggestion says WHY, so the user can judge it instead of
            // taking it on trust.
            for (final suggestion in suggestions)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                child: _SuggestionRow(
                  suggestion: suggestion,
                  onAdd: checklists.isEmpty
                      ? null
                      : () =>
                            _addSuggestionToChecklist(context, suggestion.name),
                ),
              ),
            if (tripChecklist == null && checklists.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('pack-for-this-trip'),
                  onPressed: () => _packForThisTrip(context, journey),
                  icon: const Icon(Icons.backpack_rounded, size: 18),
                  label: Text(
                    'Pack for this trip (${suggestions.length} items)',
                  ),
                ),
              ),
            ] else if (tripChecklist != null) ...[
              const SizedBox(height: AppSpacing.xs),
              _PackedLine(checklist: tripChecklist),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _packForThisTrip(BuildContext context, Journey journey) async {
    final provider = context.read<ChecklistProvider>();
    final messenger = ScaffoldMessenger.of(context);

    final created = await provider.packForJourney(journey);
    if (!context.mounted) return;

    if (created != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChecklistDetailScreen(checklist: created),
        ),
      );
      return;
    }
    // Already packed: send them to the list rather than reporting a failure.
    final existing = provider.getChecklistsForJourney(journey.id).firstOrNull;
    if (existing == null || !context.mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('Already packed for this trip')),
    );
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChecklistDetailScreen(checklist: existing),
      ),
    );
  }

  /// Asks which checklist to add [item] to, then adds it.
  ///
  /// The suggestions used to be passive Chips inside a card: the app showed the
  /// user a list of things they probably needed and offered no way to act on
  /// it. They are now buttons.
  Future<void> _addSuggestionToChecklist(
    BuildContext context,
    String item,
  ) async {
    final provider = context.read<ChecklistProvider>();
    final checklists = provider.checklists;
    if (checklists.isEmpty) return;

    // With one checklist there is nothing to choose, so skip the picker.
    final target = checklists.length == 1
        ? checklists.single
        : await _pickChecklist(context, checklists);
    if (target == null || !context.mounted) return;

    // The duplicate guard lives in the provider, so every caller gets it: a
    // second "Water bottle" on a list that already has one is noise, and the
    // user is told rather than left wondering whether the tap landed.
    final added = await provider.addItemByName(target.id, item);
    if (!context.mounted) return;
    if (!added) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$item" is already on ${target.name}')),
      );
      return;
    }

    // Kept for the follow-on behaviour below.
    final live = provider.checklists.firstWhere(
      (c) => c.id == target.id,
      orElse: () => target,
    );
    final exists = live.items.any(
      (i) => i.name.trim().toLowerCase() == item.trim().toLowerCase(),
    );

    final messenger = ScaffoldMessenger.of(context);
    if (exists) {
      messenger.showSnackBar(
        SnackBar(content: Text('"$item" is already on ${live.name}.')),
      );
      return;
    }

    await provider.addItemToChecklist(
      live.id,
      ChecklistItem(checklistId: live.id, name: item),
    );
    messenger.showSnackBar(
      SnackBar(content: Text('Added "$item" to ${live.name}.')),
    );
  }

  Future<Checklist?> _pickChecklist(
    BuildContext context,
    List<Checklist> checklists,
  ) {
    return showModalBottomSheet<Checklist>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.xs,
              ),
              child: Text(
                'Add to which checklist?',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            for (final checklist in checklists)
              ListTile(
                title: Text(checklist.name),
                subtitle: Text(
                  '${checklist.items.length} items',
                  style: Theme.of(sheetContext).textTheme.bodySmall,
                ),
                trailing: const Icon(Icons.add_rounded),
                onTap: () => Navigator.pop(sheetContext, checklist),
              ),
            const SizedBox(height: AppSpacing.xs),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationReminderCard(
    BuildContext context,
    List<Checklist> linkedChecklists,
  ) {
    final title = linkedChecklists.length > 1
        ? 'Ready for this location'
        : 'Ready for this stop';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ContextCard(
        icon: Icons.location_on_rounded,
        title: 'Geofence reminder · $title',
        color: Theme.of(context).colorScheme.primaryContainer,
        onColor: Theme.of(context).colorScheme.onPrimaryContainer,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: linkedChecklists
              .map(
                (checklist) => GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ChecklistDetailScreen(checklist: checklist),
                      ),
                    );
                  },
                  child: Chip(
                    avatar: const Icon(Icons.checklist_rounded, size: 16),
                    label: Text(checklist.name),
                    backgroundColor: Theme.of(context).colorScheme.surface
                        .withValues(alpha: 0.6),
                    side: BorderSide.none,
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _buildEverydayEssentialsCard(
    BuildContext context,
    Checklist checklist,
  ) {
    final checked = checklist.items.where((i) => i.isChecked).length;
    return AppSurface(
      tier: AppSurfaceTier.raised,
      padding: EdgeInsets.zero,
      child: ListTile(
        // AppColors.warning rather than a raw amber, so the star belongs to
        // the palette and stays legible in dark mode.
        leading: const Icon(Icons.star_rounded, color: AppColors.warning),
        title: Text(
          'Everyday Essentials',
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text('$checked/${checklist.items.length} items ready'),
        trailing: SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
            value: checklist.items.isEmpty ? 0 : checklist.getProgress(),
            strokeWidth: 5,
            backgroundColor: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest,
          ),
        ),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ChecklistDetailScreen(checklist: checklist),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildChecklistCards(
    BuildContext context,
    ChecklistProvider provider,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final journeyProvider = context.read<JourneyProvider>();

    return provider.checklists.where((c) => !c.isEverydayEssentials).map((
      checklist,
    ) {
      return Column(
        children: [
          InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChecklistDetailScreen(checklist: checklist),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: colorScheme.primaryContainer,
                    child: Icon(
                      checklist.linkedLocationId != null
                          ? Icons.location_on_rounded
                          : Icons.checklist_rounded,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          checklist.name,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (checklist.description.isNotEmpty)
                          Text(
                            checklist.description,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (checklist.linkedLocationId != null)
                          Text(
                            'Linked to saved place',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colorScheme.primary),
                          ),
                        if (checklist.journeyId != null &&
                            journeyProvider.getJourneyById(
                                  checklist.journeyId!,
                                ) !=
                                null)
                          Text(
                            'Journey: ${journeyProvider.getJourneyById(checklist.journeyId!)!.title}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colorScheme.secondary),
                          ),
                        if (checklist.items.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: checklist.getProgress(),
                              minHeight: 4,
                              backgroundColor:
                                  colorScheme.surfaceContainerHighest,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${checklist.items.where((i) => i.isChecked).length}/${checklist.items.length}',
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  PopupMenuButton(
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        child: const Text('Edit'),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  AddChecklistScreen(checklist: checklist),
                            ),
                          );
                        },
                      ),
                      PopupMenuItem(
                        child: const Text('Delete'),
                        onTap: () {
                          _showDeleteConfirmation(context, provider, checklist);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Divider(indent: 64, height: 1),
        ],
      );
    }).toList();
  }

  void _showDeleteConfirmation(
    BuildContext context,
    ChecklistProvider provider,
    Checklist checklist,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Delete checklist?'),
        content: Text(
          'Are you sure you want to delete "${checklist.name}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              provider.deleteChecklist(checklist.id);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

/// One suggestion: the thing, why it is on the list, and a button to add it.
///
/// The reason sits under the name rather than in a tooltip because a tooltip is
/// invisible until you already know to ask. This is the difference between a
/// list of guesses and a recommendation the user can accept or dismiss.
class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({required this.suggestion, this.onAdd});

  final PackingSuggestion suggestion;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onColor = theme.colorScheme.onSecondaryContainer;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                suggestion.name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: onColor,
                ),
              ),
              Text(
                suggestion.reason,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer.withValues(
                    alpha: 0.75,
                  ),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          key: ValueKey('add-suggestion-${suggestion.name}'),
          tooltip: 'Add "${suggestion.name}" to a checklist',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add_rounded, size: 20),
          onPressed: onAdd,
        ),
      ],
    );
  }
}

/// "4 of 9 packed" once the trip has a checklist, so the card says where the
/// trip got to instead of still asking to be started.
class _PackedLine extends StatelessWidget {
  const _PackedLine({required this.checklist});

  final Checklist checklist;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onColor = theme.colorScheme.onSecondaryContainer;
    final progress = checklist.getProgress();

    return Row(
      children: [
        SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            value: checklist.items.isEmpty ? 0 : progress,
            strokeWidth: 3.5,
            backgroundColor: onColor.withValues(alpha: 0.18),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            checklist.items.isEmpty
                ? 'Packed — nothing on the list yet'
                : '${checklist.items.where((i) => i.isChecked).length} of '
                      '${checklist.items.length} packed',
            style: theme.textTheme.bodyMedium?.copyWith(color: onColor),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ChecklistDetailScreen(checklist: checklist),
            ),
          ),
          child: const Text('Open'),
        ),
      ],
    );
  }
}
