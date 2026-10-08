import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'data/app_database.dart';
import 'mock_deliveries.dart';
import 'tracking/tracking_service.dart';

/// One extra activity recorded at the customer site.
class ActivityRecord {
  const ActivityRecord({required this.code, this.value, this.unit});

  final String code;
  final String? value;
  final String? unit;
}

/// Holds the truck's deliveries and is the only place their status changes.
///
/// Every change is applied in memory first (the screen updates at once) and
/// then saved to SQLite, together with the event to send to dispatching.
/// Later, the API client will feed it from the server.
class DeliveryStore extends ChangeNotifier {
  DeliveryStore._();

  static final DeliveryStore instance = DeliveryStore._();

  List<Delivery> _deliveries = [];
  String? _truckPlate;

  /// The truck whose deliveries are loaded.
  String? get truckPlate => _truckPlate;

  /// Loads the deliveries of [truckPlate] (none when null).
  // TODO: refresh from the API before reading the table.
  Future<void> loadForTruck(String? truckPlate) async {
    _truckPlate = truckPlate;
    if (truckPlate == null) {
      _deliveries = [];
    } else {
      final db = AppDatabase.db;
      final any = await db.query('deliveries', columns: ['1'], limit: 1);
      if (any.isEmpty) await AppDatabase.seedTestDeliveries(truckPlate);

      final rows = await db.rawQuery(
          '${AppDatabase.deliverySelect} WHERE d.truck_plate = ?',
          [truckPlate]);
      _deliveries = rows.map(AppDatabase.deliveryFromRow).toList();
    }
    notifyListeners();
  }

  /// Debug: gives the current truck a fresh set of test deliveries.
  Future<void> resetTestData() async {
    final truck = _truckPlate;
    if (truck == null) return;
    await AppDatabase.seedTestDeliveries(truck);
    await loadForTruck(truck);
  }

  /// Debug: moves the plant (all its deliveries) or the customer site of
  /// delivery [key] to a position, to test the geofences on foot.
  Future<void> debugMoveGeofence(
    String key, {
    required bool plant,
    required double latitude,
    required double longitude,
  }) async {
    final d = byKey(key);
    if (d == null) return;
    if (plant) {
      await AppDatabase.db.update(
        'plants',
        {'latitude': latitude, 'longitude': longitude},
        where: 'plant_code = ?',
        whereArgs: [d.plantCode],
      );
    } else {
      await AppDatabase.db.update(
        'deliveries',
        {'site_latitude': latitude, 'site_longitude': longitude},
        where: 'delivery_number = ? AND plant_code = ?',
        whereArgs: [d.number, d.plantCode],
      );
    }
    await loadForTruck(_truckPlate);
  }

  /// Open deliveries, the next one first.
  List<Delivery> get current =>
      _deliveries.where((d) => !d.status.isFinished).toList()
        ..sort((a, b) => a.scheduled.compareTo(b.scheduled));

  /// Delivered and cancelled deliveries, the latest first.
  List<Delivery> get history =>
      _deliveries.where((d) => d.status.isFinished).toList()
        ..sort((a, b) => b.scheduled.compareTo(a.scheduled));

  Delivery? byKey(String key) {
    for (final d in _deliveries) {
      if (d.key == key) return d;
    }
    return null;
  }

  /// Status changes not yet sent to dispatching (read by the API client).
  Future<List<StatusEvent>> unsentEvents() async {
    final rows = await AppDatabase.db
        .query('status_events', where: 'sent = 0', orderBy: 'id');
    return [
      for (final r in rows)
        StatusEvent(
          deliveryNumber: r['delivery_number'] as String,
          plantCode: r['plant_code'] as String,
          status: DeliveryStatus.values.byName(r['status'] as String),
          trigger: StatusTrigger.values.byName(r['trigger'] as String),
          time: AppDatabase.fromDbTime(r['event_time']),
          latitude: (r['latitude'] as num?)?.toDouble(),
          longitude: (r['longitude'] as num?)?.toDouble(),
        ),
    ];
  }

