import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daily_companion/models/expense_category_meta.dart';
import 'package:daily_companion/theme/app_theme.dart';
import 'package:daily_companion/widgets/spend_breakdown_card.dart';
import 'package:daily_companion/widgets/swipe_pages.dart';

import 'test_viewports.dart';

Future<void> settleUi(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

List<BreakdownSegment> _segments(int n) {
  final all = CategoryRegistry.expenseCategories();
  return [
    for (var i = 0; i < n && i < all.length; i++)
      BreakdownSegment(meta: all[i], amount: 1000.0 - i * 100),
  ];
}

Widget _card(String title, int rows) => SpendBreakdownCard(
  title: title,
  segments: _segments(rows),
  currencySymbol: 'Rs. ',
);

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.dark(),
  home: Scaffold(
    body: SingleChildScrollView(
      padding: AppSpacing.screenPadding,
      child: child,
    ),
  ),
);

double _heightOf(WidgetTester tester) =>
    tester.getSize(find.byType(SwipePages)).height;

void main() {
  group('a swipe changes page', () {
    for (final viewport in [
      TestViewports.phonePortrait,
      TestViewports.phoneSmall,
    ]) {
      testWidgets('left then right at $viewport', (tester) async {
        usePhoneLayout(tester, viewport);
        await tester.pumpWidget(
          _host(
            const SwipePages(
              labels: ['Spending', 'Income'],
              pages: [Text('SPEND'), Text('INCOME')],
            ),
          ),
        );
        await settleUi(tester);

        expect(find.text('SPEND'), findsOneWidget);
        expect(find.text('1 of 2 · Spending'), findsOneWidget);

        await tester.fling(
          find.byKey(const ValueKey('swipe-gesture-area')),
          const Offset(-220, 0),
          900,
        );
        await settleUi(tester);
        expect(find.text('INCOME'), findsOneWidget);
        expect(find.text('2 of 2 · Income'), findsOneWidget);

        await tester.fling(
          find.byKey(const ValueKey('swipe-gesture-area')),
          const Offset(220, 0),
          900,
        );
        await settleUi(tester);
        expect(find.text('SPEND'), findsOneWidget);
      });
    }
  });

  group('the dots are an affordance, not decoration', () {
    testWidgets('tapping a dot jumps to that page', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await tester.pumpWidget(
        _host(
          const SwipePages(
            labels: ['Spending', 'Income'],
            pages: [Text('SPEND'), Text('INCOME')],
          ),
        ),
      );
      await settleUi(tester);

      await tester.tap(find.byKey(const ValueKey('swipe-dot-1')));
      await settleUi(tester);
      expect(find.text('INCOME'), findsOneWidget);
    });

    testWidgets('the count is spelled out in words', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await tester.pumpWidget(
        _host(
          const SwipePages(
            labels: ['Spending', 'Income'],
            pages: [Text('SPEND'), Text('INCOME')],
          ),
        ),
      );
      await settleUi(tester);

      // So it does not depend on recognising a row of pips.
      expect(find.text('1 of 2 · Spending'), findsOneWidget);
    });
  });

  group('the box is as tall as the page it is showing', () {
    // WHY NOT A PageView. The two breakdowns cannot share one fixed height: the
    // card measures 216 pixels plus 22 per category, so a two-category month
    // needs 260 and a nine-category month needs 414. A box sized for the worst
    // case leaves two hundred pixels of empty card under a poor month, and one
    // sized for the month on screen clips as soon as a seventh category appears.
    testWidgets('a short page is not padded out to a tall one', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await tester.pumpWidget(
        _host(
          SwipePages(
            labels: const ['Few', 'Many'],
            pages: [_card('Few categories', 2), _card('Many categories', 8)],
          ),
        ),
      );
      await settleUi(tester);

      final withFew = _heightOf(tester);
      expect(
        withFew,
        lessThan(300),
        reason: 'a two-category card was padded to ${withFew}px',
      );

      await tester.tap(find.byKey(const ValueKey('swipe-dot-1')));
      await settleUi(tester);

      final withMany = _heightOf(tester);
      expect(
        withMany,
        greaterThan(withFew + 80),
        reason:
            'swapping to the eight-category page did not make the box taller '
            '($withFew -> $withMany), so a page is being clipped or padded',
      );
    });

    testWidgets('a nine-category month is not clipped', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await tester.pumpWidget(
        _host(
          SwipePages(
            labels: const ['Full'],
            pages: [_card('Every category', 9)],
          ),
        ),
      );
      await settleUi(tester);

      expect(
        tester.takeException(),
        isNull,
        reason: 'a full month of categories overflows its page',
      );
      // Every legend row is on screen, not just the ones that fitted.
      expect(find.byType(SpendBreakdownCard), findsOneWidget);
    });
  });

  group('edge cases', () {
    testWidgets('no pages renders nothing rather than throwing', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await tester.pumpWidget(_host(const SwipePages(pages: [])));
      await settleUi(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(SwipePages), findsOneWidget);
    });

    testWidgets('one page cannot be swiped away', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await tester.pumpWidget(
        _host(const SwipePages(labels: ['Only'], pages: [Text('ONLY')])),
      );
      await settleUi(tester);

      await tester.fling(
        find.byKey(const ValueKey('swipe-gesture-area')),
        const Offset(-220, 0),
        900,
      );
      await settleUi(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('ONLY'), findsOneWidget);
    });

    testWidgets('a swiped page is still described to a screen reader', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await tester.pumpWidget(
        _host(
          const SwipePages(
            labels: ['Spending', 'Income'],
            pages: [Text('SPEND'), Text('INCOME')],
          ),
        ),
      );
      await settleUi(tester);

      expect(find.bySemanticsLabel('Page 1'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('swipe-dot-1')));
      await settleUi(tester);
      expect(find.bySemanticsLabel('Page 2'), findsOneWidget);
    });
  });

  group('the count label can get out of the way of a FAB', () {
    // A floating action button sits bottom-RIGHT on a phone, which is exactly
    // where this row's count label was. The FAB comes BACK on a scroll-up -- the
    // moment the user is looking at the row -- and landed on "1 of 2", hiding
    // which page they were on. So the label can go to the left, where nothing
    // floats.
    Widget host({required bool countOnTheLeft}) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: SwipePages(
          labels: const ['Spending', 'Income'],
          pages: [_card('Spending', 4), _card('Income', 2)],
          countOnTheLeft: countOnTheLeft,
        ),
      ),
    );

    testWidgets('on the left by request, before the dots', (tester) async {
      await tester.pumpWidget(host(countOnTheLeft: true));
      await settleUi(tester);

      final label = find.byKey(const ValueKey('swipe-indicator-count'));
      final dot = find.byKey(const ValueKey('swipe-dot-0'));

      expect(label, findsOneWidget);
      expect(dot, findsOneWidget);
      // The dot's centre is to the RIGHT of the label's, which is what "before"
      // means in a row.
      expect(tester.getCenter(dot).dx, greaterThan(tester.getCenter(label).dx));
    });

    testWidgets('on the right by default, after the dots', (tester) async {
      await tester.pumpWidget(host(countOnTheLeft: false));
      await settleUi(tester);

      final label = find.byKey(const ValueKey('swipe-indicator-count'));
      final dot = find.byKey(const ValueKey('swipe-dot-0'));

      expect(tester.getCenter(dot).dx, lessThan(tester.getCenter(label).dx));
    });

    testWidgets('both orders keep the same width, so neither can drift', (
      tester,
    ) async {
      await tester.pumpWidget(host(countOnTheLeft: true));
      await settleUi(tester);
      final leftRow = tester.getSize(
        find.byKey(const ValueKey('swipe-indicator-count')).hitTestable(),
      );
      final leftLabel = leftRow.width;

      await tester.pumpWidget(host(countOnTheLeft: false));
      await settleUi(tester);
      final rightLabel = tester
          .getSize(find.byKey(const ValueKey('swipe-indicator-count')))
          .width;

      // One order uses Flexible, the other Expanded. If the dots and the gap are
      // the same size in both, the label is the same width in both, and the row
      // is the same total.
      expect(leftLabel, closeTo(rightLabel, 1));
    });
  });
}
