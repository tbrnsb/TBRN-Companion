import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/providers/checklist_provider.dart';
import 'package:daily_companion/providers/journey_provider.dart';
import 'package:daily_companion/providers/location_provider.dart';
import 'package:daily_companion/screens/checklists/checklist_detail_screen.dart';
import 'package:daily_companion/screens/checklists/add_checklist_screen.dart';
import 'package:daily_companion/theme/app_theme.dart';
import 'package:daily_companion/widgets/widgets.dart';

class ChecklistsScreen extends StatefulWidget {
  const ChecklistsScreen({super.key});

  @override
  State<ChecklistsScreen> createState() => _ChecklistsScreenState();
}

class _ChecklistsScreenState extends State<ChecklistsScreen> {
  @override
  Widget build(BuildContext context) {
    // Selected, not watched: this is ONE bool off the provider, and watching
    // the whole thing rebuilt the app bar and the Consumer below on every
    // checklist change in the app. The Consumer does its own watching for the
    // body; this only has to know when the list crosses the empty/not-empty
    // line, which is the same answer the empty state is built from.
    final isEmpty = context.select<ChecklistProvider, bool>(
      (p) => p.regularChecklists.isEmpty,
    );

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

              // From the REGULAR lists, not the raw ones: a preset is a
              // template for journeys, and a template attached to the place
              // you happen to be standing in is not a packing reminder.
              final locationLinkedChecklists = checklistProvider
                  .regularChecklists
                  .where(
                    (c) =>
                        c.linkedLocationId != null &&
                        c.linkedLocationId ==
                            locationProvider.currentLocationId,
                  )
                  .toList();

              // No local `isEmpty`: the build-level one above reads the
              // same expression, and a second copy shadowed it — two answers
              // to one question, kept in step only by luck.

              return ListView(
                // Clears the FAB; see AppSpacing.screenPaddingWithFab.
                padding: AppSpacing.screenPaddingWithFab,
                children: [
                  // The user's OWN lists come first. The context cards used to
                  // render above them, so a person who had packed a dozen things
                  // into a journey scrolled past decoration before reaching
                  // their own checklist and concluded it was missing. It was
                  // never missing; it was below the fold.
                  //
                  // Nothing is hidden for it. Both cards still render when they
                  // apply, directly under the list, and both are derived from
                  // data the user created rather than guessed at.
                  if (isEmpty)
                    EmptyState(
                      icon: Icons.checklist_rounded,
                      title: 'No checklists yet',
                      message: journeyProvider.activeJourney == null
                          ? 'Create your first checklist'
                          : 'Create a checklist, or pack for the trip you have going',
                      actionLabel: 'Add checklist',
                      onAction: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AddChecklistScreen(),
                          ),
                        );
                      },
                    )
                  else ...[
                    const SectionHeader('Your checklists'),
                    const SizedBox(height: AppSpacing.xs),
                    ..._buildChecklistCards(context, checklistProvider),
                  ],
                  if (checklistProvider.presets.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    const SectionHeader('Presets'),
                    const SizedBox(height: AppSpacing.xs),
                    ..._buildPresetRows(context, checklistProvider),
                  ],
                  const SizedBox(height: AppSpacing.md),
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
                    const SizedBox(height: AppSpacing.xs),
                  ],
                ],
              );
            },
      ),
      // Hidden while the list is empty. The empty state already offers
      // "Add checklist" in the middle of the screen, and a FAB saying the same
      // thing underneath it gave the user two buttons doing one job on the same
      // screen. The empty state's action is the one call to action; the FAB
      // returns once there is something to add to. One action, one label —
      // both said "checklist", one in Title Case and one in sentence case.
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
              label: const Text('Add checklist'),
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
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
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

    return provider.regularChecklists.where((c) => !c.isEverydayEssentials).map((
      checklist,
    ) {
      return Column(
        // Stable identity: a new checklist lands at the top of this list and
        // every card underneath shifts, so an unkeyed child is rebuilt from
        // scratch instead of moved.
        key: ValueKey<String>(checklist.id),
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
                  const SizedBox(width: AppSpacing.sm),
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
                          const SizedBox(height: AppSpacing.xs),
                          ClipRRect(
                            borderRadius: AppRadii.smallRadius,
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
                  const SizedBox(width: AppSpacing.xs),
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
                      PopupMenuItem(
                        child: const Text('Save as preset'),
                        onTap: () {
                          // Captured BEFORE the await: once the menu is gone
                          // and the write is in flight, this closure's
                          // context may belong to a disposed subtree, and the
                          // messenger is the only thing the snackbar needs.
                          final messenger = ScaffoldMessenger.of(context);
                          final name = checklist.name;
                          provider.saveAsPreset(checklist.id).then((saved) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  saved
                                      ? '$name saved as preset'
                                      : 'Could not save "$name" as a preset',
                                ),
                              ),
                            );
                          });
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

  /// The saved presets, as their own section under the real lists.
  ///
  /// A preset has to be VISIBLE somewhere: "Save as preset" that makes a
  /// checklist vanish from the screen reads as data loss, not as saving. These
  /// rows are lighter than the checklist cards — no progress bar, because
  /// nothing is being packed from here — but they share the same leading
  /// glyph, the same inset, and the same trailing menu, so the two sections
  /// read as one family.
  List<Widget> _buildPresetRows(
    BuildContext context,
    ChecklistProvider provider,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return provider.presets.map((preset) {
      return Column(
        key: ValueKey<String>(preset.id),
        children: [
          InkWell(
            onTap: () {
              // The place to USE a preset is the journey sheet, which is
              // where the packing list is being built. Opening the editor
              // from here would let ticks on a template's items drift, and a
              // template with ticked items is a confusing thing to start a
              // trip from.
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '"${preset.name}" is available when you start a journey',
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: colorScheme.secondaryContainer,
                    child: Icon(
                      Icons.playlist_add_check_rounded,
                      color: colorScheme.secondary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          preset.name,
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${preset.items.length} ${preset.items.length == 1 ? 'item' : 'items'} — used when starting a journey',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton(
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        child: const Text('Delete'),
                        onTap: () {
                          _showDeleteConfirmation(context, provider, preset);
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
        // The noun follows the thing: "Delete preset?" reads correctly from
        // the preset section, where the row is not a checklist to the user.
        title: Text(
          checklist.isPreset ? 'Delete preset?' : 'Delete checklist?',
        ),
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
