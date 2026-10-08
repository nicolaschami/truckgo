import 'dart:io' show Platform;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'deliveries_page.dart';

const _blue = Color(0xFF0878E5);
const _dark = Color(0xFF102A43);
const _grey = Color(0xFF58708C);
const _green = Color(0xFF2E9D5B);
const _orange = Color(0xFFE08A00);

enum _PermState { granted, partial, needed }

class _PermItem {
  _PermItem({
    required this.icon,
    required this.title,
    required this.why,
    required this.read,
    required this.ask,
    this.hint,
  });

  final IconData icon;
  final String title;
  final String why; // why the app needs it (shown before the system prompt)
  final String? hint; // extra help for the user
  final Future<_PermState> Function() read;
  final Future<PermissionStatus> Function() ask;

  _PermState state = _PermState.needed;
}

Permission get _activityPermission =>
    Platform.isIOS ? Permission.sensors : Permission.activityRecognition;

/// True when everything this page asks for is already allowed, so the
/// page can be skipped. It shows again if the driver revokes one later.
Future<bool> allPermissionsGranted() async {
  if (!await Permission.locationAlways.isGranted) return false;
  if (!await _activityPermission.isGranted) return false;
  if (Platform.isAndroid) {
    if (!await Permission.ignoreBatteryOptimizations.isGranted) return false;
    if (!await Permission.notification.isGranted) return false;
  }
  return true;
}

/// Opens the deliveries of [truckPlate], through the permissions screen only
/// when something is still missing. [replace] swaps the current screen.
Future<void> openDeliveries(
  BuildContext context,
  String? truckPlate, {
  bool replace = false,
}) async {
  final granted = await allPermissionsGranted();
  if (!context.mounted) return;

  final route = MaterialPageRoute<void>(
    builder: (context) => granted
        ? DeliveriesPage(truckPlate: truckPlate)
        : PermissionsPage(truckPlate: truckPlate),
  );
  if (replace) {
    Navigator.of(context).pushReplacement(route);
  } else {
    Navigator.of(context).push(route);
  }
}

class PermissionsPage extends StatefulWidget {
  const PermissionsPage({super.key, this.truckPlate});

  /// Plate of the selected truck (null = "Access without truck")
  final String? truckPlate;

