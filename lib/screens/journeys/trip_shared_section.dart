import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/providers/journey_provider.dart';
import 'package:flutter_application_1/providers/settings_provider.dart';
import 'package:flutter_application_1/screens/journeys/trip_summary_screen.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/utils/format.dart';
import 'package:flutter_application_1/widgets/widgets.dart';

/// The "Shared" block on journey detail.
///
/// This is where a trip becomes shared: who is on it, which of them is you, what
/// each person fronted, and the way into the summary that turns all of it into
/// "who pays whom".
///
/// It renders on EVERY trip, including one with nobody else on it, because the
/// field that adds the first person lives in here. Hiding the section until a
/// participant existed made the whole feature unreachable: a solo trip had no way
/// to become shared, because the only way in was the section that was not there.
class TripSharedSection extends StatelessWidget {
  const TripSharedSection({super.key, required this.journeyId});

  final String journeyId;

  @override
  Widget build(BuildContext context) {
    final journeys = context.watch<JourneyProvider>();
    final journey = journeys.getJourneyById(journeyId);
    // A vanished journey is the only reason to render nothing. An EMPTY roster
    // used to hide this section too, which made the feature unreachable: the
    // only call site of addParticipant in the whole app is the field below, so a
    // solo trip could never become a shared one. There was no other way in.
    if (journey == null) return const SizedBox.shrink();

    final hasPeople = journey.participants.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.lg),
        SectionHeader(
          'Shared',
          trailing: Text(
            journey.isShared
                ? '${journey.participants.length} people'
                : 'Solo so far',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppSurface(
          tier: AppSurfaceTier.raised,
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // On a solo trip there is nobody to be, so the who-am-I question is
              // not asked and the roster is not drawn — there is nothing in
              // either. The add field still is, because it is the way in.
              if (hasPeople) ...[
                _WhoAmI(journey: journey),
                const SizedBox(height: AppSpacing.md),
                _ParticipantList(journey: journey),
                const SizedBox(height: AppSpacing.md),
              ] else ...[
                Text(
                  'Going with someone? Add them here and you can split what the '
                  'trip costs between you.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              _AddParticipantField(journey: journey),
              if (journey.isShared) ...[
                const SizedBox(height: AppSpacing.md),
                _TripCodeRow(journey: journey),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const ValueKey('open-trip-summary'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TripSummaryScreen(journeyId: journeyId),
                      ),
                    ),
                    icon: const Icon(Icons.balance_rounded),
                    label: const Text('Open trip summary'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// "Which one are you?"
///
/// Required, not optional, and deliberately the first thing in the section:
/// without it the app can compute the whole settlement but cannot say what *you*
/// owe, which is the only number anyone opening this screen wants.
class _WhoAmI extends StatelessWidget {
  const _WhoAmI({required this.journey});

  final Journey journey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final localId = journey.localParticipantId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Which one are you?', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'So the app can tell you what you owe rather than the whole group\'s '
          'arithmetic.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final participant in journey.participants)
              ChoiceChip(
                key: ValueKey('who-am-i-${participant.id}'),
                label: Text(participant.name),
                selected: participant.id == localId,
                onSelected: (_) async {
                  HapticFeedback.selectionClick();
                  await context.read<JourneyProvider>().setLocalParticipant(
                    journey.id,
                    participant.id,
                  );
                },
              ),
          ],
        ),
      ],
    );
  }
}

/// Each person: paid, fair share, net.
class _ParticipantList extends StatelessWidget {
  const _ParticipantList({required this.journey});

  final Journey journey;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ParticipantTotal>>(
      future: context.read<JourneyProvider>().participantTotalsFor(journey.id),
      builder: (context, snapshot) {
        final totals = snapshot.data ?? const <ParticipantTotal>[];
        if (totals.isEmpty) return const SizedBox.shrink();

        final shares = equalShares(
          totalInPaise: totals.fold<int>(
            0,
            (sum, t) => sum + t.amountPaidInPaise,
          ),
          totals: totals,
        );
        final currencySymbol = context.select<SettingsProvider, String>(
          (s) => s.currency.symbol,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < totals.length; i++)
              _ParticipantRow(
                total: totals[i],
                shareInPaise: shares[i],
                isMe: totals[i].id == journey.localParticipantId,
                currencySymbol: currencySymbol,
                onRemove: () => _confirmRemove(context, totals[i]),
              ),
          ],
        );
      },
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    ParticipantTotal person,
  ) async {
    final journeys = context.read<JourneyProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${person.name}?'),
        content: const Text(
          'Their expenses stay on the trip — the money was really spent — but '
          'they stop counting in the settlement, and a file they share later '
          'will not add them back.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await journeys.removeParticipant(journey.id, person.id);
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.total,
    required this.shareInPaise,
    required this.isMe,
    required this.currencySymbol,
    required this.onRemove,
  });

