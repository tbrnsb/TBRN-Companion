import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/models/index.dart';
import 'package:flutter_application_1/services/storage_service.dart';
import 'package:geolocator/geolocator.dart';

class LocationProvider extends ChangeNotifier {
  final StorageService _storageService = StorageService();

  List<Location> _locations = [];
  Position? _currentPosition;
  bool _isLoading = false;
  String? _error;
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
  Future<void> initialize() async {
    await loadLocations();
    if (!kIsWeb) {
      await updateCurrentPosition();
    }
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
  Future<void> updateCurrentPosition() async {
    if (kIsWeb) {
      _currentPosition = null;
      _currentLocationId = null;
      notifyListeners();
      return;
    }

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _error = 'Location services are disabled';
        notifyListeners();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _error = 'Location permission denied';
          notifyListeners();
          return;
        }
      }

      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Check which location user is in
      _updateCurrentLocation();
      notifyListeners();
    } catch (e) {
      _error = 'Failed to get location: $e';
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