  @override
  State<PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<PermissionsPage>
    with WidgetsBindingObserver {
  bool _busy = false;

  late final List<_PermItem> _items = [
    _PermItem(
      icon: Icons.location_on_outlined,
      title: 'Location (all the time)',
      why: 'Lets us update the customer on the status of your delivery and '
          'record where it was delivered, even when the app is closed.',
      hint: "Choose 'While using the app' first, then 'Allow all the time'.",
      read: _readLocation,
      ask: _askLocation,
    ),
    _PermItem(
      icon: Icons.directions_run,
      title: 'Physical activity',
      why: 'Lets the app detect when you start and stop driving, so trips '
          'are tracked correctly.',
      read: () async => (await _activityPermission.isGranted)
          ? _PermState.granted
          : _PermState.needed,
      ask: () => _activityPermission.request(),
    ),
    if (Platform.isAndroid)
      _PermItem(
        icon: Icons.battery_charging_full,
        title: 'Battery optimization',
        why: 'Keeps tracking running in the background. Choose '
            "'Don't optimize' so Android does not stop the app.",
        read: () async => (await Permission.ignoreBatteryOptimizations.isGranted)
            ? _PermState.granted
            : _PermState.needed,
        ask: () => Permission.ignoreBatteryOptimizations.request(),
      ),
    if (Platform.isAndroid)
      _PermItem(
        icon: Icons.notifications_outlined,
        title: 'Notifications',
        why: 'Shows a notification while your deliveries are being tracked, '
            'so you always know when tracking is on.',
        read: () async => (await Permission.notification.isGranted)
            ? _PermState.granted
            : _PermState.needed,
        ask: () => Permission.notification.request(),
      ),
  ];

  // ---------------------------------------------------------------
  // LOCATION (two steps: while using the app -> all the time)
  // ---------------------------------------------------------------

  Future<_PermState> _readLocation() async {
    if (await Permission.locationAlways.isGranted) return _PermState.granted;
    if (await Permission.locationWhenInUse.isGranted) {
      return _PermState.partial;
    }
    return _PermState.needed;
  }

  Future<PermissionStatus> _askLocation() async {
    if (!await Permission.locationWhenInUse.isGranted) {
      return Permission.locationWhenInUse.request();
    }
    return Permission.locationAlways.request();
  }

  // ---------------------------------------------------------------
  // LIFECYCLE: re-check when the user comes back from the settings
  // ---------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    for (final item in _items) {
      item.state = await item.read();
    }
    if (mounted) setState(() {});
  }

  bool get _allGranted =>
      _items.every((item) => item.state == _PermState.granted);

  // ---------------------------------------------------------------
  // REQUESTING
  // ---------------------------------------------------------------

  // Returns true when the permission is fully granted
  Future<bool> _grant(_PermItem item) async {
    PermissionStatus? last;

    for (var i = 0; i < 2; i++) {
      if (await item.read() == _PermState.granted) return true;

      last = await item.ask();

      final after = await item.read();
      if (after == _PermState.granted) return true;
      if (after == _PermState.needed) break; // nothing was granted
      // partial (location while using): loop once more for "all the time"
    }

    if (last != null && last.isPermanentlyDenied) _showSettingsHint();
    return false;
  }

  Future<void> _onItemTap(_PermItem item) async {
    if (_busy) return;
    setState(() => _busy = true);
    await _grant(item);
    await _refresh();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _allowAll() async {
    if (_busy) return;
    setState(() => _busy = true);
    for (final item in _items) {
      if (!await _grant(item)) break; // stop at the first refusal
    }
    await _refresh();
    if (mounted) setState(() => _busy = false);
  }

  void _showSettingsHint() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text(
            'This permission is blocked. Open the app settings to allow it.',
          ),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () {
              openAppSettings();
            },
          ),
        ),
      );
  }

  void _continue() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => DeliveriesPage(truckPlate: widget.truckPlate),
      ),
    );
  }

  // ---------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0B57A1), Color(0xFF063470)],
          ),
        ),
        child: SafeArea(
          // Everything fits on a normal phone, so nothing scrolls.
          // The scroll view is only a safety net for very small screens.
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset('assets/images/truck_logo.png', height: 56),

                    const SizedBox(height: 16),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.80),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.65),
                                width: 1.5,
                              ),
                            ),
                            child: Column(
                              children: [
                                const Text(
                                  'Permissions Required',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: _dark,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'Allow these so the app can work properly',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 13, color: _grey),
                                ),

                                const SizedBox(height: 14),

                                for (final item in _items) ...[
                                  _PermCard(
                                    item: item,
                                    busy: _busy,
                                    onTap: () => _onItemTap(item),
                                  ),
                                  const SizedBox(height: 8),
                                ],

                                if (!_allGranted)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 2),
                                    child: Text(
                                      'All permissions are required to continue.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: _grey,
                                      ),
                                    ),
                                  ),

                                const SizedBox(height: 14),

                                // BUTTONS
                                Row(
                                  children: [
                                    Expanded(
                                      child: SizedBox(
                                        height: 48,
                                        child: OutlinedButton(
                                          onPressed: () =>
                                              Navigator.of(context).pop(),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: _blue,
                                            side: const BorderSide(
                                              color: _blue,
                                              width: 2,
                                            ),
                                            padding: EdgeInsets.zero,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                          ),
                                          child: const Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.arrow_back_rounded,
                                                size: 20,
                                              ),
                                              SizedBox(width: 6),
                                              Text(
                                                'Back',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: SizedBox(
                                        height: 48,
                                        child: ElevatedButton(
                                          onPressed: _busy
                                              ? null
                                              : (_allGranted
                                                  ? _continue
                                                  : _allowAll),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: _blue,
                                            foregroundColor: Colors.white,
                                            elevation: 4,
                                            padding: EdgeInsets.zero,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                          ),
                                          child: Text(
                                            _allGranted
                                                ? 'Continue'
                                                : 'Allow all',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------
// One permission card
// ---------------------------------------------------------------

class _PermCard extends StatelessWidget {
  const _PermCard({
    required this.item,
    required this.busy,
    required this.onTap,
  });

  final _PermItem item;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final granted = item.state == _PermState.granted;
    final partial = item.state == _PermState.partial;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: granted ? _green.withOpacity(0.5) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ROW 1: icon + title + Allow button (same line)
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: (granted ? _green : _blue).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  item.icon,
                  size: 20,
                  color: granted ? _green : _blue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    item.title,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: _dark,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (granted)
                const Icon(Icons.check_circle, color: _green, size: 26)
              else
                SizedBox(
                  height: 32,
                  child: ElevatedButton(
                    onPressed: busy ? null : onTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _blue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Allow',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),

          // DETAILS: full width, under the row
          const SizedBox(height: 6),
          Text(
            item.why,
            style: const TextStyle(fontSize: 12.5, height: 1.25, color: _grey),
          ),
          if (!granted && item.hint != null) ...[
            const SizedBox(height: 3),
            Text(
              item.hint!,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.25,
                fontWeight: FontWeight.w600,
                color: partial ? _orange : _blue,
              ),
            ),
          ],
        ],
      ),
    );
  }
}