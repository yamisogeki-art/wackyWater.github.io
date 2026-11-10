import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class OsrmStep {
  final String type; // depart, turn, continue, roundabout, arrive, ...
  final String? modifier; // left, right, slight left, uturn, ...
  final String name; // street name (may be empty)
  final double distance; // meters from this maneuver to the next one
  final LatLng location; // where the maneuver happens

  const OsrmStep({
    required this.type,
    required this.modifier,
    required this.name,
    required this.distance,
    required this.location,
  });
}

class OsrmRoute {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final List<OsrmStep> steps; // empty unless requested

  const OsrmRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.steps,
  });
}

/// Road routing via OSRM (OpenStreetMap data) - no API key needed, same
/// idea as the OpenStreetMap tiles already used for the maps.
///
/// The public demo server is fine for a prototype / thesis demo but is not
/// meant for production traffic; point [baseUrl] at your own OSRM instance
/// (or another OSRM-compatible service) before real deployment.
class OsrmService {
  static const String baseUrl = 'https://router.project-osrm.org';

  /// Route through [waypoints] in order. Returns null on any failure
  /// (offline, server busy, no road route) so callers can fall back.
  static Future<OsrmRoute?> route(List<LatLng> waypoints, {bool steps = false}) async {
    if (waypoints.length < 2) return null;

    final coords = waypoints.map((p) => '${p.longitude},${p.latitude}').join(';');
    final uri = Uri.parse(
      '$baseUrl/route/v1/driving/$coords?overview=full&geometries=geojson&steps=$steps',
    );

    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['code'] != 'Ok') return null;

      final routes = body['routes'] as List;
      if (routes.isEmpty) return null;
      final r = routes.first as Map<String, dynamic>;

      final coordinates = (r['geometry'] as Map<String, dynamic>)['coordinates'] as List;
      final points = coordinates
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();

      final parsedSteps = <OsrmStep>[];
      if (steps) {
        for (final leg in (r['legs'] as List)) {
          for (final s in ((leg as Map<String, dynamic>)['steps'] as List? ?? const [])) {
            final step = s as Map<String, dynamic>;
            final maneuver = step['maneuver'] as Map<String, dynamic>;
            final loc = maneuver['location'] as List;
            parsedSteps.add(OsrmStep(
              type: maneuver['type'] as String? ?? 'continue',
              modifier: maneuver['modifier'] as String?,
              name: step['name'] as String? ?? '',
              distance: (step['distance'] as num).toDouble(),
              location: LatLng((loc[1] as num).toDouble(), (loc[0] as num).toDouble()),
            ));
          }
        }
      }

      return OsrmRoute(
        points: points,
        distanceMeters: (r['distance'] as num).toDouble(),
        durationSeconds: (r['duration'] as num).toDouble(),
        steps: parsedSteps,
      );
    } catch (_) {
      return null;
    }
  }
}
