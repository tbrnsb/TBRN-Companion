import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_application_1/theme/app_theme.dart';

/// One chart at a time, with tappable page dots.
///
/// The three time-series charts stacked in a column pushed the first transaction
/// row about eleven hundred pixels down, so the screen opened as a wall of
/// graphs and the actual ledger was somewhere below the fold. Splitting them
/// across pages puts one graph on screen at a time and gives the dots room to
/// say how many there are.
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
    this.height,
    this.labels = const <String>[],
  });

  /// One widget per page, in order.
  final List<Widget> pages;

  /// A short name per page, shown beside the count. Optional: an empty list
  /// falls back to the count alone.
  final List<String> labels;

  /// Overrides the measured height. Almost never set: it exists so a test can
  /// pin the box, and so a caller that genuinely knows its height is not made to
  /// wait a frame for it.
  ///
  /// Left null, the pager lays every page out off-screen and takes the TALLEST.
  /// That single number is deliberate, and it is the whole fix for the empty
  /// page this used to show: one height for every page means nothing below the
  /// dots moves while the user is swiping or tapping them.
  ///
  /// The old value was a literal 640, chosen when the heatmap filled the card's
  /// width and genuinely needed the room. Once the heatmap shrank to a
  /// seven-column grid of 11-pixel cells, 640 kept reserving roughly 400 pixels
  /// of nothing under every chart — a hole in the middle of the ledger that read
  /// as a rendering fault rather than as whitespace.
  final double? height;

  /// The height used for the first frame, before anything has been measured.
  ///
  /// Deliberately SMALL. A generous first guess would show the old hole for one
  /// frame and then shrink; a tight one shows a slightly short box and then
  /// grows. Neither is wrong, and the small one cannot be mistaken for the bug
  /// this replaced.
  static const double _firstFrameHeight = 200;

  @override
  State<ChartPager> createState() => _ChartPagerState();
}

class _ChartPagerState extends State<ChartPager> {
  final _controller = PageController();
  int _index = 0;

  /// One key per page, attached to the off-screen copy in [_HeightProbe].
  ///
  /// Stable across rebuilds on purpose: a fresh key each build would throw away
  /// the element and re-lay-out every chart on every frame.
  final _probeKeys = <GlobalKey>[];

  /// The tallest page found so far, or the first-frame guess.
  double _measuredHeight = ChartPager._firstFrameHeight;

  /// The width the current measurement was taken at, so a rotation re-measures
  /// rather than reusing a number derived from the old measure.
  double? _measuredForWidth;

  /// Whether the off-screen measuring pass still needs to be in the tree.
  ///
  /// It is removed as soon as it has done its job. Leaving it there would mean
  /// every chart exists in the widget tree twice, which is not merely wasteful:
  /// "exactly one time-series chart is on screen" is a real invariant, and a
  /// permanent invisible twin makes that assertion a lie.
  bool _needsProbe = true;

  /// How many times the probe has been laid out without yielding a height.
  ///
  /// A page that renders nothing would otherwise keep the probe alive forever.
  int _probeAttempts = 0;

  /// One measurement in flight at a time.
  bool _measurePending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = widget.pages.length;
    if (count == 0) return const SizedBox.shrink();

    while (_probeKeys.length < count) {
      _probeKeys.add(GlobalKey());
    }
    _probeKeys.removeRange(count, _probeKeys.length);

