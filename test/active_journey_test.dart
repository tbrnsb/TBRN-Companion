import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daily_companion/providers/checklist_provider.dart';
import 'package:daily_companion/providers/journey_provider.dart';
import 'package:daily_companion/providers/location_provider.dart';
import 'package:daily_companion/screens/journeys/journeys_screen.dart';
import 'package:daily_companion/services/storage_service.dart';
import 'package:daily_companion/theme/app_accents.dart';
import 'package:daily_companion/theme/app_chart_colors.dart';
import 'package:daily_companion/theme/app_palettes.dart';
import 'package:daily_companion/theme/app_theme.dart';

import 'test_viewports.dart';
import 'visual_smoke_test.dart' show initTestStorage;

Future<void> settleUi(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

Widget _app(JourneyProvider journeys, ThemeData theme) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<JourneyProvider>.value(value: journeys),
      ChangeNotifierProvider(create: (_) => LocationProvider()),
      ChangeNotifierProvider(create: (_) => ChecklistProvider()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: const JourneysScreen(),
    ),
  );
}

/// A journey with a long name, items and reminders, at one palette.
Future<JourneyProvider> _withActiveJourney(WidgetTester tester) async {
  final journeys = JourneyProvider();
  addTearDown(journeys.dispose);
  await tester.runAsync(() async {
    await StorageService().clear();
    await journeys.initialize();
    await journeys.startJourney(
      origin: 'Kathmandu',
      destination: 'Pokhara',
      items: ['Boots', 'Waterproof jacket', 'Headlamp', 'Water bottle'],
    );
  });
  return journeys;
}

/// The colour a piece of text is actually painted in.
Color _textColour(WidgetTester tester, String text) {
  final widget = tester.widget<Text>(find.text(text).first);
  return widget.style?.color ?? const Color(0xFFFFFFFF);
}

