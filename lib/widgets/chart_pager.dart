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
    this.height = _defaultHeight,
    this.labels = const <String>[],
  });

  /// One widget per page, in order.
  final List<Widget> pages;

  /// A short name per page, shown beside the count. Optional: an empty list
  /// falls back to the count alone.
  final List<String> labels;

  /// A fixed height, because a PageView sizes to its tallest child and letting
  /// it do that makes the page jump when the user swipes past a shorter chart.
  ///
  /// Tall enough for the tallest chart plus its title, key and caption.
  final double height;

  static const double _defaultHeight = 268;

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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = widget.pages.length;
    if (count == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: widget.height,
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
                child: widget.pages[i],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        // The indicator row.
        //
        // The dots go first at their natural width and the count label takes
        // what is left. Sized last, the label is the one element here whose
        // text length is not known in advance — "1 of 3 · Weekly" against a
        // long label — and a Row will overflow by a pixel rather than shrink
        // it. A Wrap around the dots only made it worse: Wrap has its own
        // intrinsic width and would not yield either.
        Row(
          children: [
            for (var i = 0; i < count; i++)
              _Dot(index: i, selected: i == _index, onTap: () => _goTo(i)),
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
    );
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
