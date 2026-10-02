import 'package:flutter/material.dart';

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

  /// The offered colours, as packed ARGB.
  ///
  /// Ordered so neighbours are far apart in hue, which makes the grid read as a
  /// spread rather than as rows of a gradient.
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
}
