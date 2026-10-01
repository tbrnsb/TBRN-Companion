import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Resolves a category's colour against the surface it is about to be drawn on.
///
/// WHY THIS EXISTS. A category colour is DATA — one hex per category in
/// `expense_category_meta.dart`, carrying the hue that makes the category
/// recognisable. But it is drawn on a page, on a flat list row and on a raised
/// card, in EITHER brightness, and now in five palettes. Stage 0b made 28 fixed
/// hexes clear 3:1 on TBRN's two pages; they do not clear it on Gruvbox's raised
/// card (Travel 2.20, Snacks 1.86) or on Gruvbox's, and there is no set of 28
/// fixed hexes that clears 3:1 on six different mid-tone surfaces while keeping
/// every hue recognisable. So the hex stays the identity and the drawn colour is
/// RESOLVED.
///
/// The resolution is a lightness move in HSL, toward whichever end of the
/// background increases contrast, with hue and saturation untouched. So a
/// category keeps its colour and only changes how light or dark it is — the same
/// move Stage 0b made by hand, applied per surface so it does not have to be
/// right for six palettes at once.
///
/// NOT a licence for colours to bypass the theme. The category still never names
/// a hex outside `expense_category_meta.dart`; this reads the surface FROM the
/// active scheme, so a theme switch changes the resolved colour with no code
/// change.
class AppCategoryColour {
  AppCategoryColour._();

  /// The ratio a category colour must clear against the surface it sits on.
  static const double minimumContrast = 3.0;

  /// [base] as it should be drawn on [surface], alongside its siblings.
  ///
  /// THE SET IS THE UNIT OF THE FIX, and this is the whole design. Resolving each
  /// colour on its own converges them: several of the 28 are browns sitting in
  /// the same narrow luminance band, so pushing each to "whatever clears 3:1"
  /// pushes them all to the SAME lightness and the donut becomes eight slices of
  /// the same brown. That is worse than low contrast — it is a category legend
  /// that cannot be read at all.
  ///
  /// So one adjustment is computed for the whole set and applied to every member,
  /// which preserves their relative separation exactly while moving the set as
  /// far as the worst member needs. Saturation is scaled with it so a dark brown
  /// does not turn into a pale one on its way past the threshold.
  ///
  /// Pass the WHOLE category palette. A one-element list behaves like
  /// [resolveOne] and is correct but keeps none of the separation.
  static List<Color> resolveAll(List<Color> bases, Color surface) {
    if (bases.isEmpty) return const [];

    // Nothing fails, nothing moves. This is TBRN light: the canonical hexes are
    // what a user sees there and they stay exactly as they are.
    if (bases.every((b) => _contrast(b, surface) >= minimumContrast)) {
      return List.of(bases);
    }

    final goLighter = _luminance(surface) < 0.45;

    // ONE offset for the ENTIRE set, including the members that already passed.
    //
    // That is the whole design, and the alternative does not work. Shifting only
    // the failing members moves them ONTO the passing ones: on Gruvbox's flat
    // row that landed travel and entertainment on `other`, which is a donut of
    // three identical browns. Moving the whole palette by the same amount shifts
    // every pairwise distance by nothing at all, so the palette's separation is
    // preserved EXACTLY while the set as a whole becomes legible.
    var offset = 0.0;
    for (var step = 0; step <= 100; step++) {
      final delta = step * 0.01;
      offset = goLighter ? delta : -delta;
      if (bases.every(
        (base) => _contrast(_shifted(base, offset), surface) >= minimumContrast,
      )) {
        break;
      }
    }

    return [for (final base in bases) _shifted(base, offset)];
  }

  /// One colour moved by [offset] in lightness, and in nothing else.
  ///
  /// Hue and saturation are preserved EXACTLY. A resolver that also adjusted
  /// saturation to "compensate" would pass every contrast test here and quietly
  /// change what colour a category is — which is the one thing the category
  /// palette exists to do.
  static Color _shifted(Color base, double offset) {
    final hsl = HSLColor.fromColor(base);
    return hsl
        .withLightness((hsl.lightness + offset).clamp(0.0, 1.0))
        .toColor();
  }

  static Color resolve(Color base, Color surface) =>
      resolveAll([base], surface).single;

  static double _contrast(Color a, Color b) {
    final la = _luminance(a);
    final lb = _luminance(b);
    final lighter = math.max(la, lb);
    final darker = math.min(la, lb);
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// WCAG relative luminance.
  static double _luminance(Color c) => c.computeLuminance();
}

/// The surfaces a category colour is actually painted on.
///
/// Named here rather than left to each call site, because the list is the
/// specification: a colour is cleared against these and no others. Adding the
/// accent container here would be wrong — nothing draws a category chip on the
/// month summary card — and asserting against a surface nothing uses is how a
/// test ends up demanding a colour nobody can see.
class AppCategorySurfaces {
  AppCategorySurfaces._();

