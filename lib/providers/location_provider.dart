import 'dart:async';

import 'package:flutter/foundation.dart';
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
