import 'package:flutter/material.dart';

import 'package:daily_companion/models/expense_category_meta.dart';
import 'package:daily_companion/models/custom_category.dart';

/// The icon vocabulary a user can give their own category.
///
/// THE SHAPE IS [PlaceIcons]' AND THAT IS THE POINT. A location stores an icon
/// KEY, a string, and the glyph is resolved through a catalogue. So a category
/// does too: the record carries a key, not a glyph, and a build that learns a new
/// icon can draw a record written before it existed.
///
/// WHY MONOCHROME GLYPHS AND NOT EMOJI. Every built-in category -- Food, Travel,
/// Entertainment, Gear -- is an `Icons.*_rounded` drawn in ONE colour, and the
/// whole set reads as one family because of it. A category screen that offered
/// full-colour emoji alongside them was not offering a different kind of choice,
/// it was offering a different visual language: a bright 🍎 next to a quiet
/// amber fork, and the grid stopped reading as part of the app. Emoji are also
/// drawn by the platform's own font, so they are not this app's to recolour, and
/// several of them are brand marks -- a red apple for "fruit" is a logo, not a
/// category.
///
/// Keys are STABLE STRINGS. A key that is renamed stops resolving, so append to
/// the map and never repurpose one.
class CategoryIcons {
  CategoryIcons._();

  static const Map<String, IconData> catalogue = {
    // Food and drink
    'restaurant': Icons.restaurant_rounded,
    'cafe': Icons.local_cafe_rounded,
    'bar': Icons.local_bar_rounded,
    'pizza': Icons.local_pizza_rounded,
    'bakery': Icons.bakery_dining_rounded,
    'icecream': Icons.icecream_rounded,
    'meal': Icons.set_meal_rounded,
    'lunch': Icons.lunch_dining_rounded,
    'dinner': Icons.dinner_dining_rounded,
    'noodles': Icons.ramen_dining_rounded,
    'drink': Icons.local_drink_rounded,
    'nightlife': Icons.nightlife_rounded,
    'kitchen': Icons.kitchen_rounded,
    'table': Icons.table_restaurant_rounded,

    // Home
    'home': Icons.home_rounded,
    'cottage': Icons.cottage_rounded,
    'flat': Icons.apartment_rounded,
    'sofa': Icons.weekend_rounded,
    'bed': Icons.bed_rounded,
    'chair': Icons.chair_rounded,
    'light': Icons.light_rounded,
    'cleaning': Icons.cleaning_services_rounded,
    'garden': Icons.yard_rounded,
    'deck': Icons.deck_rounded,
    'repair': Icons.handyman_rounded,

    // Getting around
    'car': Icons.directions_car_rounded,
    'electric_car': Icons.electric_car_rounded,
    'taxi': Icons.local_taxi_rounded,
    'bus': Icons.directions_bus_rounded,
    'train': Icons.train_rounded,
    'flight': Icons.flight_rounded,
    'bike': Icons.directions_bike_rounded,
    'walk': Icons.directions_walk_rounded,
    'boat': Icons.directions_boat_rounded,
    'motorbike': Icons.two_wheeler_rounded,
    'tram': Icons.tram_rounded,
    'parking': Icons.local_parking_rounded,

    // Shopping and money
    'shop': Icons.shopping_bag_rounded,
    'store': Icons.storefront_rounded,
    'mall': Icons.local_mall_rounded,
    'market': Icons.store_rounded,
    'cart': Icons.shopping_cart_rounded,
    'offer': Icons.local_offer_rounded,
    'redeem': Icons.redeem_rounded,
    'payment': Icons.payment_rounded,
    'card': Icons.credit_card_rounded,
    'wallet': Icons.account_balance_wallet_rounded,
    'bank': Icons.account_balance_rounded,
    'savings': Icons.savings_rounded,
    'exchange': Icons.currency_exchange_rounded,
    'price_change': Icons.price_change_rounded,
    'receipt': Icons.receipt_long_rounded,
    'score': Icons.credit_score_rounded,

    // Health
    'hospital': Icons.local_hospital_rounded,
    'medicine': Icons.medication_rounded,
    'pharmacy': Icons.health_and_safety_rounded,
    'dentist': Icons.medical_services_rounded,
    'heart': Icons.favorite_rounded,
    'monitor': Icons.monitor_heart_rounded,
    'fitness': Icons.fitness_center_rounded,
    'gym': Icons.sports_gymnastics_rounded,
    'sport': Icons.sports_rounded,
    'wellbeing': Icons.self_improvement_rounded,
    'mind': Icons.psychology_rounded,
    'spa': Icons.spa_rounded,

    // Fun
    'movie': Icons.movie_rounded,
    'comedy': Icons.theater_comedy_rounded,
    'music': Icons.music_note_rounded,
    'concert': Icons.music_video_rounded,
    'podcast': Icons.mic_rounded,
    'game': Icons.videogame_asset_rounded,
    'gaming': Icons.sports_esports_rounded,
    'casino': Icons.casino_rounded,
    'football': Icons.sports_soccer_rounded,
    'basketball': Icons.sports_basketball_rounded,
    'tennis': Icons.sports_tennis_rounded,
    'book': Icons.auto_stories_rounded,
    'art': Icons.palette_rounded,
    'camera': Icons.photo_camera_rounded,

    // Learning and work
    'work': Icons.work_rounded,
    'laptop': Icons.laptop_rounded,
    'school': Icons.school_rounded,
    'study': Icons.menu_book_rounded,
    'history': Icons.history_edu_rounded,
    'document': Icons.description_rounded,
    'design': Icons.design_services_rounded,
    'architecture': Icons.architecture_rounded,
    'engineering': Icons.engineering_rounded,
    'translate': Icons.translate_rounded,
    'calculate': Icons.calculate_rounded,
    'fact_check': Icons.fact_check_rounded,

    // Tech
    'phone': Icons.phone_iphone_rounded,
    'computer': Icons.computer_rounded,
    'devices': Icons.devices_rounded,
    'headphones': Icons.headphones_rounded,
    'wifi': Icons.wifi_rounded,
    'battery': Icons.battery_charging_full_rounded,
    'storage': Icons.storage_rounded,
    'memory': Icons.memory_rounded,
    'watch': Icons.watch_rounded,
    'tv': Icons.tv_rounded,

    // Nature and weather
    'park': Icons.park_rounded,
    'forest': Icons.forest_rounded,
    'mountain': Icons.terrain_rounded,
    'water': Icons.water_rounded,
    'water_drop': Icons.water_drop_rounded,
    'beach': Icons.beach_access_rounded,
    'flower': Icons.local_florist_rounded,
    'pet': Icons.pets_rounded,
    'sun': Icons.wb_sunny_rounded,
    'storm': Icons.thunderstorm_rounded,
    'temperature': Icons.thermostat_rounded,
    'ac': Icons.ac_unit_rounded,
    'eco': Icons.eco_rounded,

    // General
    'place': Icons.place_rounded,
    'star': Icons.star_rounded,
    'flag': Icons.flag_rounded,
    'label': Icons.label_rounded,
    'tag': Icons.sell_rounded,
    'bookmark': Icons.bookmark_rounded,
    'loyalty': Icons.loyalty_rounded,
    'pushpin': Icons.push_pin_rounded,
    'more': Icons.more_horiz_rounded,
    'auto_awesome': Icons.auto_awesome_rounded,
  };

