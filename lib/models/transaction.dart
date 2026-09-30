import 'package:uuid/uuid.dart';

import 'expense_category_meta.dart';

enum TransactionType { expense, income }

/// How the money actually moved.
///
/// Deliberately not a set of accounts. Several wallets was considered and
/// rejected: it turns a two-tap field into a ledger, and every balance in the
/// app would then have to say which wallet it is talking about. This answers
/// the question people actually ask of a single expense — did I hand over
/// cash or tap my phone.
enum PaymentMethod { cash, online }

extension PaymentMethodX on PaymentMethod {
  String get label => this == PaymentMethod.cash ? 'Cash' : 'Online';

  /// Reads a persisted value, or null when there is nothing usable.
  ///
  /// Null is a real state, not a failure: every record written before this
  /// field existed has no payment method, and guessing "cash" would put a fact
  /// in the user's data that they never entered.
  static PaymentMethod? fromName(String? name) {
    if (name == null) return null;
    for (final method in PaymentMethod.values) {
      if (method.name == name) return method;
    }
    return null;
  }
}

extension TransactionTypeX on TransactionType {
  String get label {
    final name = toString().split('.').last;
    return name[0].toUpperCase() + name.substring(1);
  }
}

/// Base class for money moving in or out.
///
/// Sealed on purpose: only [Expense] and [Income] are valid. A bare
/// `Transaction` carries no category, so it would persist and then silently
/// deserialise back as an "Other" expense. Making it sealed removes the
/// possibility of creating one by accident.
sealed class Transaction {
  final String id;
  final double amount;
  final TransactionType type;
  final String description;
  final String? customCategoryName;

  /// Null when it was never recorded, which is the case for every record
  /// written before this field existed.
  final PaymentMethod? paymentMethod;
  final DateTime date;
  final DateTime createdAt;

  Transaction({
    String? id,
    required this.amount,
    required this.type,
    required this.description,
    this.customCategoryName,
    this.paymentMethod,
    DateTime? date,
    DateTime? createdAt,
  }) : id = id ?? const Uuid().v4(),
       date = date ?? DateTime.now(),
       createdAt = createdAt ?? DateTime.now();

  bool get isExpense => type == TransactionType.expense;
  bool get isIncome => type == TransactionType.income;

  /// The human-readable category this transaction is filed under.
  ///
  /// Delegates to [getCategoryName] so [Expense] and [Income] report their real
  /// category instead of the bare type name. For an expense, the custom name
  /// takes over when the category is [ExpenseCategory.other], which is the only
  /// pairing the picker ever produces.
  String get effectiveCategoryName => getCategoryName();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'amount': amount,
      'type': type.toString().split('.').last,
      'description': description,
      'customCategoryName': customCategoryName,
      'paymentMethod': paymentMethod?.name,
      'date': date.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// Reads a persisted transaction back.
  ///
  /// MIGRATION SAFETY: records written before the `type` key existed have no
  /// `type` at all, and records written by any future/older writer may carry an
  /// unrecognised value. Both fall back to [TransactionType.expense], because
  /// every pre-existing record on disk is an expense. This default is the
  /// entire migration story for existing user data — do not change it.
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

  /// Which participant fronted this expense, on a shared trip.
  ///
  /// It lives ON THE EXPENSE and not in a box of its own, deliberately. A
  /// separate `payments` box would outlive the expenses it points at: delete an
  /// expense and its payer record would sit there forever pointing at nothing,
  /// needing its own cleanup and its own migration story. Here the payment dies
  /// with its expense, and there is nothing to reconcile.
  ///
  /// Null on every expense written before this field existed, and null on an
  /// expense on a trip that is not shared — those are ordinary expenses and the
  /// app must not imply a payment was tracked for them.
  final String? paidByParticipantId;

  bool get hasCoordinates => latitude != null && longitude != null;

