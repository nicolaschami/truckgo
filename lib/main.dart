import 'package:flutter/material.dart';
import 'SplashScreen.dart';
import 'api/delivery_sync.dart';
import 'delivery_store.dart';
import 'mock_deliveries.dart';
import 'tracking/arrival_notifications.dart';
import 'tracking/geofence_service.dart';

// The splash screen opens the database and keeps Android's launch screen up
// until its image is ready, so the two look like one (see SplashScreen).
void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _geofence = GeofenceService.instance;

  final _sync = DeliverySync.instance;

  @override
  void initState() {
    super.initState();
    _geofence.siteReminder.addListener(_onSiteReminder);
    _sync.movedAway.addListener(_onMovedAway);
  }

  @override
  void dispose() {
    _geofence.siteReminder.removeListener(_onSiteReminder);
    _sync.movedAway.removeListener(_onMovedAway);
    super.dispose();
  }

  // The office moved a delivery the driver had already started to another
  // truck: it has left the list, so say why (on whatever screen is open).
  Future<void> _onMovedAway() async {
    final d = _sync.movedAway.value;
    final context = _navigatorKey.currentContext;
    if (d == null || context == null) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.swap_horiz, color: Color(0xFFE08A00), size: 36),
        title: Text('Delivery ${d.number} was moved'),
        content: Text(
          'The office moved this delivery to another truck. '
          'It is no longer in your list.\n\n${d.shipToName}',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    _sync.movedAway.value = null;
  }

  // The truck entered a customer site zone: ask the driver to confirm,
  // on whatever screen is open (also after tapping the notification).
  Future<void> _onSiteReminder() async {
    final d = _geofence.siteReminder.value;
    final context = _navigatorKey.currentContext;
    if (d == null || context == null) return;

    final arrived = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.location_on, color: Color(0xFF0878E5), size: 36),
        title: Text('You are at ${d.shipToName}'),
        content: Text('Confirm your arrival for delivery ${d.number}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not yet'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Yes, I have arrived'),
          ),
        ],
      ),
    );

    _geofence.dismissReminder();
    await ArrivalNotifications.cancel(d);
    if (arrived == true) {
      await DeliveryStore.instance.setStatus(
          d.key, DeliveryStatus.arrivedAtSite,
          trigger: StatusTrigger.driver);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      home: const SplashScreen(),
    );
  }
}
