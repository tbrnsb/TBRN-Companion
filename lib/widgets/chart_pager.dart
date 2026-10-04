import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:daily_companion/theme/app_theme.dart';

import 'page_indicator.dart';

/// One chart at a time, with tappable page dots.
///
/// The three time-series charts stacked in a column pushed the first transaction
/// row about eleven hundred pixels down, so the screen opened as a wall of graphs
/// and the actual ledger was somewhere below the fold. Splitting them across
/// pages puts one graph on screen at a time and gives the dots room to say how
/// many there are.
///
/// NEVER put two charts side by side here. At 360dp that is about 165 pixels
/// each, and the donut alone is already 132 — two of them would be unreadable
/// rather than compact.
///
/// The dots are tappable and labelled. A carousel whose only way forward is a
/// swipe has no affordance, and nobody finds page two. The count is spelled out
/// in words as well, so it does not depend on recognising a row of pips.
class ChartPager extends StatefulWidget {
  const ChartPager({
    super.key,
    required this.pages,
    this.height = pageHeight,
    this.labels = const <String>[],
  });

  /// One widget per page, in order.
  final List<Widget> pages;

  /// A short name per page, shown beside the count. Optional: an empty list
  /// falls back to the count alone.
  final List<String> labels;

  /// Overrides the computed box height. Almost never set; it exists so a test
  /// can pin the box, and so a caller that genuinely knows its height need not
  /// ask.
  final double height;

  /// The most the box is allowed to grow for a large system font.
  ///
  /// A chart page is mostly TEXT -- a title, a legend, a caption -- so a bigger
  /// font needs a bigger box or the plot is drawn over its own heading. The
  /// pages themselves ask for no more room than they are given ([Expanded] plots,
  /// see `spend_trend_cards.dart`), so the box growing is what keeps them from
  /// overflowing rather than trading one clipping problem for another.
  ///
  /// CLAMPED, because at a 2x font an unclamped box is a full screen of chart and
  /// the page below it is pushed off; past this the page is allowed to be cramped
  /// rather than unbounded.
  static const double maxTextScaleGrowth = 1.6;

  /// One height for every page, so nothing below the dots moves while the user
  /// swipes or taps them. Per-page heights were tried and abandoned: measuring
  /// them needs the pages laid out unconstrained off-screen, which means a second
  /// copy of every chart in the tree, and the two attempts at it produced a
  /// stale number that clipped a page and then a layout that fought itself.
  ///
  /// This is the number the device produced, not a guess. Measured per page at
  /// 412dp: heatmap 226, daily 228, balance 214, weekly 266 — the weekly page is
  /// the tallest because its caption wraps to two lines. Rounded up to 280 for
  /// headroom, which is still 360 pixels less than the 640 this used to reserve
  /// and showed as a hole under every chart.
  ///
  /// `chart_pager_test.dart` asserts that no page overflows this box at either
  /// viewport, so a chart that grows past it fails a test instead of silently
  /// clipping.
  /// 300 rather than 280.
  ///
  /// The heatmap gained a weekday header row above its grid -- seven letters so
  /// the columns can be named, which is what makes it a calendar rather than a
  /// texture -- and that row is about twenty pixels of page. At 280 the heatmap
  /// overflowed its slot by ten, which on a device is a black-and-yellow stripe
  /// across the bottom of the calendar.
  ///
  /// Raising the constant rather than shrinking the header, because the header is
  /// the fix for a real defect and 280 is only a number that happened to fit the
  /// four OLDEST pages. The `lessThan(320)` budget in `chart_pager_test.dart`
  /// still holds with twenty pixels of room in it, so the next page that needs
  /// more has to spend that budget rather than assume it.
  static const double pageHeight = 300;

  @override
  State<ChartPager> createState() => _ChartPagerState();
}

class _ChartPagerState extends State<ChartPager> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.pages.length;
    if (count == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          key: const ValueKey('chart-page-box'),
          height: _boxHeight(context),
          child: PageView.builder(
            controller: _controller,
            itemCount: count,
            onPageChanged: (i) {
              HapticFeedback.selectionClick();
              setState(() => _index = i);
            },
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: KeyedSubtree(
                // A page's identity, so a rebuild does not reuse the previous
                // page's element and leave a chart painted twice.
                key: ValueKey('chart-page-$i'),
                // CLIPPED, then centred.
                //
                // The clip is the guarantee, and it is here because a plot that
                // is taller than its slot used to be painted OVER the heading
                // above it. A page now fills its slot exactly, so this normally
                // clips nothing at all -- but `Center` on a child that somehow
                // exceeds its box still spills, and spilling upwards is what
                // put bars through "In and out, by day". Clipped to the slot, the
                // worst a too-tall page can do is lose its own bottom edge.
                child: ClipRect(child: Center(child: widget.pages[i])),
                // CENTRED IN THE BOX, not hung from its top edge.
                //
                // Every page shares one 280-pixel box so nothing below the dots
                // moves as the user swipes, but the pages are not all 280 tall:
                // the device measured heatmap 226, balance 214, weekly 266. Hung
                // from the top, the short pages left a band of empty card under
                // the last element — up to 66 pixels of nothing — and the charts
                // read as sitting too high in a card that had room below them.
                // Centring puts the whitespace in the two margins where it looks
                // deliberate instead of in one gap underneath where it looks
                // like the chart failed to fill its box.
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        PageIndicatorRow(
          keyPrefix: 'chart',
          count: count,
          index: _index,
          labels: widget.labels,
          onSelect: _goTo,
        ),
      ],
    );
  }

  /// The box height for this text scale.
  ///
  /// Grows with the system font, clamped, because a chart page is mostly text and
  /// a fixed box draws the plot over its own heading once the text outgrows it.
  /// The pages ask for no more than they are given -- their plots are
  /// [Expanded] -- so the extra room is absorbed by the plot rather than being
  /// clipped, and nothing below the dots moves.
  double _boxHeight(BuildContext context) {
    // A caller that PINNED a height keeps it: the height is then a fact about
    // that caller, not a default to be second-guessed by the ambient font.
    if (widget.height != ChartPager.pageHeight) return widget.height;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return ChartPager.pageHeight *
        scale.clamp(1.0, ChartPager.maxTextScaleGrowth);
  }

  void _goTo(int i) {
    if (i == _index) return;
    HapticFeedback.selectionClick();
    // animateToPage rather than jumpTo: a jump leaves the previous page
    // half-scrolled, which looks like a rendering fault.
    _controller.animateToPage(
      i,
      duration: AppMotion.medium,
      curve: Curves.easeOutCubic,
    );
    setState(() => _index = i);
  }
}