  /// The catalogue arranged into the groups the picker shows.
  ///
  /// An unordered list of ninety glyphs is a wall. Grouped, it is a menu someone
  /// can read: you are looking for something to do with money, and "Payment" is
  /// findable in a way that a flat grid of ninety is not.
  static const Map<String, List<String>> groups = {
    'Food and drink': [
      'restaurant',
      'cafe',
      'bar',
      'pizza',
      'bakery',
      'icecream',
      'meal',
      'lunch',
      'dinner',
      'noodles',
      'drink',
      'nightlife',
      'kitchen',
      'table',
    ],
    'Home': [
      'home',
      'cottage',
      'flat',
      'sofa',
      'bed',
      'chair',
      'light',
      'cleaning',
      'garden',
      'deck',
      'repair',
    ],
    'Getting around': [
      'car',
      'electric_car',
      'taxi',
      'bus',
      'train',
      'flight',
      'bike',
      'walk',
      'boat',
      'motorbike',
      'tram',
      'parking',
    ],
    'Shopping and money': [
      'shop',
      'store',
      'mall',
      'market',
      'cart',
      'offer',
      'redeem',
      'payment',
      'card',
      'wallet',
      'bank',
      'savings',
      'exchange',
      'price_change',
      'receipt',
      'score',
    ],
    'Health': [
      'hospital',
      'medicine',
      'pharmacy',
      'dentist',
      'heart',
      'monitor',
      'fitness',
      'gym',
      'sport',
      'wellbeing',
      'mind',
      'spa',
    ],
    'Fun': [
      'movie',
      'comedy',
      'music',
      'concert',
      'podcast',
      'game',
      'gaming',
      'casino',
      'football',
      'basketball',
      'tennis',
      'book',
      'art',
      'camera',
    ],
    'Learning and work': [
      'work',
      'laptop',
      'school',
      'study',
      'history',
      'document',
      'design',
      'architecture',
      'engineering',
      'translate',
      'calculate',
      'fact_check',
    ],
    'Tech': [
      'phone',
      'computer',
      'devices',
      'headphones',
      'wifi',
      'battery',
      'storage',
      'memory',
      'watch',
      'tv',
    ],
    'Nature and weather': [
      'park',
      'forest',
      'mountain',
      'water',
      'water_drop',
      'beach',
      'flower',
      'pet',
      'sun',
      'storm',
      'temperature',
      'ac',
      'eco',
    ],
    'General': [
      'place',
      'star',
      'flag',
      'label',
      'tag',
      'bookmark',
      'loyalty',
      'pushpin',
      'more',
      'auto_awesome',
    ],
  };

