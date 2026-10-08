import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:truckg/data/app_database.dart';
import 'package:truckg/data/session_store.dart';
import 'package:truckg/delivery_store.dart';
import 'package:truckg/mock_deliveries.dart';

const truck = 'AB-1234';

void main() {
  sqfliteFfiInit();
  final store = DeliveryStore.instance;
  final first = mockDeliveries[0].key;
  final second = mockDeliveries[1].key;
  final third = mockDeliveries[2].key;

  // A fresh in-memory database for every test
  setUp(() async {
    await AppDatabase.open(
        path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    await store.loadForTruck(truck);
  });
  tearDown(AppDatabase.close);

  Future<List<Map<String, Object?>>> events(String key) {
    final d = store.byKey(key)!;
    return AppDatabase.db.query('status_events',
        where: 'delivery_number = ? AND plant_code = ?',
        whereArgs: [d.number, d.plantCode],
        orderBy: 'id');
  }

  test('test deliveries are loaded for the truck on first run', () {
    expect(store.current.length, mockDeliveries.length);
    expect(store.history.length, mockHistory.length);
    expect(store.byKey(first)!.truckPlate, truck);
    expect(store.byKey(first)!.shippingPoint, 'Quarry North - Plant 2');
  });

  test('weights from dispatching drive Loading and In transit', () async {
    await store.setStatus(first, DeliveryStatus.atPlant,
        trigger: StatusTrigger.geofence);
    await store.receiveWeights(first, tareTons: 14.2);
    expect(store.byKey(first)!.status, DeliveryStatus.loading);
    expect(store.byKey(first)!.loadedTons, isNull);

    await store.receiveWeights(first, grossTons: 34.24);
    expect(store.byKey(first)!.status, DeliveryStatus.inTransit);
    expect(store.byKey(first)!.loadedTons, closeTo(20.04, 0.0001));

    final rows = await events(first);
    expect(rows.map((r) => r['status']), ['atPlant', 'loading', 'inTransit']);
    expect(rows.first['trigger'], 'geofence');
    expect(rows.last['trigger'], 'dispatch');
    expect(rows.every((r) => r['sent'] == 0), isTrue);
  });

  test('status and weights survive a restart', () async {
    await store.receiveWeights(first, tareTons: 14.2);

    // Simulate closing and reopening the app
    await store.loadForTruck(null);
    await store.loadForTruck(truck);

    final d = store.byKey(first)!;
    expect(d.status, DeliveryStatus.loading);
    expect(d.tareTons, 14.2);
  });

  test('status never goes backwards, a missed geofence can be skipped',
      () async {
    await store.receiveWeights(second, tareTons: 14.2);
    expect(store.byKey(second)!.status, DeliveryStatus.loading);

    final changed = await store.setStatus(second, DeliveryStatus.atPlant,
        trigger: StatusTrigger.geofence);
    expect(changed, isFalse);
    expect(store.byKey(second)!.status, DeliveryStatus.loading);
  });

  test('cancelled and delivered are final', () async {
    await store.setStatus(third, DeliveryStatus.cancelled,
        trigger: StatusTrigger.dispatch);
    expect(store.current.any((d) => d.key == third), isFalse);

    final changed = await store.setStatus(third, DeliveryStatus.delivered,
        trigger: StatusTrigger.driver);
    expect(changed, isFalse);
    expect(store.byKey(third)!.status, DeliveryStatus.cancelled);
  });

  test('completing saves the signature and activities as unsent', () async {
    await store.completeDelivery(
      first,
      customerName: 'Dan Whitfield',
      customerNotes: null,
      driverNotes: 'Gate 2',
      signaturePng: Uint8List.fromList([1, 2, 3]),
      activities: const [
        ActivityRecord(code: 'waiting', value: '15', unit: 'min'),
      ],
    );
    expect(store.byKey(first)!.status, DeliveryStatus.delivered);

    final pod = await AppDatabase.db.query('proof_of_delivery');
    expect(pod.single['customer_name'], 'Dan Whitfield');
    expect(pod.single['signature'], [1, 2, 3]);
    expect(pod.single['sent'], 0);

    final acts = await AppDatabase.db.query('delivery_activities');
    expect(acts.single['activity_code'], 'waiting');
    expect(acts.single['value'], '15');
  });

  test('the driver keeps their truck after logout', () async {
    final session = SessionStore.instance;
    await session.login('drv2041');
    await session.saveTruckLink(truck, ['TR-1001']);
    await session.logout();

    await session.login('drv2041');
    final link = await session.truckLink();
    expect(link!.truckPlate, truck);
    expect(link.trailerPlates, ['TR-1001']);
    expect(await session.truckLink('someone-else'), isNull);
  });

  // Uses a file, because an in-memory database is empty when reopened.
  test('7-day clean-up only removes data already sent', () async {
    final path = '${(await databaseFactoryFfi.getDatabasesPath())}/cleanup.db';
    await AppDatabase.close();
    await databaseFactoryFfi.deleteDatabase(path);
    await AppDatabase.open(path: path, factory: databaseFactoryFfi);
    await store.loadForTruck(truck);

    final d = store.byKey(third)!;
    await store.setStatus(third, DeliveryStatus.cancelled,
        trigger: StatusTrigger.dispatch);
    final old =
        AppDatabase.toDbTime(DateTime.now().subtract(const Duration(days: 8)));
    final where = 'delivery_number = ? AND plant_code = ?';
    final args = [d.number, d.plantCode];
    await AppDatabase.db
        .update('deliveries', {'updated_at': old}, where: where, whereArgs: args);

    Future<int> count() async => (await AppDatabase.db
            .query('deliveries', where: where, whereArgs: args))
        .length;

    // Old, but its event is not sent yet: kept
    await AppDatabase.close();
    await AppDatabase.open(path: path, factory: databaseFactoryFfi);
    expect(await count(), 1);

    // Once sent: removed on the next start, with its events
    await AppDatabase.db.update('status_events', {'sent': 1},
        where: where, whereArgs: args);
    await AppDatabase.close();
    await AppDatabase.open(path: path, factory: databaseFactoryFfi);
    expect(await count(), 0);
    expect(
        (await AppDatabase.db
                .query('status_events', where: where, whereArgs: args))
            .length,
        0);

    await AppDatabase.close();
    await databaseFactoryFfi.deleteDatabase(path);
  });
}
