import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../mock_deliveries.dart';
import '../mock_vehicles.dart';

/// The app's local SQLite database (see docs/system-design.md).
///
/// Tables filled from dispatching: vehicles, plants, deliveries.
/// Tables sent to dispatching (offline queue, `sent` = 0 until sent):
/// status_events, gps_positions, proof_of_delivery, delivery_activities.
/// Local only: session, driver_trucks.
class AppDatabase {
  AppDatabase._();

  static const _version = 1;
  static const keepDays = 7;

  static Database? _db;

  /// Where the database file is (for the debug "Share test data").
  static String? path;

  static Database get db {
    final db = _db;
    if (db == null) throw StateError('AppDatabase.open() was not called');
    return db;
  }

  /// Opens (and creates on first run) the database. Tests pass an in-memory
  /// [path] and their own [factory].
  static Future<Database> open({String? path, DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), 'truckgo.db');
    AppDatabase.path = dbPath;
    _db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: _version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) => _createTables(db),
      ),
    );
    await _cleanUp(_db!);
    return _db!;
  }

  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  // ---------------------------------------------------------------
  // SCHEMA
  // ---------------------------------------------------------------

  static Future<void> _createTables(Database db) async {
    final batch = db.batch();

    // Who is logged in (one row)
    batch.execute('''
      CREATE TABLE session (
        id            INTEGER PRIMARY KEY CHECK (id = 1),
        username      TEXT NOT NULL,
        api_token     TEXT,
        logged_in_at  TEXT NOT NULL
      )''');

    // Remembered driver <-> truck link (kept after logout)
    batch.execute('''
      CREATE TABLE driver_trucks (
        username        TEXT PRIMARY KEY,
        truck_plate     TEXT NOT NULL,
        trailer_plates  TEXT NOT NULL DEFAULT '',
        linked_at       TEXT NOT NULL
      )''');

    batch.execute('''
      CREATE TABLE vehicles (
        plate     TEXT PRIMARY KEY,
        is_truck  INTEGER NOT NULL,
        model     TEXT NOT NULL,
        detail    TEXT NOT NULL,
        status    TEXT NOT NULL
      )''');

    batch.execute('''
      CREATE TABLE plants (
        plant_code         TEXT PRIMARY KEY,
        name               TEXT NOT NULL,
        latitude           REAL NOT NULL,
        longitude          REAL NOT NULL,
        geofence_radius_m  REAL NOT NULL DEFAULT 200
      )''');

    batch.execute('''
      CREATE TABLE deliveries (
        delivery_number         TEXT NOT NULL,
        plant_code              TEXT NOT NULL REFERENCES plants (plant_code),
        order_number            TEXT NOT NULL,
        truck_plate             TEXT,
        sold_to_code            TEXT NOT NULL,
        sold_to_name            TEXT NOT NULL,
        ship_to_name            TEXT NOT NULL,
        ship_to_address         TEXT NOT NULL,
        site_latitude           REAL NOT NULL,
        site_longitude          REAL NOT NULL,
        site_geofence_radius_m  REAL NOT NULL DEFAULT 200,
        site_contact            TEXT NOT NULL,
        material                TEXT NOT NULL,
        ordered_tons            REAL NOT NULL,
        tare_tons               REAL,
        gross_tons              REAL,
        scheduled_at            TEXT NOT NULL,
        window_start            TEXT NOT NULL,
        window_end              TEXT NOT NULL,
        distance_km             REAL NOT NULL,
        notes                   TEXT,
        status                  TEXT NOT NULL,
        updated_at              TEXT NOT NULL,
        PRIMARY KEY (delivery_number, plant_code)
      )''');
    batch.execute(
        'CREATE INDEX idx_deliveries_truck ON deliveries (truck_plate)');

    batch.execute('''
      CREATE TABLE status_events (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        delivery_number  TEXT NOT NULL,
        plant_code       TEXT NOT NULL,
        status           TEXT NOT NULL,
        trigger          TEXT NOT NULL,
        event_time       TEXT NOT NULL,
        latitude         REAL,
        longitude        REAL,
        sent             INTEGER NOT NULL DEFAULT 0,
        sent_at          TEXT
      )''');
    batch.execute('CREATE INDEX idx_status_events_sent ON status_events (sent)');

    batch.execute('''
      CREATE TABLE gps_positions (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        truck_plate  TEXT NOT NULL,
        latitude     REAL NOT NULL,
        longitude    REAL NOT NULL,
        accuracy_m   REAL,
        speed_kmh    REAL,
        heading      REAL,
        recorded_at  TEXT NOT NULL,
        sent         INTEGER NOT NULL DEFAULT 0,
        sent_at      TEXT
      )''');
    batch.execute('CREATE INDEX idx_gps_positions_sent ON gps_positions (sent)');

    batch.execute('''
      CREATE TABLE proof_of_delivery (
        delivery_number  TEXT NOT NULL,
        plant_code       TEXT NOT NULL,
        customer_name    TEXT NOT NULL,
        customer_notes   TEXT,
        driver_notes     TEXT,
        signature        BLOB,
        accepted         INTEGER NOT NULL,
        signed_at        TEXT NOT NULL,
        sent             INTEGER NOT NULL DEFAULT 0,
        sent_at          TEXT,
        PRIMARY KEY (delivery_number, plant_code)
      )''');

    batch.execute('''
      CREATE TABLE delivery_activities (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        delivery_number  TEXT NOT NULL,
        plant_code       TEXT NOT NULL,
        activity_code    TEXT NOT NULL,
        value            TEXT,
        unit             TEXT
      )''');

    await batch.commit(noResult: true);
  }

  // ---------------------------------------------------------------
  // 7-DAY CLEAN-UP: only data already sent to dispatching is removed
  // ---------------------------------------------------------------

  static Future<void> _cleanUp(Database db) async {
    final limit = toDbTime(DateTime.now().subtract(const Duration(days: keepDays)));

    await db.transaction((txn) async {
      await txn.delete('gps_positions',
          where: 'sent = 1 AND recorded_at < ?', whereArgs: [limit]);

      // Finished deliveries with nothing left to send
      await txn.rawDelete('''
        DELETE FROM deliveries
        WHERE status IN ('delivered', 'cancelled')
          AND updated_at < ?
          AND NOT EXISTS (
            SELECT 1 FROM status_events e
            WHERE e.delivery_number = deliveries.delivery_number
              AND e.plant_code = deliveries.plant_code AND e.sent = 0)
          AND NOT EXISTS (
            SELECT 1 FROM proof_of_delivery pod
            WHERE pod.delivery_number = deliveries.delivery_number
              AND pod.plant_code = deliveries.plant_code AND pod.sent = 0)
      ''', [limit]);

      // Sent rows that belong to deliveries that no longer exist
      for (final table in [
        'status_events',
        'proof_of_delivery',
        'delivery_activities',
      ]) {
        await txn.rawDelete('''
          DELETE FROM $table
          WHERE NOT EXISTS (
            SELECT 1 FROM deliveries d
            WHERE d.delivery_number = $table.delivery_number
              AND d.plant_code = $table.plant_code)
          ${table == 'delivery_activities' ? '' : 'AND sent = 1'}
        ''');
      }
    });
  }

  // ---------------------------------------------------------------
  // TEST DATA (until the API fills these tables)
  // ---------------------------------------------------------------

  /// Fills vehicles and plants on first run.
  static Future<void> seedReferenceData() async {
    final count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM vehicles'));
    if (count != null && count > 0) return;

    final batch = db.batch();
    for (final v in [...mockTrucks, ...mockTrailers]) {
      batch.insert('vehicles', {
        'plate': v.plate,
        'is_truck': v.isTruck ? 1 : 0,
        'model': v.model,
        'detail': v.detail,
        'status': v.status.name,
      });
    }
    for (final d in [...mockDeliveries, ...mockHistory]) {
      batch.insert(
        'plants',
        {
          'plant_code': d.plantCode,
          'name': d.shippingPoint,
          'latitude': d.plantLatitude,
          'longitude': d.plantLongitude,
          'geofence_radius_m': d.plantGeofenceRadiusM,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Gives [truckPlate] the test deliveries. Existing test deliveries (same
  /// keys) are replaced, with everything recorded for them.
  static Future<void> seedTestDeliveries(String truckPlate) async {
    await seedReferenceData();
    await db.transaction((txn) async {
      for (final d in [...mockDeliveries, ...mockHistory]) {
        // Test plants back to their place (the debug tools can move them)
        await txn.update(
          'plants',
          {'latitude': d.plantLatitude, 'longitude': d.plantLongitude},
          where: 'plant_code = ?',
          whereArgs: [d.plantCode],
        );

        final where = 'delivery_number = ? AND plant_code = ?';
        final args = [d.number, d.plantCode];
        for (final table in [
          'status_events',
          'proof_of_delivery',
          'delivery_activities',
          'deliveries',
        ]) {
          await txn.delete(table, where: where, whereArgs: args);
        }
        await txn.insert(
            'deliveries', deliveryToRow(d.copyWith(truckPlate: truckPlate)));
      }
    });
  }

  // ---------------------------------------------------------------
  // MAPPING
  // ---------------------------------------------------------------

  /// Dates are stored as UTC ISO-8601 text.
  static String toDbTime(DateTime t) => t.toUtc().toIso8601String();
  static DateTime fromDbTime(Object? v) => DateTime.parse(v as String).toLocal();

  static Map<String, Object?> deliveryToRow(Delivery d) => {
        'delivery_number': d.number,
        'plant_code': d.plantCode,
        'order_number': d.orderNumber,
        'truck_plate': d.truckPlate,
        'sold_to_code': d.soldToCode,
        'sold_to_name': d.soldToName,
        'ship_to_name': d.shipToName,
        'ship_to_address': d.shipToAddress,
        'site_latitude': d.latitude,
        'site_longitude': d.longitude,
        'site_geofence_radius_m': d.siteGeofenceRadiusM,
        'site_contact': d.siteContact,
        'material': d.material,
        'ordered_tons': d.orderedTons,
        'tare_tons': d.tareTons,
        'gross_tons': d.grossTons,
        'scheduled_at': toDbTime(d.scheduled),
        'window_start': toDbTime(d.windowStart),
        'window_end': toDbTime(d.windowEnd),
        'distance_km': d.distanceKm,
        'notes': d.notes,
        'status': d.status.name,
        'updated_at': toDbTime(DateTime.now()),
      };

  /// [row] is a deliveries row joined with its plant (see [deliverySelect]).
  static Delivery deliveryFromRow(Map<String, Object?> row) => Delivery(
        number: row['delivery_number'] as String,
        plantCode: row['plant_code'] as String,
        orderNumber: row['order_number'] as String,
        truckPlate: row['truck_plate'] as String?,
        soldToCode: row['sold_to_code'] as String,
        soldToName: row['sold_to_name'] as String,
        shipToName: row['ship_to_name'] as String,
        shipToAddress: row['ship_to_address'] as String,
        latitude: (row['site_latitude'] as num).toDouble(),
        longitude: (row['site_longitude'] as num).toDouble(),
        siteGeofenceRadiusM: (row['site_geofence_radius_m'] as num).toDouble(),
        siteContact: row['site_contact'] as String,
        shippingPoint: row['plant_name'] as String,
        plantLatitude: (row['plant_latitude'] as num).toDouble(),
        plantLongitude: (row['plant_longitude'] as num).toDouble(),
        plantGeofenceRadiusM: (row['plant_radius_m'] as num).toDouble(),
        material: row['material'] as String,
        orderedTons: (row['ordered_tons'] as num).toDouble(),
        tareTons: (row['tare_tons'] as num?)?.toDouble(),
        grossTons: (row['gross_tons'] as num?)?.toDouble(),
        scheduled: fromDbTime(row['scheduled_at']),
        windowStart: fromDbTime(row['window_start']),
        windowEnd: fromDbTime(row['window_end']),
        distanceKm: (row['distance_km'] as num).toDouble(),
        notes: row['notes'] as String?,
        status: DeliveryStatus.values.byName(row['status'] as String),
      );

  static const deliverySelect = '''
    SELECT d.*, p.name AS plant_name, p.latitude AS plant_latitude,
           p.longitude AS plant_longitude, p.geofence_radius_m AS plant_radius_m
    FROM deliveries d
    JOIN plants p ON p.plant_code = d.plant_code
  ''';
}
