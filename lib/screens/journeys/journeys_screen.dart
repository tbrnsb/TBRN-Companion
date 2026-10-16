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
import 'package:daily_companion/screens/journeys/heading_home_sheet.dart';
import 'package:daily_companion/widgets/place_autocomplete_field.dart';
import 'package:daily_companion/theme/app_accents.dart';
import 'package:daily_companion/services/notification_service.dart';
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

  /// Ticked at creation to say this trip is the user's alone.
  ///
  /// Off by default, because the existing behaviour -- show the shared section,
  /// say "Solo so far", offer the field -- is the right answer for a trip nobody
  /// has joined yet. This is the answer for a trip the user does not want
  /// shared at all, and it has to be chosen deliberately rather than inferred
  /// from an empty roster, which is exactly the state it exists to differ from.
  bool _solo = false;

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
                      // The sheet recaps the packing list and ends the trip. It
                      // returns true only if it actually ended one, so a
                      // dismissal leaves the trip running.
                      await HeadingHomeSheet.show(context, active);
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (geofenceAlert != null) ...[
                  ContextCard(
                    icon: Icons.location_on_rounded,
                    title: 'Saved place alert',
                    child: Text(geofenceAlert),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                _buildStartJourneyCard(context, journeyProvider),
                const SizedBox(height: AppSpacing.lg),
                _SummaryRow(provider: journeyProvider),
                const SizedBox(height: AppSpacing.lg),
                // The month grid that used to live here is now the calendar in
                // the app bar, on every tab. It answered a general question —
                // "what was on the 12th?" — from the one screen that had
                // nothing to do with it, and it duplicated day details the
                // ledger already owns. Recent journeys below is the journey
                // tab's actual job.
                const SectionHeader('Recent journeys'),
                const SizedBox(height: AppSpacing.xs),
                if (journeyProvider.journeys.isEmpty)
                  // Says what the section is for AND where the next trip
                  // comes from. The bare sentence it replaced named neither
                  // the screen nor a way forward, and the card that starts a
                  // trip sits directly above it. Same component as every other
                  // empty list in the app; the copy is asserted verbatim by
                  // journey_items_test.
                  const EmptyState(
                    icon: Icons.flight_takeoff_rounded,
                    title: 'No journeys yet',
                    message:
                        'Your trips will be listed here. Use "Start a '
                        'new journey" above to log the first one.',
                  )
                else
                  ...journeyProvider.journeys.map(
                    // Newest first, so the next trip inserts at the top and
                    // every tile below shifts: keyed so they move rather than
                    // rebuild.
                    (journey) => _JourneyTile(
                      key: ValueKey<String>(journey.id),
                      journey: journey,
                    ),
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

  /// Fills [controller] with the name of the place the app thinks you are at.
  ///
  /// The button used to do nothing at all when there was no current location
  /// — no sound, no word, no reason — which is the worst possible answer for
  /// a control that looks like it should work.
  void _fillFromCurrentLocation(
    BuildContext context,
    TextEditingController controller,
  ) {
    final locationProvider = context.read<LocationProvider>();
    final currentId = locationProvider.currentLocationId;
    final location = currentId == null
        ? null
        : locationProvider.getLocationById(currentId);

    if (location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No current location saved yet'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(AppSpacing.md),
        ),
      );
      return;
    }
    controller.text = location.name;
  }

  /// Opens the preset picker and folds the chosen template into the list.
  ///
  /// Items already in the list are skipped, case-insensitively, for the same
  /// reason the typed entry skips them: adding the same thing twice by
  /// accident is a bug the user then has to clean up by hand.
  Future<void> _choosePreset(BuildContext context) async {
    final presets = context.read<ChecklistProvider>().presets;
    if (presets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No presets yet — save one from a checklist’s menu first',
          ),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(AppSpacing.md),
        ),
      );
      return;
    }

    final selectedPreset = await showDialog<Checklist>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose a preset'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: presets.length,
            itemBuilder: (context, index) {
              final preset = presets[index];
              return ListTile(
                title: Text(preset.name),
                subtitle: Text(
                  '${preset.items.length} ${preset.items.length == 1 ? 'item' : 'items'}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                onTap: () => Navigator.of(context).pop(preset),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (selectedPreset == null || !mounted) return;

    setState(() {
      for (final item in selectedPreset.items) {
        final name = item.name.trim();
        if (name.isEmpty) continue;
        final alreadyThere = _plannedItems.any(
          (existing) => existing.toLowerCase() == name.toLowerCase(),
        );
        if (!alreadyThere) _plannedItems.add(name);
      }
    });
  }

  /// Schedules ONE reminder for the start of this trip.
  ///
  /// The time offered starts from the planned start when there is one — the
  /// reminder is about the trip, so the trip's own time is the sensible
  /// default. A time that has already passed today is bumped to TOMORROW
  /// rather than silently scheduled in the past, where it would never fire.
  ///
  /// One id, not one per tap: rescheduling replaces the previous reminder
  /// instead of stacking a second alarm the user cannot find.
  Future<void> _scheduleReminder(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final now = DateTime.now();

    final selectedTime = await showTimePicker(
      context: context,
      initialTime: _plannedStart != null
          ? TimeOfDay.fromDateTime(_plannedStart!)
          : TimeOfDay.now(),
    );
    if (selectedTime == null || !mounted) return;

    final base = _plannedStart ?? now;
    var scheduled = DateTime(
      base.year,
      base.month,
      base.day,
      selectedTime.hour,
      selectedTime.minute,
    );
    // Rolls forward until it is actually AHEAD of now. Adding a single day
    // left a planned start from two or more days ago still in the past,
    // where the alarm never fires while the snackbar promises it will — the
    // CHANGELOG says "rolls to tomorrow", and that has to be true for any
    // date the picker can produce, not just yesterday.
    while (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    final destination = _destinationController.text.trim();
    // ONE fixed id, deliberately: a reminder set for a later trip replaces
    // this slot's previous entry instead of stacking a second alarm behind
    // it. The service derives the platform id deterministically from this
    // string, so the replacement also holds across app restarts, and the
    // snackbar below always names the time that is currently armed.
    final scheduledOk = await NotificationService.scheduleAt(
      id: 'journey_start_reminder',
      title: 'Journey reminder',
      body: destination.isEmpty
          ? 'Time to start your journey!'
          : 'Time to start your journey to $destination!',
      scheduledTime: scheduled,
    );

    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              scheduledOk ? Icons.alarm_rounded : Icons.alarm_off_rounded,
              size: 20,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                scheduledOk
                    ? 'Reminder set for ${DateFormat.yMMMd().add_jm().format(scheduled)}'
                    : 'The reminder could not be set',
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(AppSpacing.md),
      ),
    );
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
        childrenPadding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        children: [
          PlaceAutocompleteField(
            controller: _originController,
            label: 'Where are you starting?',
            onUseCurrentLocation: () =>
                _fillFromCurrentLocation(context, _originController),
          ),
          const SizedBox(height: AppSpacing.sm),
          PlaceAutocompleteField(
            controller: _destinationController,
            label: 'Where are you going?',
            onUseCurrentLocation: () =>
                _fillFromCurrentLocation(context, _destinationController),
          ),
          const SizedBox(height: AppSpacing.sm),
          _PackingListEditor(
            entryController: _itemEntryController,
            items: _plannedItems,
            onAdd: _addPlannedItems,
            onRemove: (item) => setState(() => _plannedItems.remove(item)),
          ),
          const SizedBox(height: AppSpacing.sm),
          // NEXT TO THE EDITOR IT FEEDS, and left-aligned like every other
          // action on this card: a bare TextButton in a Column centres itself
          // horizontally, which is why the old pair of them drifted to the
          // middle of the sheet while everything around them sat on the left
          // edge.
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _choosePreset(context),
              icon: const Icon(Icons.playlist_add_check_rounded, size: 18),
              label: const Text('Add from preset'),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
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
          const SizedBox(height: AppSpacing.xxs),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _scheduleReminder(context),
              icon: const Icon(Icons.alarm_rounded, size: 18),
              label: const Text('Remind me'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // A checkbox, not a switch: the label is the whole point, and a
          // switch with no words beside it is a guess about what is on.
          CheckboxListTile(
            value: _solo,
            onChanged: (value) => setState(() => _solo = value ?? false),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              'Solo trip',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            subtitle: Text(
              // Not "no people section": a solo trip still draws a Shared
              // block with a header and a way back to sharing. What it does
              // not draw is the roster, the add field, or the splitting UI,
              // and that is what this line is promising.
              'Nobody to add, nothing to split.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _notesController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Trip notes'),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                HapticFeedback.heavyImpact();

                // Read at the moment of the action, not watched by the build.
                // This screen's own build does not watch ChecklistProvider --
                // the active card and each trip row do, for their own state --
                // so pulling it in here too would only add a second reason for
                // the whole timeline to rebuild over one value used once, on
                // one button.
                final checklists = context.read<ChecklistProvider>();
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

                // The items typed into this journey become a real, tickable
                // checklist in the same breath as the journey itself. That step
                // lives inside `startJourney`, not here: a caller that forgot it
                // produced a journey whose items went nowhere, and the trip's
                // own "Pack for this trip" button then stayed on screen forever
                // reporting that the user had already packed.
                await journeyProvider.startJourney(
                  destination: destination,
                  origin: origin,
                  notes: _notesController.text.trim(),
                  items: List.of(_plannedItems),
                  plannedStart: _plannedStart,
                  isSolo: _solo,
                  checklists: checklists,
                );
                if (!mounted) return;
                setState(() => _plannedStart = null);

                _destinationController.clear();
                _originController.clear();
                _notesController.clear();
                _itemEntryController.clear();
                setState(() {
                  _plannedItems.clear();
                  // Reset with the rest of the form, or the next journey the
                  // user writes is silently solo because the last one was.
                  _solo = false;
                });
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.white),
                        SizedBox(width: AppSpacing.xs),
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
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: _tile(context, stats[1])),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(child: _tile(context, stats[2])),
            const SizedBox(width: AppSpacing.sm),
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

    // Selected, not watched: a trip usually starts with no checklist and gains
    // one moments later, and this card has to redraw when it does — but that is
    // a bool, and watching the whole provider redrew it on every checklist
    // change to any trip in the app. Null-progress on the tile below is the
    // same signal seen from the other end.
    final hasLinkedChecklist = context.select<ChecklistProvider, bool>(
      (p) => p.getChecklistsForJourney(journey.id).isNotEmpty,
    );

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
          if (!hasLinkedChecklist && journey.items.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            // The LEGACY packing list: rows written before a trip's items
            // became a real, tickable checklist. They have no ticks and no
            // entry in the Pack tab, so this card is the only place they exist
            // and dropping them would make them unreachable from anywhere.
            //
            // Gated on `!hasLinkedChecklist` for the same reason the trip's own
            // screen gates its header chips: a trip started from the app now
            // turns its items into a checklist in the same breath, and drawing
            // them here as well showed one list twice in two visual forms,
            // one of which could never be ticked -- on two different screens.
            //
            // A low tint of the second accent, labels still in ink so they
            // clear the text contrast and not the non-text one.
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
          // name is the thing being looked at. Ending the trip is the action
          // that CLOSES all of that, so it should be reachable, not louder than
          // the name. Filled in the warm accent it was the most saturated thing
          // on the card and the eye went to the button before the trip.
          //
          // "Heading home?" rather than "Complete journey": it is the moment
          // described in the first person, and it leads somewhere -- the sheet
          // that walks the packing list before ending anything. The old label
          // named a state change with no indication anything else happens.
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
              icon: const Icon(Icons.home_rounded, size: 18),
              label: const Text('Heading home?'),
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
  const _JourneyTile({super.key, required this.journey});

  final Journey journey;

  @override
  Widget build(BuildContext context) {
    final start = DateFormat('MMM d, y').format(journey.startTime);
    final end = journey.endTime != null
        ? DateFormat('MMM d, y • h:mm a').format(journey.endTime!)
        : 'In progress';
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
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
              const SizedBox(height: AppSpacing.xxs),
              Row(
                children: [
                  Icon(Icons.circle, size: 8, color: statusColor),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    status.label,
                    // `labelMedium` carries the size and the weight already.
                    // This was a bare `TextStyle` with no role behind it, so it
                    // discarded the theme's type for this one line.
                    style: textTheme.labelMedium?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
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
                    // No `visualDensity: compact` here: compact sizes this to
                    // 40x40, which is under the 48 floor the remove target is
                    // supposed to clear. The icon stays 18 either way.
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
