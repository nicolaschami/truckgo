import 'package:sqflite/sqflite.dart';

import '../mock_vehicles.dart';
import 'app_database.dart';

/// A driver's remembered truck (and trailers).
class TruckLink {
  const TruckLink({required this.truckPlate, required this.trailerPlates});

  final String truckPlate;
  final List<String> trailerPlates;
}

/// The logged-in driver, their remembered truck, and the vehicles list.
class SessionStore {
  SessionStore._();

  static final SessionStore instance = SessionStore._();

  Database get _db => AppDatabase.db;

  String? _username;

  /// The logged-in driver, or null.
  String? get username => _username;

  /// Restores the driver saved by the last login (call once at start-up).
  Future<void> load() async {
    final rows = await _db.query('session', limit: 1);
    _username = rows.isEmpty ? null : rows.first['username'] as String;
  }

  // TODO: save the API token returned by the login endpoint.
  Future<void> login(String username) async {
    _username = username;
    await _db.insert(
      'session',
      {
        'id': 1,
        'username': username,
        'logged_in_at': AppDatabase.toDbTime(DateTime.now()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Logs out. The driver's truck link is kept for the next login.
  Future<void> logout() async {
    _username = null;
    await _db.delete('session');
  }

  // ---------------------------------------------------------------
  // DRIVER <-> TRUCK LINK
  // ---------------------------------------------------------------

  Future<TruckLink?> truckLink([String? username]) async {
    final user = username ?? _username;
    if (user == null) return null;
    final rows = await _db.query('driver_trucks',
        where: 'username = ?', whereArgs: [user], limit: 1);
    if (rows.isEmpty) return null;
    final trailers = rows.first['trailer_plates'] as String;
    return TruckLink(
      truckPlate: rows.first['truck_plate'] as String,
      trailerPlates: trailers.isEmpty ? [] : trailers.split(','),
    );
  }

  Future<void> saveTruckLink(String truckPlate, List<String> trailerPlates) async {
    final user = _username;
    if (user == null) return;
    await _db.insert(
      'driver_trucks',
      {
        'username': user,
        'truck_plate': truckPlate,
        'trailer_plates': trailerPlates.join(','),
        'linked_at': AppDatabase.toDbTime(DateTime.now()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Forgets the link, e.g. when the driver works without a truck today.
  Future<void> clearTruckLink() async {
    final user = _username;
    if (user == null) return;
    await _db.delete('driver_trucks', where: 'username = ?', whereArgs: [user]);
  }

  // ---------------------------------------------------------------
  // VEHICLES
  // ---------------------------------------------------------------

  // TODO: refresh this table from the API.
  Future<List<Vehicle>> vehicles({required bool trucks}) async {
    await AppDatabase.seedReferenceData();
    final rows = await _db.query('vehicles',
        where: 'is_truck = ?', whereArgs: [trucks ? 1 : 0], orderBy: 'plate');
    return [
      for (final r in rows)
        Vehicle(
          plate: r['plate'] as String,
          model: r['model'] as String,
          detail: r['detail'] as String,
          isTruck: r['is_truck'] == 1,
          status: VehicleStatus.values.byName(r['status'] as String),
        ),
    ];
  }
}