  /// The glyph for [key], or the generic sparkle.
  ///
  /// Never null and never throwing, for the same reason [PlaceIcons.resolve] is
  /// not: every record written before a key existed, and every key this build
  /// does not know, has to draw SOMETHING.
  static IconData resolve(String? key) {
    if (key == null) return Icons.auto_awesome_rounded;
    return catalogue[key] ?? Icons.auto_awesome_rounded;
  }

  /// Whether [key] is one this build knows.
  ///
  /// Separate from [resolve] because "draw a fallback" and "this is a valid
  /// choice" are different questions, and a test asserting the picker only
  /// offers real keys needs the second one.
  static bool isKnown(String? key) => key != null && catalogue.containsKey(key);

  /// The key a category with no icon of its own gets.
  static const String defaultKey = 'auto_awesome';

  /// Every key, in GROUP order, so the picker and a test agree on the order.
  static List<String> get keys => [for (final group in groups.values) ...group];

  /// The group [key] is filed under, for a label a person can read.
  ///
  /// The device showed "Icon cafe" under the picker, which is a key from the
  /// catalogue rather than anything the user chose or would recognise -- the
  /// colour row beside it said "orange" and read perfectly well. The group is
  /// already on screen as a heading, so it is the one description of the choice
  /// that is both true and understandable without a new table of names.
  static String? groupOf(String? key) {
    if (key == null) return null;
    for (final entry in groups.entries) {
      if (entry.value.contains(key)) return entry.key;
    }
    return null;
  }
}

/// The colours a user can give their own category.
///
/// A SPREAD OF HUES, NOT A RAMP OF ONE. A ramp is what a scale needs -- five
/// steps of the same red so "more spending" reads as "more red" -- and it is
/// exactly wrong for a picker: eight steps of one orange are eight categories a
/// person cannot tell apart in a legend, which is the one job a category colour
/// has.
///
/// Every entry is DISTINCT. A palette that lists the same hex twice offers the
/// user two buttons that do the same thing, and there is no way for them to tell
/// which is which. `category_icons_test.dart` asserts uniqueness, because a
/// duplicate is invisible in review and maddening in use.
///
/// These are the colours AS AUTHORED. What is drawn is resolved per surface by
/// [AppCategoryColour], so a palette that is legible on cream is legible on
/// Gruvbox's card too without the picker knowing anything about themes.
class CategoryColours {
  CategoryColours._();

  /// The hand-picked palette, as packed ARGB.
  ///
  /// Ordered so neighbours are far apart in hue, which makes the grid read as a
  /// spread rather than as rows of a gradient.
  ///
  /// NOT, on its own, the set the picker offers. [availableFor] draws from this
  /// plus every built-in category colour; offering only these meant the
  /// withholding it does could never remove anything.
  static const List<int> swatches = [
    0xFFD8A657, // amber -- Gruvbox yellow, and the app's own accent
    0xFF7DAEA3, // teal
    0xFFEA6962, // red
    0xFF89B482, // green
    0xFF6C9BC7, // blue
    0xFFD3869B, // pink
    0xFFDE741D, // orange
    0xFFA9B665, // olive
    0xFFC8553D, // brick
    0xFF9C8B7A, // taupe
    0xFFB0A090, // stone
    0xFF5E8C7E, // pine
    0xFFA36BA8, // orchid
    0xFFC08A5E, // clay
    0xFF7A6A9E, // mauve -- the generic custom colour, offered explicitly
    0xFF4F8A8B, // lagoon
    0xFFB5763F, // bronze
    0xFF8A9A5B, // moss
    0xFFBE6B62, // coral
    0xFF5F7FA8, // steel
    0xFFD2A24C, // honey
    0xFF7C6F64, // bark -- Gruvbox dark_foreground
    0xFF6B8E4E, // fern
    0xFFA05A7A, // plum
  ];

