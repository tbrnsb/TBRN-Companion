import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:daily_companion/theme/app_theme.dart';

/// One tappable page dot, shared by every pager in the app.
///
/// Lives here rather than inside [ChartPager] because there is more than one
/// pager now, and two copies of a control is how a screen ends up with a row of
/// pips that look subtly different from the row above it.
class PageDot extends StatelessWidget {
  const PageDot({
    super.key,
    required this.index,
    required this.selected,
    required this.onTap,
    this.keyPrefix = 'page',
  });

  final int index;
  final bool selected;
  final VoidCallback onTap;

  /// Namespaces the dot's key.
  ///
  /// Two pagers on one screen both have a dot 0, a dot 1 and so on, so a shared
  /// key makes `find.byKey` ambiguous and a test that taps "the second dot" taps
  /// whichever it happens to hit first. Each pager passes its own prefix.
  final String keyPrefix;

  /// The tap target is a fixed-width box around the pip, not the pip itself.
  ///
  /// Sized rather than padded on purpose. Padding the pip up to a 32-pixel
  /// target made a row of three exactly one pixel too wide at 360dp; a fixed
  /// width gets the same target without the row's arithmetic depending on it.
  static const double _targetWidth = AppSpacing.xl + AppSpacing.xs;
  static const double _targetHeight = AppSpacing.lg;

  /// The alpha an inactive page dot is painted at.
  ///
  /// Measured, not guessed. At the 0.35 this used, an inactive dot composited to
  /// **1.63:1 on cream and 2.25:1 on Gruvbox** — the single worst offender in
  /// the app, and the "nearly invisible" a swipe control gets judged on. 0.75 is
  /// the lowest alpha that clears 3:1 (the non-text floor) in all six specs;
  /// measured, it gives 3.22 on Latte and 3.40 on cream.
  ///
  /// It stays clearly quieter than the active dot, which is full strength
  /// `primary`. An inactive indicator needs to be findable, not to shout.
  static const double inactiveDotAlpha = 0.75;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: _targetWidth,
      height: _targetHeight,
      child: Semantics(
        button: true,
        selected: selected,
        label: 'Page ${index + 1}',
        child: InkWell(
          key: ValueKey('$keyPrefix-dot-$index'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.small),
          child: Center(
            child: AnimatedContainer(
              duration: AppMotion.fast,
              width: selected ? AppSpacing.sm : AppSpacing.xs,
              height: AppSpacing.xs,
              decoration: BoxDecoration(
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

/// The dot row plus the "2 of 3 · Label" count, shared by every pager.
///
/// The dots go first at their natural width and the count label takes what is
/// left. Sized last, the label is the one element here whose text length is not
/// known in advance — "1 of 4 · Heatmap" against a long label — and a Row will
/// overflow by a pixel rather than shrink it.
class PageIndicatorRow extends StatelessWidget {
  const PageIndicatorRow({
    super.key,
    required this.count,
    required this.index,
    required this.labels,
    required this.onSelect,
    this.keyPrefix = 'page',
    this.countOnTheLeft = false,
  });

  /// See [SwipePages.countOnTheLeft].
  final bool countOnTheLeft;

  final int count;
  final int index;
  final List<String> labels;
  final ValueChanged<int> onSelect;

  /// See [PageDot.keyPrefix].
  final String keyPrefix;

  /// "2 of 3 · Daily" — the count in words, and what this page is.
  String get countLabel {
    final position = '${index + 1} of $count';
    if (index < labels.length && labels[index].isNotEmpty) {
      return '$position · ${labels[index]}';
    }
    return position;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final label = Text(
      countLabel,
      key: ValueKey('$keyPrefix-indicator-count'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: countOnTheLeft ? TextAlign.start : TextAlign.end,
      style: theme.textTheme.labelMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    );

    return Row(
      children: [
        // The count FIRST when something floats over the right of the screen.
        //
        // `Flexible` in BOTH orders, not `Expanded` in one of them. Expanded
        // stretches the label to fill whatever the dots left, so moving the
        // label from right to left would have changed its width by the width of
        // the dots and made the two versions of this row visibly different
        // sizes. Flexible lets it take exactly what it needs in either position,
        // and the leftover space falls at the end of the row both times.
        if (countOnTheLeft) ...[
          Flexible(child: label),
          const SizedBox(width: AppSpacing.xs),
        ],
        for (var i = 0; i < count; i++)
          PageDot(
            keyPrefix: keyPrefix,
            index: i,
            selected: i == index,
            onTap: () {
              if (i == index) return;
              HapticFeedback.selectionClick();
              onSelect(i);
            },
          ),
        if (!countOnTheLeft) ...[
          const SizedBox(width: AppSpacing.xs),
          Flexible(child: label),
        ],
      ],
    );
  }
}
