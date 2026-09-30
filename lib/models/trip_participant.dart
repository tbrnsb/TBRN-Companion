import 'package:uuid/uuid.dart';

/// Someone sharing a trip's costs.
///
/// A NAME, not an account. This is three friends splitting a taxi, not three
/// hundred users with passwords: there is no login, no email, nothing that
/// identifies anybody beyond the word they gave you, and nothing to sync. A
/// participant that needed an account would make the whole feature depend on a
/// backend, which would undo the one thing the app promises — that nothing
/// leaves the phone.
///
/// Stored as a list of plain JSON maps inside the journey's own record rather
/// than in a Hive box of its own, for the same reason: a separate box would need
/// its own lifecycle, and a participant is meaningless without the trip it
/// belongs to.
class TripParticipant {
  const TripParticipant({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  TripParticipant.create({
    required String name,
    DateTime? createdAt,
    String? id,
  }) : this(
         id: id ?? const Uuid().v4(),
         name: name,
         createdAt: createdAt ?? DateTime.now(),
       );

  /// Generated once and never reused. Survives the trip being exported and
  /// re-imported on another phone, which is what lets an expense's
  /// `paidByParticipantId` still mean the same person after a round trip.
  final String id;

  /// What the user typed. Never resolved against anything.
  final String name;

  final DateTime createdAt;

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'createdAt': createdAt.toIso8601String()};
  }

  /// Reads a participant back, defensively.
  ///
  /// MIGRATION SAFETY, same rule as the rest of the app: a field that is absent
  /// reads as its default rather than throwing, because an absent field is what
  /// every record written before this feature looks like. A record with no id
  /// gets a fresh one rather than being dropped — a nameless participant the user
  /// did add should not silently disappear on load.
  factory TripParticipant.fromJson(Map<String, dynamic> json) {
    return TripParticipant(
      id: json['id']?.toString() ?? const Uuid().v4(),
      name: json['name']?.toString() ?? '',
      createdAt: _parseCreatedAt(json['createdAt']),
    );
  }

  TripParticipant copyWith({String? name}) {
    return TripParticipant(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TripParticipant && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'TripParticipant($id, $name)';
}

DateTime _parseCreatedAt(Object? raw) {
  if (raw is String) {
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed;
  }
  return DateTime.now();
}

/// Reads a participants list out of stored JSON.
///
/// A field that is missing, the wrong type, or a list holding something that is
/// not a map all read as "no participants" rather than throwing. A file from a
/// future build, or a hand-edited one, has to load.
List<TripParticipant> participantsFromJson(Object? raw) {
  if (raw is! List) return <TripParticipant>[];
  final participants = <TripParticipant>[];
  for (final entry in raw) {
    if (entry is Map) {
      participants.add(
        TripParticipant.fromJson(Map<String, dynamic>.from(entry)),
      );
    }
  }
  return participants;
}

/// The shape a participants list takes in JSON, with the field names in one
/// place so `toJson` and `fromJson` cannot disagree.
List<Map<String, dynamic>> participantsToJson(
  List<TripParticipant> participants,
) {
  return [for (final p in participants) p.toJson()];
}
