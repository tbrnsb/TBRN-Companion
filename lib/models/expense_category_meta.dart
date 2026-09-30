import 'package:flutter/material.dart';

/// Expense categories.
///
/// MIGRATION SAFETY: a transaction stores its category by *name*
/// (`category.toString().split('.').last`), never by index, so adding a value
/// here cannot change what any existing record means. Records naming a
/// category this build no longer knows still load as `other` via the
/// `firstWhere(orElse:)` in [Expense.fromJson]. Values must only ever be
/// appended or renamed together with a migration; reordering them is harmless
/// because nothing reads an index.
enum ExpenseCategory {
  food,
  travel,
  gear,
  entertainment,
  housing,
  shopping,
  health,
  utilities,
  other,
}

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

/// One slice of a category breakdown: a resolved category plus the total
/// recorded against it.
///
/// Lives in the model layer so a provider can build a breakdown without
/// depending on a widget type. [meta] is the real category the user sees, so
/// two `ExpenseCategory.other` rows with different custom names become two
/// distinct slices rather than one anonymous bucket.
class CategorySlice {
  const CategorySlice({required this.meta, required this.amount});

  final CategoryMeta meta;
  final double amount;
}

class CategoryRegistry {
  CategoryRegistry._();

  static const List<CategoryMeta> _expenseMetas = [
    // Nine categories, ordered by how often they are expected to be used, with
    // `other` last because it is the one that leads somewhere else.
    //
    // Colours have to stay distinguishable from each other: the breakdown donut
    // puts slices of these side by side and two similar browns next to each
    // other are unreadable. design_system_test.dart asserts a minimum
    // separation between every pair.
    //
    // They also have to be VISIBLE. A category colour is drawn as an icon tint
    // and as a legend swatch, on a cream page in light mode and a near-black one
    // in dark mode, and it has to clear 3:1 against BOTH. Nine of the original
    // twenty-one did not, and the worst was Travel at 1.78 on near-black — the
    // carafe brown, which is the same value as the page background family, so on
    // a dark screen the Travel slice was very nearly invisible.
    //
    // Getting there is mostly a lightness move. Hue is what makes a category
    // recognisable, so every colour below keeps its hue to within two degrees
    // and its saturation exactly; 15 of the 28 in this file are unchanged. The
    // one real casualty is Travel, which has to roughly triple in luminance to
    // clear near-black: a colour that dark cannot be visible on a background
    // that dark, whatever its hue. It is still a warm brown.
    CategoryMeta(
      id: 'food',
      name: 'Food',
      icon: Icons.restaurant_rounded,
      color: Color(0xFFA6712B),
      popularity: 0,
    ),
    CategoryMeta(
      id: 'travel',
      name: 'Travel',
      icon: Icons.directions_car_rounded,
      color: Color(0xFF826654),
      popularity: 1,
    ),
    CategoryMeta(
      id: 'entertainment',
      name: 'Entertainment',
      icon: Icons.movie_rounded,
      color: Color(0xFF7A5C8E),
      popularity: 2,
    ),
    CategoryMeta(
      id: 'gear',
      name: 'Gear',
      icon: Icons.backpack_rounded,
      color: Color(0xFF5C7A52),
      popularity: 3,
    ),
    CategoryMeta(
      id: 'housing',
      name: 'Housing',
      icon: Icons.home_rounded,
      color: Color(0xFF7A8256),
      popularity: 4,
    ),
    CategoryMeta(
      id: 'shopping',
      name: 'Shopping',
      icon: Icons.shopping_bag_rounded,
      color: Color(0xFFA6637A),
      popularity: 5,
    ),
    CategoryMeta(
      id: 'health',
      name: 'Health',
      icon: Icons.favorite_rounded,
      color: Color(0xFFBA6B3B),
      popularity: 6,
    ),
    CategoryMeta(
      id: 'utilities',
      name: 'Utilities',
      icon: Icons.bolt_rounded,
      color: Color(0xFF6E7F80),
      popularity: 7,
    ),
    CategoryMeta(
      id: 'other',
      name: 'Other',
      icon: Icons.payments_rounded,
      color: Color(0xFF967A64),
      popularity: 8,
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
      color: Color(0xFF6A866A),
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
      color: Color(0xFF9B794B),
      popularity: 3,
    ),
    CategoryMeta(
      id: 'gift',
      name: 'Gift',
      icon: Icons.volunteer_activism_rounded,
      color: Color(0xFF987962),
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

  /// Types offered from the "Other" screen that are deliberately NOT among the
  /// main nine.
  ///
  /// These are not `ExpenseCategory` values on purpose. A transaction stores
  /// its category by name, so adding enum values would mean every one of these
  /// needed a slot in `_expenseMetas` — which would push them into the
  /// add-expense chip row and into the nine-way breakdown, quietly redefining
  /// what "the main categories" means. Choosing one of these files the expense
  /// as `ExpenseCategory.other` with `customName` set, which is exactly what
  /// the storage already handles for a hand-typed name.
  ///
  /// The user asked for these specifically after the Other screen offered the
  /// main nine a second time instead of anything new.
  static const List<CategoryMeta> _suggestedExpenseMetas = [
    CategoryMeta(
      id: 'suggested:fruits',
      name: 'Fruits',
      icon: Icons.apple_rounded,
      color: Color(0xFFC2410C),
      popularity: 20,
    ),
    CategoryMeta(
      id: 'suggested:vegetables',
      name: 'Vegetables',
      icon: Icons.eco_rounded,
      color: Color(0xFF3F7D20),
      popularity: 21,
    ),
    CategoryMeta(
      id: 'suggested:snacks',
      name: 'Snacks',
      icon: Icons.cookie_rounded,
      color: Color(0xFFBA1859),
      popularity: 22,
    ),
    CategoryMeta(
      id: 'suggested:coffee',
      name: 'Coffee',
      icon: Icons.coffee_rounded,
      color: Color(0xFF7D593F),
      popularity: 23,
    ),
    CategoryMeta(
      id: 'suggested:electronics',
      name: 'Electronics',
      icon: Icons.memory_rounded,
      color: Color(0xFF1E53E1),
      popularity: 24,
    ),
    CategoryMeta(
      id: 'suggested:phone',
      name: 'Phone & Internet',
      icon: Icons.smartphone_rounded,
      color: Color(0xFF0E7490),
      popularity: 25,
    ),
    CategoryMeta(
      id: 'suggested:sports',
      name: 'Sports',
      icon: Icons.sports_cricket_rounded,
      color: Color(0xFF15803D),
      popularity: 26,
    ),
    CategoryMeta(
      id: 'suggested:kids',
      name: 'Kids',
      icon: Icons.child_care_rounded,
      color: Color(0xFFB45309),
      popularity: 27,
    ),
    CategoryMeta(
      id: 'suggested:personal care',
      name: 'Personal Care',
      icon: Icons.content_cut_rounded,
      color: Color(0xFFA41CB0),
      popularity: 28,
    ),
    CategoryMeta(
      id: 'suggested:books',
      name: 'Books & Study',
      icon: Icons.menu_book_rounded,
      color: Color(0xFF574DD0),
      popularity: 29,
    ),
    CategoryMeta(
      id: 'suggested:pets',
      name: 'Pets',
      icon: Icons.pets_rounded,
      color: Color(0xFFA64017),
      popularity: 30,
    ),
    CategoryMeta(
      id: 'suggested:gifts',
      name: 'Gifts',
      icon: Icons.card_giftcard_rounded,
      // Violet rather than the obvious blue: blue put it 139 from "Phone &
      // Internet", under the 150 the separation check requires. design_system_test
      // covers the suggested types alongside the main nine for this reason.
      color: Color(0xFF7C3AED),
      popularity: 31,
    ),
  ];

  /// The suggested types, in the order they are offered.
  static List<CategoryMeta> suggestedExpenseTypes() =>
      List.unmodifiable(_suggestedExpenseMetas);

  /// The suggested type called [name], or null if it is not one of them.
  ///
  /// Matched on the id rather than the display name so a rename cannot silently
  /// orphan an expense that was filed under the old label.
  static CategoryMeta? suggestedForName(String? name) {
    if (name == null) return null;
    final wanted = name.trim().toLowerCase();
    if (wanted.isEmpty) return null;
    for (final meta in _suggestedExpenseMetas) {
      if (meta.id.substring('suggested:'.length) == wanted) return meta;
    }
    return null;
  }

  static CategoryMeta metaFor(ExpenseCategory category, {String? customName}) {
    if (category == ExpenseCategory.other &&
        customName != null &&
        customName.isNotEmpty) {
      // A suggested type keeps its own icon and colour instead of collapsing to
      // the generic "Custom" sparkle, so "Fruits" reads as fruit in the
      // breakdown donut and on the detail screen, not as an unnamed other.
      final suggested = suggestedForName(customName);
      if (suggested != null) return suggested;
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
