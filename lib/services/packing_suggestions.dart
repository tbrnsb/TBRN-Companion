/// What to pack for a particular trip.
///
/// Reads the trip itself — where, when, how long — instead of a fixed list
/// matched on keywords. "Pokhara" used to fall through to a generic essentials
/// list because no keyword matched, so two completely different trips got the
/// same six suggestions and the card read as decoration.
///
/// Pure Dart, no Flutter import: it is a decision about names, and it should be
/// testable without a widget tree, a Hive box or a clock.
///
/// NO NETWORK. Every input is already on the phone. The README promises nothing
/// leaves the device and a suggestion engine that phoned a weather API to decide
/// whether you need a jacket would break that promise to save the user typing.
library;

/// One thing to pack, and why it is on the list.
///
/// The reason is not decoration. A bare "Water bottle" is a guess the user has to
/// evaluate; "Water bottle — three days out" tells them the app thought about
/// their trip, and it is the difference between a list and a recommendation.
class PackingSuggestion {
  const PackingSuggestion(this.name, this.reason);

  final String name;

  /// One short line. Never a sentence the user has to parse.
  final String reason;

  @override
  String toString() => '$name — $reason';
}

/// The kind of place a trip is going to, which drives most of the list.
enum TripKind { city, mountain, coast, forest, desert, lake, home }

/// A read of a trip: kind, length, and season. Three questions, three answers.
class TripProfile {
  const TripProfile({
    required this.kind,
    required this.nights,
    required this.month,
    required this.title,
  });

  final TripKind kind;

  /// Nights away, at least 1. A trip with no end date is treated as a weekend,
  /// which is the most common thing people mean when they do not say.
  final int nights;

  /// 1-12.
  final int month;

  /// The destination as written, for the reason lines.
  final String title;

  /// "3 nights", "a day trip", "a week or more".
  String get lengthLabel {
    if (nights <= 0) return 'a day trip';
    if (nights == 1) return 'one night';
    if (nights < 7) return '$nights nights';
    return 'a week or more';
  }

  /// Northern hemisphere months.
  ///
  /// The app has no location for a trip beyond its destination name, and asking
  /// for one to get a season right is a worse trade than being wrong half the
  /// year. Nepal is the common case and it is northern, so this is right for the
  /// app's actual user. Documented here because it is an assumption, not a fact.
  bool get isColdSeason => month == 12 || month <= 2;

  bool get isHotSeason => month >= 4 && month <= 9;

  bool get isMonsoon => month >= 6 && month <= 9;
}

/// The suggestion engine.
class PackingSuggestions {
  PackingSuggestions._();

  /// Maximum suggestions returned.
  ///
  /// A card with twenty chips is a wall. Eight is enough to be useful and short
  /// enough to scan; the rest live behind "Pack for this trip", which adds all
  /// of them.
  static const int limit = 8;

  /// Reads [destination], [startTime] and [endTime] into a [TripProfile].
  ///
  /// All three are nullable because all three can be missing on a half-made
  /// trip, and a suggestion list is never worth refusing to produce.
  static TripProfile profileFor({
    String? destination,
    DateTime? startTime,
    DateTime? endTime,
  }) {
    final now = DateTime.now();
    final start = startTime ?? now;

    var nights = 2;
    if (endTime != null) {
      final days = endTime.difference(start).inHours / 24;
      if (days.isFinite && days >= 0) {
        // A day trip is a real answer, not "under a day, call it one night".
        // An explicit end time that equals the start is a day trip, and
        // falling through to the default here would say "2 nights" about a trip
        // that finishes before dinner.
        nights = days >= 1 ? days.round() : 0;
      }
    }

    return TripProfile(
      kind: kindFor(destination),
      nights: nights < 0 ? 0 : nights,
      month: start.month,
      title: (destination ?? '').trim(),
    );
  }

  /// What kind of place [destination] names.
  ///
  /// Keyword matching, and that is the honest limit of it: with no network there
  /// is no gazetteer. The vocabulary is wide on purpose — a place name is
  /// whatever the user typed, and "Everest" has to land in the same bucket as
  /// "Annapurna" — and anything unrecognised becomes [TripKind.city], which is
  /// the right default for a trip and gets the shortest list.
  static TripKind kindFor(String? destination) {
    final d = (destination ?? '').toLowerCase();
    if (d.isEmpty) return TripKind.home;

    bool has(List<String> words) => words.any(d.contains);

    if (has([
      'everest',
      'annapurna',
      'mountain',
      'mount',
      'peak',
      'summit',
      'trek',
      'trail',
      'hike',
      'hiking',
      'alp',
      'glacier',
      'pass',
      'highlands',
      'himalaya',
      'sherpa',
    ])) {
      return TripKind.mountain;
    }
    if (has([
      'beach',
      'coast',
      'island',
      'islands',
      'sea',
      'ocean',
      'bay',
      'lagoon',
      'reef',
      'seaside',
      'harbour',
      'harbor',
      'river',
    ])) {
      return TripKind.coast;
    }
    if (has([
      'forest',
      'jungle',
      'rainforest',
      'woodland',
      'park',
      'national park',
      'wildlife',
      'safari',
      'amazon',
    ])) {
      return TripKind.forest;
    }
    if (has(['desert', 'dune', 'dunes', 'sahara', 'gobi', 'arid', 'oasis'])) {
      return TripKind.desert;
    }
    if (has([
      'lake',
      'pokhara',
      'phewa',
      'tilicho',
      'begnas',
      'gosaikunda',
      'reservoir',
      'lagoon',
      'loch',
    ])) {
      return TripKind.lake;
    }
    // "Staycation" and friends: nowhere to go, so nothing to pack for.
    if (has(['staycation', 'home', 'house', 'stay home'])) return TripKind.home;

    return TripKind.city;
  }