void main() {
  setUpAll(() async {
    await initTestStorage();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('the active journey card has a hierarchy', () {
    // THE DEVICE COMPLAINT: "bad in all themes". Every element on the card was
    // the same ink at competing sizes, so nothing read as more important than
    // anything else and the loudest content was two paragraphs of generic
    // advice. A hierarchy is measurable -- the label, the title and the advice
    // must be three different colours -- and that is what this asserts.
    for (final palette in AppPalette.values) {
      testWidgets('$palette separates the label, the title and the advice', (
        tester,
      ) async {
        usePhoneLayout(tester, TestViewports.phonePortrait);
        final journeys = await _withActiveJourney(tester);

        await tester.pumpWidget(_app(journeys, AppTheme.darkFor(palette)));
        await settleUi(tester);

        final label = _textColour(tester, 'ACTIVE JOURNEY');
        final title = _textColour(tester, 'Kathmandu → Pokhara');
        final advice = _textColour(tester, 'While you are out');

        expect(
          label,
          isNot(title),
          reason:
              'on $palette the card label and the route title are the same '
              'colour, so the label competes with the thing it labels',
        );
        expect(
          advice,
          isNot(title),
          reason:
              'on $palette the reminder advice is as loud as the route title',
        );
      });
    }
  });

  group('the accents the card uses are legible on the card', () {
    // Both accents measure roughly 2.7:1 on Gruvbox's `selection` container as
    // authored, under the 3:1 floor for a non-text mark, so they are resolved
    // against the surface they land on rather than used raw.
    for (final palette in AppPalette.values) {
      testWidgets('$palette clears 3:1 where it is used', (tester) async {
        usePhoneLayout(tester, TestViewports.phonePortrait);
        final theme = AppTheme.darkFor(palette);
        final journeys = await _withActiveJourney(tester);

        await tester.pumpWidget(_app(journeys, theme));
        await settleUi(tester);

        final scheme = theme.colorScheme;
        final card = scheme.primaryContainer;
        final accents = theme.extension<AppAccents>()!;

        for (final entry in {
          'warm': accents.warm,
          'cool': accents.cool,
        }.entries) {
          final drawn = AppCategoryColour.resolve(entry.value, card);
          expect(
            _contrast(drawn, card),
            greaterThanOrEqualTo(3.0),
            reason:
                'on $palette the ${entry.key} accent resolves to $drawn on the '
                'card $card, which is under 3:1',
          );
        }

        // The label on the card is drawn in the resolved cool accent, and it is
        // TEXT, so it is held to the stricter floor rather than the non-text one.
        final label = _textColour(tester, 'ACTIVE JOURNEY');
        expect(
          _contrast(label, card),
          greaterThanOrEqualTo(3.0),
          reason: 'on $palette the card label is $label on $card',
        );
      });
    }
  });

  group('a long trip name does not collide with the open affordance', () {
    for (final viewport in [
      TestViewports.phonePortrait,
      TestViewports.phoneSmall,
    ]) {
      testWidgets('no overflow at $viewport', (tester) async {
        usePhoneLayout(tester, viewport);
        final journeys = JourneyProvider();
        addTearDown(journeys.dispose);
        await tester.runAsync(() async {
          await StorageService().clear();
          await journeys.initialize();
          await journeys.startJourney(
            origin: 'Kathmandu and the surrounding valley',
            destination: 'Pokhara and the Annapurna circuit',
            items: ['Boots', 'Waterproof jacket'],
          );
        });

        await tester.pumpWidget(_app(journeys, AppTheme.dark()));
        await settleUi(tester);

        expect(
          tester.takeException(),
          isNull,
          reason: 'the active journey card overflows at $viewport',
        );
      });
    }
  });

  group('the "Complete journey" button is not louder than the trip', () {
    // THE DEVICE COMPLAINT, second pass: the button was the most saturated
    // thing on the card in every theme, and the eye went to it before the trip
    // name -- which is the one thing the card is FOR. Filled in the warm accent
    // it read as "press this" rather than "this is what you are on".
    //
    // So the fill is gone. What is left has to still read as the card's own
    // action, which is why the outline is the accent: findable, without the slab
    // of colour that buried the name.
    for (final palette in AppPalette.values) {
      testWidgets('$palette outlines the CTA instead of filling it', (
        tester,
      ) async {
        usePhoneLayout(tester, TestViewports.phonePortrait);
        final journeys = await _withActiveJourney(tester);

        await tester.pumpWidget(_app(journeys, AppTheme.darkFor(palette)));
        await settleUi(tester);

        final cta = find.byKey(const ValueKey('complete-journey'));
        expect(cta, findsOneWidget);

        // Outlined, not filled. A FilledButton here is the whole bug, and the
        // label is what makes the search unambiguous -- some filled buttons are
        // perfectly right elsewhere on the screen.
        expect(tester.widget(cta), isA<OutlinedButton>());
        expect(
          find.widgetWithText(FilledButton, 'Complete journey'),
          findsNothing,
        );
        expect(
          find.widgetWithText(OutlinedButton, 'Complete journey'),
          findsOneWidget,
        );

        final button = tester.widget<OutlinedButton>(cta);
        final resolved = button.style;

        // Nothing filled behind the label...
        final background = resolved?.backgroundColor?.resolve({});
        expect(
          background == null || background.a == 0,
          isTrue,
          reason:
              'the CTA has a background of $background, so it is a slab of '
              'colour again',
        );

        // ...and what is left is a hairline, not a slab. A full-width fill was
        // the loudest element on the card; the whole weight of this fix is that
        // there is now a line around the label instead of colour behind it.
        //
        // The outline's own colour is deliberately NOT asserted to be a
        // saturated accent. On tbrn the warm accent resolves to the palette's
        // cream foreground, which is a low-saturation colour by definition, and
        // "the accent" is not the same colour in every palette -- a test that
        // assumed it was would be testing the palette rather than this card.
        final side = resolved?.side?.resolve({});
        expect(side, isNotNull, reason: 'an outlined button with no outline');
        expect(side!.width, greaterThan(0), reason: 'the outline is invisible');
        expect(
          side.width,
          lessThanOrEqualTo(2),
          reason: 'a ${side.width}px outline is starting to be a slab',
        );
        expect(side.color.a, greaterThan(0));
        expect(
          find.text('Complete journey'),
          findsOneWidget,
          reason: 'the label itself must survive being restyled',
        );
      });
    }
  });
}
