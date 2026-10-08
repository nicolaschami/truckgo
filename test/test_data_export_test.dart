import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:truckg/data/app_database.dart';
import 'package:truckg/tracking/test_data_export.dart';

void main() {
  sqfliteFfiInit();

  setUp(() async {
    await AppDatabase.open(
        path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    final db = AppDatabase.db;
    for (final (lat, lng, t) in [
      (40.3430, -3.5241, '2026-10-08T08:00:00.000Z'),
      (40.3440, -3.5250, '2026-10-08T08:00:30.000Z'),
    ]) {
      await db.insert('gps_positions', {
        'truck_plate': 'AB-1234',
        'latitude': lat,
        'longitude': lng,
        'recorded_at': t,
      });
    }
    await db.insert('status_events', {
      'delivery_number': '422211',
      'plant_code': 'QN2',
      'status': 'atPlant',
      'trigger': 'geofence',
      'event_time': '2026-10-08T08:00:10.000Z',
      'latitude': 40.3431,
      'longitude': -3.5242,
    });
  });
  tearDown(AppDatabase.close);

  test('GPX has the trail and the status changes as markers', () async {
    final gpx = await TestDataExport.buildGpx(truckPlate: 'AB-1234');

    expect(gpx, startsWith('<?xml'));
    expect('<trkpt '.allMatches(gpx).length, 2);
    expect(gpx, contains('<trkpt lat="40.343" lon="-3.5241">'
        '<time>2026-10-08T08:00:00.000Z</time></trkpt>'));
    expect(gpx, contains('<wpt lat="40.3431" lon="-3.5242">'));
    expect(gpx, contains('<name>atPlant – 422211</name>'));
    expect(gpx, contains('<desc>trigger: geofence</desc>'));
  });

  test('the database copy is a complete, readable database', () async {
    final dir = await Directory.systemTemp.createTemp('truckgo_export');
    final copy = File('${dir.path}/copy.db');

    await TestDataExport.copyDatabase(copy);
    expect(await copy.exists(), isTrue);

    final db = await databaseFactoryFfi.openDatabase(copy.path);
    final rows = await db.query('gps_positions');
    expect(rows.length, 2);
    await db.close();
    await dir.delete(recursive: true);
  });
}
