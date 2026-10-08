import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/app_database.dart';

/// Debug: sends the test results through the phone's share menu (WhatsApp,
/// email...), for testers far away. Until the API exists, this is the only
/// way to get the data off a phone without a computer.
///
/// - truckgo-<time>.db: a full copy of the database
/// - truckgo-<time>.gpx: the GPS trail, with the status changes as markers
///   (opens in Google Earth, Google My Maps and most map apps)
class TestDataExport {
  TestDataExport._();

  static Future<void> share({String? truckPlate}) async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .substring(0, 16)
        .replaceAll(':', '-')
        .replaceAll('T', '_');

    final dbFile = File(p.join(dir.path, 'truckgo-$stamp.db'));
    await copyDatabase(dbFile);

    final gpxFile = File(p.join(dir.path, 'truckgo-$stamp.gpx'));
    await gpxFile.writeAsString(await buildGpx(truckPlate: truckPlate));

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(dbFile.path), XFile(gpxFile.path)],
        subject: 'TruckGo test data $stamp',
        text: 'TruckGo test data${truckPlate == null ? '' : ' – $truckPlate'}',
      ),
    );
  }

  /// A consistent copy, even while the app keeps writing.
  static Future<void> copyDatabase(File target) async {
    if (await target.exists()) await target.delete();
    try {
      await AppDatabase.db.execute('VACUUM INTO ?', [target.path]);
    } catch (_) {
      // Older SQLite without VACUUM INTO: plain file copy
      final source = AppDatabase.path;
      if (source != null) await File(source).copy(target.path);
    }
  }

  /// GPX 1.1: the trail from gps_positions, status changes as waypoints.
  static Future<String> buildGpx({String? truckPlate}) async {
    final db = AppDatabase.db;
    final points = await db.query(
      'gps_positions',
      where: truckPlate == null ? null : 'truck_plate = ?',
      whereArgs: truckPlate == null ? null : [truckPlate],
      orderBy: 'recorded_at',
    );
    final events = await db.query(
      'status_events',
      where: 'latitude IS NOT NULL',
      orderBy: 'event_time',
    );

    final out = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<gpx version="1.1" creator="TruckGo" '
          'xmlns="http://www.topografix.com/GPX/1/1">');

    for (final e in events) {
      out
        ..writeln('  <wpt lat="${e['latitude']}" lon="${e['longitude']}">')
        ..writeln('    <time>${e['event_time']}</time>')
        ..writeln('    <name>${_xml('${e['status']} – ${e['delivery_number']}')}'
            '</name>')
        ..writeln('    <desc>${_xml('trigger: ${e['trigger']}')}</desc>')
        ..writeln('  </wpt>');
    }

    out
      ..writeln('  <trk>')
      ..writeln('    <name>${_xml('TruckGo ${truckPlate ?? ''}'.trim())}</name>')
      ..writeln('    <trkseg>');
    for (final pt in points) {
      out.writeln('      <trkpt lat="${pt['latitude']}" lon="${pt['longitude']}">'
          '<time>${pt['recorded_at']}</time></trkpt>');
    }
    out
      ..writeln('    </trkseg>')
      ..writeln('  </trk>')
      ..writeln('</gpx>');
    return out.toString();
  }

  static String _xml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