  /// The colours still available for a NEW category of [kind].
  ///
  /// Two colours are withheld, and both for the same reason: a category is
  /// identified by its colour on a chart, in a legend and in a list, so two
  /// categories sharing one is two things a person cannot tell apart.
  ///
  ///  - Anything already used by a BUILT-IN category of this kind. The nine
  ///    expense categories ship with their own colours, and offering the same
  ///    shade for a custom one put "Coffee" and "Food" in the same colour on the
  ///    same donut.
  ///  - Anything already used by another CUSTOM category OF THIS KIND. Income
  ///    and expense are separate charts, so the same colour on both sides is
  ///    harmless and is deliberately allowed -- someone may genuinely have a
  ///    "Refund" on each, and forcing them apart would be inventing a rule the
  ///    user did not ask for.
  ///
  /// THE POOL IS [swatches] PLUS EVERY BUILT-IN COLOUR, ON BOTH SIDES.
  ///
  /// It used to be [swatches] alone, and the built-in colours have zero
  /// intersection with that list. So `used` was assembled out of values the
  /// pool could never contain, the filter removed nothing, and the income and
  /// expense colour grids came out pixel-identical while the Kind control above
  /// them changed — the per-kind rule existed, was documented, and was
  /// unreachable. Withholding has to be able to withhold something, which means
  /// the things being withheld have to be on offer in the first place.
  ///
  /// An income colour is therefore offered on the expense side and vice versa.
  /// They are never in the same chart, and that is exactly the distinction the
  /// second bullet is making. Cross-kind LISTS are where that trade shows:
  /// transaction search, a CSV export and a place's breakdown put both kinds
  /// in one row of results, so an expense custom can sit there wearing the
  /// hue that labels Salary. It was accepted because every row states its own
  /// kind in words and the two never share a chart — withholding the other
  /// side's hues would break the sharing the bullet above deliberately allows.
  ///
  /// ORDERED, and the order is part of the contract: the hand-picked [swatches]
  /// come first and the opposite kind's built-in hues last, so the first
  /// colour offered in a cross-kind list is never one that already belongs to
  /// a built-in category somewhere else on the screen.
  ///
  /// Editing an existing category keeps its current colour available, otherwise
  /// opening it and saving would silently move it to a different colour.
  ///
  /// De-duplicated, in that order: a value that is both a swatch and a
  /// built-in is one colour, not the same colour twice.
  static List<int> availableFor({
    required CategoryKind kind,
    Iterable<CustomCategory> existing = const [],
    int? keepColour,
  }) {
    final builtIns = <int>{
      for (final meta in CategoryRegistry.expenseCategories())
        meta.color.toARGB32(),
      for (final meta in CategoryRegistry.incomeCategories())
        meta.color.toARGB32(),
    };

    final used = <int>{
      for (final meta
          in kind == CategoryKind.income
              ? CategoryRegistry.incomeCategories()
              : CategoryRegistry.expenseCategories())
        meta.color.toARGB32(),
      for (final category in existing)
        if (category.kind == kind && category.colorValue != null)
          category.colorValue!,
    };
    // `keepColour` is the category being edited; its own colour must not be
    // filtered out from under it.
    if (keepColour != null) used.remove(keepColour);

    final available = <int>[];
    void offer(int value) {
      if (used.contains(value) || available.contains(value)) return;
      available.add(value);
    }

    // Swatches FIRST, built-ins last — hand-picked, then the hues that already
    // label a built-in of the opposite kind. Written as two passes rather than
    // inherited from a set literal's insertion order, so the cross-kind lists
    // above cannot lose the ordering to an edit that never mentions it.
    for (final swatch in swatches) {
      offer(swatch);
    }
    for (final hue in builtIns) {
      offer(hue);
    }
    return available;
  }