  final ParticipantTotal total;
  final int shareInPaise;
  final bool isMe;
  final String currencySymbol;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final netInPaise = total.amountPaidInPaise - shareInPaise;
    final isOwed = netInPaise > 0;
    final owes = netInPaise < 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        total.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: AppSpacing.xs),
                      _Badge(
                        text: 'You',
                        color: scheme.primaryContainer,
                        onColor: scheme.onPrimaryContainer,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'paid ${AppFormat.money(total.amountPaidInPaise / 100, symbol: currencySymbol)}'
                  ' · share ${AppFormat.money(shareInPaise / 100, symbol: currencySymbol)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                isOwed
                    ? '+${AppFormat.money(netInPaise / 100, symbol: currencySymbol)}'
                    : owes
                    ? AppFormat.money(
                        netInPaise.abs() / 100,
                        symbol: currencySymbol,
                      )
                    : AppFormat.money(0, symbol: currencySymbol),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isOwed
                      ? AppColors.success
                      : owes
                      ? scheme.error
                      : scheme.onSurfaceVariant,
                ),
              ),
              Text(
                isOwed
                    ? 'is owed'
                    : owes
                    ? 'owes'
                    : 'even',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          IconButton(
            key: ValueKey('remove-${total.id}'),
            tooltip: 'Remove ${total.name}',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// "Add someone" by name.
class _AddParticipantField extends StatefulWidget {
  const _AddParticipantField({required this.journey});

  final Journey journey;

  @override
  State<_AddParticipantField> createState() => _AddParticipantFieldState();
}

class _AddParticipantFieldState extends State<_AddParticipantField> {
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _controller.text.trim();
    if (name.isEmpty || _busy) return;

    setState(() => _busy = true);
    final journeys = context.read<JourneyProvider>();
    final added = await journeys.addParticipant(widget.journey.id, name);
    if (!mounted) return;

    setState(() {
      _busy = false;
      if (added != null) _controller.clear();
    });

    final messenger = ScaffoldMessenger.of(context);
    if (added == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not add that name.')),
      );
    } else if (added.name == name && added.id.isNotEmpty) {
      // Two people on a trip can share a name, so this only confirms the tap
      // landed; the row itself is what disambiguates them.
      HapticFeedback.lightImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            key: const ValueKey('add-participant-field'),
            controller: _controller,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _add(),
            decoration: const InputDecoration(
              hintText: 'Add someone by name',
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        IconButton.filled(
          key: const ValueKey('add-participant-submit'),
          tooltip: 'Add',
          onPressed: _busy ? null : _add,
          icon: const Icon(Icons.person_add_alt_rounded, size: 20),
        ),
      ],
    );
  }
}

/// The trip code, prominent and copyable.
///
/// The copy is the whole point of a code you read aloud: confirming with a
/// friend is one tap rather than three. It identifies the trip and does nothing
/// else, so nothing here implies that matching codes connect two phones.
class _TripCodeRow extends StatelessWidget {
  const _TripCodeRow({required this.journey});

  final Journey journey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final code = journey.tripCode;

    if (code == null || code.isEmpty) {
      return OutlinedButton.icon(
        onPressed: () =>
            context.read<JourneyProvider>().ensureTripCode(journey.id),
        icon: const Icon(Icons.tag_rounded, size: 18),
        label: const Text('Make a trip code'),
      );
    }

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Trip code', style: theme.textTheme.labelMedium),
              Text(
                code,
                key: const ValueKey('trip-code'),
                style: theme.textTheme.titleLarge?.copyWith(
                  letterSpacing: 3,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'Read this out so you are both looking at the same trip. It '
                'sends nothing — your data stays on each phone.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          key: const ValueKey('copy-trip-code'),
          tooltip: 'Copy code',
          icon: const Icon(Icons.copy_rounded, size: 20),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: code));
            if (!context.mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Trip code copied')));
          },
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.text,
    required this.color,
    required this.onColor,
  });

  final String text;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppRadii.smallRadius,
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: onColor, fontWeight: FontWeight.w700),
      ),
    );
  }
}
