import 'package:uuid/uuid.dart';

enum JourneyStatus { upcoming, active, completed }

extension JourneyStatusX on JourneyStatus {
  String get label {
    switch (this) {
      case JourneyStatus.upcoming:
        return 'Upcoming';
      case JourneyStatus.active:
        return 'Active';
      case JourneyStatus.completed:
        return 'Completed';
    }
  }
}

class Journey {
  final String id;
  final String destination;
  final String origin;
  final String notes;
  final List<String> items;
  final DateTime startTime;
  final DateTime? endTime;
  final bool completed;
  final DateTime createdAt;
  final DateTime updatedAt;

  Journey({
    String? id,
    required this.destination,
    required this.origin,
    this.notes = '',
    List<String>? items,
    DateTime? startTime,
    this.endTime,
    this.completed = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       items = items ?? const [],
       startTime = startTime ?? DateTime.now(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'destination': destination,
      'origin': origin,
      'notes': notes,
      'items': items,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'completed': completed ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Journey.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final parsedItems = rawItems is List
        ? rawItems.map((item) => item.toString()).toList()
        : <String>[];

    return Journey(
      id: json['id'],
      destination: json['destination'] ?? '',
      origin: json['origin'] ?? '',
      notes: json['notes'] ?? '',
      items: parsedItems,
      startTime: DateTime.parse(
        json['startTime'] ?? DateTime.now().toIso8601String(),
      ),
      endTime: json['endTime'] == null
          ? null
          : DateTime.tryParse(json['endTime']),
      completed: json['completed'] == 1 || json['completed'] == true,
      createdAt: DateTime.parse(
        json['createdAt'] ?? DateTime.now().toIso8601String(),
      ),
      updatedAt: DateTime.parse(
        json['updatedAt'] ?? DateTime.now().toIso8601String(),
      ),
    );
  }

  Journey copyWith({
    String? destination,
    String? origin,
    String? notes,
    List<String>? items,
    DateTime? startTime,
    DateTime? endTime,
    bool? completed,
  }) {
    return Journey(
      id: id,
      destination: destination ?? this.destination,
      origin: origin ?? this.origin,
      notes: notes ?? this.notes,
      items: items ?? this.items,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      completed: completed ?? this.completed,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  /// Derived status: completed if done; upcoming if it starts in the future;
  /// otherwise the journey is currently active.
  JourneyStatus get status {
    if (completed) return JourneyStatus.completed;
    if (startTime.isAfter(DateTime.now())) return JourneyStatus.upcoming;
    return JourneyStatus.active;
  }

  /// Display name — journeys are destination-centric.
  String get title => destination.isNotEmpty ? destination : origin;

  int get durationMinutes {
    if (endTime == null) return 0;
    return endTime!.difference(startTime).inMinutes.abs();
  }

  String get durationText {
    final totalMinutes = durationMinutes;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours == 0) return '${minutes}m';
    return '${hours}h ${minutes}m';
  }
}