  /// What a colour is called, so it is identified by a word rather than by
  /// comparing it against a list of swatches.
  ///
  /// AUTHORED, NOT DERIVED. The hue-bucket logic this replaces split the circle
  /// into nine bands and had thirty-nine colours to put in them: eleven came
  /// out as "orange", seven as "green", five as "red" — and the swatch this
  /// palette calls amber was LABELLED "orange", because a bucket only knows the
  /// bucket. A name is a vocabulary, so it is written down like one.
  ///
  /// Covers every colour [availableFor] can offer: [swatches] and both sides'
  /// built-ins. Built-ins are named for how they look rather than after the
  /// category they belong to, so a legend does not turn into a second list of
  /// category names that then have to be told apart from the real one.
  ///
  /// Anything else — a colour written by an older build — falls back to naming
  /// its hue. Same inaccuracy as before, but it is still something to read.
  static String nameOf(int value) {
    final authored = _names[value];
    if (authored != null) return authored;
    return _hueName(value);
  }

  /// How many colours the vocabulary names outright.
  ///
  /// Asserted against the size of the offered palette, because the two are
  /// meant to be the same set: a built-in colour added without a name would
  /// quietly fall through to the hue buckets, which is the bug this replaced.
  static int get namedColourCount => _names.length;

  /// Colour -> its name, in the order they are offered.
  static const Map<int, String> _names = {
    // The swatches, in [swatches] order. These are the palette's own names and
    // they are what a legend, a screen reader and the row under the grid all
    // say out loud.
    0xFFD8A657: 'amber',
    0xFF7DAEA3: 'teal',
    0xFFEA6962: 'red',
    0xFF89B482: 'green',
    0xFF6C9BC7: 'blue',
    0xFFD3869B: 'pink',
    0xFFDE741D: 'orange',
    0xFFA9B665: 'olive',
    0xFFC8553D: 'brick',
    0xFF9C8B7A: 'taupe',
    0xFFB0A090: 'stone',
    0xFF5E8C7E: 'pine',
    0xFFA36BA8: 'orchid',
    0xFFC08A5E: 'clay',
    0xFF7A6A9E: 'mauve',
    0xFF4F8A8B: 'lagoon',
    0xFFB5763F: 'bronze',
    0xFF8A9A5B: 'moss',
    0xFFBE6B62: 'coral',
    0xFF5F7FA8: 'steel',
    0xFFD2A24C: 'honey',
    0xFF7C6F64: 'bark',
    0xFF6B8E4E: 'fern',
    0xFFA05A7A: 'plum',
    // The built-ins, both sides. None of these answers to a swatch's name, so
    // the two vocabularies do not collide once they share a grid.
    0xFFA6712B: 'ochre', // Food
    0xFF826654: 'mocha', // Travel
    0xFF7A5C8E: 'violet', // Entertainment
    0xFF478F55: 'clover', // Gear
    0xFF7A8256: 'sage', // Housing
    0xFFA6637A: 'rosewood', // Shopping
    0xFFA63D3D: 'crimson', // Health
    0xFF5E8C7B: 'jade', // Utilities
    0xFF9E8B6E: 'sand', // Other
    0xFF7E5A2E: 'walnut', // Salary
    0xFF4E7A52: 'laurel', // Freelance
    0xFF2F6E7E: 'petrol', // Investment
    0xFFC9A227: 'gold', // Bonus
    0xFFB5495B: 'rose', // Gift
    0xFF6C7E8C: 'slate', // Other Income
  };

  /// The fallback for a colour outside [_names]: its hue, plus a lightness
  /// qualifier where the lightness is extreme enough to be worth saying.
  static String _hueName(int value) {
    final hsl = HSLColor.fromColor(Color(value));
    final hue = hsl.hue;
    final light = hsl.lightness;
    final tone = light < 0.35
        ? 'dark'
        : light > 0.72
        ? 'pale'
        : '';
    String name;
    if (hue < 15 || hue >= 345) {
      name = 'red';
    } else if (hue < 40) {
      name = 'orange';
    } else if (hue < 70) {
      name = 'amber';
    } else if (hue < 160) {
      name = 'green';
    } else if (hue < 200) {
      name = 'teal';
    } else if (hue < 255) {
      name = 'blue';
    } else if (hue < 290) {
      name = 'purple';
    } else if (hue < 330) {
      name = 'pink';
    } else {
      name = 'rose';
    }
    return tone.isEmpty ? name : '$tone $name';
  }
}
