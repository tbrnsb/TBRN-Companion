import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/providers/checklist_provider.dart';
import 'package:daily_companion/providers/journey_provider.dart';
import 'package:daily_companion/providers/location_provider.dart';
import 'package:daily_companion/screens/journeys/journey_detail_screen.dart';
import 'package:daily_companion/screens/journeys/journey_detail_sheets.dart';
import 'package:daily_companion/theme/app_accents.dart';
import 'package:daily_companion/theme/app_chart_colors.dart';
import 'package:daily_companion/theme/app_theme.dart';
import 'package:daily_companion/utils/format.dart';
import 'package:daily_companion/widgets/widgets.dart';

ColorScheme colorSchemeOf(BuildContext context) =>
    Theme.of(context).colorScheme;

class JourneysScreen extends StatefulWidget {
  const JourneysScreen({super.key});

  @override
  State<JourneysScreen> createState() => _JourneysScreenState();
}

class _JourneysScreenState extends State<JourneysScreen> {
  final _destinationController = TextEditingController();
  final _originController = TextEditingController();
  final _notesController = TextEditingController();
  final _itemEntryController = TextEditingController();

  /// What the user is packing, one entry at a time.
  ///
  /// This was a single "What are you taking? (comma separated)" field. The
  /// journey model has always stored a list, so the commas were pure typing
  /// ceremony: no way to see what was already added, no way to remove one item
  /// without retyping the rest, and a stray comma silently creating an empty
  /// entry. The list is the real shape of the data.
  final List<String> _plannedItems = [];

  /// The month the shared log describes. Not editable here any more — the
  /// calendar in the app bar owns month navigation now — so it is just "now",
  /// stated once instead of at every use.
  final DateTime _timelineMonth = DateTime.now();
  DateTime? _plannedStart;

