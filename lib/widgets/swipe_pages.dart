import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:daily_companion/theme/app_theme.dart';

import 'page_indicator.dart';

/// One page at a time, swiped horizontally, with tappable dots — and a box that
/// is as tall as the page it is showing.
///
/// WHY NOT A [PageView]. `PageView` lays its children out inside a viewport, so
/// it has to be told how tall that viewport is, and one number has to fit every
/// page. The category breakdowns cannot: the card measures 216 pixels plus 22
/// per category, so a month with two categories needs 260 and a month with all
/// nine needs 414. A fixed box tall enough for the worst case leaves two hundred
/// pixels of empty card under a two-category month, and one tall enough for the
/// month on screen clips as soon as somebody spends in a seventh category — which
/// is the exact pair of failures the chart pager was measured to avoid.
///
/// Measuring the pages to size the box needs them laid out off-screen, which
/// means a second copy of every page in the tree. That was tried on
/// [ChartPager] and produced a stale number that clipped a page.
///
/// So the height follows the page instead. The content is swapped with an
/// [AnimatedSize] around it, which animates the box as the pages swap, so
/// nothing below the dots jumps and a short page is never padded to a tall one's
/// height. The gesture, the dots and the spoken count are the same as the chart
/// pager's, so the two controls do not feel like different products.
class SwipePages extends StatefulWidget {
  const SwipePages({
    super.key,
    required this.pages,
    this.labels = const <String>[],
    this.gap = AppSpacing.md,
    this.countOnTheLeft = false,
  });

  /// Puts the count label before the dots instead of after them.
  ///
  /// A floating action button occupies the bottom-RIGHT of a phone screen, so a
  /// count label on the right of this row is a label the button will cover at
  /// exactly the moment the button comes back -- which is the moment the user is
  /// looking at it. On the left it is clear of anything that floats.
  final bool countOnTheLeft;

  final List<Widget> pages;
  final List<String> labels;

  /// The breathing room between the content and the dots.
  final double gap;

  @override
  State<SwipePages> createState() => _SwipePagesState();
}

class _SwipePagesState extends State<SwipePages> {
  int _index = 0;

  /// How far a drag has to travel in TOTAL before it counts as a page change.
  ///
  /// Accumulated across the whole gesture, not measured per event. A drag
  /// arrives as a stream of small deltas, so testing each one against the
  /// threshold asks a single event to cover the whole distance and a real swipe
  /// never registers; only a very fast flick delivers a delta that large.
  static const double _dragThreshold = 60;

  /// A flick faster than this changes page regardless of how far it travelled.
  ///
  /// Below this the distance rule decides, so a short deliberate drag and a slow
  /// one behave the same way.
  static const double _flingVelocity = 200;

  /// How far the current drag has travelled, left negative.
  double _dragDistance = 0;

  void _goTo(int i) {
    if (i == _index || i < 0 || i >= widget.pages.length) return;
    HapticFeedback.selectionClick();
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pages.isEmpty) return const SizedBox.shrink();
    final count = widget.pages.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The height follows the page, and ANIMATES between the two heights, so
        // the section below does not jump when the pages have different numbers
        // of categories. `clipBehavior` is hard-edge on purpose: a page taller
        // than the box it is animating out of would otherwise paint over the
        // page replacing it.
        AnimatedSize(
          duration: AppMotion.medium,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: GestureDetector(
            // The swipe area is the PAGE, not the whole widget. The dot row
            // below is its own control and drags on it belong to it.
            //
            // Keyed so a test can aim at it: the centre of the whole widget
            // falls in the gap between the page and the dots, which is claimed by
            // nothing, so a drag aimed at `SwipePages` silently does nothing and
            // looks like a broken gesture rather than a badly aimed one.
            key: const ValueKey('swipe-gesture-area'),
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) => _dragDistance = 0,
            onHorizontalDragUpdate: (details) =>
                _dragDistance += details.delta.dx,
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;

              // The flick wins over the distance, so a quick flick feels instant
              // instead of being ignored for having travelled only a little.
              final travelled = velocity.abs() > _flingVelocity
                  ? velocity
                  : _dragDistance;
              _dragDistance = 0;
              if (travelled.abs() < _dragThreshold) return;
              _goTo(travelled < 0 ? _index + 1 : _index - 1);
            },
            child: KeyedSubtree(
              key: ValueKey('swipe-page-$_index'),
              child: widget.pages[_index],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        PageIndicatorRow(
          keyPrefix: 'swipe',
          count: count,
          index: _index,
          labels: widget.labels,
          countOnTheLeft: widget.countOnTheLeft,
          onSelect: _goTo,
        ),
      ],
    );
  }
}
