import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daily_companion/theme/app_theme.dart';
import 'package:daily_companion/widgets/chart_pager.dart';
import 'package:daily_companion/widgets/spend_trend_cards.dart';
import 'package:daily_companion/widgets/spending_heatmap.dart';

import 'test_viewports.dart';

/// The only day a freshly seeded demo month has recorded.
final _oneDay = DateTime(2026, 10, 2);

/// September 2026, the eight days the demo month actually holds.
///
/// The shape that showed the bug on the device: few days, so the rods are wide
/// and spaced far apart, and a peak that leaves the tallest rod near the top of
/// its frame.
final _september = <DayTotal>[
  DayTotal(date: DateTime(2026, 9, 1), income: 900, expenses: 0),
  DayTotal(date: DateTime(2026, 9, 2), income: 0, expenses: 320),
  DayTotal(date: DateTime(2026, 9, 6), income: 0, expenses: 150),
  DayTotal(date: DateTime(2026, 9, 11), income: 0, expenses: 900),
  DayTotal(date: DateTime(2026, 9, 15), income: 0, expenses: 60),
  DayTotal(date: DateTime(2026, 9, 19), income: 0, expenses: 640),
  DayTotal(date: DateTime(2026, 9, 24), income: 0, expenses: 1500),
  DayTotal(date: DateTime(2026, 9, 26), income: 0, expenses: 400),
];

Future<void> settleUi(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// How many pixels in [rect] of the captured widget differ from [background].
///
/// WHY PIXELS. "The chart drew nothing" is not a widget-tree assertion — the
/// `LineChart` is in the tree either way, it simply paints no path. A curved
/// line with a single spot has nothing to interpolate, so fl_chart builds a
/// degenerate path and the page comes up blank while every finder still passes.
/// The only way to catch that is to look at what was actually painted.
Future<int> _paintedPixels(
  WidgetTester tester,
  Rect rect,
  Color background,
) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );

  late ui.Image image;
  late ByteData? bytes;
  await tester.runAsync(() async {
    image = await boundary.toImage(pixelRatio: 1.0);
    bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  });
  final stride = image.width * 4;
  final height = image.height;
  image.dispose();

  final data = bytes!;
  var painted = 0;
  final left = rect.left.floor();
  final top = rect.top.floor();
  final right = rect.right.ceil();
  final bottom = rect.bottom.ceil();

  for (var y = top; y < bottom && y < height; y++) {
    for (var x = left; x < right; x++) {
      if (x < 0 || x >= image.width) continue;
      final i = y * stride + x * 4;
      if (i + 3 >= data.lengthInBytes) continue;
      final r = data.getUint8(i);
      final g = data.getUint8(i + 1);
      final b = data.getUint8(i + 2);
      final a = data.getUint8(i + 3);
      if (a == 0) continue;
      final drift =
          (r - background.r * 255).abs() +
          (g - background.g * 255).abs() +
          (b - background.b * 255).abs();
      if (drift > 12) painted++;
    }
  }
  return painted;
}

Widget _host(Widget child, Color background) => MaterialApp(
  theme: AppTheme.dark(),
  home: Scaffold(
    body: Container(
      color: background,
      padding: const EdgeInsets.all(16),
      child: RepaintBoundary(key: const ValueKey('capture'), child: child),
    ),
  ),
);

/// The painted/background runs along one horizontal line, as [runs] of booleans.
///
/// Used to measure whether two bars in a group are separated by real card
/// background or have been drawn flush against each other. On the device the
/// "In" and "Out" rods met with no visible seam and read as one block, which
/// no widget-tree assertion can see.
Future<List<bool>> _rowRuns(WidgetTester tester, Rect rect, double atY) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  late ui.Image image;
  late ByteData? bytes;
  await tester.runAsync(() async {
    image = await boundary.toImage(pixelRatio: 1.0);
    bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  });
  final stride = image.width * 4;
  final height = image.height;
  image.dispose();

  final data = bytes!;
  final runs = <bool>[];
  final y = atY.round();
  if (y < 0 || y >= height) return runs;

  for (var x = rect.left.floor(); x < rect.right.ceil(); x++) {
    if (x < 0 || x >= image.width) continue;
    final i = y * stride + x * 4;
    if (i + 3 >= data.lengthInBytes) continue;
    // ALPHA, NOT COLOUR. The captured subtree is only the chart, so everything
    // the chart did not paint is TRANSPARENT (0,0,0,0) rather than the surface
    // colour behind it. Comparing RGB against a named background therefore reads
    // the whole row as painted and reports a gap of zero for a chart that has
    // one. Coverage is the honest signal: alpha above zero IS paint.
    runs.add(data.getUint8(i + 3) > 8);
  }
  return runs;
}

