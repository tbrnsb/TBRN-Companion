import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:daily_companion/services/notification_service.dart';
import 'package:daily_companion/models/index.dart';
import 'package:daily_companion/services/storage_service.dart';
import 'package:geolocator/geolocator.dart';

/// Why a position is or is not available.
///
/// The provider used to keep a single `_error` string, and the UI rendered one
/// generic "Location unavailable on this device" for all of it. That hides the
/// only thing the user can act on: a denied permission needs a different action
/// from a phone whose GPS is switched off.
enum LocationStatus {
  /// Never asked, or not asked again this session.
  unknown,

  /// A read is in flight.
  locating,

  /// A fix is held.
  ready,

  /// The OS-level location toggle is off. Only Settings can fix this.
  serviceDisabled,

  /// The user said no. Asking again in-app is allowed once.
  permissionDenied,

  /// The user said no, and chose "don't ask again". Only Settings can fix it.
  permissionDeniedForever,

  /// Permission is fine and GPS is on, but no fix arrived (indoors, cold GPS).
  noFix,
}

class LocationProvider extends ChangeNotifier {
  final StorageService _storageService = StorageService();

  List<Location> _locations = [];
  Position? _currentPosition;
  bool _isLoading = false;
  String? _error;
  LocationStatus _status = LocationStatus.unknown;
  String? _currentLocationId; // ID of location user is currently in

  List<Location> get locations => _locations;

  // Get places linked to a journey
  List<Location> getLocationsForJourney(String journeyId) {
    return _locations.where((l) => l.journeyId == journeyId).toList();
  }

  /// Find saved checkpoints whose radius contains the given coordinates.
  List<Location> checkpointsAt(double latitude, double longitude) {
    return _locations
        .where((l) => l.isWithinGeofence(latitude, longitude))
        .toList();
  }

  Location? getLocationById(String id) {
    for (final l in _locations) {
      if (l.id == id) return l;
    }
    return null;
  }

  Position? get currentPosition => _currentPosition;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get currentLocationId => _currentLocationId;

  /// Why a position is or is not available. The UI keys its message and its
  /// recovery action off this rather than off [error].
  LocationStatus get status => _status;

  /// True when the only fix is in system Settings, so the app must not offer a
  /// retry that cannot work.
  bool get needsSystemSettings =>
      _status == LocationStatus.permissionDeniedForever ||
      _status == LocationStatus.serviceDisabled;

  String? getGeofenceAlertForJourney(Journey? activeJourney) {
    if (activeJourney == null) return null;
    final targetName = activeJourney.destination.trim();
    if (targetName.isEmpty) return null;

    final targetLocation = _locations.firstWhere(
      (location) =>
          location.name.toLowerCase() == targetName.toLowerCase() ||
          targetName.toLowerCase().contains(location.name.toLowerCase()),
      orElse: () =>
          Location(name: '', latitude: 0, longitude: 0, description: ''),
    );

    if (targetLocation.name.isEmpty) {
      return 'Saved place alert is ready for ${activeJourney.destination}. Add a matching location to enable geofence reminders.';
    }

    if (_currentPosition == null) {
      return 'Location access is unavailable, but ${targetLocation.name} is ready to trigger a geofence reminder when GPS is available.';
    }

    final distance = targetLocation.calculateDistance(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
    );

    if (distance <= targetLocation.radiusMeters) {
      return 'Geofence triggered: you are at ${targetLocation.name}. Final travel checklist check is due.';
    }

    if (distance <= targetLocation.radiusMeters * 2.5) {
      return 'Approaching ${targetLocation.name}. Check your route and essentials before arrival.';
    }

    return null;
  }

  // Initialize - load all locations
  ///
  /// LOADS ONLY. It does not ask for location permission, and that is the whole
  /// point of this method existing separately from [updateCurrentPosition].
  ///
  /// It used to call that too, which meant the app asked for the device's
  /// location within a second of opening, before the user had done anything at
  /// all. A permission prompt before the first tap reads as the app wanting
  /// something from you rather than serving you, and for an app that stores
  /// everything locally it is the first thing that makes someone suspicious.
  ///
  /// The saved places are what this screen needs to render, and they are in
  /// storage. Position is a separate question, asked only when the user does
  /// something that needs it: adding a place from where they are standing, or
  /// asking for the geofence check.
  Future<void> initialize() async {
    await loadLocations();
  }

