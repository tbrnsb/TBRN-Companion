import 'package:uuid/uuid.dart';

class LocationLog {
  final String id;
  final String locationId;
  final DateTime arrivalTime;
  final DateTime? departureTime;
  final DateTime createdAt;

  LocationLog({
    String? id,
    required this.locationId,
    required this.arrivalTime,
    this.departureTime,
    DateTime? createdAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'locationId': locationId,
      'arrivalTime': arrivalTime.toIso8601String(),
      'departureTime': departureTime?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  // Create from JSON
  factory LocationLog.fromJson(Map<String, dynamic> json) {
    return LocationLog(
      id: json['id'],
      locationId: json['locationId'],
      arrivalTime: DateTime.parse(json['arrivalTime']),
      departureTime: json['departureTime'] != null
          ? DateTime.parse(json['departureTime'])
          : null,
      createdAt: DateTime.parse(json['createdAt']),
    );
  }

  // Copy with modifications
  LocationLog copyWith({DateTime? departureTime}) {
    return LocationLog(
      id: id,
      locationId: locationId,
      arrivalTime: arrivalTime,
      departureTime: departureTime ?? this.departureTime,
      createdAt: createdAt,
    );
  }

  // Get duration at location (in minutes)
  int? getDurationMinutes() {
    if (departureTime == null) return null;
    return departureTime!.difference(arrivalTime).inMinutes;
  }

  // Check if currently at location
  bool isCurrentlyHere() => departureTime == null;
}
