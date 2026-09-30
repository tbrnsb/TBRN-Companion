import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/checklist_provider.dart';
import 'package:flutter_application_1/providers/journey_provider.dart';
import 'package:flutter_application_1/providers/location_provider.dart';
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
      appBar: AppBar(title: const Text('Smart Packing')),
      body: Consumer3<ChecklistProvider, LocationProvider, JourneyProvider>(
        builder:
            (context, checklistProvider, locationProvider, journeyProvider, _) {
              if (checklistProvider.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              final activeJourney = journeyProvider.activeJourney;
              final recommendations = checklistProvider
                  .getRecommendedItemsForTrip(
                    tripType: activeJourney?.destination ?? '',
                    notes: activeJourney?.notes ?? '',
                    destination: activeJourney?.destination ?? '',
                  );

              final locationLinkedChecklists = checklistProvider.checklists
                  .where(
                    (c) =>
                        c.linkedLocationId != null &&
                        c.linkedLocationId ==
                            locationProvider.currentLocationId,
                  )
                  .toList();

              if (checklistProvider.checklists.isEmpty) {
                return EmptyState(
                  icon: Icons.checklist_rounded,
                  title: 'No checklists yet',
                  message:
                      'Create your first checklist to start packing smarter',
                  actionLabel: 'Create Checklist',
                  onAction: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AddChecklistScreen(),
                      ),
                    );
                  },
                );
              }

              return ListView(
                padding: AppSpacing.screenPadding,
                children: [
                  if (activeJourney != null)
                    _buildTripRecommendationCard(context, recommendations),
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
                  const SizedBox(height: 16),
                  const SectionHeader('All Checklists'),
                  const SizedBox(height: 12),
                  ..._buildChecklistCards(context, checklistProvider),
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

  Widget _buildTripRecommendationCard(
    BuildContext context,
    List<String> recommendations,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ContextCard(
        icon: Icons.auto_awesome_rounded,
        title: 'Trip suggestions',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tap one to add it to a checklist.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final item in recommendations)
                  ActionChip(
                    avatar: const Icon(Icons.add_rounded, size: 18),
                    label: Text(item),
                    tooltip: 'Add "$item" to a checklist',
                    onPressed: () => _addSuggestionToChecklist(context, item),
                  ),
              ],
            ),
          ],
        ),
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

    // Re-read: the picker may have been open a while.
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
