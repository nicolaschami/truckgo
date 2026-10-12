import 'dart:async';

import 'package:flutter/widgets.dart';

import '../delivery_store.dart';
import '../mock_deliveries.dart';
import 'api_client.dart';

/// Keeps the phone's deliveries in step with the server.
///
/// While a truck's deliveries are open it asks the server
///   - once at the start: ALL the truck's deliveries;
///   - then every [interval]: only what changed since the last answer
///     (`?since=`), usually nothing — a tiny, cheap call;
///   - at once when the app comes back to the screen, and when the driver
///     pulls the list down ([syncNow]).
/// A call that fails (no network) is simply tried again at the next tick:
/// the phone keeps working with what it has.
class DeliverySync with WidgetsBindingObserver {
  DeliverySync._();

  static final DeliverySync instance = DeliverySync._();

  static const interval = Duration(seconds: 60);

  String? _truckPlate;

  /// The server's time of the last answer: "what changed after this?".
  /// Null = the next call asks for the full list.
  DateTime? _since;

  Timer? _timer;
  Future<void>? _running;

  /// When the last call succeeded (null = not yet). Shown on the list.
  final lastSuccess = ValueNotifier<DateTime?>(null);

  /// Why the last call failed (null = it worked).
  final lastError = ValueNotifier<ApiException?>(null);

  /// A delivery the driver had started was moved to another truck: the app
  /// shows a message (see main.dart), then sets this back to null.
  final movedAway = ValueNotifier<Delivery?>(null);

  /// Starts following [truckPlate]: the full list now, changes every minute.
  Future<void> start(String truckPlate) async {
    stop();
    _truckPlate = truckPlate;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(interval, (_) => syncNow());
    await syncNow();
  }

  /// Stops asking (another truck, logout).
  void stop() {
    _timer?.cancel();
    _timer = null;
    _truckPlate = null;
    _since = null;
    lastSuccess.value = null;
    lastError.value = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  /// The app comes back to the screen: ask at once, it may have slept.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) syncNow();
  }

  /// Asks the server now. A call already under way is waited for instead of
  /// starting a second one (the timer and a pull-down can meet).
  Future<void> syncNow() => _running ??= _sync().whenComplete(() => _running = null);

  Future<void> _sync() async {
    final truck = _truckPlate;
    if (truck == null) return;
    final since = _since;

    try {
      final answer =
          await ApiClient.instance.truckDeliveries(truck, since: since);
      // The driver may have changed truck while we waited
      if (truck != _truckPlate) return;

      final moved = await DeliveryStore.instance.applyFromServer(
        answer.deliveries.map(deliveryFromJson).toList(),
        answer.removed,
        fullList: since == null,
      );
      // Only now: if applying failed, the same changes come again next time
      _since = answer.serverTime;
      lastSuccess.value = DateTime.now();
      lastError.value = null;
      if (moved.isNotEmpty) movedAway.value = moved.first;
    } on ApiException catch (e) {
      lastError.value = e;
    }
  }
}

/// A delivery as the server sends it (DeliveryDto) → the app's Delivery.
Delivery deliveryFromJson(Map<String, dynamic> j) {
  double num_(String name) => (j[name] as num).toDouble();
  double? numOrNull(String name) => (j[name] as num?)?.toDouble();
  DateTime time(String name) => DateTime.parse(j[name] as String).toLocal();

  return Delivery(
    number: j['number'] as String,
    plantCode: j['plantCode'] as String,
    shippingPoint: j['plantName'] as String,
    plantLatitude: num_('plantLatitude'),
    plantLongitude: num_('plantLongitude'),
    plantGeofenceRadiusM: num_('plantGeofenceRadiusM'),
    orderNumber: j['orderNumber'] as String,
    truckPlate: j['truckPlate'] as String?,
    soldToCode: j['soldToCode'] as String,
    soldToName: j['soldToName'] as String,
    shipToName: j['shipToName'] as String,
    shipToAddress: j['shipToAddress'] as String,
    latitude: num_('siteLatitude'),
    longitude: num_('siteLongitude'),
    siteGeofenceRadiusM: num_('siteGeofenceRadiusM'),
    siteContact: j['siteContact'] as String,
    material: j['material'] as String,
    orderedTons: num_('orderedTons'),
    tareTons: numOrNull('tareTons'),
    grossTons: numOrNull('grossTons'),
    scheduled: time('scheduledAt'),
    windowStart: time('windowStart'),
    windowEnd: time('windowEnd'),
    distanceKm: num_('distanceKm'),
    notes: j['notes'] as String?,
    status: DeliveryStatus.values.byName(j['status'] as String),
  );
}
