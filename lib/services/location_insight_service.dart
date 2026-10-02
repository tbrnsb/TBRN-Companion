import 'dart:math' as math;

import 'package:hive_flutter/hive_flutter.dart';
import 'package:daily_companion/models/index.dart';

/// A geographic cluster of expense coordinates, treated as evidence of
/// repeated visits to the same unnamed place.
class FrequentLocationCandidate {
  FrequentLocationCandidate({
    required this.centerLatitude,
    required this.centerLongitude,
    required this.visitCount,
    required this.totalSpent,
    required this.key,
  });

  final double centerLatitude;
  final double centerLongitude;

  /// Number of distinct visit days (multiple expenses on the same day at
  /// the same spot count as a single visit).
  final int visitCount;
  final double totalSpent;

  /// Stable key derived from rounded coordinates, used for dismissal state.
  final String key;

  String get coordinateLabel =>
      '${centerLatitude.toStringAsFixed(4)}, ${centerLongitude.toStringAsFixed(4)}';
}

/// Location intelligence for expenses:
///
/// - checkpoint matching (is the user inside a saved place's radius?)
/// - frequent-location detection from expense coordinates (no background
///   tracking — expense entry timestamps/coords are the only evidence)
///
/// Dismissal/cooldown state is persisted in a Hive box so suggestions and
/// confirmations never spam the user.
class LocationInsightService {
  LocationInsightService._();

  static const String _stateBoxName = 'location_insight_state';
  static Box<String>? _stateBox;

  /// Two expenses closer than this are considered the same spot.
  static const double clusterRadiusMeters = 150;

  /// Visits (distinct days) required before suggesting a saved place.
  static const int visitThreshold = 4;

  /// Don't re-suggest a dismissed cluster within this period.
  static const Duration dismissalCooldown = Duration(days: 30);

  /// Don't re-ask "At [checkpoint]?" for the same checkpoint within this
  /// period after the user said no.
  static const Duration checkpointDeclineCooldown = Duration(hours: 24);

  static Future<void> initialize() async {
    _stateBox = await Hive.openBox<String>(_stateBoxName);
  }

  // ----- persisted state helpers -----

  static bool _isDismissed(String key, Duration cooldown) {
    final box = _stateBox;
    if (box == null) return false;
    final raw = box.get(key);
    if (raw == null) return false;
    final at = DateTime.tryParse(raw);
    if (at == null) return false;
    return DateTime.now().difference(at) < cooldown;
  }

  static Future<void> _markDismissed(String key) async {
    await _stateBox?.put(key, DateTime.now().toIso8601String());
  }

  // ----- checkpoint matching -----

  /// Checkpoints the user has recently declined to be associated with.
  static bool isCheckpointDeclined(String locationId) =>
      _isDismissed('declined_ckpt_$locationId', checkpointDeclineCooldown);

  static Future<void> declineCheckpoint(String locationId) =>
      _markDismissed('declined_ckpt_$locationId');

  /// Find the nearest saved checkpoint containing [latitude]/[longitude]
  /// that hasn't been recently declined by the user.
  static Location? suggestCheckpoint(
    List<Location> locations,
    double latitude,
    double longitude,
  ) {
    Location? best;
    double bestDistance = double.infinity;
    for (final location in locations) {
      if (isCheckpointDeclined(location.id)) continue;
      if (!location.isWithinGeofence(latitude, longitude)) continue;
      final distance = location.calculateDistance(latitude, longitude);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = location;
      }
    }
    return best;
  }

  // ----- frequent location detection -----

  static String _clusterKey(double lat, double lng) {
    // ~100m grid (~0.001 deg) makes the key stable per neighborhood.
    return 'frequent_${(lat * 1000).round()}_${(lng * 1000).round()}';
  }

  /// Cluster expense coordinates and return candidates that have been
  /// visited on at least [visitThreshold] distinct days and are not inside
  /// an already-saved checkpoint nor recently dismissed.
  static List<FrequentLocationCandidate> findFrequentLocations({
    required List<Expense> expenses,
    required List<Location> savedLocations,
  }) {
    final located = expenses.where((e) => e.hasCoordinates).toList();
    if (located.length < visitThreshold) return const [];

    final clusters = <_Cluster>[];
    for (final expense in located) {
      _Cluster? match;
      for (final cluster in clusters) {
        if (_distanceMeters(
              cluster.lat,
              cluster.lng,
              expense.latitude!,
              expense.longitude!,
            ) <=
            clusterRadiusMeters) {
          match = cluster;
          break;
        }
      }
      if (match == null) {
        clusters.add(_Cluster()..add(expense));
      } else {
        match.add(expense);
      }
    }

    final candidates = <FrequentLocationCandidate>[];
    for (final cluster in clusters) {
      if (cluster.visitDays.length < visitThreshold) continue;

      // Skip clusters already covered by a saved checkpoint.
      final alreadySaved = savedLocations.any(
        (l) =>
            l.isWithinGeofence(cluster.lat, cluster.lng) ||
            _distanceMeters(
                  l.latitude,
                  l.longitude,
                  cluster.lat,
                  cluster.lng,
                ) <=
                clusterRadiusMeters,
      );
      if (alreadySaved) continue;

      final key = _clusterKey(cluster.lat, cluster.lng);
      if (_isDismissed(key, dismissalCooldown) || isSnoozed(key)) continue;

      candidates.add(
        FrequentLocationCandidate(
          centerLatitude: cluster.lat,
          centerLongitude: cluster.lng,
          visitCount: cluster.visitDays.length,
          totalSpent: cluster.totalSpent,
          key: key,
        ),
      );
    }

    candidates.sort((a, b) => b.visitCount.compareTo(a.visitCount));
    return candidates;
  }

  static Future<void> dismissFrequentLocation(String key) =>
      _markDismissed(key);

  static Future<void> snoozeFrequentLocation(String key) =>
      _markDismissed('snooze_$key');

  static bool isSnoozed(String key) =>
      _isDismissed('snooze_$key', const Duration(days: 7));

  // ----- geo math -----

  static double _distanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c * 1000;
  }

  static double _toRad(double deg) => deg * (math.pi / 180);
}

class _Cluster {
  late double lat;
  late double lng;
  double totalSpent = 0;
  final Set<String> visitDays = {};
  int _count = 0;

  void add(Expense e) {
    // Running average keeps the cluster centered on observed points.
    lat = ((lat * _count) + e.latitude!) / (_count + 1);
    lng = ((lng * _count) + e.longitude!) / (_count + 1);
    _count++;
    totalSpent += e.amount;
    visitDays.add('${e.date.year}-${e.date.month}-${e.date.day}');
  }
}
