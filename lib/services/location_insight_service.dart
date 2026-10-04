import 'dart:math' as math;

import 'package:hive_flutter/hive_flutter.dart';
import 'package:daily_companion/models/index.dart';

/// A geographic cluster of transaction coordinates, treated as evidence of
/// repeated visits to the same unnamed place.
///
/// SPENDS AND EARNINGS BOTH. This used to take `List<Expense>` because only an
/// expense had coordinates. Both now do, and a place you are paid at is as much
/// a place you keep going to as a shop — so the cluster counts both, and the
/// candidate's total is the sum of money moved there rather than money spent.
class FrequentLocationCandidate {
  FrequentLocationCandidate({
    required this.centerLatitude,
    required this.centerLongitude,
    required this.transactionCount,
    required this.dayCount,
    required this.totalSpent,
    required this.key,
  });

  final double centerLatitude;
  final double centerLongitude;

  /// How many transactions have been recorded at this spot.
  ///
  /// THIS IS WHAT THE THRESHOLD IS COUNTED IN, and what the prompt quotes. It
  /// used to be a count of distinct DAYS, which is why five transactions in one
  /// sitting produced no prompt at all: one day, threshold four.
  final int transactionCount;

  /// How many DIFFERENT DAYS those transactions fell on.
  ///
  /// Reported rather than gating. It is the difference between "a place you
  /// keep going to" and "one visit where you bought four things", and it is
  /// worth knowing — but it must not be the thing that silences a prompt the
  /// user is waiting for.
  final int dayCount;

  /// Money moved at this cluster — spending AND income.
  ///
  /// Named for the domain it came from and kept rather than renamed: the key is
  /// "you have been spending here a lot", and a single word change would read as
  /// a different claim about the same number.
  final double totalSpent;
  final String key;

  String get coordinateLabel =>
      '${centerLatitude.toStringAsFixed(4)}, ${centerLongitude.toStringAsFixed(4)}';
}

/// Location intelligence for transactions:
///
/// - checkpoint matching (is the user inside a saved place's radius?)
/// - frequent-location detection from transaction coordinates (no background
///   tracking — entry timestamps/coords are the only evidence)
///
/// Dismissal/cooldown state is persisted in a Hive box so suggestions and
/// confirmations never spam the user.
class LocationInsightService {
  LocationInsightService._();

  static const String _stateBoxName = 'location_insight_state';
  static Box<String>? _stateBox;

  /// Two transactions closer than this are considered the same spot.
  ///
  /// 150 m is about a city block. It has to be wider than a phone's positional
  /// error, or a single visit scatters across two clusters and the count never
  /// reaches the threshold — which is the whole failure this feature exists to
  /// catch.
  static const double clusterRadiusMeters = 150;

  /// Transactions at one spot required before offering to name it.
  ///
  /// Four. Low enough that a regular routine is noticed while it is still
  /// forming, high enough that one purchase does not become a suggestion the
  /// user has to dismiss.
  ///
  /// COUNTED IN TRANSACTIONS, not days. See the note where it is compared.
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

  /// Cluster transaction coordinates and return candidates that have been
  /// visited on at least [visitThreshold] distinct days and are not inside
  /// an already-saved checkpoint nor recently dismissed.
  ///
  /// Takes [Transaction], not [Expense]: income carries a location too, and a
  /// spot the user is paid at repeatedly is the same evidence as a shop they
  /// buy lunch at.
  static List<FrequentLocationCandidate> findFrequentLocations({
    required List<Transaction> transactions,
    required List<Location> savedLocations,
  }) {
    final located = transactions.where((e) => e.hasCoordinates).toList();
    if (located.length < visitThreshold) return const [];

    final clusters = <_Cluster>[];
    for (final transaction in located) {
      _Cluster? match;
      for (final cluster in clusters) {
        if (_distanceMeters(
              cluster.lat,
              cluster.lng,
              transaction.latitude!,
              transaction.longitude!,
            ) <=
            clusterRadiusMeters) {
          match = cluster;
          break;
        }
      }
      if (match == null) {
        clusters.add(_Cluster()..add(transaction));
      } else {
        match.add(transaction);
      }
    }

    final candidates = <FrequentLocationCandidate>[];
    for (final cluster in clusters) {
      // THE COUNT IS TRANSACTIONS, NOT DAYS. It used to be
      // `cluster.visitDays.length`, which meant five expenses recorded in one
      // sitting counted as ONE visit and the prompt never appeared — the user
      // blitzed five transactions at an unsaved spot and got silence, and the
      // number they had agreed (4) was being applied to the wrong thing.
      //
      // Counting transactions is what "you have been spending here a lot"
      // actually means. The spam risks are handled by the other guards rather
      // than by weakening this one: clusters are capped at [clusterRadiusMeters],
      // a spot already covered by a saved place is skipped entirely, and a
      // dismissal suppresses that spot for [dismissalCooldown]. Day spread is
      // still RECORDED, and reported, it just no longer decides.
      if (cluster.count < visitThreshold) continue;

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
          transactionCount: cluster.count,
          dayCount: cluster.visitDays.length,
          totalSpent: cluster.totalSpent,
          key: key,
        ),
      );
    }

    candidates.sort((a, b) => b.transactionCount.compareTo(a.transactionCount));
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
  // Zero-initialised rather than `late`, and [add] seeds from the first point.
  //
  // It used to be `late double lat` with a running average, which reads `lat`
  // BEFORE assigning it — so the very first `add` threw
  // LateInitializationError and this method could never have returned a result
  // for any input. It was dead code, so nothing called it and nothing noticed.
  // Wiring it up is what surfaced it.
  double lat = 0;
  double lng = 0;
  double totalSpent = 0;
  final Set<String> visitDays = {};
  int _count = 0;

  /// Transactions in this cluster. What [visitThreshold] is compared against.
  int get count => _count;

  /// Takes a [Transaction] so income clusters exactly as expense does.
  void add(Transaction e) {
    if (_count == 0) {
      // SEED, do not average. Averaging against an unstarted sum would divide
      // the first point by one and be right by luck; making the first point the
      // centre is the actual rule, and it stays correct as points arrive.
      lat = e.latitude!;
      lng = e.longitude!;
    } else {
      // Running average keeps the cluster centered on observed points.
      lat = ((lat * _count) + e.latitude!) / (_count + 1);
      lng = ((lng * _count) + e.longitude!) / (_count + 1);
    }
    _count++;
    totalSpent += e.amount;
    visitDays.add('${e.date.year}-${e.date.month}-${e.date.day}');
  }
}