  Expense({
    super.id,
    required super.amount,
    required this.category,
    required super.description,
    this.locationId,
    super.customCategoryName,
    super.paymentMethod,
    this.latitude,
    this.longitude,
    this.locationCapturedAt,
    this.journeyId,
    this.paidByParticipantId,
    super.date,
    super.createdAt,
  }) : super(type: TransactionType.expense);

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
    // Optional: absent on every expense written before the field existed.
    json['paidByParticipantId'] = paidByParticipantId;
    return json;
  }

  factory Expense.fromJson(Map<String, dynamic> json) {
    return Expense(
      id: json['id'],
      amount: (json['amount'] as num).toDouble(),
      category: ExpenseCategory.values.firstWhere(
        (e) => e.toString().split('.').last == json['category'],
        orElse: () => ExpenseCategory.other,
      ),
      description: json['description'],
      locationId: json['locationId'],
      customCategoryName: json['customCategoryName'],
      paymentMethod: PaymentMethodX.fromName(json['paymentMethod'] as String?),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      locationCapturedAt: json['locationCapturedAt'] == null
          ? null
          : DateTime.tryParse(json['locationCapturedAt']),
      journeyId: json['journeyId'],
      // Not validated against the journey's participant list here, and that is
      // the point: an expense whose payer id resolves to nobody — imported
      // before the participants merged, or a participant since deleted — has to
      // load and display. Validating would turn a recoverable display name into
      // a thrown error on the way past real user data.
      paidByParticipantId: json['paidByParticipantId']?.toString(),
      date: DateTime.parse(json['date']),
      createdAt: _parseCreatedAt(json['createdAt']),
    );
  }

  Expense copyWith({
    double? amount,
    ExpenseCategory? category,
    String? description,
    String? locationId,
    String? customCategoryName,
    PaymentMethod? paymentMethod,
    double? latitude,
    double? longitude,
    DateTime? locationCapturedAt,
    String? journeyId,
    String? paidByParticipantId,
    DateTime? date,
    DateTime? createdAt,
    bool clearLocation = false,
    bool clearCoordinates = false,
    bool clearJourney = false,
    bool clearPaidByParticipant = false,
  }) {
    return Expense(
      id: id,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      description: description ?? this.description,
      locationId: clearLocation ? null : (locationId ?? this.locationId),
      customCategoryName: customCategoryName ?? this.customCategoryName,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      latitude: clearCoordinates ? null : (latitude ?? this.latitude),
      longitude: clearCoordinates ? null : (longitude ?? this.longitude),
      locationCapturedAt: clearCoordinates
          ? null
          : (locationCapturedAt ?? this.locationCapturedAt),
      journeyId: clearJourney ? null : (journeyId ?? this.journeyId),
      paidByParticipantId: clearPaidByParticipant
          ? null
          : (paidByParticipantId ?? this.paidByParticipantId),
      date: date ?? this.date,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class Income extends Transaction {
  final String category;

  Income({
    super.id,
    required super.amount,
    required this.category,
    required super.description,
    super.customCategoryName,
    super.paymentMethod,
    super.date,
    super.createdAt,
  }) : super(type: TransactionType.income);

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
      amount: (json['amount'] as num).toDouble(),
      category: json['category'],
      description: json['description'],
      customCategoryName: json['customCategoryName'],
      paymentMethod: PaymentMethodX.fromName(json['paymentMethod'] as String?),
      date: DateTime.parse(json['date']),
      createdAt: _parseCreatedAt(json['createdAt']),
    );
  }

  Income copyWith({
    double? amount,
    String? category,
    String? description,
    String? customCategoryName,
    PaymentMethod? paymentMethod,
    DateTime? date,
    DateTime? createdAt,
  }) {
    return Income(
      id: id,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      description: description ?? this.description,
      customCategoryName: customCategoryName ?? this.customCategoryName,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      date: date ?? this.date,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// `createdAt` was absent from records written before the field existed.
/// Returns null in that case so the constructor stamps a fresh value.
DateTime? _parseCreatedAt(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}

extension TransactionExtensions on Transaction {
  CategoryMeta get categoryMeta {
    if (this is Expense) {
      return (this as Expense).categoryMeta;
    }
    return CategoryRegistry.metaForIncome((this as Income).category);
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

  /// Which participant paid, for a shared trip. Null for income and for any
  /// expense saved before the field existed.
  String? get paidByParticipantId {
    if (this is Expense) {
      return (this as Expense).paidByParticipantId;
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

  /// The display label for this transaction's category.
  ///
  /// Resolves from the concrete subtype. [Expense] has an instance method of
  /// this name, which wins over this extension; [Income] is handled here.
  /// Deliberately does not read [effectiveCategoryName] — that delegates here,
  /// and going back the other way would recurse.
  String getCategoryName() {
    if (this is Expense) {
      return (this as Expense).getCategoryName();
    }
    final income = this as Income;
    return income.customCategoryName ??
        CategoryRegistry.metaForIncome(income.category).name;
  }

  ExpenseCategory? get expenseCategory {
    if (this is Expense) {
      return (this as Expense).category;
    }
    return null;
  }
}
