import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

/// Opens this app's page in system Settings.
///
/// Reached when the only way forward is a permission the app cannot request
/// again itself, either because the user chose "don't ask again" or because
/// the phone's location toggle is off. `Geolocator.openAppSettings` is the
/// geolocator-provided route, so it is used rather than a hand-rolled intent.
///
/// This lives outside the add-place screen because it is a location-domain
/// escape hatch that several screens need, and importing the screen that owns
/// it would be circular.
Future<void> openAppSettingsForLocation(BuildContext context) async {
  await Geolocator.openAppSettings();
  if (!context.mounted) return;
  // The user is on their way to the toggle; nothing to do here until they come
  // back, and they can retry.
}