  @override
  void dispose() {
    _destinationController.dispose();
    _originController.dispose();
    _notesController.dispose();
    _itemEntryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<JourneyProvider, LocationProvider>(
      builder: (context, journeyProvider, locationProvider, _) {
        final active = journeyProvider.activeJourney;
        final geofenceAlert = locationProvider.getGeofenceAlertForJourney(
          active,
        );

        return Scaffold(
          appBar: AppBar(
            title: const Text('Journey Companion'),
            actions: [
              IconButton(
                tooltip: 'Share journey log',
                onPressed: () => _shareJourneys(journeyProvider),
                icon: const Icon(Icons.ios_share_rounded),
              ),
              const AppCalendarButton(),
              const AppGearButton(),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: journeyProvider.loadJourneys,
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                if (active != null) ...[
                  _ActiveJourneyCard(
                    journey: active,
                    onOpen: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => JourneyDetailScreen(journey: active),
                      ),
                    ),
                    reminderHints: journeyProvider.smartReminders,
                    onComplete: () async {
                      await journeyProvider.completeJourney(active.id);
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                if (geofenceAlert != null) ...[
                  ContextCard(
                    icon: Icons.location_on_rounded,
                    title: 'Saved place alert',
                    child: Text(geofenceAlert),
                  ),
                  const SizedBox(height: 12),
                ],
                _buildStartJourneyCard(context, journeyProvider),
                const SizedBox(height: 24),
                _SummaryRow(provider: journeyProvider),
                const SizedBox(height: AppSpacing.lg),
                // The month grid that used to live here is now the calendar in
                // the app bar, on every tab. It answered a general question —
                // "what was on the 12th?" — from the one screen that had
                // nothing to do with it, and it duplicated day details the
                // ledger already owns. Recent journeys below is the journey
                // tab's actual job.
                const SectionHeader('Recent journeys'),
                const SizedBox(height: 12),
                if (journeyProvider.journeys.isEmpty)
                  const AppSurface(
                    tier: AppSurfaceTier.flat,
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Center(child: Text('No journeys logged yet.')),
                  )
                else
                  ...journeyProvider.journeys.map(
                    (journey) => _JourneyTile(journey: journey),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Adds what is in the entry field to the packing list.
  ///
  /// Commas still split, because that is how people paste a list they already
  /// have somewhere, and rejecting that would be pedantic. The entry field is
  /// cleared either way so the same text cannot be added twice by accident, and
  /// a repeat of something already listed is ignored rather than duplicated.
  void _addPlannedItems() {
    final typed = _itemEntryController.text.trim();
    if (typed.isEmpty) return;

    final additions = typed
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty);

    setState(() {
      for (final item in additions) {
        final alreadyThere = _plannedItems.any(
          (existing) => existing.toLowerCase() == item.toLowerCase(),
        );
        if (!alreadyThere) _plannedItems.add(item);
      }
    });
    _itemEntryController.clear();
  }

  Widget _buildStartJourneyCard(
    BuildContext context,
    JourneyProvider journeyProvider,
  ) {
    return AppSurface(
      tier: AppSurfaceTier.raised,
      padding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(
          Icons.play_arrow_rounded,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text(
          'Start a new journey',
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          TextField(
            controller: _originController,
            decoration: const InputDecoration(
              labelText: 'Where are you starting?',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _destinationController,
            decoration: const InputDecoration(
              labelText: 'Where are you going?',
            ),
          ),
          const SizedBox(height: 12),
          _PackingListEditor(
            entryController: _itemEntryController,
            items: _plannedItems,
            onAdd: _addPlannedItems,
            onRemove: (item) => setState(() => _plannedItems.remove(item)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  _plannedStart == null
                      ? 'Starts now'
                      : 'Starts: ${DateFormat.yMMMd().add_jm().format(_plannedStart!)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _plannedStart ?? now,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    if (!context.mounted) return;
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.now(),
                    );
                    if (!context.mounted) return;
                    setState(() {
                      _plannedStart = DateTime(
                        picked.year,
                        picked.month,
                        picked.day,
                        time?.hour ?? now.hour,
                        time?.minute ?? now.minute,
                      );
                    });
                  }
                },
                icon: const Icon(Icons.event_rounded, size: 18),
                label: const Text('Planned start'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Trip notes'),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                HapticFeedback.heavyImpact();
                final destination = _destinationController.text.trim();
                final origin = _originController.text.trim();
                if (destination.isEmpty || origin.isEmpty) {
                  HapticFeedback.vibrate();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Origin and destination are required.'),
                      behavior: SnackBarBehavior.floating,
                      margin: EdgeInsets.all(AppSpacing.md),
                    ),
                  );
                  return;
                }

                await journeyProvider.startJourney(
                  destination: destination,
                  origin: origin,
                  notes: _notesController.text.trim(),
                  items: List.of(_plannedItems),
                  plannedStart: _plannedStart,
                );
                if (!mounted) return;
                setState(() => _plannedStart = null);

                _destinationController.clear();
                _originController.clear();
                _notesController.clear();
                _itemEntryController.clear();
                setState(_plannedItems.clear);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.white),
                        SizedBox(width: 12),
                        Expanded(child: Text('Journey started!')),
                      ],
                    ),
                    // A success snackbar, themed rather than pinned to
                    // Colors.green, which ignored the app's palette and the
                    // user's dark mode.
                    backgroundColor: AppColors.success,
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.all(AppSpacing.md),
                  ),
                );
              },
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Start journey'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareJourneys(JourneyProvider provider) async {
    final summary = provider.buildShareSummaryText(month: _timelineMonth);
    final lines = <String>[
      'Journey Log',
      '================',
      summary,
      '---',
      ...provider.journeys.map((journey) {
        final start = DateFormat.yMMMd().add_jm().format(journey.startTime);
        final end = journey.endTime == null
            ? 'In progress'
            : DateFormat.yMMMd().add_jm().format(journey.endTime!);
        return [
          '${journey.origin} → ${journey.destination}',
          'Status: ${journey.completed ? 'Completed' : 'Active'}',
          'Started: $start',
          'Ended: $end',
          if (journey.notes.isNotEmpty) 'Notes: ${journey.notes}',
          if (journey.items.isNotEmpty) 'Items: ${journey.items.join(', ')}',
          '---',
        ].join('\n');
      }),
    ];

    await SharePlus.instance.share(ShareParams(text: lines.join('\n')));
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.provider});

  final JourneyProvider provider;

  @override
  Widget build(BuildContext context) {
    // Each stat carries the sheet it opens, so the number on screen and the
    // detail behind it cannot drift apart.
    final stats = [
      (
        label: 'Trips',
        value: provider.totalJourneys.toString(),
        icon: Icons.route_rounded,
        stat: JourneyStat.trips,
      ),
      (
        label: 'Completed',
        value: provider.completedJourneys.toString(),
        icon: Icons.check_circle_rounded,
        stat: JourneyStat.completed,
      ),
      (
        label: 'Avg. time',
        value: AppFormat.duration(provider.averageJourneyMinutes),
        icon: Icons.timer_rounded,
        stat: JourneyStat.averageTime,
      ),
      (
        label: 'Packed',
        value: provider.totalPackedItems.toString(),
        icon: Icons.backpack_rounded,
        stat: JourneyStat.packed,
      ),
    ];

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _tile(context, stats[0])),
            const SizedBox(width: 12),
            Expanded(child: _tile(context, stats[1])),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _tile(context, stats[2])),
            const SizedBox(width: 12),
            Expanded(child: _tile(context, stats[3])),
          ],
        ),
      ],
    );
  }

  Widget _tile(
    BuildContext context,
    ({String label, String value, IconData icon, JourneyStat stat}) stat,
  ) {
    return Semantics(
      button: true,
      label: '${stat.label}: ${stat.value}. Tap for details.',
      child: InkWell(
        borderRadius: AppRadii.smallRadius,
        onTap: () {
          HapticFeedback.lightImpact();
          JourneyStatSheet.show(context, stat.stat);
        },
        child: AppStatTile(
          icon: stat.icon,
          label: stat.label,
          value: stat.value,
        ),
      ),
    );
  }

  /// A duration in the largest unit that says something.
  ///
  /// Days-aware, because the device showed a three-day average trip as "72h 0m".
  /// That is arithmetically right and useless to read: nobody thinks in 72-hour
  /// units, and "0m" at the end is noise. Only two units, and only as many as
  /// carry information — a trip of two days is "2d 3h", not "2d 3h 0m".
}