  // Load all locations from database
  Future<void> loadLocations() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _locations = await _storageService.getAllLocations();
    } catch (e) {
      _error = 'Failed to load locations: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Get current GPS position
  ///
  /// The one place in the app that ASKS for location permission, and that is
  /// deliberate: both callers are a person tapping something that means "where
  /// am I" — "Use current location" while adding a place, or the locate button on
  /// the Places tab. A prompt that answers the question you just asked is
  /// reasonable. A prompt that arrives because the app opened is not.
  Future<void> updateCurrentPosition() async {
    if (kIsWeb) {
      _currentPosition = null;
      _currentLocationId = null;
      _status = LocationStatus.serviceDisabled;
      notifyListeners();
      return;
    }

    _status = LocationStatus.locating;
    _error = null;
    notifyListeners();

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _error = 'Location services are turned off on this phone.';
        _status = LocationStatus.serviceDisabled;
        notifyListeners();
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        _error =
            'Location permission was permanently denied. Enable it in '
            'Settings → Apps → Daily Companion → Permissions.';
        _status = LocationStatus.permissionDeniedForever;
        notifyListeners();
        return;
      }

      if (permission == LocationPermission.denied) {
        _error = 'Location permission was denied.';
        _status = LocationStatus.permissionDenied;
        notifyListeners();
        return;
      }

      // A high-accuracy read can take a while on a cold GPS indoors, so give
      // it a bounded wait and report a distinct "no fix" rather than an opaque
      // failure. `high` accuracy is wanted for geofence arrival checks.
      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 20),
      );

      _status = LocationStatus.ready;
      _updateCurrentLocation();
      await _checkArrivals();
      notifyListeners();
    } on TimeoutException {
      // No fix in time. This is a real, common case and deserves its own
      // message: moving near a window usually resolves it.
      _error = 'Could not get a GPS fix in time. Try again somewhere clearer.';
      _status = LocationStatus.noFix;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to get location: $e';
      _status = LocationStatus.noFix;
      notifyListeners();
    }
  }

  // Check if user is within any geofenced area
  void _updateCurrentLocation() {
    if (_currentPosition == null) return;

    _currentLocationId = null;
    for (var location in _locations) {
      if (location.isWithinGeofence(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      )) {
        _currentLocationId = location.id;
        break;
      }
    }
  }

  /// Places already announced for the current visit.
  ///
  /// Without this, standing at a place fires the notification on every position
  /// update -- which is every few seconds while the app is open, so "you have
  /// arrived" would repeat until the user turned the phone off.
  final Set<String> _arrived = {};

  /// How close counts as arriving.
  ///
  /// WIDER THAN THE GEOFENCE ON PURPOSE. A place's own radius is the question
  /// "am I inside this place", which is right for the cluster prompts and wrong
  /// for arrival: at a 200m radius you are flagged as having arrived several
  /// streets away, and the user is told they are somewhere they plainly are not.
  static const double arrivalRadiusMeters = 1000;

  /// Whether to announce arrival at [location] right now, and whether the user
  /// is inside it at all.
  ///
  /// Split out from the loop so the rules are testable without a position fix,
  /// which a unit test cannot produce and should not try to.
  static ArrivalDecision shouldAnnounceArrival({
    required Location location,
    required double latitude,
    required double longitude,
    required bool alreadyAnnounced,
  }) {
    if (!location.notificationsEnabled) {
      return const ArrivalDecision(inside: false, announce: false);
    }

    final distance = location.calculateDistance(latitude, longitude);
    final inside = distance <= arrivalRadiusMeters;

    // Re-arm only on leaving, so approaching again announces again. Clearing on
    // arrival alone would silence every place the user visits twice.
    return ArrivalDecision(
      inside: inside,
      announce: inside && !alreadyAnnounced,
    );
  }

  /// Notifies once per approach to any place that asked to be notified about.
  ///
  /// SCOPE, STATED PLAINLY: this runs when a position is read, which the app
  /// does while it is open and the user has asked for a fix. It is NOT a
  /// background geofence and does not claim to be -- firing on arrival with the
  /// app killed needs a foreground service and its own permission prompt, which
  /// is a much larger thing to put in someone's pocket without asking. What this
  /// does is honest: it tells you when you have arrived while you are using the
  /// app to record where you are, which is the moment you most want to be told.
  ///
  /// A place can opt out individually. See [Location.notificationsEnabled].
  Future<void> _checkArrivals() async {
    final position = _currentPosition;
    if (position == null || _locations.isEmpty) return;

    for (final location in _locations) {
      // The DECISION is a pure function so it can be tested without a GPS fix,
      // which is the only way to test it at all -- a real position cannot be
      // supplied in a unit test, and the logic that matters (who is eligible,
      // who has already been told) is exactly the part that never needs one.
      final announce = shouldAnnounceArrival(
        location: location,
        latitude: position.latitude,
        longitude: position.longitude,
        alreadyAnnounced: _arrived.contains(location.id),
      );
      if (!announce.inside) {
        _arrived.remove(location.id);
        continue;
      }
      if (!announce.announce) continue;
      _arrived.add(location.id);

      await NotificationService.showTripReminder(
        title: 'You have arrived at ${location.name}',
        body: location.journeyId != null
            ? 'Journey reached. Check what you packed, and confirm you are ready '
                  'to head back.'
            : 'Check anything you meant to do here.',
      );
    }
  }

  /// Silences the arrival notification for one place.
  Future<void> setNotificationsEnabled(
    String locationId, {
    required bool enabled,
  }) async {
    final location = _locations.firstWhere(
      (l) => l.id == locationId,
      orElse: () =>
          Location(name: '', latitude: 0, longitude: 0, description: ''),
    );
    if (location.name.isEmpty || location.notificationsEnabled == enabled) {
      return;
    }
    await updateLocation(location.copyWith(notificationsEnabled: enabled));
    // Re-arm so switching it back on does not wait for the user to walk out
    // and back in before the next arrival can be announced.
    if (enabled) {
      _arrived.remove(locationId);
    } else {
      _arrived.add(locationId);
    }
  }

  /// Reset by an explicit test hook, never by the app.
  @visibleForTesting
  void forgetArrivals() => _arrived.clear();

  // Add new location bookmark
  Future<void> addLocation(Location location) async {
    try {
      await _storageService.addLocation(location);
      _locations.add(location);
      notifyListeners();
    } catch (e) {
      _error = 'Failed to add location: $e';
      notifyListeners();
    }
  }

  // Update location bookmark
  Future<void> updateLocation(Location location) async {
    try {
      await _storageService.updateLocation(location);
      final index = _locations.indexWhere((l) => l.id == location.id);
      if (index != -1) {
        _locations[index] = location;
        notifyListeners();
      }
    } catch (e) {
      _error = 'Failed to update location: $e';
      notifyListeners();
    }
  }

  // Delete location bookmark
  Future<void> deleteLocation(String id) async {
    try {
      await _storageService.deleteLocation(id);
      _locations.removeWhere((l) => l.id == id);
      notifyListeners();
    } catch (e) {
      _error = 'Failed to delete location: $e';
      notifyListeners();
    }
  }

  // Log arrival at a location
  Future<void> logArrival(String locationId) async {
    try {
      // Check if already logged at this location
      final activeLog = await _storageService.getActiveLocationLog(locationId);
      if (activeLog != null) return; // Already logged

      final log = LocationLog(
        locationId: locationId,
        arrivalTime: DateTime.now(),
      );
      await _storageService.addLocationLog(log);
      _currentLocationId = locationId;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to log arrival: $e';
      notifyListeners();
    }
  }

  // Log departure from a location
  Future<void> logDeparture(String locationId) async {
    try {
      final activeLog = await _storageService.getActiveLocationLog(locationId);
      if (activeLog != null) {
        final updatedLog = activeLog.copyWith(departureTime: DateTime.now());
        await _storageService.updateLocationLog(updatedLog);
      }
      _currentLocationId = null;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to log departure: $e';
      notifyListeners();
    }
  }

  // Get location logs for a specific location
  Future<List<LocationLog>> getLocationLogs(String locationId) async {
    try {
      return await _storageService.getLocationLogs(locationId);
    } catch (e) {
      _error = 'Failed to get location logs: $e';
      notifyListeners();
      return [];
    }
  }

  // Get location logs for a date range
  Future<List<LocationLog>> getLocationLogsInRange(
    String locationId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      return await _storageService.getLocationLogsInDateRange(
        locationId,
        startDate,
        endDate,
      );
    } catch (e) {
      _error = 'Failed to get location logs: $e';
      notifyListeners();
      return [];
    }
  }

  // Get distance to a location
  double getDistanceToLocation(String locationId) {
    if (_currentPosition == null) return 0;

    final location = _locations.firstWhere(
      (l) => l.id == locationId,
      orElse: () =>
          Location(name: '', latitude: 0, longitude: 0, description: ''),
    );

    return location.calculateDistance(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
    );
  }

  // Watch location changes (continuous monitoring)
  Stream<Position> watchPosition() {
    if (kIsWeb) {
      return const Stream.empty();
    }

    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
      ),
    );
  }
}

/// Whether the user is inside a place, and whether to announce it.
///
/// Two questions rather than one boolean, because they answer different needs:
/// [inside] drives re-arming the alert for next time, and [announce] drives
/// showing one now. Collapsing them means either re-announcing on every reading
/// or never re-announcing a place visited twice.
class ArrivalDecision {
  const ArrivalDecision({required this.inside, required this.announce});

  final bool inside;
  final bool announce;
}
