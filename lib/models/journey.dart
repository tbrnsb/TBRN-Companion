import 'package:uuid/uuid.dart';

import 'trip_participant.dart';

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

  /// Who is sharing this trip's costs.
  ///
  /// Empty by default, which is what every journey created before this feature
  /// reads back as — a trip is not shared because a field exists, it is shared
  /// because the user added people to it.
  final List<TripParticipant> participants;

  /// Which participant is "me" on this trip.
  ///
  /// Required before the app can say what *you* owe, which is the one number an
  /// importing user wants. Null means the user has not answered yet — not
  /// "you owe nothing", which would be the confidently wrong answer.
  final String? localParticipantId;

  /// Transfers the user has ticked as paid, as keys not rows.
  ///
  /// The settlement is recomputed from the expenses every time it is shown, so
  /// this has to be recognisable across recomputes. See [Transfer.key]:
  /// "fromId>toId:amountInPaise", which two devices that imported the same
  /// snapshot both compute identically.
  final List<String> settledTransfers;

  /// A short code friends can read aloud to confirm they are on the same trip.
  ///
  /// It identifies the trip and does NOTHING else: no sync, no room, no live
  /// state. It exists so two people can confirm they are looking at the same
  /// trip rather than two trips that happen to share a name. Never word it as
  /// though joining it connects them.
  final String? tripCode;

  /// Ids the user has deliberately deleted from this trip.
  ///
  /// This is what makes "import only ever adds" safe. Without a record of the
  /// deletion, an older snapshot still listing that expense would put it back —
  /// and the user would watch an expense they deleted on purpose reappear every
  /// time a friend re-shared, with no way to stop it. A tombstone is the cost of
  /// add-only merging: the app refuses to forget, so it also refuses to undo.
  ///
  /// Ids are UUIDs minted by this app and unique across every record type, so
  /// one list covers deleted expenses and deleted participants alike.
  final List<String> removedIds;

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
    List<TripParticipant>? participants,
    this.localParticipantId,
    List<String>? settledTransfers,
    this.tripCode,
    List<String>? removedIds,
  }) : id = id ?? const Uuid().v4(),
       items = items ?? const [],
       participants = participants ?? const [],
       settledTransfers = settledTransfers ?? const [],
       removedIds = removedIds ?? const [],
       startTime = startTime ?? DateTime.now(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  /// Whether this trip is shared between people.
  ///
  /// Two or more participants, not one. A one-person trip has nobody to owe and
  /// to be owed by, so every shared-trip affordance stays out of the way.
  bool get isShared => participants.length >= 2;

  /// The user themselves, or null when they have not said which one they are.
  TripParticipant? get localParticipant {
    final id = localParticipantId;
    if (id == null) return null;
    for (final participant in participants) {
      if (participant.id == id) return participant;
    }
    return null;
  }

  /// Whether the local participant is known. Distinct from "owes nothing".
  bool get hasLocalParticipant => localParticipant != null;

  /// [participantId] resolved to a name, falling back to the id itself.
  ///
  /// An id that resolves to nobody is a real state — an expense imported from a
  /// file whose participant list has not been merged yet — and the fallback keeps
  /// the screen readable instead of printing an empty row.
  String participantName(String? participantId) {
    if (participantId == null || participantId.isEmpty) return 'Unassigned';
    for (final participant in participants) {
      if (participant.id == participantId) return participant.name;
    }
    return participantId;
  }

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
      // Optional keys. Every one of these reads back as its default on a
      // record written before the field existed, which is what makes adding
      // them safe for existing data.
      'participants': participantsToJson(participants),
      'localParticipantId': localParticipantId,
      'settledTransfers': settledTransfers,
      'tripCode': tripCode,
      'removedIds': removedIds,
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
      participants: participantsFromJson(json['participants']),
      localParticipantId: json['localParticipantId']?.toString(),
      settledTransfers: _stringList(json['settledTransfers']),
      tripCode: json['tripCode']?.toString(),
      removedIds: _stringList(json['removedIds']),
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
    List<TripParticipant>? participants,
    String? localParticipantId,
    List<String>? settledTransfers,
    String? tripCode,
    List<String>? removedIds,
    bool clearLocalParticipant = false,
    bool clearTripCode = false,
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
      participants: participants ?? this.participants,
      localParticipantId: clearLocalParticipant
          ? null
          : (localParticipantId ?? this.localParticipantId),
      settledTransfers: settledTransfers ?? this.settledTransfers,
      tripCode: clearTripCode ? null : (tripCode ?? this.tripCode),
      removedIds: removedIds ?? this.removedIds,
    );
  }

  /// Whether the user deleted this record from this trip.
  ///
  /// Checked by the importer before adding anything: a file that still lists a
  /// deleted record must not put it back.
  bool isRemoved(String recordId) => removedIds.contains(recordId);

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

/// Reads a list of string keys, defensively.
///
/// Entries are stringified rather than skipped, and anything that is not a list
/// at all reads as empty. A settled-transfer key is a value the app wrote, so a
/// future build that changes its shape must not be able to make an existing trip
/// fail to load.
List<String> _stringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return [for (final entry in raw) entry.toString()];
}
