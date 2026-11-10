import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../../services/driver_delivery_service.dart';
import '../../services/driver_location_service.dart';
import '../../services/osrm_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import 'delivery_details_screen.dart';

/// "Navigation (Driver)": in-app turn-by-turn to the selected stop.
/// A green banner shows the next maneuver and its distance; the bottom bar
/// shows remaining time, distance and ETA. Directions come from OSRM
/// (see osrm_service.dart) and follow the driver's live GPS position.
class DriverNavigationScreen extends StatefulWidget {
  final DeliveryStop stop;
  final DriverStopsController controller;

  const DriverNavigationScreen({super.key, required this.stop, required this.controller});

  @override
  State<DriverNavigationScreen> createState() => _DriverNavigationScreenState();
}

class _DriverNavigationScreenState extends State<DriverNavigationScreen> {
  static const double _reachedMeters = 30;

  final MapController _map = MapController();
  bool _mapReady = false;
  bool _loading = true;
  String? _error;
  OsrmRoute? _route;
  Position? _pos;
  StreamSubscription<Position>? _sub;
  int _next = 1; // index of the upcoming maneuver in route.steps
  bool _follow = true;
  bool _arrived = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _map.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final pos = await DriverLocationService.currentPosition();
    if (!mounted) return;

    final dest = widget.stop.latLng;
    if (dest == null) {
      setState(() {
        _loading = false;
        _error = 'This stop has no map location.';
      });
      return;
    }
    if (pos == null) {
      setState(() {
        _loading = false;
        _error = 'Turn on location (and allow it for this app) to start navigation.';
      });
      return;
    }

    final route = await OsrmService.route([LatLng(pos.latitude, pos.longitude), dest], steps: true);
    if (!mounted) return;
    if (route == null || route.steps.isEmpty) {
      setState(() {
        _loading = false;
        _error = "Couldn't get directions right now. Check your connection and try again.";
      });
      return;
    }