  /// Moves a delivery to [status]. Ignored when it would go backwards or the
  /// delivery is already finished, so a late or repeated event is harmless.
  /// Returns true when the status changed.
  Future<bool> setStatus(
    String key,
    DeliveryStatus status, {
    required StatusTrigger trigger,
  }) async {
    final index = _deliveries.indexWhere((d) => d.key == key);
    if (index < 0) return false;
    final delivery = _deliveries[index];

    if (delivery.status.isFinished) return false;
    if (status != DeliveryStatus.cancelled &&
        status.index <= delivery.status.index) {
      return false;
    }

    _deliveries[index] = delivery.copyWith(status: status);
    notifyListeners();

    final now = DateTime.now();
    await AppDatabase.db.transaction((txn) async {
      await txn.update(
        'deliveries',
        {'status': status.name, 'updated_at': AppDatabase.toDbTime(now)},
        where: 'delivery_number = ? AND plant_code = ?',
        whereArgs: [delivery.number, delivery.plantCode],
      );
      final here = TrackingService.instance.freshPosition;
      await txn.insert('status_events', {
        'delivery_number': delivery.number,
        'plant_code': delivery.plantCode,
        'status': status.name,
        'trigger': trigger.name,
        'event_time': AppDatabase.toDbTime(now),
        'latitude': here?.latitude,
        'longitude': here?.longitude,
      });
    });
    return true;
  }

  /// Weights received from dispatching. The 1st weight (tare) moves the
  /// delivery to Loading, the 2nd weight (gross) to In transit.
  Future<void> receiveWeights(
    String key, {
    double? tareTons,
    double? grossTons,
  }) async {
    final index = _deliveries.indexWhere((d) => d.key == key);
    if (index < 0) return;
    final updated = _deliveries[index]
        .copyWith(tareTons: tareTons, grossTons: grossTons);
    _deliveries[index] = updated;

    await AppDatabase.db.update(
      'deliveries',
      {
        'tare_tons': updated.tareTons,
        'gross_tons': updated.grossTons,
        'updated_at': AppDatabase.toDbTime(DateTime.now()),
      },
      where: 'delivery_number = ? AND plant_code = ?',
      whereArgs: [updated.number, updated.plantCode],
    );

    final next = updated.grossTons != null
        ? DeliveryStatus.inTransit
        : (updated.tareTons != null ? DeliveryStatus.loading : null);

    // setStatus notifies; notify here only when the status did not change.
    if (next == null ||
        !await setStatus(key, next, trigger: StatusTrigger.dispatch)) {
      notifyListeners();
    }
  }

  /// Saves the proof of delivery and the extra activities, then marks the
  /// delivery as Delivered.
  Future<void> completeDelivery(
    String key, {
    required String customerName,
    required String? customerNotes,
    required String? driverNotes,
    required Uint8List? signaturePng,
    required List<ActivityRecord> activities,
  }) async {
    final d = byKey(key);
    if (d == null) return;

    await AppDatabase.db.transaction((txn) async {
      await txn.insert('proof_of_delivery', {
        'delivery_number': d.number,
        'plant_code': d.plantCode,
        'customer_name': customerName,
        'customer_notes': customerNotes,
        'driver_notes': driverNotes,
        'signature': signaturePng,
        'accepted': 1,
        'signed_at': AppDatabase.toDbTime(DateTime.now()),
      });
      for (final a in activities) {
        await txn.insert('delivery_activities', {
          'delivery_number': d.number,
          'plant_code': d.plantCode,
          'activity_code': a.code,
          'value': a.value,
          'unit': a.unit,
        });
      }
    });

    await setStatus(key, DeliveryStatus.delivered,
        trigger: StatusTrigger.driver);
  }
}
