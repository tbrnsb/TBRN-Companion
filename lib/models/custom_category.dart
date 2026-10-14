import 'dart:convert';

import 'package:flutter/material.dart';

import 'category_icons.dart';

/// Whether a category is money out or money in.
///
/// Part of the record rather than implied by which screen is showing it, because
/// a category the user named is the same category wherever it appears, and
/// "Groceries" being an expense on one screen and not offered as an income
/// category on another is a fact about the category rather than about the screen.
enum CategoryKind { expense, income }

extension CategoryKindX on CategoryKind {
  String get label => switch (this) {
    CategoryKind.expense => 'Expense',
    CategoryKind.income => 'Income',
  };
}

/// A category the user added.
///
/// Persisted as JSON in the SAME box that used to hold bare names, so no new box
/// and no migration of the box itself — see [StorageService] for the read path.
/// A value written by an older build is a plain name, and
/// [CustomCategory.fromStored] reads that back as an expense category with the
/// generic appearance, which is exactly what it was.
@immutable
class CustomCategory {
  const CustomCategory({
    required this.name,
    this.kind = CategoryKind.expense,
    this.colorValue,
    this.iconKey,
    this.aliases = const [],
  });

  final String name;
  final CategoryKind kind;

  /// Names this category was called before, oldest first.
  ///
  /// The id is DERIVED from the name -- `custom:<lowercased name>` -- so a
  /// rename does not move the category, it destroys one key and create another.
  /// Every transaction already filed under the old name holds that name as
  /// plain text, and without this the rename left the whole history reading
  /// "random" while the picker offered "misc": one category, two names on
  /// screen, and a search for the new name that could not find the old rows.
  ///
  /// Carrying the previous names forward is what lets a past row resolve to the
  /// category that used to answer to it. Kept on the record rather than in the
  /// transaction, because there is no reason to rewrite every row and no way to
  /// reach them all from the rename itself.
  final List<String> aliases;

  /// The colour as a packed ARGB int, or null to use the generic custom colour.
  ///
  /// An INT rather than a [Color] so the record has no Flutter dependency and
  /// can be written straight to storage; and OPTIONAL because a category created
  /// before this feature existed has no colour of its own and should keep
  /// looking the way it did rather than being recoloured by a migration.
  final int? colorValue;

  /// A key into [CategoryIcons], or null to use the generic sparkle.
  ///
  /// A KEY and not a glyph, so the record survives a build that renames or adds
  /// an icon, and so a category written before an icon existed still draws.
  /// See [CategoryIcons] for why these are monochrome glyphs and not emoji.
  ///
  /// OPTIONAL and nullable for the same reason as [colorValue]: a category
  /// created before this existed keeps the appearance it had rather than being
  /// given one by a migration.
  final String? iconKey;

  /// The glyph this category is drawn with.
  IconData get icon => CategoryIcons.resolve(iconKey);

  /// The colour it is drawn in, or null to use the generic custom colour.
  Color get resolvedColor => color ?? _defaultColor;

  /// The generic colour, used when the user has not chosen one.
  static Color get _defaultColor => const Color(0xFF9C8B7A);

  /// The id a transaction, budget or breakdown stores for this category.
  String get id => 'custom:${name.trim().toLowerCase()}';

  Color? get color => colorValue == null ? null : Color(colorValue!);

  CustomCategory copyWith({
    String? name,
    CategoryKind? kind,
    int? colorValue,
    String? iconKey,
    bool clearColor = false,
    bool clearIcon = false,
  }) => CustomCategory(
    name: name ?? this.name,
    kind: kind ?? this.kind,
    colorValue: clearColor ? null : (colorValue ?? this.colorValue),
    iconKey: clearIcon ? null : (iconKey ?? this.iconKey),
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'kind': kind.name,
    if (colorValue != null) 'color': colorValue,
    if (iconKey != null) 'icon': iconKey,
    if (aliases.isNotEmpty) 'aliases': aliases,
  };

  String encode() => CustomCategoryCodec.encode(this);

  /// Reads a stored value, whether it is JSON or a bare legacy name.
  ///
  /// NEVER THROWS. A value this cannot read is treated as a category with no
  /// readable name, which the caller drops; the alternative is a corrupt entry
  /// taking the whole settings screen down with it, because one unparseable
  /// string in a box of strings is enough to do that.
  static CustomCategory? fromStored(String stored) {
    final trimmed = stored.trim();
    if (trimmed.isEmpty) return null;

    if (!trimmed.startsWith('{')) {
      // The legacy format: the name on its own, an expense, generic appearance.
      return CustomCategory(name: trimmed);
    }

    try {
      final decoded = CustomCategoryCodec.decode(trimmed);
      if (decoded == null || decoded.name.trim().isEmpty) return null;
      return decoded;
    } catch (_) {
      return null;
    }
  }
}

/// The JSON shape, kept apart from the model so the model carries no encoding
/// knowledge and the format has exactly one home.
class CustomCategoryCodec {
  CustomCategoryCodec._();

  /// Bumped only for a change an older build could not read. An older build
  /// falls back to "a category with an unreadable name", which it drops, rather
  /// than crashing on it.
  static const int version = 1;

  static String encode(CustomCategory category) =>
      jsonEncode(category.toJson());

  /// Null for anything unreadable, rather than throwing.
  ///
  /// A corrupt value has to be survivable: one unparseable string in a box of
  /// strings is enough to take the whole settings screen down otherwise, and the
  /// cost of losing a category is far lower than the cost of a screen that will
  /// not open.
  static CustomCategory? decode(String stored) {
    final Object? decoded;
    try {
      decoded = jsonDecode(stored);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final name = decoded['name'];
    if (name is! String || name.trim().isEmpty) return null;
    final kind = decoded['kind'];
    final colour = decoded['color'];
    final iconKey = decoded['icon'];
    // Read defensively: a record written before aliases existed has no key, and
    // one written by a build that stored them differently must not be dropped
    // over a field that only exists to make history read correctly.
    final rawAliases = decoded['aliases'];
    final aliases = <String>[
      if (rawAliases is List)
        for (final alias in rawAliases)
          if (alias is String && alias.trim().isNotEmpty && alias != name)
            alias,
    ];
    return CustomCategory(
      name: name,
      kind: kind == CategoryKind.income.name
          ? CategoryKind.income
          : CategoryKind.expense,
      colorValue: colour is int ? colour : null,
      // An `emoji` key is READ AND IGNORED rather than treated as an icon. A
      // record written by the build that briefly offered emoji has a key here
      // this catalogue has never heard of, so it falls back to the generic
      // sparkle -- which is exactly what it was drawing before.
      aliases: aliases,
      iconKey: iconKey is String && CategoryIcons.isKnown(iconKey)
          ? iconKey
          : null,
    );
  }
}