class _ActiveJourneyCard extends StatelessWidget {
  const _ActiveJourneyCard({
    required this.journey,
    required this.reminderHints,
    required this.onComplete,
    required this.onOpen,
  });

  final Journey journey;
  final List<String> reminderHints;
  final VoidCallback onComplete;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final started = DateFormat('MMM d, h:mm a').format(journey.startTime);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accents = AppAccents.of(context);

    // The card this is drawn on, so both accents can be resolved FOR it rather
    // than assumed. On Gruvbox the container is `selection` #504945 and both
    // accents measure about 2.7:1 on it -- under the 3:1 floor for a non-text
    // mark -- so they are lightened here rather than shipped as authored.
    final card = AppSurfaces.specFor(AppSurfaceTier.accent, colorScheme).color;
    final ink = colorScheme.onPrimaryContainer;
    final quiet = ink.withValues(alpha: 0.72);
    final supporting = AppCategoryColour.resolve(accents.cool, card);
    final emphasis = AppCategoryColour.resolve(accents.warm, card);

    // The journey in progress is the single most important thing on this
    // screen, so it is the screen's one accent surface.
    return AppSurface(
      tier: AppSurfaceTier.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // THE EYEBROW, in the second accent.
          //
          // Everything on this card used to be one colour, so nothing on it read
          // as more important than anything else -- which is what "bad in every
          // theme" looked like. The label is what the card IS, so it is the one
          // thing that should not be the loudest: small, tracked out, and in the
          // cool accent rather than the amber everything else competes for.
          Row(
            children: [
              Icon(Icons.route_rounded, size: 16, color: supporting),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'ACTIVE JOURNEY',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: supporting,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          InkWell(
            onTap: onOpen,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The loudest thing on the card, and the only large text.
                //
                // Clamped to two lines with an ellipsis: at `titleLarge` a long
                // origin and destination ran into the open affordance on the
                // right, and two place names colliding reads as a rendering
                // fault rather than as a long name.
                Expanded(
                  child: Text(
                    '${journey.origin} \u2192 ${journey.destination}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: ink,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.open_in_new_rounded,
                    size: 16,
                    color: quiet,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Started $started',
            style: theme.textTheme.bodySmall?.copyWith(color: quiet),
          ),
          if (journey.items.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            // The packing list, as a set of supporting things rather than more
            // headings: a low tint of the second accent, labels still in ink so
            // they clear the text contrast and not the non-text one.
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: journey.items
                  .map(
                    (item) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: supporting.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(AppRadii.small),
                        border: Border.all(
                          color: supporting.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        item,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: ink,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (reminderHints.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            // The reminders, as ONE quiet inset block.
            //
            // They were two identical bell icons each followed by a paragraph of
            // generic advice, drawn in the same ink and the same size as
            // everything else, so the card's loudest content was filler. One
            // marker, one block, secondary weight: present, and not competing.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppRadii.small),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.notifications_active_rounded,
                        color: quiet,
                        size: 14,
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      Expanded(
                        child: Text(
                          'While you are out',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: quiet,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  for (final hint in reminderHints)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xxs),
                      child: Text(
                        hint,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: quiet,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          // AN OUTLINED BUTTON, not a filled one.
          //
          // The trip is in progress: it is the card's subject, and the route
          // name is the thing being looked at. "Complete journey" is the action
          // that ENDS all of that, so it should be reachable, not louder than
          // the name. Filled in the warm accent it was the most saturated thing
          // on the card and the eye went to the button before the trip.
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const ValueKey('complete-journey'),
              style: OutlinedButton.styleFrom(
                // The emphasis accent as the OUTLINE, so the row still reads as
                // the card's action and is findable, without the slab of fill
                // that made it the loudest element.
                foregroundColor: emphasis,
                side: BorderSide(
                  color: emphasis.withValues(alpha: 0.7),
                  width: 1.5,
                ),
              ),
              onPressed: onComplete,
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: const Text('Complete journey'),
            ),
          ),
        ],
      ),
    );
  }
}

/// "4 of 9 packed" on a journey row.
///
/// A trip's own item list had no ticks and no progress, so a trip that was fully
/// packed and a trip that had not been started looked identical from the
/// timeline. This reads the checklist the trip now owns.
class _PackProgressLine extends StatelessWidget {
  const _PackProgressLine({required this.progress});

  final PackProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final complete = progress.total > 0 && progress.packed == progress.total;

    return Row(
      children: [
        Icon(
          complete ? Icons.check_circle_rounded : Icons.backpack_rounded,
          size: 14,
          color: complete
              ? AppColors.success
              : theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          complete ? 'Packed' : progress.label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: complete
                ? AppColors.success
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: complete ? FontWeight.w600 : null,
          ),
        ),
      ],
    );
  }
}

class _JourneyTile extends StatelessWidget {
  const _JourneyTile({required this.journey});

  final Journey journey;

  @override
  Widget build(BuildContext context) {
    final start = DateFormat('MMM d, y').format(journey.startTime);
    final end = journey.endTime != null
        ? DateFormat('MMM d, y • h:mm a').format(journey.endTime!)
        : 'In progress';
    final colorScheme = Theme.of(context).colorScheme;
    final status = journey.status;

    // Where the trip got to. Null when it has no checklist, which is different
    // from "nothing packed" and is the cue to offer the one-tap pack.
    final progress = context.watch<ChecklistProvider>().packProgressFor(
      journey.id,
    );

    final statusColor = switch (status) {
      // AppColors rather than literals, so the journey timeline stays in the
      // warm palette in dark mode too. The old Color(0xFF5C7A52) is the
      // success green on a light background and disappears on a dark one.
      JourneyStatus.active => AppColors.success,
      JourneyStatus.upcoming => AppColors.info,
      JourneyStatus.completed => colorScheme.onSurfaceVariant,
    };

    return Column(
      children: [
        ListTile(
          leading: CircleAvatar(
            backgroundColor: statusColor.withValues(alpha: 0.15),
            child: Icon(switch (status) {
              JourneyStatus.active => Icons.navigation_rounded,
              JourneyStatus.upcoming => Icons.event_rounded,
              JourneyStatus.completed => Icons.check_circle_rounded,
            }, color: statusColor),
          ),
          title: Text(
            '${journey.origin} → ${journey.destination}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(Icons.circle, size: 8, color: statusColor),
                  const SizedBox(width: 6),
                  Text(
                    status.label,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              Text('Started: $start · Ended: $end'),
              if (progress != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                _PackProgressLine(progress: progress),
              ],
            ],
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => JourneyDetailScreen(journey: journey),
            ),
          ),
        ),
        const Divider(indent: 72, height: 1),
      ],
    );
  }
}

/// Adds items to a journey one at a time and shows what is already going.
///
/// A list rather than one comma-separated field, because the journey model
/// always stored a list and the commas bought nothing: there was no way to see
/// what had been added, and no way to drop one item without retyping the rest.
class _PackingListEditor extends StatelessWidget {
  const _PackingListEditor({
    required this.entryController,
    required this.items,
    required this.onAdd,
    required this.onRemove,
  });

  final TextEditingController entryController;
  final List<String> items;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What are you taking?',
          style: textTheme.labelLarge?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          // Stable identity: the hint text changes once the first item is
          // added, so the field cannot be found by its hint afterwards.
          key: const ValueKey('journey-item-entry'),
          controller: entryController,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onAdd(),
          decoration: InputDecoration(
            hintText: items.isEmpty ? 'Boots, jacket, map' : 'Add another',
            suffixIcon: IconButton(
              tooltip: 'Add to the list',
              icon: const Icon(Icons.add_rounded),
              onPressed: onAdd,
            ),
          ),
        ),
        if (items.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          // A wrapped list of rows, not chips: an item name can be a phrase, and
          // a chip truncates to fit its pill where a full-width row does not.
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
              child: Row(
                children: [
                  Icon(
                    Icons.check_box_outline_blank_rounded,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(child: Text(item, style: textTheme.bodyMedium)),
                  IconButton(
                    tooltip: 'Remove $item',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => onRemove(item),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
