import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../mock_deliveries.dart';

/// Phone notification reminding the driver to confirm arrival at a site.
/// Needed because the driver is usually in Google Maps, not in TruckGo.
/// Tapping it opens TruckGo, which then shows the confirm dialog.
class ArrivalNotifications {
  ArrivalNotifications._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    if (_ready) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            // Permission is asked on the permissions screen
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      _ready = true;
    } catch (_) {
      // No notifications (e.g. in tests): the in-app dialog still works
    }
  }

  static Future<void> showSiteArrival(Delivery d) async {
    await init();
    if (!_ready) return;
    await _plugin.show(
      id: d.key.hashCode,
      title: 'You have arrived at ${d.shipToName}',
      body: 'Tap to confirm your arrival for delivery ${d.number}.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'site_arrival',
          'Arrival reminders',
          channelDescription:
              'Reminds you to confirm arrival at the customer site',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  static Future<void> cancel(Delivery d) async {
    if (_ready) await _plugin.cancel(id: d.key.hashCode);
  }
}
