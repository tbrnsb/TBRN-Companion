import 'package:flutter/material.dart';

import 'package:daily_companion/theme/app_theme.dart';

/// A progress bar that eases to its new value instead of jumping.
///
/// [LinearProgressIndicator] paints whatever value it is given on the frame it
/// is rebuilt, so checking an item made the bar snap from 0% to 40%. Easing it
/// over [AppMotion.fast] is the difference between a bar that reads as
/// responding and one that reads as glitching.
class AppProgressBar extends StatelessWidget {
  const AppProgressBar({super.key, required this.value, this.minHeight = 6});

  /// 0.0 to 1.0. Values outside that range are clamped, because a negative
  /// tween target is not something the bar can draw.
  final double value;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final target = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    final colorScheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(minHeight),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: target),
        duration: AppMotion.fast,
        curve: Curves.easeOut,
        builder: (context, animated, _) => LinearProgressIndicator(
          value: animated,
          minHeight: minHeight,
          backgroundColor: colorScheme.surfaceContainerHighest,
          valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
        ),
      ),
    );
  }
}

/// A checklist item's label, which fades and strikes through when checked.
///
/// Wrapping the label rather than swapping it keeps the row from jumping, and
/// the fade is what makes checking read as a transition instead of a redraw.
class AppCheckableLabel extends StatelessWidget {
  const AppCheckableLabel({
    super.key,
    required this.text,
    required this.checked,
  });

  final String text;
  final bool checked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return AnimatedDefaultTextStyle(
      duration: AppMotion.fast,
      curve: Curves.easeOut,
      style: theme.textTheme.bodyLarge!.copyWith(
        color: checked ? muted : theme.colorScheme.onSurface,
        decoration: checked ? TextDecoration.lineThrough : TextDecoration.none,
        decorationColor: muted,
      ),
      child: AnimatedOpacity(
        duration: AppMotion.fast,
        curve: Curves.easeOut,
        opacity: checked ? 0.7 : 1.0,
        child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
