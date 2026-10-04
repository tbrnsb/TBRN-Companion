import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/services/place_launcher.dart';
import 'package:daily_companion/theme/app_theme.dart';

import 'test_viewports.dart';

/// Records what was launched instead of leaving the app.
class _RecordingLauncher extends UrlLauncherPlatform {
  final List<Uri> launched = [];
  final List<Uri> asked = [];
  Set<String> unsupported = const {};

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async {
    asked.add(Uri.parse(url));
    return !unsupported.contains(Uri.parse(url).scheme);
  }

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(Uri.parse(url));
    return true;
  }
}

void main() {
  late _RecordingLauncher platform;
  const place = PlaceLink(
    latitude: 28.2096,
    longitude: 83.9856,
    name: 'Phewa Lake',
  );

  setUp(() {
    platform = _RecordingLauncher();
    UrlLauncherPlatform.instance = platform;
  });

  Future<void> pump(WidgetTester tester) async {
    usePhoneLayout(tester, TestViewports.phonePortrait);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => PlaceLauncher.open(context, place),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  group('a place opens in a maps app', () {
    // THE FEATURE WAS HALF A FEATURE. The app read a pasted Google Maps link --
    // every URL shape -- and then had no way to OPEN one: no url_launcher
    // dependency and no launchUrl call anywhere. Coordinates were stored, shown
    // and inert, and a user with a maps app installed had to retype them.
    testWidgets('it tries the platform geo: scheme first', (tester) async {
      await pump(tester);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(platform.launched, hasLength(1));
      // geo: FIRST, not the Google URL: a geo: intent is answered by whichever
      // maps app the device has, including one that is not Google Maps.
      expect(platform.launched.single.scheme, 'geo');
      expect(platform.launched.single.toString(), contains('28.2096,83.9856'));
    });

    testWidgets('it carries the name so the map can label the pin', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Percent-encoded, which is what a geo: URI wants: a raw space in a URI is
      // not a legal one, and a maps app parsing the label wants it escaped.
      expect(platform.launched.single.toString(), contains('Phewa%20Lake'));
    });

    testWidgets('it falls back to the Google URL when geo: is unsupported', (
      tester,
    ) async {
      // A device with no app registered for geo: is a normal state, not an
      // error, and the next candidate is a web address a browser can always
      // handle.
      platform.unsupported = {'geo'};
      await pump(tester);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(platform.launched, hasLength(1));
      expect(platform.launched.single.scheme, 'https');
      expect(platform.launched.single.host, 'www.google.com');
      expect(
        platform.launched.single.queryParameters['query'],
        '28.2096,83.9856',
      );
    });

    testWidgets('it reports failure rather than throwing when nothing can', (
      tester,
    ) async {
      // A device with no maps app at all has to be survivable: the caller gets
      // false and shows a message, not an exception from a plugin.
      platform.unsupported = {'geo', 'https'};
      await pump(tester);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(platform.launched, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  group('the failure message is actionable', () {
    // It used to read "No maps app found. The coordinates are 28.2096,
    // 83.9856." -- which dumps the one piece of information the user could not
    // act on, on top of a coordinate pair that was on screen a moment earlier,
    // and says nothing about what to do. Reported from the device as
    // "it says no maps are found the coordinates are XYZ,ABC so thats a
    // problem". The coordinates were never the fix; a maps app is.
    testWidgets('it says what to do, not just the coordinates', (tester) async {
      platform.unsupported = {'geo', 'https'};
      usePhoneLayout(tester, TestViewports.phonePortrait);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => PlaceLauncher.openOrExplain(context, place),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Names the actual remedy, so the message is something to act on.
      expect(find.textContaining('Install Google Maps'), findsOneWidget);
      // And no longer leads with the coordinate dump.
      expect(find.textContaining('The coordinates are'), findsNothing);
    });
  });

  group('a label that would break the URI is encoded, not pasted', () {
    // The URI used to be assembled by string concatenation, so an unescaped
    // `&` in a place name became a second query parameter and the maps app read
    // the label as empty. This is the shape of name that proved it.
    testWidgets('an ampersand in the name survives', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => PlaceLauncher.open(
                  context,
                  const PlaceLink(
                    latitude: 28.2096,
                    longitude: 83.9856,
                    name: 'Cafe & Bar',
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final uri = platform.launched.single;
      // Encoded, so it is part of the label and not a parameter separator...
      expect(uri.toString(), contains('Cafe%20%26%20Bar'));
      // ...which means `q` is still the whole label and nothing leaked out.
      expect(uri.queryParameters['q'], contains('Cafe & Bar'));
    });
  });

  group('the place row offers it', () {
    testWidgets('the row is tappable and says where it goes', (tester) async {
      await pump(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: PlaceLinkTile(place: place)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Phewa Lake'), findsOneWidget);
      // The trailing glyph is what says "this leaves the app", and a row that
      // opens something external without saying so is a surprise.
      expect(find.byIcon(Icons.open_in_new_rounded), findsOneWidget);
    });
  });
}
