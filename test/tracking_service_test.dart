import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:truckg/data/app_database.dart';
import 'package:truckg/delivery_store.dart';
import 'package:truckg/mock_deliveries.dart';
import 'package:truckg/tracking/tracking_service.dart';

const truck = 'AB-1234';

Position fix(double lat, double lng, {DateTime? at}) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: at ?? DateTime.now(),
      accuracy: 8,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 90,
      headingAccuracy: 0,
      speed: 20, // m/s
      speedAccuracy: 0,
    );

void main() {
  sqfliteFfiInit();
  late StreamController<Position> gps;
  late TrackingService tracking;

  setUp(() async {
    await AppDatabase.open(
        path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    gps = StreamController<Position>();
    tracking = TrackingService(
      positions: (_) => gps.stream,
      checkReady: () async => null,
    );
    TrackingService.instance = tracking;
  });

  tearDown(() async {
    await tracking.stop();
    // Not awaited: close() never completes when nothing listened
    unawaited(gps.close());
    await AppDatabase.close();
  });

  Future<List<Map<String, Object?>>> saved() =>
      AppDatabase.db.query('gps_positions', orderBy: 'id');

  test('saves a position at most every 30 seconds', () async {
    await tracking.start(truck);
    expect(tracking.isRunning, isTrue);

    gps.add(fix(52.40, -1.50));
    gps.add(fix(52.41, -1.51)); // a few seconds later: not saved
    await pumpEventQueue();

    final rows = await saved();
    expect(rows.length, 1);
    expect(rows.single['truck_plate'], truck);
    expect(rows.single['speed_kmh'], closeTo(72, 0.01));
    expect(rows.single['sent'], 0);

    // The latest position is always known, even when not saved
    expect(tracking.lastPosition!.latitude, 52.41);
  });

  test('does not start without permission', () async {
    final noPermission = TrackingService(
      positions: (_) => gps.stream,
      checkReady: () async => 'Location permission is missing',
    );
    await noPermission.start(truck);
    expect(noPermission.isRunning, isFalse);
    expect(noPermission.problem, 'Location permission is missing');
  });

  test('status changes record the current GPS position', () async {
    final store = DeliveryStore.instance;
    await store.loadForTruck(truck);
    await tracking.start(truck);
    gps.add(fix(52.5545, -1.5260));
    await pumpEventQueue();

    final key = mockDeliveries.first.key;
    await store.setStatus(key, DeliveryStatus.atPlant,
        trigger: StatusTrigger.geofence);

    final events = await store.unsentEvents();
    expect(events.single.latitude, 52.5545);
    expect(events.single.longitude, -1.5260);
  });

  test('an old position is not attached to a status change', () async {
    final store = DeliveryStore.instance;
    await store.loadForTruck(truck);
    await tracking.start(truck);
    gps.add(fix(52.5545, -1.5260,
        at: DateTime.now().subtract(const Duration(minutes: 5))));
    await pumpEventQueue();

    await store.setStatus(mockDeliveries.first.key, DeliveryStatus.atPlant,
        trigger: StatusTrigger.geofence);
    expect((await store.unsentEvents()).single.latitude, isNull);
  });
}
