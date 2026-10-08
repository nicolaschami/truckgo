import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../delivery_store.dart';
import '../mock_deliveries.dart';
import 'arrival_notifications.dart';
import 'tracking_service.dart';

/// Watches the truck's GPS against the plant and the customer site of its
/// next delivery (both stored with latitude, longitude and radius):
///
/// - Entering the plant zone while the delivery is Assigned sets At plant
///   (trigger: geofence).
/// - Entering the site zone while In transit only reminds the driver
///   (notification + [siteReminder]); the driver confirms the arrival.
class GeofenceService {
  GeofenceService({
    required this.tracking,
    required this.store,
    Future<void> Function(Delivery)? notify,
  }) : _notify = notify ?? ArrivalNotifications.showSiteArrival;

  static GeofenceService instance = GeofenceService(
    tracking: TrackingService.instance,
    store: DeliveryStore.instance,
  );

  /// GPS positions less precise than this are ignored.
  static const maxAccuracyM = 100.0;

  /// The zone counts as left only beyond radius x this, so a position
  /// jumping around the edge does not repeat the reminder.
  static const leaveFactor = 1.5;

  final TrackingService tracking;
  final DeliveryStore store;
  final Future<void> Function(Delivery) _notify;

  /// The delivery whose site the truck just reached: the app shows the
  /// "confirm arrival" dialog while this is set.
  final ValueNotifier<Delivery?> siteReminder = ValueNotifier(null);

  // Deliveries already reminded while inside their site zone
  final Set<String> _reminded = {};
  bool _listening = false;

  // ---------------------------------------------------------------
  // DEBUG: small zones, to test on foot around the house
  // ---------------------------------------------------------------

  static const testRadiusM = 15.0;
  bool _smallTestZones = false;

  bool get smallTestZones => _smallTestZones;

  /// Uses [testRadiusM] for every zone, with a GPS position every 5 m.
  Future<void> setSmallTestZones(bool on) async {
    _smallTestZones = on;
    _reminded.clear();
    await tracking.setFine(on);
    await _check();
  }

  double plantRadiusM(Delivery d) =>
      _smallTestZones ? testRadiusM : d.plantGeofenceRadiusM;

  double siteRadiusM(Delivery d) =>
      _smallTestZones ? testRadiusM : d.siteGeofenceRadiusM;

  /// Distance from the last GPS position to the plant / site of [d].
  double? distanceToPlantM(Delivery d) {
    final p = tracking.lastPosition;
    return p == null
        ? null
        : distanceM(p.latitude, p.longitude, d.plantLatitude, d.plantLongitude);
  }

  double? distanceToSiteM(Delivery d) {
    final p = tracking.lastPosition;
    return p == null
        ? null
        : distanceM(p.latitude, p.longitude, d.latitude, d.longitude);
  }

  void start() {
    if (_listening) return;
    _listening = true;
    // Check on every new GPS position, and also when the deliveries change
    // (loaded, new status, zone moved) using the last known position: a
    // truck standing still sends no new positions.
    tracking.addListener(_check);
    store.addListener(_check);
    _check();
  }

  void stop() {
    if (!_listening) return;
    _listening = false;
    tracking.removeListener(_check);
    store.removeListener(_check);
    siteReminder.value = null;
  }

  /// The driver answered the reminder (either way).
  void dismissReminder() => siteReminder.value = null;

  static double distanceM(double lat1, double lng1, double lat2, double lng2) =>
      Geolocator.distanceBetween(lat1, lng1, lat2, lng2);

  Future<void> _check() async {
    final p = tracking.lastPosition;
    if (p == null || p.accuracy > maxAccuracyM) return;

    // The next delivery is the one the truck is working on
    final open = store.current;
    if (open.isEmpty) return;
    final d = open.first;

    // PLANT: automatic At plant
    if (d.status == DeliveryStatus.assigned) {
      final toPlant =
          distanceM(p.latitude, p.longitude, d.plantLatitude, d.plantLongitude);
      if (toPlant <= plantRadiusM(d)) {
        await store.setStatus(d.key, DeliveryStatus.atPlant,
            trigger: StatusTrigger.geofence);
      }
      return;
    }

    // SITE: remind the driver to confirm arrival
    if (d.status == DeliveryStatus.inTransit) {
      final toSite = distanceM(p.latitude, p.longitude, d.latitude, d.longitude);
      if (toSite <= siteRadiusM(d)) {
        if (_reminded.add(d.key)) {
          siteReminder.value = d;
          await _notify(d);
        }
      } else if (toSite > siteRadiusM(d) * leaveFactor) {
        // Left the zone: remind again on the next entry
        _reminded.remove(d.key);
      }
    }
  }
}
