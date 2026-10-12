import 'package:sqflite/sqflite.dart';

import '../api/api_client.dart';
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

  /// Restores the driver saved by the last login (call once at start-up),
  /// with their login token, so the app can talk to the server at once.
  Future<void> load() async {
    final rows = await _db.query('session', limit: 1);
    _username = rows.isEmpty ? null : rows.first['username'] as String;
    ApiClient.instance.token =
        rows.isEmpty ? null : rows.first['api_token'] as String?;
  }

  /// Remembers the driver after the server accepted their PIN, with the
  /// token the server gave (sent with every call from now on).
  Future<void> login(String username, String token) async {
    _username = username;
    ApiClient.instance.token = token;
    await _db.insert(
      'session',
      {
        'id': 1,
        'username': username,
        'api_token': token,
        'logged_in_at': AppDatabase.toDbTime(DateTime.now()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Logs out. The driver's truck link is kept for the next login.
  Future<void> logout() async {
    _username = null;
    ApiClient.instance.token = null;
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

  /// Replaces the stored vehicles with the server's list. Throws an
  /// ApiException when the server cannot be reached (the old list stays).
  Future<void> refreshVehicles() async {
    final fresh = await ApiClient.instance.vehicles();
    await _db.transaction((txn) async {
      await txn.delete('vehicles');
      for (final v in fresh) {
        await txn.insert('vehicles', {
          'plate': v.plate,
          'is_truck': v.isTruck ? 1 : 0,
          'model': v.model,
          'detail': v.detail,
          'status': v.status.name,
        });
      }
    });
  }

  /// The stored trucks (or trailers): the last list received from the server.
  Future<List<Vehicle>> vehicles({required bool trucks}) async {
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