/// The widest run of card background that sits BETWEEN two painted runs.
int _widestInnerGap(List<bool> runs) {
  var best = 0;
  var current = 0;
  var seenPaint = false;
  for (final painted in runs) {
    if (painted) {
      if (seenPaint) best = current > best ? current : best;
      current = 0;
      seenPaint = true;
    } else if (seenPaint) {
      current++;
    }
  }
  return best;
}

/// Pixels in [rect] that are [target], within [tolerance] per channel.
///
/// COLOUR-MATCHED rather than "differs from the background", because the band
/// under test legitimately contains the heading's own glyphs. Counting those
/// would pass whether or not a bar crossed them. The question here is
/// specifically "did a ROD colour land in the heading's rows", which is what a
/// bar escaping its own slot looks like.
Future<int> _pixelsNear(
  WidgetTester tester,
  Rect rect,
  Color target, {
  int tolerance = 24,
  int minRun = 5,
}) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  late ui.Image image;
  late ByteData? bytes;
  await tester.runAsync(() async {
    image = await boundary.toImage(pixelRatio: 1.0);
    bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  });
  final stride = image.width * 4;
  final height = image.height;
  image.dispose();

  final data = bytes!;

  bool matches(int x, int y) {
    final i = y * stride + x * 4;
    if (i + 3 >= data.lengthInBytes) return false;
    if (data.getUint8(i + 3) == 0) return false;
    final dr = (data.getUint8(i) - target.r * 255).abs();
    final dg = (data.getUint8(i + 1) - target.g * 255).abs();
    final db = (data.getUint8(i + 2) - target.b * 255).abs();
    return dr <= tolerance && dg <= tolerance && db <= tolerance;
  }

  // Only pixels belonging to a RUN count, and a run has to be at least [minRun]
  // wide. The heading is drawn in the very colour a bar is, so without this the
  // test measures its own glyphs and passes no matter what the plot does. At
  // pixelRatio 1 a rod is 7 wide and a glyph stroke is 1 or 2, so the width is
  // what separates "a bar crossed the text" from "the text is there".
  var hits = 0;
  for (var y = rect.top.floor(); y < rect.bottom.ceil() && y < height; y++) {
    var run = 0;
    for (var x = rect.left.floor(); x <= rect.right.ceil(); x++) {
      if (x >= 0 && x < image.width && matches(x, y)) {
        run++;
      } else {
        if (run >= minRun) hits += run;
        run = 0;
      }
    }
  }
  return hits;
}

