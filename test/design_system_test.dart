import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/widgets/app_motion.dart';

import 'test_viewports.dart';

void main() {
  group('surface tiers', () {
    testWidgets('a surface is an ink surface, not a decorated box', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: AppSurface(
              tier: AppSurfaceTier.raised,
              child: ListTile(
                title: const Text('A tile on a surface'),
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // A Container with a background colour is not an ink surface, so the
      // ListTile's own background and splashes would be hidden by it and
      // Flutter throws "ListTile background color or ink splashes may be
      // invisible". This asserts the surface is built on a Material.
      expect(tester.takeException(), isNull);

      // The nearest Material ancestor of the tile is the surface itself.
      final tileMaterial = tester.widget<Material>(
        find
            .ancestor(
              of: find.text('A tile on a surface'),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(tileMaterial.type, MaterialType.canvas);
    });

    testWidgets('each tier produces a distinct fill', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final scheme = AppTheme.light().colorScheme;
      final flat = AppSurfaces.specFor(AppSurfaceTier.flat, scheme);
      final raised = AppSurfaces.specFor(AppSurfaceTier.raised, scheme);
      final accent = AppSurfaces.specFor(AppSurfaceTier.accent, scheme);

      // The whole point of three tiers: if they all resolved to the same
      // colour there would be no hierarchy, which is what the app looked like
      // when every card was the same flat outlined box.
      expect(flat.color, isNot(raised.color));
      expect(raised.color, isNot(accent.color));
      expect(flat.color, isNot(accent.color));

      // flat has no border, raised does, accent is a tonal container.
      expect(flat.border.style, BorderStyle.none);
      expect(raised.border.style, BorderStyle.solid);
      expect(accent.color, scheme.primaryContainer);
    });

    testWidgets('every tier works in dark mode too', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      final scheme = AppTheme.dark().colorScheme;
      for (final tier in AppSurfaceTier.values) {
        final spec = AppSurfaces.specFor(tier, scheme);
        expect(spec.color, isNotNull, reason: '$tier has no dark fill');
      }
    });
  });

  group('type scale', () {
    test('supporting text is clearly lighter than the headline', () {
      final theme = AppTheme.light();
      final text = theme.textTheme;

      // The app used to run on three sizes, so nothing was a headline. The
      // scale has to have real size distance between the two ends of it.
      expect(
        text.displayMedium!.fontSize!,
        greaterThan(text.titleSmall!.fontSize!),
      );
      expect(
        text.displayMedium!.fontSize!,
        greaterThan(text.bodySmall!.fontSize!),
      );

      // And weight contrast, so the eye has something to land on.
      expect(
        text.displayMedium!.fontWeight!.value,
        greaterThan(text.titleMedium!.fontWeight!.value),
      );
      expect(
        text.titleMedium!.fontWeight!.value,
        greaterThan(text.bodySmall!.fontWeight!.value),
      );
    });

    test('every style states its own size, in both brightnesses', () {
      // In this Flutter version every fontSize in the default text theme is
      // null and only appears when a style is merged against the platform
      // default at paint time. A scale that relies on that has no guaranteed
      // size contrast, so every role states its own.
      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        for (final entry in {
          'displayMedium': theme.textTheme.displayMedium,
          'headlineMedium': theme.textTheme.headlineMedium,
          'titleMedium': theme.textTheme.titleMedium,
          'titleSmall': theme.textTheme.titleSmall,
          'bodyLarge': theme.textTheme.bodyLarge,
          'bodyMedium': theme.textTheme.bodyMedium,
          'bodySmall': theme.textTheme.bodySmall,
          'labelLarge': theme.textTheme.labelLarge,
          'labelMedium': theme.textTheme.labelMedium,
        }.entries) {
          expect(entry.value, isNotNull, reason: '${entry.key} is missing');
          expect(
            entry.value!.fontSize,
            isNotNull,
            reason: '${entry.key} has no size of its own',
          );
          expect(
            entry.value!.color,
            isNotNull,
            reason: '${entry.key} has no colour of its own',
          );
        }
      }
    });
  });

  group('motion', () {
    test('durations stay inside the 150-250ms band', () {
      // Nothing bouncy and nothing slow: a tap that takes longer than 250ms to
      // acknowledge feels broken, not smooth.
      expect(AppMotion.fast.inMilliseconds, inInclusiveRange(150, 250));
      expect(AppMotion.medium.inMilliseconds, inInclusiveRange(150, 250));
    });

    testWidgets('the progress bar eases to its new value', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      Widget bar(double value) => MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 200, child: AppProgressBar(value: value)),
          ),
        ),
      );

      await tester.pumpWidget(bar(0));
      await tester.pumpAndSettle();

      await tester.pumpWidget(bar(1));
      // Mid-transition the bar must be part-way, not snapped to its target.
      await tester.pump(const Duration(milliseconds: 90));
      final mid = tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value!;
      expect(mid, greaterThan(0));
      expect(mid, lessThan(1));

      await tester.pumpAndSettle();
      final done = tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value!;
      expect(done, closeTo(1, 0.001));
    });

    testWidgets('the progress bar clamps an out-of-range value', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: Center(child: AppProgressBar(value: 4.2))),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final value = tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value!;
      expect(value, lessThanOrEqualTo(1));
    });
  });
}
