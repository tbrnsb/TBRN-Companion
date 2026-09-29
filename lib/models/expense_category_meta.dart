import 'package:flutter/material.dart';

enum ExpenseCategory { food, travel, gear, entertainment, utilities, other }

enum IncomeCategory { salary, freelance, investment, bonus, gift, other }

class CategoryMeta {
  const CategoryMeta({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.popularity,
  });

  final String id;
  final String name;
  final IconData icon;
  final Color color;

  final int popularity;
}

class CategoryRegistry {
  CategoryRegistry._();

  static const List<CategoryMeta> _expenseMetas = [
    CategoryMeta(
      id: 'food',
      name: 'Food',
      icon: Icons.restaurant_rounded,
      color: Color(0xFFB07A2E),
      popularity: 0,
    ),
    CategoryMeta(
      id: 'travel',
      name: 'Travel',
      icon: Icons.directions_car_rounded,
      color: Color(0xFF4B392F),
      popularity: 1,
    ),
    CategoryMeta(
      id: 'gear',
      name: 'Gear',
      icon: Icons.backpack_rounded,
      color: Color(0xFF5C7A52),
      popularity: 4,
    ),
    CategoryMeta(
      id: 'entertainment',
      name: 'Entertainment',
      icon: Icons.movie_rounded,
      color: Color(0xFF7A5C8E),
      popularity: 3,
    ),
    CategoryMeta(
      id: 'utilities',
      name: 'Utilities',
      icon: Icons.bolt_rounded,
      color: Color(0xFF6E7F80),
      popularity: 5,
    ),
    CategoryMeta(
      id: 'other',
      name: 'Other',
      icon: Icons.payments_rounded,
      color: Color(0xFFA8907D),
      popularity: 6,
    ),
  ];

  static const List<CategoryMeta> _incomeMetas = [
    CategoryMeta(
      id: 'salary',
      name: 'Salary',
      icon: Icons.work_rounded,
      color: Color(0xFF8C6D3E),
      popularity: 0,
    ),
    CategoryMeta(
      id: 'freelance',
      name: 'Freelance',
      icon: Icons.handshake_rounded,
      color: Color(0xFF7A9A7A),
      popularity: 1,
    ),
    CategoryMeta(
      id: 'investment',
      name: 'Investment',
      icon: Icons.trending_up_rounded,
      color: Color(0xFF5C7A8C),
      popularity: 2,
    ),
    CategoryMeta(
      id: 'bonus',
      name: 'Bonus',
      icon: Icons.emoji_events_rounded,
      color: Color(0xFFB08C5A),
      popularity: 3,
    ),
    CategoryMeta(
      id: 'gift',
      name: 'Gift',
      icon: Icons.volunteer_activism_rounded,
      color: Color(0xFFA88C78),
      popularity: 4,
    ),
    CategoryMeta(
      id: 'other',
      name: 'Other Income',
      icon: Icons.attach_money_rounded,
      color: Color(0xFF6C7E8C),
      popularity: 5,
    ),
  ];

  static const CategoryMeta _customMeta = CategoryMeta(
    id: 'custom',
    name: 'Custom',
    icon: Icons.auto_awesome_rounded,
    color: Color(0xFF8A6F4D),
    popularity: 99,
  );

  static CategoryMeta metaFor(ExpenseCategory category, {String? customName}) {
    if (category == ExpenseCategory.other &&
        customName != null &&
        customName.isNotEmpty) {
      return CategoryMeta(
        id: 'custom:${customName.toLowerCase()}',
        name: customName,
        icon: _customMeta.icon,
        color: _customMeta.color,
        popularity: _customMeta.popularity,
      );
    }
    return _expenseMetas.firstWhere(
      (m) => m.id == category.name,
      orElse: () => _expenseMetas.last,
    );
  }

  static CategoryMeta metaForIncome(String categoryName) {
    return _incomeMetas.firstWhere(
      (m) => m.id == categoryName,
      orElse: () => _incomeMetas.last,
    );
  }

  static List<CategoryMeta> incomeCategories() =>
      List.unmodifiable(_incomeMetas);

  static List<CategoryMeta> expenseCategories() =>
      List.unmodifiable(_expenseMetas);
}

extension ExpenseCategoryX on ExpenseCategory {
  CategoryMeta get meta => CategoryRegistry.metaFor(this);
}

extension IncomeCategoryX on IncomeCategory {
  CategoryMeta get meta {
    switch (this) {
      case IncomeCategory.salary:
        return CategoryRegistry.metaForIncome('salary');
      case IncomeCategory.freelance:
        return CategoryRegistry.metaForIncome('freelance');
      case IncomeCategory.investment:
        return CategoryRegistry.metaForIncome('investment');
      case IncomeCategory.bonus:
        return CategoryRegistry.metaForIncome('bonus');
      case IncomeCategory.gift:
        return CategoryRegistry.metaForIncome('gift');
      case IncomeCategory.other:
        return CategoryRegistry.metaForIncome('other');
    }
  }
}