void main() {
  final surface = AppTheme.dark().colorScheme.surface;

  group('the pixel helper can see a chart that definitely paints', () {
    // THE INSTRUMENT HAS TO BE PROVEN FIRST. Every other assertion in this file
    // is "painted > 0", and a helper that always answers 0 would make all of
    // them pass for the wrong reason. The daily chart is full of solid bars, so
    // if this cannot see them, the failures elsewhere mean nothing.
    testWidgets('sees the solid bars of a daily chart', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      await tester.pumpWidget(
        _host(
          DailyTotalsChart(
            days: [DayTotal(date: _oneDay, income: 5000, expenses: 4126.75)],
            currencySymbol: 'Rs. ',
          ),
          surface,
        ),
      );
      await settleUi(tester);

      final painted = await _paintedPixels(
        tester,
        tester.getRect(find.byType(BarChart)),
        surface,
      );

      expect(painted, greaterThan(200));
    });
  });

  group('a group of bars is separated by real background', () {
    // THE BUG. `barsSpace: 2` left the In and Out rods with a seam too small to
    // read on a phone, so the pair looked like one solid block and you could not
    // tell there were two series at all.
    for (final (name, chart) in <(String, Widget Function())>[
      (
        'daily',
        () => DailyTotalsChart(
          days: [DayTotal(date: _oneDay, income: 5000, expenses: 4126.75)],
          currencySymbol: 'Rs. ',
        ),
      ),
      (
        'weekly',
        () => WeeklyTotalsChart(
          days: [DayTotal(date: _oneDay, income: 5000, expenses: 4126.75)],
          currencySymbol: 'Rs. ',
        ),
      ),
    ]) {
      testWidgets('$name leaves a visible gap between its two bars', (
        tester,
      ) async {
        usePhoneLayout(tester, TestViewports.phonePortrait);

        await tester.pumpWidget(_host(chart(), surface));
        await settleUi(tester);

        final plot = tester.getRect(find.byType(BarChart));
        // Through the upper half of the plot, where both rods are solid.
        final runs = await _rowRuns(tester, plot, plot.top + plot.height * 0.3);

        // The bars have to actually be there, or a gap of 0 would be the
        // helper reporting "nothing painted" rather than "bars flush".
        expect(
          runs.where((painted) => painted).length,
          greaterThan(4),
          reason: 'the $name chart painted no bars on this row at all',
        );
        expect(
          _widestInnerGap(runs),
          greaterThanOrEqualTo(3),
          reason: 'the $name chart drew its two bars flush together',
        );
      });
    }
  });

  group('the running balance chart actually paints', () {
    // THE BUG. A month whose only recorded day is the 2nd gives the line ONE
    // spot. `isCurved: true` cannot interpolate a single point, so no path is
    // built and the page renders as a title, a sentence, and an empty box.
    testWidgets('paints with a single recorded day', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      await tester.pumpWidget(
        _host(
          CumulativeBalanceChart(
            days: [DayTotal(date: _oneDay, income: 5150, expenses: 4126.75)],
            currencySymbol: 'Rs. ',
          ),
          surface,
        ),
      );
      await settleUi(tester);

      final painted = await _paintedPixels(
        tester,
        tester.getRect(find.byType(LineChart)),
        surface,
      );

      expect(
        painted,
        greaterThan(200),
        reason: 'a single-day running balance drew no line at all',
      );
    });

    testWidgets('labels a single day ONCE, not three times', (tester) async {
      // THE DEVICE SHOWED "2/10  2/10  2/10" under one dot.
      //
      // One spot is given half a day of air at each end so it is not clipped
      // against the left edge, and that axis is -0.5 to 0.5 -- every stop on it
      // is fractional, and `toInt()` truncates towards zero, so -0.5, 0.0 and
      // 0.5 all became "the first point". The same date three times reads as a
      // rendering fault even though the chart is correct.
      usePhoneLayout(tester, TestViewports.phonePortrait);

      await tester.pumpWidget(
        _host(
          CumulativeBalanceChart(
            days: [DayTotal(date: _oneDay, income: 5150, expenses: 4126.75)],
            currencySymbol: 'Rs. ',
          ),
          surface,
        ),
      );
      await settleUi(tester);

      final label = '${_oneDay.day}/${_oneDay.month}';
      expect(
        find.text(label),
        findsOneWidget,
        reason: 'the one recorded date is drawn $label more than once',
      );
    });

    testWidgets('paints across a full month', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final days = [
        for (var d = 1; d <= 28; d++)
          DayTotal(
            date: DateTime(2026, 8, d),
            income: d == 1 ? 5000 : 0,
            expenses: d.isEven ? 120 : 0,
          ),
      ];

      await tester.pumpWidget(
        _host(
          CumulativeBalanceChart(days: days, currencySymbol: 'Rs. '),
          surface,
        ),
      );
      await settleUi(tester);

      final painted = await _paintedPixels(
        tester,
        tester.getRect(find.byType(LineChart)),
        surface,
      );

      expect(painted, greaterThan(500));
    });
  });

  group('the end date labels are not clipped', () {
    // The device showed a running balance page carrying a bare "10" floating at
    // the left edge: the "2/10" first-point label, centred on x = 0 and
    // therefore half outside the plot. `textAlign` cannot fix that, because the
    // clipping happens OUTSIDE the Text.
    testWidgets('both end labels sit inside the chart box', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final days = [
        for (var d = 1; d <= 28; d++)
          DayTotal(
            date: DateTime(2026, 8, d),
            income: d == 1 ? 5000 : 0,
            expenses: d.isEven ? 120 : 0,
          ),
      ];

      await tester.pumpWidget(
        _host(
          CumulativeBalanceChart(days: days, currencySymbol: 'Rs. '),
          surface,
        ),
      );
      await settleUi(tester);

      final chart = tester.getRect(find.byType(LineChart));

      for (final label in ['1/8', '28/8']) {
        final found = find.text(label);
        expect(found, findsOneWidget, reason: '$label is missing');
        final rect = tester.getRect(found);
        expect(
          rect.left,
          greaterThanOrEqualTo(chart.left - 0.5),
          reason: '$label starts left of the chart',
        );
        expect(
          rect.right,
          lessThanOrEqualTo(chart.right + 0.5),
          reason: '$label runs past the right of the chart',
        );
      }
    });
  });

  centeringTests();
}

// -----------------------------------------------------------------------------
// VERTICAL CENTRING
// -----------------------------------------------------------------------------

/// The four real pages, in the order the pager shows them, with the finder that
/// locates each one's actual content.
///
/// A [KeyedSubtree] has no render object of its own, so asking for the page by
/// its key measures the nearest ancestor that does — the page viewport — and
/// every page comes out 280 tall and "centred" whether or not it is. These
/// finders name the page widget itself, so the rect is the content's rect.
List<(Widget, Finder Function())> _pagerPages() => [
  (
    SpendingHeatmap(days: _busyMonth(), currencySymbol: 'Rs. '),
    () => find.byType(SpendingHeatmap),
  ),
  (
    DailyTotalsChart(days: _busyMonth(), currencySymbol: 'Rs. '),
    () => find.byType(DailyTotalsChart),
  ),
  (
    CumulativeBalanceChart(days: _busyMonth(), currencySymbol: 'Rs. '),
    () => find.byType(CumulativeBalanceChart),
  ),
  (
    WeeklyTotalsChart(days: _busyMonth(), currencySymbol: 'Rs. '),
    () => find.byType(WeeklyTotalsChart),
  ),
];

