// Truck routes from OpenRouteService (driving-hgv profile).
//
// Get a free key at https://openrouteservice.org (Dashboard -> Tokens),
// then run the app with:
//   flutter run --dart-define=ORS_API_KEY=your_key_here
// Without a key the map draws a straight dashed line instead.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

const _orsApiKey = String.fromEnvironment('ORS_API_KEY');

class TruckRoute {
  const TruckRoute({
    required this.points,
    required this.distanceKm,
    required this.duration,
    required this.isRoad,
  });

  final List<LatLng> points;
  final double distanceKm;
  final Duration? duration; // null for the straight-line fallback
  final bool isRoad; // false = straight line (no key or request failed)
}

// Routes already fetched, so reopening a delivery does not use the quota again.
final Map<String, TruckRoute> _cache = {};

Future<TruckRoute> fetchTruckRoute(LatLng from, LatLng to) async {
  final cacheKey = '${from.latitude},${from.longitude}>'
      '${to.latitude},${to.longitude}';
  final cached = _cache[cacheKey];
  if (cached != null) return cached;

  if (_orsApiKey.isNotEmpty) {
    try {
      final response = await http
          .post(
            Uri.parse('https://api.openrouteservice.org/v2/directions/'
                'driving-hgv/geojson'),
            headers: {
              'Authorization': _orsApiKey,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'coordinates': [
                [from.longitude, from.latitude],
                [to.longitude, to.latitude],
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final feature = (jsonDecode(response.body)['features'] as List).first;
        final coords = feature['geometry']['coordinates'] as List;
        final summary = feature['properties']['summary'];
        final route = TruckRoute(
          points: [
            for (final c in coords)
              LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
          ],
          distanceKm: (summary['distance'] as num) / 1000,
          duration: Duration(seconds: (summary['duration'] as num).round()),
          isRoad: true,
        );
        _cache[cacheKey] = route;
        return route;
      }
    } catch (_) {
      // Fall through to the straight line.
    }
  }

  return TruckRoute(
    points: [from, to],
    distanceKm: const Distance().as(LengthUnit.Meter, from, to) / 1000,
    duration: null,
    isRoad: false,
  );
}