  /// The page, a flat list row, and a raised card, in that order.
  ///
  /// Derived from the active scheme rather than named per palette, so a new
  /// palette is covered by being a real theme rather than by being added to a
  /// list somewhere.
  static List<(String name, Color surface)> forScheme(ColorScheme scheme) => [
    ('page', scheme.surface),
    ('flat row', AppSurfaces.specFor(AppSurfaceTier.flat, scheme).color),
    ('raised card', AppSurfaces.specFor(AppSurfaceTier.raised, scheme).color),
  ];
}

/// The heatmap's own colour tokens, resolved against the cell background.
///
/// Kept here beside the category resolver because they answer the same question —
/// "what colour should this be on THIS surface" — and both are what Phase B item
/// 5d fills in. The slot names are fixed now:
///
/// - `AppChartColors.spendRamp(scheme)` — the SPEND ramp, one hue, several
///   steps, index 0 the faintest day.
/// - `AppChartColors.heatmapEmpty(scheme)` — a day inside the month with nothing
///   spent on it.
/// - `AppChartColors.heatmapDead(scheme)` — a cell that is not part of the month.
class AppChartColors {
  AppChartColors._();

  /// The spend ramp, LOWEST SPEND FIRST.
  ///
  /// Deliberately NOT derived from `primary`. More spending ramping toward the
  /// primary reads as SELECTED rather than as cost, which is why the heatmap card
  /// looked pasted onto the screen: not a colour problem, a meaning problem.
  ///
  /// Separate steps per brightness because a faint red on cream and a faint red
  /// on near-black are different contrast problems.
  static List<Color> spendRamp(ColorScheme scheme) => _rampFor(
    HSLColor.fromColor(
      scheme.brightness == Brightness.dark
          ? const Color(0xFFD96A50)
          : const Color(0xFFB5452C),
    ),
    against: scheme.surface,
  );

  /// Five steps of one hue, generated so the CONSTRAINTS hold by construction.
  ///
  /// Generated rather than listed because the constraints are the whole point and
  /// a listed ramp rots the moment a palette changes: every step has to clear 3:1
  /// on the card it is drawn on, consecutive steps have to be separable at a
  /// 15-pixel cell, and the whole thing has to stay in ONE hue so it reads as a
  /// scale rather than as a set of categories.
  ///
  /// It walks lightness UP from the first step that clears 3:1. Starting there is
  /// what makes the faintest step visibly different from the empty cell instead
  /// of nearly matching it — which is the failure item 5d is about, and the
  /// reason the old ramp faded a day with light spending into the surface.
  static List<Color> _rampFor(HSLColor base, {required Color against}) {
    const steps = 5;
    final result = <Color>[];

    // Far enough from the background's own lightness to be a MARK rather than a
    // tint. On a mid-tone surface a 3:1 step still needs headroom or the steps
    // bunch up and the scale stops being readable.
    final goLighter = against.computeLuminance() < 0.45;
    final start = _firstLightnessClearing(base, against, goLighter);

    for (var i = 0; i < steps; i++) {
      // AWAY from the background, not always up. Walking lightness up on a light
      // card walks it INTO the page, so the top steps vanish — which is the same
      // failure as a faint bottom step, from the other end.
      final delta = goLighter ? i * 0.11 : -i * 0.11;
      result.add(base.withLightness((start + delta).clamp(0.0, 1.0)).toColor());
    }
    return result;
  }

  static double _firstLightnessClearing(
    HSLColor base,
    Color against,
    bool goLighter,
  ) {
    for (var i = 1; i <= 100; i++) {
      final delta = i * 0.01;
      final candidate = base
          .withLightness(
            (goLighter ? base.lightness + delta : base.lightness - delta).clamp(
              0.0,
              1.0,
            ),
          )
          .toColor();
      if (_contrast(candidate, against) >= 3.4) {
        return HSLColor.fromColor(candidate).lightness;
      }
    }
    return goLighter ? 0.9 : 0.2;
  }

  /// A day inside the month with nothing spent on it.
  ///
  /// Its own token, not `surfaceContainerHighest`, because on the dark-dominant
  /// palettes the highest container sits close enough to the page that "nothing
  /// happened" and "not part of this month" became the same colour.
  static Color heatmapEmpty(ColorScheme scheme) => scheme.surfaceContainer;

  /// A cell that is not part of the month at all: before the first, after the
  /// last. DEAD SPACE, and it must not read as a day.
  ///
  /// Distinct from [heatmapEmpty] on purpose. A calendar with gaps in it is still
  /// a calendar; a grid whose padding looks like a quiet week is a chart lying
  /// about its own shape.
  static Color heatmapDead(ColorScheme scheme) => scheme.surfaceContainerLowest;

  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final lighter = math.max(la, lb);
    final darker = math.min(la, lb);
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// How many steps the ramp offers. A function of the ramp, not a constant, so a
  /// palette with a different-length ramp cannot have a legend claiming another.
  static int rampLength(ColorScheme scheme) => spendRamp(scheme).length;

  /// The ramp step for [intensity] in 0..1.
  ///
  /// The faintest step is the ramp's FIRST entry rather than a low-alpha version
  /// of its top: an alpha over the cell surface puts the faint end near the empty
  /// cell's colour, so a lightly-spent day looks like nothing happened and the
  /// scale reads as noise rather than as magnitude.
  static Color spendStep(ColorScheme scheme, double intensity) {
    final ramp = spendRamp(scheme);
    if (intensity <= 0) return heatmapEmpty(scheme);
    final index = (intensity * ramp.length).ceil().clamp(1, ramp.length) - 1;
    return ramp[index];
  }
}
