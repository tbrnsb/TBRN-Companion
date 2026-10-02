import 'package:flutter/material.dart';

import 'custom_category.dart';

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
      // Red rather than the orange-brown it was: `food` is the amber in this
      // set and the two were inside the separation threshold of each other while
      // sharing a donut slice boundary.
      color: Color(0xFFA63D3D),
      popularity: 6,
    ),
    CategoryMeta(
      id: 'utilities',
      name: 'Utilities',
      icon: Icons.bolt_rounded,
      // Cooler and bluer than `other`'s warm brown. The two were 4 units apart in
      // the weighted metric and they share a donut slice boundary, so which is
      // which was a guess. Fixed the COLOUR, not the threshold.
      color: Color(0xFF5E8C7B),
      popularity: 7,
    ),
    CategoryMeta(
      id: 'other',
      name: 'Other',
      icon: Icons.payments_rounded,
      // A warm tan. It is the catch-all and must not look like a category, but
      // it still has to carry real chroma: a near-neutral grey fails the palette's
      // own saturation floor, and a desaturated colour is one a phone cannot
      // tell from the surface.
      color: Color(0xFF9E8B6E),
      popularity: 8,
    ),
  ];

  static const List<CategoryMeta> _incomeMetas = [
    CategoryMeta(
      id: 'salary',
      name: 'Salary',
      icon: Icons.work_rounded,
      color: Color(0xFF7E5A2E),
      popularity: 0,
    ),
    CategoryMeta(
      id: 'freelance',
      name: 'Freelance',
      icon: Icons.handshake_rounded,
      color: Color(0xFF4E7A52),
      popularity: 1,
    ),
    CategoryMeta(
      id: 'investment',
      name: 'Investment',
      icon: Icons.trending_up_rounded,
      // Greener than the slate it was. Investment and `other` measured inside the
      // threshold of each other on the cream page, and they share the income
      // donut; the hue moved rather than the threshold.
      color: Color(0xFF2F6E7E),
      popularity: 2,
    ),
    CategoryMeta(
      id: 'bonus',
      name: 'Bonus',
      icon: Icons.emoji_events_rounded,
      // Gold rather than the brown it was: bonus, gift and custom were three
      // near-identical browns inside one donut, which is a legend that cannot be
      // read. Hue is what makes a category recognisable, so the hue moved.
      color: Color(0xFFC9A227),
      popularity: 3,
    ),
    CategoryMeta(
      id: 'gift',
      name: 'Gift',
      icon: Icons.volunteer_activism_rounded,
      color: Color(0xFFB5495B),
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

  /// The categories the user has added, by id.
  ///
  /// HELD HERE, not asked for, because the registry is static and
  /// [CategoryRegistry.metaFor] / [metaById] are called from a dozen places --
  /// a breakdown slice, a budget row, a transaction tile, an export -- that have
  /// no way to reach storage and must not each go and read a box. Loaded once at
  /// startup and again after any change, the same way `_expenseMetas` is a
  /// constant.
  ///
  /// A record that is not here resolves to the generic custom appearance, which
  /// is what a category created before icons and colours existed should look
  /// like.
  static Map<String, CustomCategory> _customById = const {};

  /// Replaces the held records. Called by the app once storage has been read.
  static void setCustomCategories(Iterable<CustomCategory> categories) {
    _customById = {for (final c in categories) c.id: c};
  }

  /// The record for [id], or null when the user has not added it.
  static CustomCategory? customById(String id) => _customById[id];

  /// Every category the user has added, in the order they were given.
  static List<CustomCategory> get customCategories =>
      List.unmodifiable(_customById.values);

  /// The meta a custom category is drawn with, honouring the user's own colour
  /// and icon when they have chosen them.
  static CategoryMeta metaForCustom(CustomCategory custom) => CategoryMeta(
    id: custom.id,
    name: custom.name,
    icon: custom.icon,
    color: custom.resolvedColor,
    popularity: _customMeta.popularity,
  );

  static const CategoryMeta _customMeta = CategoryMeta(
    id: 'custom',
    name: 'Custom',
    icon: Icons.auto_awesome_rounded,
    // Deliberately mauve rather than another brown: a hand-typed category is the
    // catch-all, and if it looks like a built-in the user cannot tell which slice
    // of the donut it is.
    color: Color(0xFF7A6A9E),
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
      // A roasted brown that is DARKER and redder than `travel`'s grey-brown.
      // They measured inside the separation threshold of each other while sharing
      // a donut, so which slice was which was a guess.
      color: Color(0xFF6B3F2A),
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
      // Olive rather than the amber-brown it was: `fruits` is already the
      // red-orange in this set.
      color: Color(0xFF7D6B1F),
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
      // Blue rather than the violet it was: `gifts` is already the purple in this
      // set, and the separation check caught them sharing a donut.
      color: Color(0xFF2F6FB5),
      popularity: 29,
    ),
    CategoryMeta(
      id: 'suggested:pets',
      name: 'Pets',
      icon: Icons.pets_rounded,
      // Plum rather than the rust it was: `fruits` is already the red-orange in
      // this set and two rusts shared a donut.
      color: Color(0xFF8B3A62),
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
      // The user's OWN colour and icon when there are any, so a category they
      // gave an identity in Settings is recognisable everywhere it appears and
      // not just on the screen where they set it.
      final held = _customById['custom:${customName.toLowerCase()}'];
      if (held != null) return metaForCustom(held);
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

  /// The meta for a stored category id, or null when the id is not one the app
  /// knows.
  ///
  /// Needed because a custom category is PERSISTED as an id —
  /// `custom:coffee` — and a budget, a breakdown slice and a transaction all
  /// hold that string rather than an enum. Anything reading one back needs a
  /// lookup by id; without this, every reader had to hand-roll a `firstWhere`
  /// and fall back to a DIFFERENT category than the one that was stored, which
  /// is how a Coffee budget quietly became an Other one.
  ///
  /// Null rather than a fallback, because a caller showing a picker must be able
  /// to tell "no such category" from "this category".
  static CategoryMeta? metaById(String id) {
    for (final meta in _expenseMetas) {
      if (meta.id == id) return meta;
    }
    // `suggested:` as well as `custom:`. A custom category the user happened to
    // name after one the app suggests is stored under `suggested:<name>` so it
    // keeps that icon and colour, so a lookup that only understood `custom:`
    // resolved those to null — and a null is what a picker reads as "no such
    // category", so a Coffee budget became unselectable.
    final isCustom = id.startsWith('custom:');
    final isSuggested = id.startsWith('suggested:');
    if (isCustom || isSuggested) {
      final name = isSuggested
          ? id.substring('suggested:'.length)
          : id.substring('custom:'.length);
      if (name.isEmpty) return null;
      if (isSuggested) {
        for (final meta in _suggestedExpenseMetas) {
          if (meta.id == id) return meta;
        }
      }
      // A suggested type keeps its own icon and colour rather than collapsing to
      // the generic custom sparkle, exactly as [metaFor] does.
      final suggested = suggestedForName(name);
      if (suggested != null) return suggested;

      // AND THE RECORD THE USER ACTUALLY SAVED, if it is loaded.
      //
      // This is the difference between a chosen icon existing and a chosen icon
      // being seen. Everything that renders a category by its stored id -- a
      // transaction tile, a budget row, a breakdown segment -- comes through
      // here, and this branch used to hand every one of them the generic
      // sparkle. So the icon and the colour could be set in Settings, stored
      // correctly, survive a restart, and still not be drawn anywhere outside
      // the two screens that happened to hold the record. The name is the
      // stored one too, so a category the user has since RENAMED is drawn under
      // the new name rather than the id it was filed under.
      final stored = _customById[id];
      if (stored != null) return metaForCustom(stored);

      // No record loaded: the id is all there is, so a category named after one
      // the app suggests is recognisable and everything else is generic.
      return CategoryMeta(
        id: id,
        name: _titleCase(name),
        icon: _customMeta.icon,
        color: _customMeta.color,
        popularity: _customMeta.popularity,
      );
    }
    return null;
  }

  /// "coffee beans" -> "Coffee Beans", because a stored id is lower-cased and
  /// the label is what the user typed.
  static String _titleCase(String lower) => lower
      .split(RegExp(r'[\s_-]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

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

  /// The id of the bucket that leads somewhere else rather than naming a thing.
  static const String otherId = 'other';

  /// [items] in the order a person should choose from them: `other` LAST.
  ///
  /// THE ONE RULE, applied everywhere a list of categories is put in front of
  /// somebody, because the alternative is a rule per screen and one of them
  /// eventually forgets. `other` is not a category in the way Food is: tapping it
  /// opens another screen to name the real one, so sitting it between Housing
  /// and Travel puts a two-step action in the middle of a list of one-step ones
  /// and makes the list longer to scan for no reason.
  ///
  /// It cannot be left to the order the metas happen to be declared in, because
  /// the lists that reach the user are not the declared list: the expense picker
  /// re-sorts by popularity, the budget rows sort by label, and a custom
  /// category read back from storage arrives in whatever order the box gave it.
  /// Any of those can put `other` in the middle.
  ///
  /// STABLE. Everything else keeps the order it arrived in, so a screen that
  /// sorted deliberately has not had its sort undone -- only `other` has been
  /// moved, and it moves to the end rather than to a position of its own.
  static List<T> othersLast<T>(
    Iterable<T> items, {
    required bool Function(T) isOther,
  }) {
    final rest = <T>[];
    final others = <T>[];
    for (final item in items) {
      (isOther(item) ? others : rest).add(item);
    }
    return [...rest, ...others];
  }

  /// [CategoryMeta.othersLast] with the predicate already supplied.
  static List<CategoryMeta> metasOthersLast(Iterable<CategoryMeta> metas) =>
      othersLast(metas, isOther: (m) => m.id == otherId);
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
