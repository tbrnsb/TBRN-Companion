import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/journey_provider.dart';
import 'package:flutter_application_1/providers/location_provider.dart';
import 'package:flutter_application_1/screens/journeys/journey_detail_screen.dart';
import 'package:flutter_application_1/screens/journeys/journey_detail_sheets.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/widgets/widgets.dart';

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
  DateTime _timelineMonth = DateTime.now();
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
                _TimelineCard(
                  month: _timelineMonth,
                  journeys: journeyProvider.getJourneysForMonth(_timelineMonth),
                  onPrevious: () => setState(() {
                    _timelineMonth = DateTime(
                      _timelineMonth.year,
                      _timelineMonth.month - 1,
                    );
                  }),
                  onNext: () => setState(() {
                    _timelineMonth = DateTime(
                      _timelineMonth.year,
                      _timelineMonth.month + 1,
                    );
                  }),
                ),
                const SizedBox(height: 24),
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

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({
    required this.month,
    required this.journeys,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime month;
  final List<Journey> journeys;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(month.year, month.month, 1);
    final lastDay = DateTime(month.year, month.month + 1, 0);
    final leadingEmptyDays = firstDay.weekday % 7;
    final totalCells = leadingEmptyDays + lastDay.day;
    final rows = (totalCells / 7).ceil();
    const weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final colorScheme = Theme.of(context).colorScheme;

    final dayMap = <DateTime, int>{};
    for (final journey in journeys) {
      final key = DateTime(
        journey.startTime.year,
        journey.startTime.month,
        journey.startTime.day,
      );
      dayMap[key] = (dayMap[key] ?? 0) + 1;
    }

    return AppSurface(
      tier: AppSurfaceTier.raised,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: onPrevious,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                // Flexible, because the row is two 48dp tap targets either side
                // of this text. On a 360dp phone that left the label 29px wider
                // than the space and the row overflowed. Fitted rather than
                // ellipsised: a month name is short, and shrinking it a little
                // beats showing "Septemb…".
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      DateFormat.yMMMM().format(month),
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onNext,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: weekdays
                  .map(
                    (day) => Expanded(
                      child: Center(
                        child: Text(
                          day,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1.15,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
              ),
              itemCount: rows * 7,
              itemBuilder: (context, index) {
                final dayNumber = index - leadingEmptyDays + 1;
                if (index < leadingEmptyDays || dayNumber > lastDay.day) {
                  return const SizedBox.shrink();
                }

                final date = DateTime(month.year, month.month, dayNumber);
                final count =
                    dayMap[DateTime(date.year, date.month, date.day)] ?? 0;
                final isToday = DateUtils.isSameDay(date, DateTime.now());

                return Semantics(
                  button: true,
                  label: count > 0
                      ? '$dayNumber, $count trip${count == 1 ? '' : 's'}. '
                            'Tap to see what happened.'
                      : '$dayNumber. Nothing recorded.',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      DayActivitySheet.show(context, date);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isToday
                            ? colorScheme.primaryContainer
                            : colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Text(
                            '$dayNumber',
                            style: TextStyle(
                              fontWeight: isToday
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isToday
                                  ? colorScheme.onPrimaryContainer
                                  : null,
                            ),
                          ),
                          if (count > 0)
                            Positioned(
                              bottom: 4,
                              child: Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: colorScheme.primary,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
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
        value: _formatMinutes(provider.averageJourneyMinutes),
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

  String _formatMinutes(double minutes) {
    if (minutes <= 0) return '0m';
    final whole = minutes.round();
    final hours = whole ~/ 60;
    final mins = whole % 60;
    if (hours == 0) return '${mins}m';
    return '${hours}h ${mins}m';
  }
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
    final colorScheme = Theme.of(context).colorScheme;

    // The journey in progress is the single most important thing on this
    // screen, so it is the screen's one accent surface.
    return AppSurface(
      tier: AppSurfaceTier.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.route_rounded,
                size: 20,
                color: colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 8),
              Text(
                'Active journey',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: onOpen,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${journey.origin} → ${journey.destination}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  Icons.open_in_new_rounded,
                  size: 18,
                  color: colorScheme.onPrimaryContainer,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Started: $started',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
            ),
          ),
          if (journey.items.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: journey.items
                  .map(
                    (item) => Chip(
                      label: Text(item),
                      backgroundColor: colorScheme.surface.withValues(
                        alpha: 0.6,
                      ),
                      side: BorderSide.none,
                    ),
                  )
                  .toList(),
            ),
          ],
          if (reminderHints.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...reminderHints.map(
              (hint) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.notifications_active_rounded,
                      color: colorScheme.onPrimaryContainer,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hint,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: colorScheme.onPrimaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onComplete,
              icon: const Icon(Icons.check_circle_rounded),
              label: const Text('Complete journey'),
            ),
          ),
        ],
      ),
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
