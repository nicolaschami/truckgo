import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:truckg/api/api_client.dart';
import 'package:truckg/api/delivery_sync.dart';
import 'package:truckg/data/app_database.dart';
import 'package:truckg/delivery_store.dart';
import 'package:truckg/mock_deliveries.dart';

const truck = 'AB-1234';

/// A delivery as the server sends it (DeliveryDto), with the fields a test
/// wants to change.
Map<String, dynamic> dto(String number,
    {String status = 'assigned', double? tare, double? gross}) => {
      'number': number,
      'plantCode': 'QN2',
      'plantName': 'Quarry North - Plant 2',
      'plantLatitude': 52.55,
      'plantLongitude': -1.52,
      'plantGeofenceRadiusM': 200,
      'orderNumber': 'SO-$number',
      'truckPlate': truck,
      'trailerPlate': 'TR-1001',
      'soldToCode': '100245',
      'soldToName': 'Northgate Construction Ltd',
      'shipToCode': '100245-01',
      'shipToName': 'Riverside Arena Works',
      'shipToAddress': 'Arena Way, Coventry',
      'siteLatitude': 52.44,
      'siteLongitude': -1.49,
      'siteGeofenceRadiusM': 200,
      'siteContact': 'Dan Whitfield',
      'sitePhone': null,
      'material': 'AC 32 dense base 40/60',
      'orderedTons': 20,
      'tareTons': tare,
      'tareWeighedAt': null,
      'grossTons': gross,
      'grossWeighedAt': null,
      'loadedTons': null,
      'weighbridgeTicket': null,
      'scheduledAt': '2026-10-13T09:00:00Z',
      'windowStart': '2026-10-13T08:45:00Z',
      'windowEnd': '2026-10-13T09:15:00Z',
      'distanceKm': 12.5,
      'notes': null,
      'status': status,
      'updatedAt': '2026-10-13T07:00:00Z',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // DeliverySync watches the app's life cycle
  sqfliteFfiInit();
  final store = DeliveryStore.instance;
  final sync = DeliverySync.instance;

  // The fake server: each test says what the next answers are, and every
  // request the app made is kept to check it
  late List<Object> answers; // a JSON answer, or an exception to throw
  late List<http.Request> requests;
  var serverClock = DateTime.utc(2026, 10, 13, 8);

  Map<String, dynamic> page(List<Map<String, dynamic>> deliveries,
      {List<String> removed = const []}) {
    serverClock = serverClock.add(const Duration(minutes: 1));
    return {
      'serverTime': serverClock.toIso8601String(),
      'deliveries': deliveries,
      'removed': [
        for (final n in removed) {'plantCode': 'QN2', 'number': n},
      ],
    };
  }

  setUp(() async {
    await AppDatabase.open(
        path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    await store.loadForTruck(truck);
    answers = [];
    requests = [];
    ApiClient.instance.httpClient = MockClient((request) async {
      requests.add(request);
      final next = answers.removeAt(0);
      if (next is Exception) throw next;
      if (next is int) return http.Response('', next); // a status code
      return http.Response(jsonEncode(next), 200);
    });
  });

  tearDown(() async {
    sync.stop();
    await AppDatabase.close();
  });

  String key(String number) => deliveryKey(number, 'QN2');

  test('the first call gets the full list, the next ones only changes', () async {
    answers = [
      page([dto('500001'), dto('500002')]),
      page([dto('500003')]), // a new delivery planned meanwhile
    ];

    await sync.start(truck);
    expect(requests[0].url.path, '/api/v1/trucks/AB-1234/deliveries');
    expect(requests[0].url.queryParameters, isEmpty); // no "since": all of them
    expect(store.current.map((d) => d.number), ['500001', '500002']);
    expect(store.byKey(key('500001'))!.shippingPoint, 'Quarry North - Plant 2');

    await sync.syncNow();
    // "since" = the server's time of the previous answer
    expect(requests[1].url.queryParameters['since'],
        startsWith('2026-10-13T08:01:00'));
    expect(store.current.length, 3); // added quietly to the list
    expect(sync.lastError.value, isNull);
    expect(sync.lastSuccess.value, isNotNull);
  });

  test('a delivery moved to another truck leaves the list', () async {
    answers = [
      page([dto('500001'), dto('500002')]),
      page([], removed: ['500002']),
    ];
    await sync.start(truck);
    await sync.syncNow();

    expect(store.current.map((d) => d.number), ['500001']);
    expect(sync.movedAway.value, isNull); // not started: no message needed
  });

  test('the driver is told when a started delivery is moved away, '
      'and its unsent statuses are kept', () async {
    answers = [
      page([dto('500001')]),
      page([], removed: ['500001']),
    ];
    await sync.start(truck);
    await store.setStatus(key('500001'), DeliveryStatus.atPlant,
        trigger: StatusTrigger.geofence);

    await sync.syncNow();

    expect(store.current, isEmpty);
    expect(sync.movedAway.value!.number, '500001');
    expect((await store.unsentEvents()).single.status, DeliveryStatus.atPlant);
  });

  test('the full list removes what the server no longer lists', () async {
    await AppDatabase.seedTestDeliveries(truck); // old deliveries on the phone
    await store.loadForTruck(truck);
    expect(store.current, isNotEmpty);

    answers = [page([dto('500001')])];
    await sync.start(truck);

    expect(store.current.map((d) => d.number), ['500001']);
    expect(store.history, isEmpty);
  });

  test("the status only moves forward: the phone's own progress stays", () async {
    answers = [
      page([dto('500001')]),
      page([dto('500001')]), // server still says "assigned"
      page([dto('500001', tare: 14.2)]), // the 1st weight
      page([dto('500001', tare: 14.2, gross: 34.24)]), // the 2nd weight
    ];
    await sync.start(truck);
    await store.setStatus(key('500001'), DeliveryStatus.atPlant,
        trigger: StatusTrigger.geofence);

    await sync.syncNow();
    expect(store.byKey(key('500001'))!.status, DeliveryStatus.atPlant);

    await sync.syncNow();
    expect(store.byKey(key('500001'))!.status, DeliveryStatus.loading);

    await sync.syncNow();
    final d = store.byKey(key('500001'))!;
    expect(d.status, DeliveryStatus.inTransit);
    expect(d.loadedTons, closeTo(20.04, 0.0001));
    expect((await store.unsentEvents()).map((e) => e.status),
        [DeliveryStatus.atPlant, DeliveryStatus.loading, DeliveryStatus.inTransit]);
  });

  test('a cancellation from the server applies', () async {
    answers = [
      page([dto('500001')]),
      page([dto('500001', status: 'cancelled')]),
    ];
    await sync.start(truck);
    await sync.syncNow();

    expect(store.current, isEmpty);
    expect(store.history.single.status, DeliveryStatus.cancelled);
  });

  test('offline: the list stays and the next call asks again', () async {
    answers = [
      page([dto('500001')]),
      const SocketException('no network'),
      page([dto('500002')]),
    ];
    await sync.start(truck);

    await sync.syncNow();
    expect(sync.lastError.value!.kind, ApiErrorKind.offline);
    expect(store.current.length, 1);

    // Back online: still "since" the last answer that worked
    await sync.syncNow();
    expect(requests[2].url.queryParameters['since'],
        requests[1].url.queryParameters['since']);
    expect(store.current.length, 2);
    expect(sync.lastError.value, isNull);
  });

  test('an expired login is reported as unauthorized', () async {
    answers = [401];
    await sync.start(truck);
    expect(sync.lastError.value!.kind, ApiErrorKind.unauthorized);
  });

  test('login sends the PIN and reads the token', () async {
    answers = [
      {
        'accessToken': 'abc',
        'expiresAt': '2026-10-13T20:00:00Z',
        'driver': {
          'username': 'test1',
          'displayName': 'Test Driver',
          'companyCode': 'DEMO',
          'companyName': 'TruckGo Demo',
        },
        'mustChangePin': false,
      },
    ];
    final result = await ApiClient.instance.login('test1', '1234');

    expect(result.accessToken, 'abc');
    expect(result.displayName, 'Test Driver');
    expect(jsonDecode(requests.single.body), {'username': 'test1', 'pin': '1234'});
  });
}
