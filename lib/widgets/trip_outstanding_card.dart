import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:daily_companion/providers/journey_provider.dart';
import 'package:daily_companion/providers/settings_provider.dart';
import 'package:daily_companion/screens/journeys/trip_summary_screen.dart';
import 'package:daily_companion/theme/app_theme.dart';
import 'package:daily_companion/utils/format.dart';

/// "On Pokhara — you're owed Rs 867".
///
/// The whole point of a shared trip is that someone owes you money, and the
/// Transactions tab is where the user already looks at money. Without this, the
/// outstanding balance only exists inside a trip the user has to go and find.
///
/// Hidden when nothing is outstanding. A card that reads "everyone is even" is
/// noise, and a permanently visible one trains the eye to skip it — which is
/// exactly when it would matter.
///
/// NOT A SIXTH TAB. There is no "Shared" destination; the flow is
/// Journey → Shared → Summary, and this card is a shortcut into the last step.
class TripOutstandingCard extends StatelessWidget {
  const TripOutstandingCard({super.key});

  @override
  Widget build(BuildContext context) {
    final journeys = context.watch<JourneyProvider>();
    final currencySymbol = context.select<SettingsProvider, String>(
      (s) => s.currency.symbol,
    );

    return FutureBuilder<List<TripOutstanding>>(
      future: journeys.outstandingAcrossTrips(),
      builder: (context, snapshot) {
        final outstanding = snapshot.data ?? const <TripOutstanding>[];
        if (outstanding.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: AppSurface(
            tier: AppSurfaceTier.raised,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final trip in outstanding) ...[
                  _TripRow(trip: trip, currencySymbol: currencySymbol),
                  if (trip != outstanding.last)
                    const SizedBox(height: AppSpacing.sm),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TripRow extends StatelessWidget {
  const _TripRow({required this.trip, required this.currencySymbol});

  final TripOutstanding trip;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final net = AppFormat.money(trip.localNet.abs(), symbol: currencySymbol);

    // Before the user has said which participant they are, there is no "you"
    // figure to show — only the group's outstanding total.
    final (String status, Color color) = switch (trip.localNetInPaise) {
      > 0 => ('you get $net back', AppColors.success),
      < 0 => ('you owe $net', scheme.error),
      _ => ('$net still to settle', scheme.onSurfaceVariant),
    };

    return InkWell(
      key: ValueKey('outstanding-${trip.journey.id}'),
      borderRadius: AppRadii.smallRadius,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TripSummaryScreen(journeyId: trip.journey.id),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Row(
          children: [
            Icon(Icons.route_rounded, size: 20, color: scheme.primary),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trip.journey.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '$status · ${trip.remainingCount} '
                    '${trip.remainingCount == 1 ? 'payment' : 'payments'} left',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: color),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20),
          ],
        ),
      ),
    );
  }
}
