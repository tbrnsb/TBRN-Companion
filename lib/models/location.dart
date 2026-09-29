import 'package:uuid/uuid.dart';

import 'dart:math' as math;

class Location {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String description;
  final String? color; // Hex color code
  final String? icon; // Icon emoji or name
  final double radiusMeters; // Geofence radius
  final String? journeyId; // Optional journey this place belongs to
  final DateTime createdAt;
  final DateTime updatedAt;

  Location({
    String? id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.description,
    this.color,
    this.icon,
    this.journeyId,
    this.radiusMeters = 100.0,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  // Convert to JSON for database storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'description': description,
      'color': color,
      'icon': icon,
      'journeyId': journeyId,
      'radiusMeters': radiusMeters,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  // Create from JSON
  factory Location.fromJson(Map<String, dynamic> json) {
    return Location(
      id: json['id'],
      name: json['name'],
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      description: json['description'],
      color: json['color'],
      icon: json['icon'],
      journeyId: json['journeyId'],
      radiusMeters: (json['radiusMeters'] as num?)?.toDouble() ?? 100.0,
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }

  // Copy with modifications
  Location copyWith({
    String? name,
    double? latitude,
    double? longitude,
    String? description,
    String? color,
    String? icon,
    String? journeyId,
    double? radiusMeters,
    bool clearJourney = false,
  }) {
    return Location(
      id: id,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      description: description ?? this.description,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      journeyId: clearJourney ? null : (journeyId ?? this.journeyId),
      radiusMeters: radiusMeters ?? this.radiusMeters,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  // Calculate distance from coordinates (Haversine formula)
  double calculateDistance(double userLat, double userLng) {
    const double earthRadiusKm = 6371.0;

    double dLat = _toRadians(latitude - userLat);
    double dLng = _toRadians(longitude - userLng);

    double a =
        (math.sin(dLat / 2) * math.sin(dLat / 2)) +
        (math.cos(_toRadians(userLat)) *
            math.cos(_toRadians(latitude)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2));

    double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    double distance = earthRadiusKm * c;

    return distance * 1000; // Return in meters
  }

  double _toRadians(double degrees) {
    return degrees * (math.pi / 180);
  }

  // Check if coordinates are within geofence
  bool isWithinGeofence(double userLat, double userLng) {
    double distance = calculateDistance(userLat, userLng);
    return distance <= radiusMeters;
  }
}

// Removed custom Math class - using dart:math instead
