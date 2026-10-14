import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/providers/checklist_provider.dart';
import 'package:daily_companion/providers/journey_provider.dart';
import 'package:daily_companion/theme/app_theme.dart';

/// "Heading home?" — the end of a trip.
///
/// The request was a button that reminds you of everything you packed, lets you
/// tick it off, and then ends the trip with what you took, what you brought back
/// and how long it all took.
///
/// It is a sheet rather than a screen because it is a decision made once, on the
/// way out the door. Everything it shows is a recap: the packing list, a count
/// of what is still unticked, and the running duration. Nothing here is new
/// information and nothing is editable except the ticks, because a trip that
/// needed editing at the end should have been corrected earlier.
///
/// The ticks are the point rather than a formality. Someone who packed eight of
/// ten things has not forgotten the list -- they chose the other two. But
/// someone who ticked nothing at all has almost certainly not looked, and this
/// is the last screen that can catch that. So the list is shown by default and
/// the trip cannot be ended while anything is unticked, with a deliberate
/// override rather than a silent one.
class HeadingHomeSheet extends StatefulWidget {
  const HeadingHomeSheet({required this.journey, super.key});

  final Journey journey;

  static Future<bool?> show(BuildContext context, Journey journey) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => HeadingHomeSheet(journey: journey),
    );
  }

  @override
  State<HeadingHomeSheet> createState() => _HeadingHomeSheetState();
}

class _HeadingHomeSheetState extends State<HeadingHomeSheet> {
  /// Set once the user has chosen to end the trip with items unticked. Guards
  /// the button, and is surfaced as an explicit choice rather than a disabled
  /// control, so nobody wonders why they cannot continue.
  bool _overrideUnticked = false;
  bool _ending = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final checklists = context.watch<ChecklistProvider>();
    final journey = widget.journey;

    final owned = checklists.getChecklistsForJourney(journey.id);
    final items = [
      for (final checklist in owned)
        for (final item in checklist.items) (checklist: checklist, item: item),
    ];

    final packed = items.where((e) => e.item.isChecked).length;
    final total = items.length;
    final allPacked = total > 0 && packed == total;

    // A trip with NOTHING to pack can be ended freely. "Nothing to pack" is a
    // different fact from "nothing packed": there is no list to have ignored,
    // so there is nothing to remind anyone about and nothing to override. The
    // guard is here to catch someone who never LOOKED at a list they have, not
    // to stop a trip that never had one.
    final canEnd = total == 0 || allPacked || _overrideUnticked;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.md,
          right: AppSpacing.md,
          bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Heading home?', style: theme.textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              _subtitle(journey, packed, total),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // The list, not a count. A reminder of what to look for is only a
            // reminder if it says what to look for.
            if (total == 0)
              const _InlineNote(
                icon: Icons.backpack_outlined,
                text: 'Nothing was packed for this trip.',
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.4,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final entry in items)
                      CheckboxListTile(
                        value: entry.item.isChecked,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(
                          entry.item.name,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            decoration: entry.item.isChecked
                                ? TextDecoration.lineThrough
                                : null,
                            color: entry.item.isChecked
                                ? scheme.onSurfaceVariant
                                : scheme.onSurface,
                          ),
                        ),
                        onChanged: (_) => checklists.toggleItem(entry.item.id),
                      ),
                  ],
                ),
              ),

            if (total > 0 && !allPacked && !_overrideUnticked)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: _OverrideRow(
                  unticked: total - packed,
                  onOverride: () => setState(() => _overrideUnticked = true),
                ),
              ),

            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Keep going'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: canEnd && !_ending ? () => _end(context) : null,
                    icon: _ending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.flag_rounded, size: 18),
                    label: const Text('End trip'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle(Journey journey, int packed, int total) {
    final duration = journey.isRunning
        ? '${journey.durationText} so far'
        : journey.durationText;
    if (total == 0) {
      return '${journey.title} · $duration';
    }
    return '${journey.title} · $duration · $packed of $total packed';
  }

  Future<void> _end(BuildContext context) async {
    setState(() => _ending = true);
    final journeys = context.read<JourneyProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    await journeys.completeJourney(widget.journey.id);
    if (!mounted) return;

    navigator.pop(true);
    messenger.showSnackBar(
      SnackBar(
        content: Text('${widget.journey.title} is in the log.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _OverrideRow extends StatelessWidget {
  const _OverrideRow({required this.unticked, required this.onOverride});

  final int unticked;
  final VoidCallback onOverride;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            '$unticked still unticked.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        TextButton(onPressed: onOverride, child: const Text('End anyway')),
      ],
    );
  }
}

class _InlineNote extends StatelessWidget {
  const _InlineNote({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
