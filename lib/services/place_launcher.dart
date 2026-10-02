import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import 'package:daily_companion/models/index.dart';

/// Opens a saved place in a maps app.
///
/// WHY THIS EXISTS. The app could PARSE a pasted Google Maps link -- it reads
/// the coordinates out of every shape the link comes in -- and then had no way
/// to open one. There was no `url_launcher` dependency and no `launchUrl` call
/// anywhere, so a place's coordinates were stored, shown, and otherwise inert:
/// the feature was half a feature. A user with a saved place and a maps app
/// installed had to retype the coordinates.
///
/// WHICH URL, AND WHY THE ORDER MATTERS. Three shapes are tried in turn:
///   1. `geo:` -- the platform's own scheme, which hands the point to whichever
///      maps app the device has, including one that is not Google Maps.
///   2. the Google Maps universal URL -- the same, as a web address.
///   3. nothing, and a message.
///
/// `geo:` FIRST rather than the Google URL, because a `geo:` intent is answered
/// by any installed maps app, and a user in Kathmandu with Mapbox or Organic
/// Maps installed should not be pushed to a web page. Tries are ordered by
/// decreasing universality, and a failure at one step is not an error to report
/// until every step has been tried.
class PlaceLauncher {
  PlaceLauncher._();

  /// Opens [place] in a maps app. True when something took it.
  ///
  /// Never throws: a device with no maps app at all is a normal state, and the
  /// caller gets `false` to show a message rather than an exception.
  static Future<bool> open(BuildContext context, PlaceLink place) async {
    final coordinates = '${place.latitude},${place.longitude}';

    // 1. The platform scheme.
    final geo = Uri.parse(
      'geo:$coordinates?q=$coordinates(${place.name ?? ''})',
    );
    if (await _try(geo)) return true;

    // 2. The Google Maps universal URL, which a browser can always handle.
    final web = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': coordinates,
    });
    if (await _try(web)) return true;

    return false;
  }

  static Future<bool> _try(Uri uri) async {
    try {
      if (await launcher.canLaunchUrl(uri)) {
        return await launcher.launchUrl(
          uri,
          mode: launcher.LaunchMode.externalApplication,
        );
      }
    } catch (_) {
      // A plugin that throws is a plugin that throws; the next candidate is
      // still worth trying and the caller only hears about it if all fail.
      return false;
    }
    return false;
  }

  /// Opens [place], or explains why it could not.
  ///
  /// The message names the coordinates, because when no maps app can be opened
  /// the coordinates are the only thing the user can still act on.
  static Future<void> openOrExplain(
    BuildContext context,
    PlaceLink place,
  ) async {
    final opened = await open(context, place);
    if (opened || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'No maps app found. The coordinates are '
          '${place.latitude}, ${place.longitude}.',
        ),
        backgroundColor: scheme.surfaceContainerHighest,
      ),
    );
  }
}

/// A tappable place row that opens the place in a maps app.
class PlaceLinkTile extends StatelessWidget {
  const PlaceLinkTile({super.key, required this.place, this.subtitle});

  final PlaceLink place;

  /// Optional line under the name, for when the caller has something to add.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListTile(
      key: const ValueKey('open-in-maps'),
      leading: Icon(Icons.place_rounded, color: scheme.primary),
      title: Text(place.name ?? 'Saved place'),
      subtitle: Text(
        subtitle ?? '${place.latitude}, ${place.longitude}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      trailing: const Icon(Icons.open_in_new_rounded, size: 18),
      onTap: () => PlaceLauncher.openOrExplain(context, place),
    );
  }
}