  /// The full suggestion list for [profile], already trimmed to [limit].
  ///
  /// Ordered by how certain the app is: things that follow from the trip being
  /// what it is, before things that follow from the season, before the
  /// duration-driven odds and ends.
  static List<PackingSuggestion> forProfile(TripProfile profile) {
    final out = <PackingSuggestion>[];

    void add(String name, String reason) {
      // Case-insensitive dedupe: a suggestion that restates something already
      // on the list is noise, and "Water bottle" appearing twice in a card of
      // eight is worse than not appearing.
      final exists = out.any((s) => s.name.toLowerCase() == name.toLowerCase());
      if (!exists) out.add(PackingSuggestion(name, reason));
    }

    // --- Certain: what the place is ---
    switch (profile.kind) {
      case TripKind.mountain:
        add('Warm layers', 'it gets cold up there, especially after dark');
        add(
          'Rain shell',
          profile.isMonsoon
              ? 'it rains most days this month'
              : 'weather turns fast above the treeline',
        );
        add('Water bottle', profile.lengthLabel);
        add('Sunscreen', 'the sun is stronger than you expect up there');
        add('First aid kit', 'the nearest clinic is not close');
        if (profile.nights >= 3) {
          add('Headlamp', 'you will be walking after dark');
        }
      case TripKind.coast:
        add('Swimwear', 'you are going to be in the water');
        add(
          'Reef-safe sunscreen',
          profile.isHotSeason
              ? 'high UV this month'
              : 'still strong on the water',
        );
        add('Sandals', 'sand is easier than shoes');
        add('Water bottle', profile.lengthLabel);
        add('Dry bag', 'phones and cameras do not like salt spray');
        if (profile.nights >= 4) {
          add('Snorkel mask', 'worth having if the water is clear');
        }
      case TripKind.forest:
        add(
          'Insect repellent',
          profile.isMonsoon
              ? 'the wet season is when the mosquitoes are'
              : 'essential in forest',
        );
        add('Quick-dry clothes', 'humid, and nothing dries overnight');
        add('Water bottle', profile.lengthLabel);
        add('First aid kit', 'scratches and bites are likely');
        add('Binoculars', 'for the early start most wildlife needs');
      case TripKind.desert:
        add('Sunscreen', 'the sun here is not negotiable');
        add(
          'Warm layers',
          profile.isColdSeason
              ? 'nights get genuinely cold in the desert'
              : 'the temperature swing from day to night is the thing',
        );
        add('Water bottle', 'you are carrying most of your water');
        add('Head covering', 'sun on the neck and shoulders burns fastest');
        add('Lip balm with SPF', 'drier than you think');
      case TripKind.lake:
        add('Water bottle', profile.lengthLabel);
        add('Sun hat', 'you will be out on the water all day');
        add(
          'Light jacket',
          profile.isColdSeason || profile.isMonsoon
              ? 'it turns cool by evening'
              : 'for the boat ride in the evening',
        );
        if (profile.nights >= 2) {
          add('Swimwear', 'if the water is warm enough');
        }
      case TripKind.city:
        add('Wallet', 'you will want cash on hand');
        add('Phone charger', 'a long day out drains a battery');
        if (profile.nights >= 2) {
          add('Comfortable shoes', 'more walking than you expect');
        }
        if (profile.isRainyCity) add('Umbrella', 'forecast looks unsettled');
      case TripKind.home:
        break;
    }

    // --- Certain-ish: the month ---
    if (profile.isColdSeason) {
      add('Warm jacket', 'it is cold out this month');
    } else if (profile.isHotSeason && profile.kind != TripKind.coast) {
      add('Light cotton clothes', 'it is hot out this month');
    }
    if (profile.isMonsoon) {
      add(
        'Raincoat',
        profile.kind == TripKind.city
            ? 'it rains this month'
            : 'the monsoon does not care what you planned',
      );
    }

    // --- Odds and ends that follow from how long you are going ---
    if (profile.nights == 0) {
      add('Day bag', 'you are out and back');
    }
    if (profile.nights >= 4) {
      add('Laundry soap', 'a week is long enough to wash a thing');
    }
    if (profile.nights >= 7) {
      add('Full-size toiletries', 'do not rely on a tiny one');
    }

    // Always true, and its absence from every list was a bug.
    add('Medication', 'whatever you actually take');
    add(
      'Toiletries',
      profile.nights == 0
          ? 'just what you need for the day'
          : 'for ${profile.lengthLabel}',
    );

    return out.take(limit).toList();
  }

  /// Suggestions for a trip described by its parts.
  static List<PackingSuggestion> forTrip({
    String? destination,
    DateTime? startTime,
    DateTime? endTime,
  }) {
    return forProfile(
      profileFor(
        destination: destination,
        startTime: startTime,
        endTime: endTime,
      ),
    );
  }
}

extension on TripProfile {
  /// A coarse "is this the wet season" for cities, where [isMonsoon] is a
  /// monsoon-region term and would be wrong in, say, London in June.
  bool get isRainyCity => month >= 5 && month <= 9 && kind == TripKind.city;
}
