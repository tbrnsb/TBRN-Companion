import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:daily_companion/models/expense_category_meta.dart';

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

  /// [meta]'s colour as it should be drawn on [surface].
  ///
  /// THIS is what a call site should use, rather than reading `meta.color`.
  /// Reading the raw hex is what made category colours look pasted onto whichever
  /// palette was active: the registry hexes were tuned for TBRN's cream page, so
  /// on Gruvbox's mid-tone card or a near-black dark page they sat at whatever
  /// contrast the tuning happened to land on. Twenty-nine places read the hex
  /// directly, which is why this resolver existed, was tested, and was almost
  /// never called.
  ///
  /// It resolves the WHOLE built-in set and returns this category's share,
  /// because the set is the unit: several of these colours are browns in one
  /// narrow lightness band, and moving only a failing one lands it on top of a
  /// passing neighbour. See [resolveAll].
  ///
  /// A CUSTOM category is handed back untouched. The user chose that hex, and
  /// re-deriving it per theme would quietly restyle the one colour in the app
  /// that somebody picked on purpose.
  static Color forMeta(CategoryMeta meta, Color surface) {
    if (meta.id.startsWith('custom:')) return meta.color;
    final index = _indexOf(meta.name);
    if (index == null) return meta.color;
    return _builtInResolved(surface)[index];
  }

  /// Every built-in category's colour on [surface], keyed by category id.
  ///
  /// For a caller drawing several slices at once, so a single [resolveAll]
  /// serves all of them and they keep their separation from each other.
  static Map<String, Color> allBuiltInOn(Color surface) {
    final resolved = _builtInResolved(surface);
    return {
      for (var i = 0; i < _builtInOrder.length; i++)
        _builtInOrder[i].name: resolved[i],
    };
  }

  /// The built-ins, in the fixed order [_builtInResolved] returns them in.
  ///
  /// Expense first, then the suggested "Other" types, then income, because that
  /// is the order they can appear together in a breakdown: a donut is either
  /// spending or income, and the suggested types join the expense side.
  static final List<CategoryMeta> _builtInOrder = [
    ...CategoryRegistry.expenseCategories(),
    ...CategoryRegistry.suggestedExpenseTypes(),
    ...CategoryRegistry.incomeCategories(),
  ];

  /// Keyed by NAME, not by [CategoryMeta.id].
  ///
  /// Two built-ins share the id `other` -- the expense "Other" and the income
  /// "Other Income" -- so an id-keyed map silently dropped one of them and gave
  /// the other its colour. Every one of the 27 names is unique.
  ///
  /// Name is also the honest key: a transaction persists its category as a NAME
  /// (`Expense.fromJson` reads `json['category']`), so this is the same string
  /// the data is actually keyed on.
  static final Map<String, int> _indexByName = {
    for (var i = 0; i < _builtInOrder.length; i++) _builtInOrder[i].name: i,
  };

  static int? _indexOf(String name) => _indexByName[name];

  /// The resolved set for [surface], memoised per surface.
  ///
  /// The memo is on the [Color] itself, so the two or three surfaces a screen
  /// actually draws on are resolved once rather than on every rebuild, and a
  /// palette change lands on a different key so it cannot serve a stale answer.
  static final Expando<List<Color>> _cache = Expando('categoryColours');

  /// WHY THE SET IS RESOLVED PER FAMILY, not all at once.
  ///
  /// Moving every category by ONE offset is what preserves their separation, and
  /// it is also the flaw. On Gruvbox's mid-tone card the whole set has to go
  /// lighter, and `Utilities` (a sage green) and `Other` (a taupe) landed on
  /// `#8BB1A3` and `#99A6B0` — 107 apart on the project's own colour distance,
  /// against a floor of 150. Two slices of one donut, effectively the same grey.
  ///
  /// Nothing is wrong with either hex: before any shift they are 1248 apart. The
  /// shift is what merged them, because a uniform lightness move takes two
  /// low-chroma neighbours toward the same grey.
  ///
  /// So the set is split by HUE and each family gets its own offset. Utilities is
  /// green and Other is warm, so they are no longer dragged to the same place by
  /// a contrast constraint that only one of them actually has. Within a family the
  /// uniform move is kept, because that is where the crowding is: the warm
  /// browns really are all sitting in one narrow band and really do need to move
  /// together.
  static List<Color> _builtInResolved(Color surface) {
    return _cache[surface] ??= _resolveByFamily(surface);
  }

  /// Six hue bands, assigned by the colour's own hue rather than by its id.
  ///
  /// By hue so a category added later lands in the right family without anyone
  /// remembering to update a list. The gold `Bonus` (hue 46) is deliberately in
  /// the WARM band and not the green one, because a yellow-gold sitting among the
  /// greens reads as a fifth green.
  static int _familyOf(Color colour) {
    final hue = HSLColor.fromColor(colour).hue;
    if (hue < 48 || hue >= 350) return _warm;
    if (hue < 165) return _green;
    if (hue < 200) return _teal;
    if (hue < 250) return _blue;
    if (hue < 320) return _purple;
    return _pink;
  }

  static const int _warm = 0;
  static const int _green = 1;
  static const int _teal = 2;
  static const int _blue = 3;
  static const int _purple = 4;
  static const int _pink = 5;
  static const int _familyCount = 6;

  static List<Color> _resolveByFamily(Color surface) {
    // Bucket the indices by family, keeping the original order inside each so the
    // result is still index-aligned with `_builtInOrder`.
    final buckets = List.generate(_familyCount, (_) => <int>[]);
    for (var i = 0; i < _builtInOrder.length; i++) {
      buckets[_familyOf(_builtInOrder[i].color)].add(i);
    }

    final out = List<Color>.filled(
      _builtInOrder.length,
      const Color(0xFF000000),
    );
    final familyOf = List<int>.filled(_builtInOrder.length, 0);
    for (var f = 0; f < _familyCount; f++) {
      for (final i in buckets[f]) {
        familyOf[i] = f;
      }
    }

    for (final bucket in buckets) {
      if (bucket.isEmpty) continue;
      final resolved = resolveAll([
        for (final i in bucket) _builtInOrder[i].color,
      ], surface);
      for (var k = 0; k < bucket.length; k++) {
        out[bucket[k]] = resolved[k];
      }
    }

    return _repairCrossFamily(out, familyOf, surface);
  }

  /// THE B HALF: separate pairs that the per-family moves pushed together.
  ///
  /// Per-family offsets fix crowding WITHIN a family, and they introduce a
  /// different defect: nothing stops one family landing on another. Warm pushed
  /// +0.20 meets blue pushed +0.02, and on Gruvbox's card the expense "Other" and
  /// the income "Other Income" arrived at the SAME colour -- 0 apart, the worst
  /// possible outcome. Shopping and Gift went from 572 to 131 the same way.
  ///
  /// So after the families have each moved, any CROSS-family pair that fell below
  /// the floor is walked apart. The member with more room is the one that moves,
  /// and it moves in lightness only, AWAY from its partner and towards whichever
  /// end of the background already gives it contrast -- so it cannot break the
  /// 3:1 it just earned.
  ///
  /// Pairs inside one family are left alone. They are the ones the uniform move
  /// exists to preserve, and separating them individually is the failure the
  /// original comment warns about.
  ///
  /// Bounded rather than unbounded: a full separation is not always reachable by
  /// lightness alone, and looping forever on an impossible pair would hang a
  /// frame. What is unreachable is reported by the test, not silently accepted.
  static List<Color> _repairCrossFamily(
    List<Color> colours,
    List<int> familyOf,
    Color surface,
  ) {
    final out = List<Color>.of(colours);
    final goLighter = _luminance(surface) < 0.45;

    for (var pass = 0; pass < _repairPasses; pass++) {
      var moved = false;

      for (var i = 0; i < out.length; i++) {
        for (var j = i + 1; j < out.length; j++) {
          if (familyOf[i] == familyOf[j]) continue;
          if (_separation(out[i], out[j]) >= _minimumSeparation) continue;

          // Move the one that can afford it, in whichever direction its own
          // contrast already points. Moving the darker one lighter on a dark
          // surface keeps both readable; moving it darker would undo the 3:1 the
          // resolve pass just bought.
          final slack =
              _contrast(out[i], surface) - AppCategoryColour.minimumContrast;
          final iCanMove = slack.abs() >= 0.02;
          final target = iCanMove ? i : j;
          final away = goLighter ? 1 : -1;

          out[target] = _shifted(out[target], away * _repairStep);
          moved = true;
        }
      }

      if (!moved) break;
    }
    return out;
  }

  /// How far apart two colours must read, on the same luma-weighted measure
  /// `design_system_test.dart` uses.
  ///
  /// The SAME measure and the same floor as the existing separation test, on
  /// purpose. This file once used an HSL-based distance of its own and reported
  /// 175 failing pairs on colours that ship today, including "Travel/Coffee 6" --
  /// it was measuring something the app had never claimed. A guard is only worth
  /// having if it agrees with the guard already in the suite.
  static const double _minimumSeparation = 150.0;

  /// Perceived distance, luma-weighted: the eye is most sensitive to green and
  /// least to blue.
  static double _separation(Color a, Color b) {
    final dr = (a.r - b.r) * 255;
    final dg = (a.g - b.g) * 255;
    final db = (a.b - b.b) * 255;
    return dr * dr * 0.30 + dg * dg * 0.59 + db * db * 0.11;
  }

  static const int _repairPasses = 40;
  static const double _repairStep = 0.02;

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

  /// How far a structure token must be visible against the card it sits on.
  ///
  /// This is NOT the 3:1 that non-text gets and NOT the 4.5 of body copy. These
  /// are grid STRUCTURE -- the empty boxes that make a grid read as a grid -- and
  /// 3:1 would make a month-shaped block of grey so heavy it competes with the
  /// spending it is meant to frame. 1.6 is enough to see a cell against the card
  /// and light enough to stay in the background. Measured, asserted, and derived
  /// rather than hand-picked, so it holds in all six specs.
  static const double structureFloor = 1.6;

  /// The floor for DEAD padding, deliberately below [structureFloor].
  ///
  /// Its own number rather than "the empty token at some fraction", and the
  /// reason is a measured failure: with both tokens searched up to a single
  /// floor, TBRN light resolved empty to 1.6051:1 and dead to 1.6061:1 —
  /// indistinguishable, which is the bug this whole change exists to fix
  /// arriving through the front door.
  static const double deadFloor = 1.2;

  /// A day inside the month with nothing spent on it.
  ///
  /// Was `scheme.surfaceContainer` -- a SURFACE token, and the bug that made the
  /// heatmap look like "a random throwing of pixels". `surfaceContainer` and
  /// `surfaceContainerLowest` are the two lowest-contrast steps in the ladder,
  /// designed to sit behind content almost invisibly, so every cell carrying no
  /// spending was nearly the same colour as the card it sat on. The grid had no
  /// visible rectangle: no structure, no month shape, no way to see where the
  /// month began and ended.
  ///
  /// It is now INK, mixed toward the palette's own `onSurface` until it clears
  /// [structureFloor] against the card -- the same derivation as the spend ramp
  /// and the secondary-text token, so a palette edit cannot silently reintroduce
  /// an invisible grid.
  ///
  /// Empty is DARKER than the card on a light theme and LIGHTER on a dark one,
  /// because it is a filled box in an outline rather than a hole in the page.
  static Color heatmapEmpty(ColorScheme scheme) => _structureInk(
    scheme,
    // A starting guess only. The search walks it UP until the MEASURED contrast
    // against the card clears [structureFloor], so a palette where this guess is
    // too timid cannot produce an invisible grid.
    start: 0.16,
    floor: structureFloor,
  );

  /// A cell that is not part of the month at all: before the first, after the
  /// last. DEAD SPACE, and it must read as padding rather than as a quiet day.
  ///
  /// FAINTER than [heatmapEmpty] on purpose, so the month's outline is legible,
  /// but not invisible: a reader has to be able to see the rectangle and
  /// understand that the outer cells are padding. A month with gaps in it is
  /// still a calendar; a grid whose padding looks like a quiet week is a chart
  /// lying about its own shape.
  static Color heatmapDead(ColorScheme scheme) =>
      _structureInk(scheme, start: 0.06, floor: deadFloor);

  /// Ink mixed toward the palette's own `onSurface` until it reads against the
  /// card the heatmap is drawn on.
  ///
  /// The card comes from the scheme rather than a named token, so this holds for
  /// every palette including the ones added later, without being told about
  /// them.
  ///
  /// Walked in 100 steps because the contrast ratio is NOT linear in the mix
  /// factor: one coarse step either overshoots -- a dead cell that reads as an
  /// empty day -- or undershoots, which is the original bug.
  ///
  /// Hue and saturation are inherited from the INK, so the cells belong to the
  /// palette rather than being a neutral grey pasted over it.
  /// The smallest move from the card toward ink whose MEASURED contrast against
  /// the card reaches [floor].
  ///
  /// The floor is the specification and the token is derived from it, never the
  /// other way round. Every earlier attempt in this file specified a mix fraction
  /// per token and then checked it, which is how a fraction that is invisible on
  /// one palette passed review and failed on TBRN light.
  ///
  /// Searched rather than solved because contrast is not linear in a lightness or
  /// mix step: the same 0.07 that reads on one palette is nothing on another.
  /// 200 steps per attempt and the attempt grows, so a card needing more ink than
  /// the starting guess gets it.
  static Color _structureInk(
    ColorScheme scheme, {
    required double start,
    required double floor,
  }) {
    final card = scheme.surface;
    final ink = scheme.onSurface;

    // Toward ink on a DARK card, away from it on a light one: a filled box is
    // LIGHTER than a near-black page and DARKER than a cream one. Getting this
    // backwards produces a token that is invisible by construction, which is
    // exactly what `surfaceContainer` was.
    final mixInk = _luminance(card) < 0.45;

    final cardHsl = HSLColor.fromColor(card);
    final inkHsl = HSLColor.fromColor(ink);
    // Hue and saturation inherited from the INK, so the cells belong to the
    // palette rather than being a neutral grey pasted over it.
    final tinted = cardHsl
        .withHue(inkHsl.hue)
        .withSaturation(
          (cardHsl.saturation * 0.6 + inkHsl.saturation * 0.4).clamp(0.0, 1.0),
        )
        .toColor();

    var amount = start;
    for (var attempt = 0; attempt < 50; attempt++) {
      for (var step = 1; step <= 200; step++) {
        final t = (step / 200) * amount;
        final candidate = mixInk
            ? Color.lerp(tinted, ink, t)!
            : _darken(tinted, t);
        if (_contrast(candidate, card) >= floor) return candidate;
      }
      amount += 0.02;
    }

    // Unreachable in practice: `ink` itself clears any floor, so the search
    // always terminates. Returning the furthest step rather than the untinted
    // card means a caller can never get back a token indistinguishable from the
    // background.
    return mixInk
        ? Color.lerp(tinted, ink, 1)!
        : _darken(tinted, 1 - cardHsl.lightness);
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
  ///
  /// Zero returns [heatmapEmpty]. That is the zero-max decision: a month whose
  /// only spending is another participant's trip expense has a per-day maximum of
  /// zero, and every day reads as an empty cell rather than dividing by it.
  static Color spendStep(ColorScheme scheme, double intensity) {
    final ramp = spendRamp(scheme);
    if (intensity <= 0) return heatmapEmpty(scheme);
    final index = (intensity * ramp.length).ceil().clamp(1, ramp.length) - 1;
    return ramp[index];
  }

  /// [colour] moved [amount] toward black, in HSL lightness.
  ///
  /// HSL rather than an alpha, because an alpha over the card produces a colour
  /// whose contrast depends on the card -- and the point of these tokens is that
  /// they are the SAME ink whatever card they land on.
  static Color _darken(Color colour, double amount) {
    final hsl = HSLColor.fromColor(colour);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }

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
