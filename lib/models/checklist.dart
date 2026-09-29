import 'package:uuid/uuid.dart';

class Checklist {
  final String id;
  final String name;
  final String description;
  final List<ChecklistItem> items;
  final String? linkedLocationId;
  final String? journeyId;
  final bool isEverydayEssentials;
  final DateTime createdAt;
  final DateTime updatedAt;

  Checklist({
    String? id,
    required this.name,
    required this.description,
    List<ChecklistItem>? items,
    this.linkedLocationId,
    this.journeyId,
    this.isEverydayEssentials = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       items = items ?? [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  // Convert to JSON for database storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'linkedLocationId': linkedLocationId,
      'journeyId': journeyId,
      'isEverydayEssentials': isEverydayEssentials ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  // Create from JSON
  factory Checklist.fromJson(
    Map<String, dynamic> json,
    List<ChecklistItem> items,
  ) {
    return Checklist(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      linkedLocationId: json['linkedLocationId'],
      journeyId: json['journeyId'],
      isEverydayEssentials: json['isEverydayEssentials'] == 1,
      items: items,
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }

  // Copy with modifications
  Checklist copyWith({
    String? name,
    String? description,
    List<ChecklistItem>? items,
    String? linkedLocationId,
    String? journeyId,
    bool? isEverydayEssentials,
    bool clearJourney = false,
  }) {
    return Checklist(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      items: items ?? this.items,
      linkedLocationId: linkedLocationId ?? this.linkedLocationId,
      journeyId: clearJourney ? null : (journeyId ?? this.journeyId),
      isEverydayEssentials: isEverydayEssentials ?? this.isEverydayEssentials,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  // Get progress
  double getProgress() {
    if (items.isEmpty) return 0;
    int checkedCount = items.where((item) => item.isChecked).length;
    return checkedCount / items.length;
  }
}

class ChecklistItem {
  final String id;
  final String checklistId;
  final String name;
  final bool isChecked;
  final DateTime createdAt;

  ChecklistItem({
    String? id,
    required this.checklistId,
    required this.name,
    this.isChecked = false,
    DateTime? createdAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'checklistId': checklistId,
      'name': name,
      'isChecked': isChecked ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  // Create from JSON
  factory ChecklistItem.fromJson(Map<String, dynamic> json) {
    return ChecklistItem(
      id: json['id'],
      checklistId: json['checklistId'],
      name: json['name'],
      isChecked: json['isChecked'] == 1,
      createdAt: DateTime.parse(json['createdAt']),
    );
  }

  // Copy with modifications
  ChecklistItem copyWith({bool? isChecked}) {
    return ChecklistItem(
      id: id,
      checklistId: checklistId,
      name: name,
      isChecked: isChecked ?? this.isChecked,
      createdAt: createdAt,
    );
  }
}
