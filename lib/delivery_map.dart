import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'mock_deliveries.dart';
import 'route_service.dart';

const _blue = Color(0xFF0878E5);
const _dark = Color(0xFF102A43);
const _grey = Color(0xFF58708C);
const _green = Color(0xFF2E9D5B);
const _orange = Color(0xFFE8890C);

/// Map with the plant, the ship-to site, the truck route between them and
/// the truck's live position. The route is drawn as soon as it is shown.
///
/// [fullScreen] = false: small preview, tap it to open the full map.
class DeliveryRouteMap extends StatefulWidget {
  const DeliveryRouteMap({
    super.key,
    required this.delivery,
    this.fullScreen = false,
    this.height = 220,
  });

  final Delivery delivery;
  final bool fullScreen;
  final double height;

  @override
  State<DeliveryRouteMap> createState() => _DeliveryRouteMapState();
}

class _DeliveryRouteMapState extends State<DeliveryRouteMap> {
  final _mapController = MapController();
  bool _mapReady = false;

  TruckRoute? _route;
  LatLng? _truck;
  StreamSubscription<Position>? _positionSub;

  Delivery get d => widget.delivery;
  LatLng get _plant => LatLng(d.plantLatitude, d.plantLongitude);
  LatLng get _site => LatLng(d.latitude, d.longitude);

  @override
  void initState() {
    super.initState();
    _loadRoute();
    _followTruck();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  Future<void> _loadRoute() async {
    final route = await fetchTruckRoute(_plant, _site);
    if (!mounted) return;
    setState(() => _route = route);
    _fitRoute();
  }

  // Live truck position. Permission is asked on the permissions page,
  // so here we only use it when it was already granted.
  Future<void> _followTruck() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return;
      }
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted) {
        setState(() => _truck = LatLng(last.latitude, last.longitude));
      }
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 20,
        ),
      ).listen((p) {
        if (mounted) setState(() => _truck = LatLng(p.latitude, p.longitude));
      });
    } catch (_) {
      // No position: the map still shows the plant, site and route.
    }
  }

  LatLngBounds get _bounds =>
      LatLngBounds.fromPoints([_plant, _site, ...?_route?.points]);

  CameraFit get _fit => CameraFit.bounds(
        bounds: _bounds,
        padding: EdgeInsets.fromLTRB(
            40, widget.fullScreen ? 90 : 40, 40, widget.fullScreen ? 70 : 40),
      );

  void _fitRoute() {
    if (_mapReady) _mapController.fitCamera(_fit);
  }

  void _openFullScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _FullScreenMapPage(delivery: d),
      ),
    );
  }

  // ---------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final route = _route;

    final map = FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCameraFit: _fit,
        onMapReady: () {
          _mapReady = true;
          _fitRoute();
        },
        interactionOptions: InteractionOptions(
          flags: widget.fullScreen
              ? InteractiveFlag.all & ~InteractiveFlag.rotate
              : InteractiveFlag.none,
        ),
        onTap: widget.fullScreen ? null : (_, _) => _openFullScreen(),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.truckg',
        ),
        if (route != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: route.points,
                strokeWidth: route.isRoad ? 5 : 3.5,
                color: _blue,
                borderStrokeWidth: route.isRoad ? 1.5 : 0,
                borderColor: Colors.white,
                pattern: route.isRoad
                    ? const StrokePattern.solid()
                    : StrokePattern.dashed(segments: const [12, 8]),
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            Marker(
              point: _plant,
              width: 40,
              height: 40,
              child: const _Pin(icon: Icons.factory_outlined, color: _orange),
            ),
            Marker(
              point: _site,
              width: 40,
              height: 40,
              child: const _Pin(icon: Icons.flag_rounded, color: _green),
            ),
            if (_truck != null)
              Marker(
                point: _truck!,
                width: 34,
                height: 34,
                child: const _TruckDot(),
              ),
          ],
        ),
        const SimpleAttributionWidget(
          source: Text('OpenStreetMap contributors'),
        ),
      ],
    );

    final overlay = Positioned(
      left: 10,
      top: 10,
      right: widget.fullScreen ? 10 : 60,
      child: Align(
        alignment: Alignment.topLeft,
        child: _RouteSummary(route: route),
      ),
    );

    if (widget.fullScreen) {
      return Stack(
        children: [
          map,
          overlay,
          Positioned(
            right: 12,
            bottom: 40,
            child: FloatingActionButton.small(
              heroTag: null,
              backgroundColor: Colors.white,
              foregroundColor: _blue,
              onPressed: _fitRoute,
              child: const Icon(Icons.center_focus_strong_outlined),
            ),
          ),
        ],
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            map,
            overlay,
            Positioned(
              right: 10,
              top: 10,
              child: Material(
                color: Colors.white,
                shape: const CircleBorder(),
                elevation: 2,
                child: IconButton(
                  icon: const Icon(Icons.open_in_full_rounded, size: 20),
                  color: _blue,
                  tooltip: 'Full screen map',
                  onPressed: _openFullScreen,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FullScreenMapPage extends StatelessWidget {
  const _FullScreenMapPage({required this.delivery});

  final Delivery delivery;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B57A1),
        foregroundColor: Colors.white,
        title: Text(
          '${delivery.shippingPoint}  →  ${delivery.shipToName}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      body: DeliveryRouteMap(delivery: delivery, fullScreen: true),
    );
  }
}

class _RouteSummary extends StatelessWidget {
  const _RouteSummary({required this.route});

  final TruckRoute? route;

  @override
  Widget build(BuildContext context) {
    final r = route;
    final String text;
    if (r == null) {
      text = 'Calculating truck route…';
    } else if (r.isRoad) {
      final mins = r.duration!.inMinutes;
      final time = mins >= 60 ? '${mins ~/ 60} h ${mins % 60} min' : '$mins min';
      text = '${r.distanceKm.toStringAsFixed(1)} km  •  $time  (truck route)';
    } else {
      text = '${r.distanceKm.toStringAsFixed(1)} km straight line';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Color(0x22000000), blurRadius: 6),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            r != null && r.isRoad ? Icons.route_outlined : Icons.straighten,
            size: 16,
            color: r != null && r.isRoad ? _blue : _grey,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: _dark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: const [
          BoxShadow(color: Color(0x44000000), blurRadius: 6),
        ],
      ),
      child: Icon(icon, size: 20, color: Colors.white),
    );
  }
}

class _TruckDot extends StatelessWidget {
  const _TruckDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _blue.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: _blue,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
        ),
        child: const Icon(Icons.local_shipping, size: 12, color: Colors.white),
      ),
    );
  }
}