List<DayTotal> _busyMonth() => [
  for (var d = 1; d <= 28; d++)
    DayTotal(
      date: DateTime(2026, 8, d),
      income: d == 1 ? 5000 : 0,
      expenses: d % 3 == 0 ? 300 : 0,
    ),
];

void centeringTests() {
  group('every chart page sits centred in the pager box', () {
    // THE BUG. One 280-pixel box holds pages that measure 214 to 266, hung from
    // its top edge, so the short ones showed a band of empty card underneath and
    // read as "too high" in a card with room to spare.
    for (final (page, label) in <(int, String)>[
      (0, 'Heatmap'),
      (1, 'Daily'),
      (2, 'Balance'),
      (3, 'Weekly'),
    ]) {
      for (final viewport in [
        TestViewports.phonePortrait,
        TestViewports.phoneSmall,
      ]) {
        testWidgets('${page + 1} $label is centred at $viewport', (
          tester,
        ) async {
          usePhoneLayout(tester, viewport);

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: ChartPager(
                    pages: [for (final (page, _) in _pagerPages()) page],
                    labels: const ['Heatmap', 'Daily', 'Balance', 'Weekly'],
                  ),
                ),
              ),
            ),
          );
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }

          await tester.tap(find.byKey(ValueKey('chart-dot-$page')));
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }

          final box = tester.getRect(
            find.byKey(const ValueKey('chart-page-box')),
          );
          final content = tester.getRect(_pagerPages()[page].$2());

          final above = content.top - box.top;
          final below = box.bottom - content.bottom;

          expect(
            (above - below).abs(),
            lessThanOrEqualTo(1.0),
            reason:
                'page ${page + 1} ($label) has $above above it and $below below',
          );

          // The margin check above is `above == below`, which a page that FILLS
          // the box satisfies for free -- and all four pages now fill it, because
          // their plots are `Expanded` and absorb the slack rather than leaving
          // it in one band underneath. That was the defect, and it is now fixed
          // at the source.
          //
          // So this group is a REGRESSION GUARD rather than the primary check:
          // if a page ever becomes content-sized again, its slack must land
          // evenly above and below. The invariant that actually catches clipping
          // is in `chart_text_overlap_test.dart`, which drives real text scales.
          expect(
            content.height,
            lessThanOrEqualTo(box.height + 0.5),
            reason: '$label is taller than the pager box',
          );
        });
      }
    }
  });

  testWidgets('no bar paints over the heading above it', (tester) async {
    // SENTINEL ROD COLOURS. The real palette cannot carry this test: in the
    // dark theme `primary` IS the cream the heading is drawn in, and the muted
    // body text sits within a couple of channels of `tertiary`, so any
    // colour-match for "a bar got here" also matches the words that are
    // supposed to be there. Cyan and magenta appear nowhere in this theme, so
    // a pixel of either in the heading's rows can only have come from a rod.
    final theme = AppTheme.dark();
    final sentinels = theme.colorScheme.copyWith(
      primary: const Color(0xFF00FFFF),
      tertiary: const Color(0xFFFF00FF),
    );

    for (final scale in [1.0, 1.5, 2.0]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme.copyWith(colorScheme: sentinels),
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: RepaintBoundary(
                  key: const ValueKey('capture'),
                  // The pager's own fixed box, so this reproduces the device's
                  // constraint rather than an unbounded one.
                  child: SizedBox(
                    height: ChartPager.pageHeight,
                    child: DailyTotalsChart(
                      days: _september,
                      currencySymbol: 'Rs. ',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await settleUi(tester);
      expect(tester.takeException(), isNull);

      final boundary = tester.getRect(find.byKey(const ValueKey('capture')));
      final title = tester.getRect(find.text('In and out, by day'));
      final plot = tester.getRect(find.byType(BarChart));
      // The heading's rows, in the captured image's own coordinates. Bounded on
      // the right by the plot so nothing off to the side is counted.
      final band = Rect.fromLTRB(
        0,
        0,
        plot.right - boundary.left,
        title.bottom - boundary.top,
      );

      for (final (name, colour) in [
        ('income', sentinels.primary),
        ('expense', sentinels.tertiary),
      ]) {
        final hits = await _pixelsNear(tester, band, colour, tolerance: 8);
        expect(
          hits,
          0,
          reason:
              'the $name rod colour covers $hits px of the heading\'s rows at '
              'text scale $scale -- a bar is painting over the heading',
        );
      }
    }
  });
}
