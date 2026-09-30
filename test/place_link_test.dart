import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/location.dart';
import 'package:flutter_application_1/models/place_link.dart';
import 'package:flutter_application_1/providers/journey_provider.dart';
import 'package:flutter_application_1/providers/location_provider.dart';
import 'package:flutter_application_1/screens/locations/add_location_screen.dart';
import 'package:flutter_application_1/theme/app_theme.dart';

import 'test_viewports.dart';
import 'visual_smoke_test.dart' show initTestStorage;

Widget _host(
  Widget child, {
  LocationProvider? locations,
  JourneyProvider? journeys,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<LocationProvider>.value(
        value: locations ?? LocationProvider(),
      ),
      ChangeNotifierProvider<JourneyProvider>.value(
        value: journeys ?? JourneyProvider(),
      ),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: child),
  );
}

/// Whether the icon cell at [finder] reports itself as chosen.
///
/// Read from the semantics node rather than by casting the element, because
/// a semantics-label finder resolves to the generated semantics fragment and
/// not to the `Semantics` widget in the source tree.
bool _isSelected(WidgetTester tester, Finder finder) {
  return tester.getSemantics(finder).flagsCollection.isSelected;
}

void main() {
  setUpAll(() async {
    await initTestStorage();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('reading a pasted maps link', () {
    test('reads the share link that Google Maps actually produces', () {
      // The shape you get from "Share → Copy link" on a pinned place.
      const link =
          'https://www.google.com/maps/place/Phewa+Lake/@28.2096146,83.9856033,17z/data=!3m1!4b1!4m6!3m5!1s0x39bcda0cd0c6445d:0x6ac1c1c1c1c1c1c1!8m2!3d28.2096146!4d83.9856033';
      final parsed = PlaceLinkParser.parse(link);

      expect(parsed, isNotNull);
      expect(parsed!.latitude, closeTo(28.2096146, 0.0001));
      expect(parsed.longitude, closeTo(83.9856033, 0.0001));
    });

    test('reads the short maps.google.com form', () {
      final parsed = PlaceLinkParser.parse(
        'https://maps.google.com/?q=28.2096,83.9856',
      );
      expect(parsed!.latitude, closeTo(28.2096, 0.0001));
      expect(parsed.longitude, closeTo(83.9856, 0.0001));
    });

    test('reads the directions-search form', () {
      final parsed = PlaceLinkParser.parse(
        'https://www.google.com/maps/dir/?api=1&destination=28.2096,83.9856',
      );
      expect(parsed!.latitude, closeTo(28.2096, 0.0001));
      expect(parsed.longitude, closeTo(83.9856, 0.0001));
    });

    test('reads a geo: URI', () {
      final parsed = PlaceLinkParser.parse('geo:28.2096,83.9856');
      expect(parsed!.latitude, closeTo(28.2096, 0.0001));
      expect(parsed.longitude, closeTo(83.9856, 0.0001));
    });

    test('reads a bare coordinate pair, with or without a space', () {
      expect(
        PlaceLinkParser.parse('28.2096, 83.9856')!.latitude,
        closeTo(28.2096, 1e-6),
      );
      expect(
        PlaceLinkParser.parse('28.2096,83.9856')!.longitude,
        closeTo(83.9856, 1e-6),
      );
    });

    test('reads the southern and western hemispheres', () {
      final parsed = PlaceLinkParser.parse('-33.8688,-151.2093');
      expect(parsed!.latitude, closeTo(-33.8688, 1e-6));
      expect(parsed.longitude, closeTo(-151.2093, 1e-6));
    });

    test('rejects a latitude past the pole rather than saving it', () {
      // Silently accepting this drops a checkpoint into the sea.
      expect(PlaceLinkParser.parse('91.5,10.0'), isNull);
      expect(PlaceLinkParser.parse('-91.5,10.0'), isNull);
    });

    test('rejects a longitude past the antimeridian', () {
      expect(PlaceLinkParser.parse('28.2,181.0'), isNull);
      expect(PlaceLinkParser.parse('28.2,-181.0'), isNull);
    });

    test('rejects links with no coordinates at all', () {
      expect(PlaceLinkParser.parse('https://www.google.com/maps'), isNull);
      expect(PlaceLinkParser.parse('https://maps.app.goo.gl/abcdef'), isNull);
      expect(PlaceLinkParser.parse('Phewa Lake, Pokhara'), isNull);
    });

    test('rejects empty and whitespace input', () {
      expect(PlaceLinkParser.parse(''), isNull);
      expect(PlaceLinkParser.parse('   '), isNull);
    });

    test('tells a broken link apart from something that was not a link', () {
      // Drives two different messages, so the user knows which mistake they made.
      expect(
        PlaceLinkParser.looksLikeALink('https://maps.app.goo.gl/abcdef'),
        isFalse,
      );
      expect(
        PlaceLinkParser.looksLikeALink('https://x.com/@91.0,10.0'),
        isTrue,
      );
      expect(PlaceLinkParser.looksLikeALink('just some words'), isFalse);
      expect(PlaceLinkParser.looksLikeALink(''), isFalse);
    });
  });

  group('the icon a saved place carries', () {
    test('resolves a known key', () {
      expect(PlaceIcons.resolve('home'), Icons.home_rounded);
      expect(PlaceIcons.resolve('mountain'), Icons.terrain_rounded);
    });

    test('falls back to a pin for a place saved before icons existed', () {
      // Every record written before this feature has icon == null, so this is
      // the common case, not an edge case.
      expect(PlaceIcons.resolve(null), Icons.place_rounded);
    });

    test('falls back to a pin for a key this build does not know', () {
      // Forward compatibility: a record written by a newer build must still
      // load rather than throw on the list screen.
      expect(
        PlaceIcons.resolve('icon_from_a_future_version'),
        Icons.place_rounded,
      );
    });

    test('every advertised key resolves to its own icon', () {
      for (final key in PlaceIcons.keys) {
        expect(PlaceIcons.catalogue[key], isNotNull, reason: key);
      }
    });
  });

  group('the icon survives a save and reload', () {
    test('an icon round-trips through the model', () {
      final location = Location(
        name: 'Home',
        latitude: 28.2096,
        longitude: 83.9856,
        description: '',
        icon: 'home',
      );
      final restored = Location.fromJson(location.toJson());

      expect(restored.icon, 'home');
      expect(PlaceIcons.resolve(restored.icon), Icons.home_rounded);
    });

    test('a place with no icon still loads from the older on-disk shape', () {
      // The pre-existing shape must keep parsing, with the icon key absent.
      final restored = Location.fromJson({
        'id': 'abc',
        'name': 'Old place',
        'latitude': 28.0,
        'longitude': 83.0,
        'description': '',
        'radiusMeters': 100.0,
        'createdAt': DateTime(2024, 1, 1).toIso8601String(),
        'updatedAt': DateTime(2024, 1, 1).toIso8601String(),
      });

      expect(restored.icon, isNull);
      expect(PlaceIcons.resolve(restored.icon), Icons.place_rounded);
    });
  });

  group('the add-a-place screen', () {
    testWidgets('fits a phone without overflowing', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      await tester.pumpWidget(_host(const AddLocationScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Add a place'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a pasted link fills the coordinates', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      await tester.pumpWidget(_host(const AddLocationScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Paste a Google Maps link'),
        'https://maps.google.com/?q=28.2096,83.9856',
      );
      await tester.tap(find.byTooltip('Use the coordinates from this link'));
      await tester.pumpAndSettle();

      // TextFormField is not a TextField subclass, so the widget has to be
      // read as a TextFormField to reach its controller.
      final lat = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Latitude'),
      );
      final lng = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Longitude'),
      );
      expect(lat.controller!.text, '28.209600');
      expect(lng.controller!.text, '83.985600');
    });

    testWidgets('a link with no coordinates says so', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      await tester.pumpWidget(_host(const AddLocationScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Paste a Google Maps link'),
        'https://maps.app.goo.gl/abcdef',
      );
      await tester.tap(find.byTooltip('Use the coordinates from this link'));
      await tester.pumpAndSettle();

      // Silence would leave the user thinking the button is broken.
      expect(find.text('That does not look like a maps link.'), findsOneWidget);
    });

    testWidgets('picking an icon selects it', (tester) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);

      await tester.pumpWidget(_host(const AddLocationScreen()));
      await tester.pumpAndSettle();

      final homeChoice = find.bySemanticsLabel('home');
      expect(tester.widget<Semantics>(homeChoice).properties.selected, isFalse);

      await tester.tap(homeChoice);
      await tester.pumpAndSettle();

      expect(tester.widget<Semantics>(homeChoice).properties.selected, isTrue);
    });

    testWidgets('an existing place opens for editing with its icon chosen', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      final existing = Location(
        name: 'Phewa Lake',
        latitude: 28.2096,
        longitude: 83.9856,
        description: 'north gate',
        icon: 'water',
      );

      await tester.pumpWidget(_host(AddLocationScreen(location: existing)));
      await tester.pumpAndSettle();

      expect(find.text('Edit place'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Phewa Lake'), findsOneWidget);
      expect(
        _isSelected(tester, find.byKey(const ValueKey('place-icon-water'))),
        isTrue,
      );
    });

    testWidgets('saving without a name is refused and stays on the screen', (
      tester,
    ) async {
      usePhoneLayout(tester, TestViewports.phonePortrait);
      final locations = LocationProvider();

      await tester.pumpWidget(
        _host(const AddLocationScreen(), locations: locations),
      );
      await tester.pumpAndSettle();

      // Coordinates present, name missing.
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Latitude'),
        '28.2096',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Longitude'),
        '83.9856',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add place'));
      await tester.pumpAndSettle();

      expect(find.text('Give it a name'), findsOneWidget);
      expect(find.text('Add a place'), findsOneWidget);
      expect(locations.locations, isEmpty);
    });
  });
}