    setState(() {
      _pos = pos;
      _route = route;
      _next = route.steps.length > 1 ? 1 : 0;
      _loading = false;
    });

    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
    ).listen(_onPosition);
  }

  double _distanceTo(Position p, LatLng q) =>
      Geolocator.distanceBetween(p.latitude, p.longitude, q.latitude, q.longitude);

  void _onPosition(Position p) {
    final route = _route;
    final dest = widget.stop.latLng;
    if (route == null || dest == null || !mounted) return;

    var next = _next;
    while (next < route.steps.length - 1 && _distanceTo(p, route.steps[next].location) < _reachedMeters) {
      next++;
    }
    final arrived = _arrived || _distanceTo(p, dest) < _reachedMeters;

    setState(() {
      _pos = p;
      _next = next;
      _arrived = arrived;
    });

    if (_follow && _mapReady) _map.move(LatLng(p.latitude, p.longitude), 17);
  }

  void _toggleFollow() {
    setState(() => _follow = !_follow);
    _fitOrFollow();
  }

  void _fitOrFollow() {
    final route = _route;
    final p = _pos;
    if (!_mapReady || route == null || p == null) return;
    if (_follow) {
      _map.move(LatLng(p.latitude, p.longitude), 17);
    } else {
      _map.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(route.points),
          padding: const EdgeInsets.all(48),
        ),
      );
    }
  }

  double get _remainingMeters {
    final route = _route;
    final p = _pos;
    if (route == null || p == null || _arrived) return 0;
    final steps = route.steps;
    final i = _next.clamp(0, steps.length - 1);
    var total = _distanceTo(p, steps[i].location);
    for (var k = i; k < steps.length; k++) {
      total += steps[k].distance;
    }
    return total;
  }

  double get _remainingSeconds {
    final route = _route;
    if (route == null || route.distanceMeters <= 0) return 0;
    return route.durationSeconds * (_remainingMeters / route.distanceMeters);
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${(meters / 10).round() * 10} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String _formatDuration(double seconds) {
    final minutes = math.max(1, (seconds / 60).round());
    if (minutes < 60) return '$minutes min';
    return '${minutes ~/ 60} h ${minutes % 60} min';
  }

  IconData _iconFor(OsrmStep s) {
    if (s.type == 'arrive') return Icons.flag;
    switch (s.modifier) {
      case 'left':
        return Icons.turn_left;
      case 'right':
        return Icons.turn_right;
      case 'slight left':
        return Icons.turn_slight_left;
      case 'slight right':
        return Icons.turn_slight_right;
      case 'sharp left':
        return Icons.turn_sharp_left;
      case 'sharp right':
        return Icons.turn_sharp_right;
      case 'uturn':
        return Icons.u_turn_left;
      default:
        return Icons.arrow_upward;
    }
  }

  String _instruction(OsrmStep s) {
    final onto = s.name.isEmpty ? '' : ' onto ${s.name}';
    if (s.type == 'arrive') return 'Arrive at ${widget.stop.name}';
    if (s.type == 'roundabout' || s.type == 'rotary') {
      return 'Enter the roundabout${s.name.isEmpty ? '' : ' toward ${s.name}'}';
    }
    switch (s.modifier) {
      case 'left':
        return 'Turn left$onto';
      case 'right':
        return 'Turn right$onto';
      case 'slight left':
        return 'Bear left$onto';
      case 'slight right':
        return 'Bear right$onto';
      case 'sharp left':
        return 'Turn sharp left$onto';
      case 'sharp right':
        return 'Turn sharp right$onto';
      case 'uturn':
        return 'Make a U-turn$onto';
      default:
        return s.name.isEmpty ? 'Continue straight' : 'Navigate toward ${s.name}';
    }
  }

  void _openDetails() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => DeliveryDetailsScreen(stop: widget.stop, controller: widget.controller),
      ),
    );
  }

  Widget _banner() {
    final steps = _route!.steps;
    final step = steps[_next.clamp(0, steps.length - 1)];
    final distance = _arrived || _pos == null ? 0.0 : _distanceTo(_pos!, step.location);

    return Container(
      width: double.infinity,
      color: AppColors.navGreen,
      padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 12, 16, 16),
      child: Row(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_arrived ? Icons.flag : _iconFor(step), color: Colors.white, size: 42),
              if (!_arrived)
                Text(_formatDistance(distance), style: const TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              _arrived ? 'You have arrived' : _instruction(step),
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapView() {
    final p = _pos!;
    final dest = widget.stop.latLng!;
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: LatLng(p.latitude, p.longitude),
        initialZoom: 17,
        onMapReady: () {
          _mapReady = true;
          _fitOrFollow();
        },
        onPositionChanged: (camera, hasGesture) {
          if (hasGesture && _follow) setState(() => _follow = false);
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.wackysmart.app',
        ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: _route!.points,
              strokeWidth: 6,
              color: AppColors.primary,
              borderStrokeWidth: 1.5,
              borderColor: Colors.white,
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: dest,
              width: 40,
              height: 40,
              child: const Icon(Icons.location_on, color: Color(0xFFEF4444), size: 40),
            ),
            Marker(
              point: LatLng(p.latitude, p.longitude),
              width: 44,
              height: 44,
              child: Transform.rotate(
                angle: (p.heading.isNaN || p.heading < 0 ? 0.0 : p.heading) * math.pi / 180,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 6)],
                  ),
                  child: const Icon(Icons.navigation, color: Colors.white, size: 22),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _bottomBar() {
    final eta = DateTime.now().add(Duration(seconds: _remainingSeconds.round()));
    return Container(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 14 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 12, offset: const Offset(0, -2))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _arrived ? 'Arrived' : _formatDuration(_remainingSeconds),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.navGreen),
                ),
                Text(
                  _arrived
                      ? widget.stop.name
                      : '${_formatDistance(_remainingMeters)} - ${formatTime12(eta)}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
          if (_arrived)
            FilledButton(
              onPressed: _openDetails,
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Delivery Details'),
            )
          else
            IconButton.filledTonal(
              onPressed: _toggleFollow,
              tooltip: _follow ? 'Route overview' : 'Follow me',
              icon: Icon(_follow ? Icons.zoom_out_map : Icons.my_location),
            ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFEE2E2),
              foregroundColor: const Color(0xFFDC2626),
            ),
            child: const Text('Exit', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showingRoute = !_loading && _error == null;
    return Theme(
      data: AppTheme.driverTheme,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: showingRoute ? null : AppBar(title: const Text('Navigation')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text(_error!, textAlign: TextAlign.center),
                    ),
                  )
                : Column(
                    children: [
                      _banner(),
                      Expanded(child: _mapView()),
                      _bottomBar(),
                    ],
                  ),
      ),
    );
  }
}
