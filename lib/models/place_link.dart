import 'package:flutter/material.dart';

/// The icons a saved place can carry.
///
/// Stored on [Location.icon] as the key, never as a code point, so a record
/// written by this build still resolves if the font changes, and a record with
/// no icon still loads (every getter here falls back to a plain pin).
class PlaceIcons {
  PlaceIcons._();

  static const Map<String, IconData> catalogue = {
    'pin': Icons.place_rounded,
    'home': Icons.home_rounded,
    'work': Icons.work_rounded,
    'hotel': Icons.hotel_rounded,
    'restaurant': Icons.restaurant_rounded,
    'cafe': Icons.local_cafe_rounded,
    'bar': Icons.local_bar_rounded,
    'mountain': Icons.terrain_rounded,
    'trail': Icons.hiking_rounded,
    'water': Icons.water_rounded,
    'beach': Icons.beach_access_rounded,
    'park': Icons.park_rounded,
    'train': Icons.train_rounded,
    'plane': Icons.flight_rounded,
    'car': Icons.directions_car_rounded,
    'shop': Icons.shopping_bag_rounded,
    'market': Icons.storefront_rounded,
    'hospital': Icons.local_hospital_rounded,
    'pharmacy': Icons.medication_rounded,
    'school': Icons.school_rounded,
    'gym': Icons.fitness_center_rounded,
    'bank': Icons.account_balance_rounded,
    'post': Icons.local_post_office_rounded,
    'fuel': Icons.local_gas_station_rounded,
    'camp': Icons.cabin_rounded,
    'star': Icons.star_rounded,
    'flag': Icons.flag_rounded,
  };

  /// The icon for [key], or a plain pin.
  ///
  /// A missing or unrecognised key is normal, not an error: every record
  /// written before icons existed has none, and the key set can gain values
  /// this build does not know about.
  static IconData resolve(String? key) {
    if (key == null) return Icons.place_rounded;
    return catalogue[key] ?? Icons.place_rounded;
  }

  static String get defaultKey => 'pin';

  static List<String> get keys => catalogue.keys.toList();
}

/// A coordinate pair pulled out of a pasted link.
class PlaceLink {
  const PlaceLink({required this.latitude, required this.longitude, this.name});

  final double latitude;
  final double longitude;

  /// The place name, when the link carried one.
  final String? name;
}

/// Reads a Google Maps link, or a bare coordinate pair.
///
/// Accepts the shapes a link actually comes in:
///   https://www.google.com/maps/place/Phewa+Lake/@28.2096,83.9856,17z
///   https://maps.google.com/?q=28.2096,83.9856
///   https://www.google.com/maps/search/?api=1&query=28.2096,83.9856
///   geo:28.2096,83.9856
///   28.2096, 83.9856
///
/// Rather than pattern-match every URL shape, this looks for the first
/// decimal pair in the string and then range-checks it, so an unfamiliar
/// variant still works. A pair that is out of range is rejected rather than
/// saved, because a silently wrong coordinate puts a checkpoint in the sea.
class PlaceLinkParser {
  PlaceLinkParser._();

  static final RegExp _pair = RegExp(
    r'(-?\d{1,3}\.\d+)\s*,\s*(-?\d{1,3}\.\d+)',
  );

  /// Parses [input], or returns null if it holds no usable coordinate.
  static PlaceLink? parse(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    // A URL's path can carry a place name before the coordinates. It is
    // decoration here — the coordinates are what matter — so only a
    // coordinates-looking segment is considered, and only when there is exactly
    // one such segment, which keeps a URL with two points from being guessed at.
    final match = _pair.firstMatch(trimmed);
    if (match == null) return null;

    final latitude = double.tryParse(match.group(1)!);
    final longitude = double.tryParse(match.group(2)!);
    if (latitude == null || longitude == null) return null;

    if (latitude < -90 || latitude > 90) return null;
    if (longitude < -180 || longitude > 180) return null;

    return PlaceLink(latitude: latitude, longitude: longitude);
  }

  /// Whether [input] looks like something [parse] can read.
  ///
  /// Used to decide whether to show a "that link has no coordinates" message,
  /// so the user is not left wondering why nothing happened.
  static bool looksLikeALink(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return false;
    return trimmed.contains(RegExp(r'[0-9]\.[0-9]'));
  }
}
