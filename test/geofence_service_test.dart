import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:truckg/data/app_database.dart';
import 'package:truckg/delivery_store.dart';
import 'package:truckg/mock_deliveries.dart';
import 'package:truckg/tracking/geofence_service.dart';
import 'package:truckg/tracking/tracking_service.dart';

const truck = 'AB-1234';

Position fix(double lat, double lng, {double accuracy = 10}) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 10,
      speedAccuracy: 0,
    );

void main() {
  sqfliteFfiInit();
  final store = DeliveryStore.instance;
  late StreamController<Position> gps;
  late TrackingService tracking;
  late GeofenceService geofence;
  late List<Delivery> notified;

  // The next delivery (first in the list) and its two zones
  Delivery next() => store.current.first;

  Future<void> moveTo(double lat, double lng, {double accuracy = 10}) async {
    gps.add(fix(lat, lng, accuracy: accuracy));
    await pumpEventQueue();
  }

  setUp(() async {
    await AppDatabase.open(
        path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    await store.loadForTruck(truck);
    gps = StreamController<Position>.broadcast(); // GPS may restart
    tracking = TrackingService(
      positions: (_) => gps.stream,
      checkReady: () async => null,
    );
    TrackingService.instance = tracking;
    notified = [];
    geofence = GeofenceService(
      tracking: tracking,
      store: store,
      notify: (d) async => notified.add(d),
    );
    await tracking.start(truck);
    geofence.start();
  });

  tearDown(() async {
    geofence.stop();
    await tracking.stop();
    unawaited(gps.close());
    await AppDatabase.close();
  });

  test('entering the plant zone sets At plant automatically', () async {
    final d = next();
    // ~1 km away: nothing happens
    await moveTo(d.plantLatitude + 0.009, d.plantLongitude);
    expect(next().status, DeliveryStatus.assigned);

    // ~100 m from the plant (radius 200 m)
    await moveTo(d.plantLatitude + 0.0009, d.plantLongitude);
    expect(store.byKey(d.key)!.status, DeliveryStatus.atPlant);

    final event = (await store.unsentEvents()).single;
    expect(event.trigger, StatusTrigger.geofence);
    expect(event.latitude, closeTo(d.plantLatitude + 0.0009, 1e-9));
  });

  test('a zone moved onto a truck standing still is detected', () async {
    // One position far from the plant, then no new positions (standing)
    await moveTo(40.3430, -3.5241);
    expect(next().status, DeliveryStatus.assigned);

    // "Plant = here": the check runs without waiting for a new position
    final d = next();
    await store.debugMoveGeofence(d.key,
        plant: true, latitude: 40.3430, longitude: -3.5241);
    await pumpEventQueue();
    expect(store.byKey(d.key)!.status, DeliveryStatus.atPlant);
  });

  test('small test zones: 15 m instead of 200 m', () async {
    final d = next();
    await geofence.setSmallTestZones(true);

    // ~50 m away: inside 200 m, but outside the 15 m test zone
    await moveTo(d.plantLatitude + 0.00045, d.plantLongitude);
    expect(next().status, DeliveryStatus.assigned);
    expect(geofence.distanceToPlantM(d), closeTo(50, 2));

    // ~10 m away: inside
    await moveTo(d.plantLatitude + 0.00009, d.plantLongitude);
    expect(store.byKey(d.key)!.status, DeliveryStatus.atPlant);
  });

  test('an imprecise GPS position is ignored', () async {
    final d = next();
    await moveTo(d.plantLatitude, d.plantLongitude, accuracy: 500);
    expect(next().status, DeliveryStatus.assigned);
  });

  test('the site zone only reminds, once per visit', () async {
    final d = next();
    await store.receiveWeights(d.key, tareTons: 14.2);
    await store.receiveWeights(d.key, grossTons: 34.24); // In transit

    // Arrive at the site: reminder, but the status does not change
    await moveTo(d.latitude, d.longitude);
    expect(store.byKey(d.key)!.status, DeliveryStatus.inTransit);
    expect(notified.map((x) => x.key), [d.key]);
    expect(geofence.siteReminder.value!.key, d.key);

    // Still inside: no second reminder
    await moveTo(d.latitude + 0.0005, d.longitude);
    expect(notified.length, 1);

    // Leave (>300 m) and come back: reminded again
    await moveTo(d.latitude + 0.005, d.longitude);
    await moveTo(d.latitude, d.longitude);
    expect(notified.length, 2);
  });

  test('the plant zone does nothing once the delivery has started', () async {
    final d = next();
    await store.receiveWeights(d.key, tareTons: 14.2); // Loading
    await moveTo(d.plantLatitude, d.plantLongitude);
    expect(store.byKey(d.key)!.status, DeliveryStatus.loading);
  });
}
