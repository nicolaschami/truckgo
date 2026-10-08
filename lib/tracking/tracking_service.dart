import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../data/app_database.dart';

/// Follows the truck's GPS position while a truck's deliveries are open,
/// also with the app in the background (Android foreground service with a
/// permanent notification, iOS background location).
///
/// Saves a position at most every [saveEvery] in `gps_positions` (sent to
/// dispatching later) and keeps the latest one for status events and
/// geofences.
class TrackingService extends ChangeNotifier {
  /// Tests pass their own [positions] and [checkReady].
  TrackingService({
    Stream<Position> Function(int distanceFilterM)? positions,
    Future<String?> Function()? checkReady,
  })  : _positions = positions ?? _devicePositions,
        _checkReady = checkReady ?? _checkDevice;

  /// The app's tracking service (tests may replace it with a fake GPS).
  static TrackingService instance = TrackingService();

  static const saveEvery = Duration(seconds: 30);

  /// A position older than this is not attached to a status change.
  static const maxPositionAge = Duration(minutes: 2);

  /// A new position is reported after moving this far (metres).
  static const normalDistanceM = 20;
  static const fineDistanceM = 5; // for the small test zones

  int _distanceFilterM = normalDistanceM;

  final Stream<Position> Function(int distanceFilterM) _positions;
  final Future<String?> Function() _checkReady;
  StreamSubscription<Position>? _subscription;

  String? _truckPlate;
  Position? _last;
  DateTime? _lastSavedAt;
  String? _problem;

  bool get isRunning => _subscription != null;
  Position? get lastPosition => _last;

  /// Why tracking is not running (permission, GPS off...), or null.
  String? get problem => _problem;

  /// The latest position, if recent enough to describe "here and now".
  Position? get freshPosition {
    final p = _last;
    if (p == null) return null;
    return DateTime.now().difference(p.timestamp) <= maxPositionAge ? p : null;
  }

  /// Starts tracking for [truckPlate]. Safe to call again (restarts only
  /// when the truck changed).
  Future<void> start(String truckPlate) async {
    if (isRunning && _truckPlate == truckPlate) return;
    await stop();
    _truckPlate = truckPlate;

    final problem = await _checkReady();
    if (problem != null) {
      _problem = problem;
      notifyListeners();
      return;
    }

    _problem = null;
    _subscription = _positions(_distanceFilterM).listen(
      _onPosition,
      onError: (Object e) {
        _problem = 'GPS error: $e';
        notifyListeners();
      },
    );
    notifyListeners();
  }

  /// Reports positions every [fineDistanceM] instead of [normalDistanceM]
  /// (debug: small test zones). Restarts the GPS if it is running.
  Future<void> setFine(bool fine) async {
    final wanted = fine ? fineDistanceM : normalDistanceM;
    if (wanted == _distanceFilterM) return;
    _distanceFilterM = wanted;
    final truck = _truckPlate;
    if (isRunning && truck != null) {
      await stop();
      await start(truck);
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _truckPlate = null;
    _lastSavedAt = null;
    notifyListeners();
  }

  Future<void> _onPosition(Position p) async {
    _last = p;
    notifyListeners();

    final now = DateTime.now();
    final truck = _truckPlate;
    if (truck == null) return;
    if (_lastSavedAt != null && now.difference(_lastSavedAt!) < saveEvery) {
      return;
    }
    _lastSavedAt = now;

    await AppDatabase.db.insert('gps_positions', {
      'truck_plate': truck,
      'latitude': p.latitude,
      'longitude': p.longitude,
      'accuracy_m': p.accuracy,
      'speed_kmh': p.speed < 0 ? null : p.speed * 3.6,
      'heading': p.heading < 0 ? null : p.heading,
      'recorded_at': AppDatabase.toDbTime(p.timestamp),
    });
  }

  // ---------------------------------------------------------------
  // DEVICE
  // ---------------------------------------------------------------

  static Future<String?> _checkDevice() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return 'Location is turned off on the phone';
      }
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return 'Location permission is missing';
      }
    } catch (e) {
      return 'GPS not available';
    }
    return null;
  }

  static Stream<Position> _devicePositions(int distanceFilterM) {
    final LocationSettings settings;
    if (!kIsWeb && Platform.isAndroid) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterM,
        intervalDuration: const Duration(seconds: 10),
        // Keeps tracking with the app in the background
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'TruckGo',
          notificationText: 'Tracking your deliveries',
          notificationChannelName: 'Delivery tracking',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    } else if (!kIsWeb && Platform.isIOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterM,
        activityType: ActivityType.automotiveNavigation,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
        pauseLocationUpdatesAutomatically: false,
      );
    } else {
      settings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterM,
      );
    }
    return Geolocator.getPositionStream(locationSettings: settings);
  }
}
