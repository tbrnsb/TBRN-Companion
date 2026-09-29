import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/theme/app_theme.dart';

/// Spending-location visualization built purely from stored expense
/// coordinates — no map dependency required.
///
/// Points are plotted on a mercator-ish normalized canvas with density
/// halos, plus saved checkpoints as reference markers. Handles the
/// no-data case with a real explanation instead of a fake map.
class SpendingMap extends StatelessWidget {
  const SpendingMap({
    super.key,
    required this.expenses,
    required this.checkpoints,
    this.height = 220,
  });

  final List<Expense> expenses;
  final List<Location> checkpoints;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final located = expenses.where((e) => e.hasCoordinates).toList();

    if (located.isEmpty) {
      return Container(
        height: height,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: AppRadii.mediumRadius,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.map_outlined,
              size: 32,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'No location data yet',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Expenses saved with device location will appear here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: AppRadii.mediumRadius,
      child: Container(
        height: height,
        color: colorScheme.surfaceContainerHighest,
        child: CustomPaint(
          painter: _SpendingMapPainter(
            expenses: located,
            checkpoints: checkpoints,
            primary: colorScheme.primary,
            hotspot: AppColors.warning,
            checkpointColor: colorScheme.tertiary,
            labelColor: colorScheme.onSurfaceVariant,
            lineColor: colorScheme.outlineVariant,
          ),
        ),
      ),
    );
  }
}

class _SpendingMapPainter extends CustomPainter {
  _SpendingMapPainter({
    required this.expenses,
    required this.checkpoints,
    required this.primary,
    required this.hotspot,
    required this.checkpointColor,
    required this.labelColor,
    required this.lineColor,
  });

  final List<Expense> expenses;
  final List<Location> checkpoints;
  final Color primary;
  final Color hotspot;
  final Color checkpointColor;
  final Color labelColor;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    const padding = 28.0;

    final lats = <double>[
      ...expenses.map((e) => e.latitude!),
      ...checkpoints.map((c) => c.latitude),
    ];
    final lngs = <double>[
      ...expenses.map((e) => e.longitude!),
      ...checkpoints.map((c) => c.longitude),
    ];

    double minLat = lats.reduce(math.min);
    double maxLat = lats.reduce(math.max);
    double minLng = lngs.reduce(math.min);
    double maxLng = lngs.reduce(math.max);

    // Keep aspect ratio sane when points share a coordinate.
    final latSpan = math.max(maxLat - minLat, 0.002);
    final lngSpan = math.max(maxLng - minLng, 0.002);

    Offset project(double lat, double lng) {
      final x =
          padding + ((lng - minLng) / lngSpan) * (size.width - padding * 2);
      final y =
          padding +
          (1 - (lat - minLat) / latSpan) * (size.height - padding * 2);
      return Offset(x, y);
    }

    // Subtle graticule for spatial context.
    final gridPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final dy = size.height * i / 4;
      final dx = size.width * i / 4;
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), gridPaint);
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), gridPaint);
    }

    final maxAmount = expenses.map((e) => e.amount).fold<double>(0, math.max);

    // Density halos first (behind points).
    for (final expense in expenses) {
      final center = project(expense.latitude!, expense.longitude!);
      final weight = maxAmount == 0 ? 0.4 : expense.amount / maxAmount;
      final haloPaint = Paint()
        ..color = hotspot.withValues(alpha: 0.10 + 0.18 * weight)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
      canvas.drawCircle(center, 20 + 26 * weight, haloPaint);
    }

    // Saved checkpoints as ringed reference markers.
    final checkpointPaint = Paint()
      ..color = checkpointColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    for (final checkpoint in checkpoints) {
      final center = project(checkpoint.latitude, checkpoint.longitude);
      canvas.drawCircle(center, 9, checkpointPaint);
      canvas.drawCircle(center, 2.5, Paint()..color = checkpointColor);
    }

    // Expense points, sized by amount.
    for (final expense in expenses) {
      final center = project(expense.latitude!, expense.longitude!);
      final weight = maxAmount == 0 ? 0.4 : expense.amount / maxAmount;
      final paint = Paint()..color = primary;
      canvas.drawCircle(center, 3.5 + 5 * weight, paint);
      canvas.drawCircle(
        center,
        3.5 + 5 * weight,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpendingMapPainter oldDelegate) =>
      oldDelegate.expenses != expenses ||
      oldDelegate.checkpoints != checkpoints;
}
