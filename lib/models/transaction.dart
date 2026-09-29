import 'package:uuid/uuid.dart';

import 'expense_category_meta.dart';

enum TransactionType { expense, income }

extension TransactionTypeX on TransactionType {
  String get label {
    final name = toString().split('.').last;
    return name[0].toUpperCase() + name.substring(1);
  }
}

class Transaction {
  final String id;
  final double amount;
  final TransactionType type;
  final String description;
  final String? customCategoryName;
  final DateTime date;
  final DateTime createdAt;

  Transaction({
    String? id,
    required this.amount,
    required this.type,
    required this.description,
    this.customCategoryName,
    DateTime? date,
    DateTime? createdAt,
  }) : id = id ?? const Uuid().v4(),
       date = date ?? DateTime.now(),
       createdAt = createdAt ?? DateTime.now();

  bool get isExpense => type == TransactionType.expense;
  bool get isIncome => type == TransactionType.income;

  String get effectiveCategoryName => customCategoryName ?? _getCategoryName();

  String _getCategoryName() {
    if (type == TransactionType.expense) return 'Expense';
    if (type == TransactionType.income) return 'Income';
    return 'Other';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'amount': amount,
      'type': type.toString().split('.').last,
      'description': description,
      'customCategoryName': customCategoryName,
      'date': date.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Transaction.fromJson(Map<String, dynamic> json) {
    final type = json['type'] == null
        ? TransactionType.expense
        : TransactionType.values.firstWhere(
            (t) => t.toString().split('.').last == json['type'],
            orElse: () => TransactionType.expense,
          );

    if (type == TransactionType.income) {
      return Income.fromJson(json);
    }
    return Expense.fromJson(json);
  }
}

class Expense extends Transaction {
  final String? locationId;
  final ExpenseCategory category;
  final String? journeyId;
  final double? latitude;
  final double? longitude;
  final DateTime? locationCapturedAt;

  bool get hasCoordinates => latitude != null && longitude != null;

  Expense({
    String? id,
    required double amount,
    required this.category,
    required String description,
    this.locationId,
    String? customCategoryName,
    this.latitude,
    this.longitude,
    this.locationCapturedAt,
    this.journeyId,
    DateTime? date,
  }) : super(
         id: id,
         amount: amount,
         type: TransactionType.expense,
         description: description,
         customCategoryName: customCategoryName,
         date: date,
         createdAt: DateTime.now(),
       );

  String getCategoryName() {
    if (category == ExpenseCategory.other) return customCategoryName ?? 'Other';
    return CategoryRegistry.metaFor(category).name;
  }

  CategoryMeta get categoryMeta =>
      CategoryRegistry.metaFor(category, customName: customCategoryName);

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json['category'] = category.toString().split('.').last;
    json['locationId'] = locationId;
    json['journeyId'] = journeyId;
    json['latitude'] = latitude;
    json['longitude'] = longitude;
    json['locationCapturedAt'] = locationCapturedAt?.toIso8601String();
    return json;
  }

  factory Expense.fromJson(Map<String, dynamic> json) {
    return Expense(
      id: json['id'],
      amount: json['amount'],
      category: ExpenseCategory.values.firstWhere(
        (e) => e.toString().split('.').last == json['category'],
        orElse: () => ExpenseCategory.other,
      ),
      description: json['description'],
      locationId: json['locationId'],
      customCategoryName: json['customCategoryName'],
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      locationCapturedAt: json['locationCapturedAt'] == null
          ? null
          : DateTime.tryParse(json['locationCapturedAt']),
      journeyId: json['journeyId'],
      date: DateTime.parse(json['date']),
    );
  }

  Expense copyWith({
    double? amount,
    ExpenseCategory? category,
    String? description,
    String? locationId,
    String? customCategoryName,
    double? latitude,
    double? longitude,
    DateTime? locationCapturedAt,
    String? journeyId,
    TransactionType? type,
    DateTime? date,
    bool clearLocation = false,
    bool clearCoordinates = false,
    bool clearJourney = false,
  }) {
    return Expense(
      id: id,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      description: description ?? this.description,
      locationId: clearLocation ? null : (locationId ?? this.locationId),
      customCategoryName: customCategoryName ?? this.customCategoryName,
      latitude: clearCoordinates ? null : (latitude ?? this.latitude),
      longitude: clearCoordinates ? null : (longitude ?? this.longitude),
      locationCapturedAt: clearCoordinates
          ? null
          : (locationCapturedAt ?? this.locationCapturedAt),
      journeyId: clearJourney ? null : (journeyId ?? this.journeyId),
      date: date ?? this.date,
    );
  }
}

class Income extends Transaction {
  final String category;

  Income({
    String? id,
    required double amount,
    required this.category,
    required String description,
    String? customCategoryName,
    DateTime? date,
  }) : super(
         id: id,
         amount: amount,
         type: TransactionType.income,
         description: description,
         customCategoryName: customCategoryName,
         date: date,
         createdAt: DateTime.now(),
       );

  CategoryMeta get categoryMeta => CategoryRegistry.metaForIncome(category);

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json['category'] = category;
    return json;
  }

  factory Income.fromJson(Map<String, dynamic> json) {
    return Income(
      id: json['id'],
      amount: json['amount'],
      category: json['category'],
      description: json['description'],
      customCategoryName: json['customCategoryName'],
      date: DateTime.parse(json['date']),
    );
  }

  Income copyWith({
    double? amount,
    String? category,
    String? description,
    String? customCategoryName,
    DateTime? date,
  }) {
    return Income(
      id: id,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      description: description ?? this.description,
      customCategoryName: customCategoryName ?? this.customCategoryName,
      date: date ?? this.date,
    );
  }
}

extension TransactionExtensions on Transaction {
  CategoryMeta get categoryMeta {
    if (this is Expense) {
      return (this as Expense).categoryMeta;
    }
    return CategoryRegistry.metaForIncome(effectiveCategoryName);
  }

  String? get locationId {
    if (this is Expense) {
      return (this as Expense).locationId;
    }
    return null;
  }

  String? get journeyId {
    if (this is Expense) {
      return (this as Expense).journeyId;
    }
    return null;
  }

  double? get latitude {
    if (this is Expense) {
      return (this as Expense).latitude;
    }
    return null;
  }

  double? get longitude {
    if (this is Expense) {
      return (this as Expense).longitude;
    }
    return null;
  }

  DateTime? get locationCapturedAt {
    if (this is Expense) {
      return (this as Expense).locationCapturedAt;
    }
    return null;
  }

  bool get hasCoordinates {
    if (this is Expense) {
      return (this as Expense).hasCoordinates;
    }
    return false;
  }

  String getCategoryName() {
    if (this is Expense) {
      return (this as Expense).getCategoryName();
    }
    return CategoryRegistry.metaForIncome(effectiveCategoryName).name;
  }

  ExpenseCategory? get expenseCategory {
    if (this is Expense) {
      return (this as Expense).category;
    }
    return null;
  }
}
