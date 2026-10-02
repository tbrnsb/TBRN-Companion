import 'package:flutter/material.dart';

import 'app_palettes.dart';

/// A palette's two accents BEYOND its primary, carried on the [ThemeData].
///
/// WHY A THEME EXTENSION AND NOT `tertiary`. Material's [ColorScheme] has
/// exactly one accent slot beyond `primary` and `secondary`, this app already
/// spends `secondary` and `tertiary` on the same colour, and neither slot means
/// "the second thing on this card". What a screen actually needs is a warmer and
/// a cooler sibling of the primary so a heading, a chip, a reminder and a call to
/// action can stop all being the same amber -- which is what made the Active
/// Journey card read as one flat block in every theme.
///
/// So the pair travels as its own extension, is OPTIONAL per family, and falls
/// back to the scheme when a family has not asked for one. A widget that uses it
/// therefore works on all four palettes without knowing which ones have accents,
/// and a family that ships with one hue keeps exactly the one it had.
///
/// A [ThemeExtension] rather than a global lookup because a theme switch has to
/// change the answer with no code change, and because a test can install a theme
/// and ask for the accent the same way any widget does.
@immutable
class AppAccents extends ThemeExtension<AppAccents> {
  const AppAccents({required this.warm, required this.cool});

  /// The accents resolved from a palette spec, falling back to the scheme.
  ///
  /// The fallback is not a failure path. A family with no declared accent gets
  /// `primary` and `secondary`, which is exactly the pair it always had, so a
  /// widget written against [warm] and [cool] degrades to today's behaviour on
  /// TBRN, Catppuccin and Solitude instead of rendering an invented colour.
  factory AppAccents.from(ColorScheme scheme, AppPaletteSpec spec) =>
      AppAccents(
        warm: spec.accentWarm ?? scheme.primary,
        cool: spec.accentCool ?? scheme.secondary,
      );

  /// Warmer than [cool]. The accent for the loudest element on a card.
  final Color warm;

  /// Cooler than [warm]. The accent for the second-most important element.
  final Color cool;

  /// The accents for the nearest theme, or a pair derived from [scheme].
  ///
  /// Never returns null and never throws: a widget asking for an accent inside a
  /// bare [ThemeData] gets the scheme's own two colours rather than crashing on
  /// a missing extension. Extensions are opt-in, so a test or a one-off
  /// MaterialApp that does not install one would otherwise be a null dereference
  /// in whatever is being tested.
  static AppAccents of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppAccents>() ??
        AppAccents(
          warm: theme.colorScheme.primary,
          cool: theme.colorScheme.secondary,
        );
  }

  /// The accent for a role, so a caller states INTENT rather than picking a hue.
  ///
  /// Roles rather than colours at the call site, because "the important thing on
  /// this card" is what a screen knows and "amber" is what a palette knows.
  /// Swapping which colour answers to a role is then a one-line change here
  /// instead of an edit at every use.
  Color forRole(AppAccentRole role) => switch (role) {
    AppAccentRole.emphasis => warm,
    AppAccentRole.supporting => cool,
  };

  @override
  AppAccents copyWith({Color? warm, Color? cool}) =>
      AppAccents(warm: warm ?? this.warm, cool: cool ?? this.cool);

  @override
  AppAccents lerp(ThemeExtension<AppAccents>? other, double t) {
    if (other is! AppAccents) return this;
    return AppAccents(
      warm: Color.lerp(warm, other.warm, t)!,
      cool: Color.lerp(cool, other.cool, t)!,
    );
  }
}

/// What an accent is being asked to DO, as opposed to which colour it is.
enum AppAccentRole {
  /// The most important thing on the card: the heading, the active state, the
  /// one control that matters.
  emphasis,

  /// The next thing down: a supporting chip, a secondary badge, a quiet marker
  /// that still has to be findable.
  supporting,
}