    return LayoutBuilder(
      builder: (context, constraints) {
        // What a page actually gets: the pager's width less the trailing gutter
        // the real PageView applies to each page.
        final pageWidth = constraints.maxWidth - AppSpacing.xs;

        // Measure after layout, not during it: reading a RenderBox mid-build is
        // not safe, and the probe has to have been laid out before its size
        // means anything.
        _scheduleMeasure(pageWidth);

        return Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: widget.height ?? _measuredHeight,
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
                        // A page's identity, so a rebuild does not reuse the
                        // previous page's element and leave a chart painted
                        // twice.
                        key: ValueKey('chart-page-$i'),
                        child: widget.pages[i],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                // The indicator row.
                //
                // The dots go first at their natural width and the count label
                // takes what is left. Sized last, the label is the one element
                // here whose text length is not known in advance — "1 of 3 ·
                // Weekly" against a long label — and a Row will overflow by a
                // pixel rather than shrink it. A Wrap around the dots only made
                // it worse: Wrap has its own intrinsic width and would not
                // yield either.
                Row(
                  children: [
                    for (var i = 0; i < count; i++)
                      _Dot(
                        index: i,
                        selected: i == _index,
                        onTap: () => _goTo(i),
                      ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        _countLabel(),
                        key: const ValueKey('chart-pager-count'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            // The measuring pass, in the same Stack so it cannot add a pixel to
            // the column above it. Present only until it has a number.
            if (_needsProbe)
              Positioned(
                left: 0,
                top: 0,
                child: _HeightProbe(
                  pages: widget.pages,
                  keys: _probeKeys,
                  width: pageWidth,
                ),
              ),
          ],
        );
      },
    );
  }

  /// Queues one measurement for the end of the frame.
  ///
  /// Re-runs whenever the pages are rebuilt, because a chart's natural height
  /// depends on its own content — a longer caption, a bigger number — and a
  /// height cached from last month is a height waiting to be wrong. The result
  /// is only pushed into state when it has actually moved, so the common case
  /// costs a size read and no rebuild.
  void _scheduleMeasure(double width) {
    if (widget.height != null) return;
    if (width != _measuredForWidth) {
      // A different measure means every page's height is a different number.
      _measuredForWidth = width;
      _needsProbe = true;
      _probeAttempts = 0;
      _measuredHeight = ChartPager._firstFrameHeight;
    }
    if (!_needsProbe || _measurePending) return;
    _measurePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurePending = false;
      if (!mounted) return;
      _readHeights();
    });
  }

  /// The tallest page, from boxes that have already been laid out.
  void _readHeights() {
    var tallest = 0.0;
    for (final key in _probeKeys) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      final height = box?.size.height ?? 0;
      if (height > tallest) tallest = height;
    }
    // Zero means the probe has not been laid out yet, or the pages render
    // nothing. Either way, keeping the current height beats collapsing the box
    // and making the whole section jump.
    if (tallest <= 0) {
      if (++_probeAttempts > 3) {
        // Nothing measurable after several layouts. Stop paying for the probe
        // and leave the first-frame height in place.
        setState(() => _needsProbe = false);
      }
      return;
    }
    if ((tallest - _measuredHeight).abs() < 0.5) {
      // Already correct. Retire the probe without a rebuild of the box.
      if (_needsProbe) setState(() => _needsProbe = false);
      return;
    }
    setState(() {
      _measuredHeight = tallest;
      _needsProbe = false;
    });
  }

  /// "2 of 3 · Daily" — the count in words, and which chart this is.
  String _countLabel() {
    final position = '${_index + 1} of ${widget.pages.length}';
    if (_index < widget.labels.length && widget.labels[_index].isNotEmpty) {
      return '$position · ${widget.labels[_index]}';
    }
    return position;
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

/// Every page, laid out for real and then hidden.
///
/// The pager cannot size itself to a `PageView`, because a `PageView` only lays
/// out the page you are on and its two neighbours — so at page one of four, the
/// height of page four is genuinely not knowable from inside the pager. This is
/// how it becomes knowable: all four pages are built once, off-screen, at
/// exactly the width the real pages get, and their heights are read back.
///
/// `Opacity` at zero rather than `Offstage`, because `Offstage` skips layout
/// entirely and would report nothing. `IgnorePointer` because an invisible page
/// must not be tappable or reachable by a screen reader.
class _HeightProbe extends StatelessWidget {
  const _HeightProbe({
    required this.pages,
    required this.keys,
    required this.width,
  });

  final List<Widget> pages;
  final List<GlobalKey> keys;
  final double width;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: 0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < pages.length; i++)
              SizedBox(
                // The key sits on the box whose height IS the page's height: a
                // Column hands its children unbounded height, so this sizes to
                // the chart rather than to a constraint.
                key: keys[i],
                width: width,
                child: pages[i],
              ),
          ],
        ),
      ),
    );
  }
}

/// One tappable page dot.
class _Dot extends StatelessWidget {
  const _Dot({
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final bool selected;
  final VoidCallback onTap;

  /// The tap target is a fixed-width box around the pip, not the pip itself.
  ///
  /// Sized rather than padded on purpose. Padding the pip up to a 32-pixel
  /// target made a row of three exactly one pixel too wide at 360dp; a fixed
  /// width gets the same target without the row's arithmetic depending on it.
  static const double _targetWidth = AppSpacing.xl + AppSpacing.xs;

  /// The alpha an inactive page dot is painted at. See the call site for the
  /// measurement behind it.
  static const double inactiveDotAlpha = 0.75;
  static const double _targetHeight = AppSpacing.lg;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: _targetWidth,
      height: _targetHeight,
      child: Semantics(
        button: true,
        selected: selected,
        label: 'Chart ${index + 1}',
        child: InkWell(
          key: ValueKey('chart-dot-$index'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.small),
          child: Center(
            child: AnimatedContainer(
              duration: AppMotion.fast,
              width: selected ? AppSpacing.sm : AppSpacing.xs,
              height: AppSpacing.xs,
              decoration: BoxDecoration(
                // Measured, not guessed. At the 0.35 this used, an inactive dot
                // composited to **1.63:1 on cream and 2.25:1 on Gruvbox** — the
                // single worst offender in the app, and the "nearly invisible" a
                // swipe control gets judged on. 0.75 is the lowest alpha that
                // clears 3:1 (the non-text floor) in all six specs; measured, it
                // gives 3.22 on Latte and 3.40 on cream.
                //
                // It stays clearly quieter than the active dot, which is full
                // strength `primary`. An inactive indicator needs to be findable,
                // not to shout.
                color: selected
                    ? scheme.primary
                    : scheme.onSurfaceVariant.withValues(
                        alpha: inactiveDotAlpha,
                      ),
                borderRadius: BorderRadius.circular(AppSpacing.xxs),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
