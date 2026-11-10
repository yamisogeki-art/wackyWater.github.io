import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../services/driver_delivery_service.dart';
import '../../services/osrm_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../widgets/stop_badge.dart';
import 'delivery_details_screen.dart';
import 'driver_enroute_screen.dart';

/// "Customer Location (Driver)": the driver's stops as numbered pins joined by
/// a road route (OSRM), with a "Next Stop" card and Start Navigation.
///
/// Tap a pin to make it the selected stop; tap the card to open its
/// delivery details.
class DriverRouteScreen extends StatefulWidget {
  final DriverStopsController controller;

  const DriverRouteScreen({super.key, required this.controller});

  @override
  State<DriverRouteScreen> createState() => _DriverRouteScreenState();
}

class _DriverRouteScreenState extends State<DriverRouteScreen> {
  static const LatLng _defaultCenter = LatLng(7.6800, 122.4800);

  final MapController _map = MapController();
  bool _mapReady = false;
  OsrmRoute? _route;
  String _signature = '';
  int _selected = 0;

  DriverStopsController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onControllerChanged);
    _signature = _signatureOf();
    _loadRoute();
  }

  @override
  void dispose() {
    _c.removeListener(_onControllerChanged);
    _map.dispose();
    super.dispose();
  }

  String _signatureOf() {
    final p = _c.position;
    final pos = p == null ? '-' : '${p.latitude.toStringAsFixed(3)},${p.longitude.toStringAsFixed(3)}';
    return '${_c.stops.map((s) => s.id).join(',')}|$pos';
  }

  void _onControllerChanged() {
    final sig = _signatureOf();
    if (sig == _signature) return;
    _signature = sig;
    if (!mounted) return;
    setState(() {
      if (_selected >= _c.stops.length) _selected = 0;
    });
    _loadRoute();
  }

  /// Driver position (if known) followed by every stop that has coordinates.
  List<LatLng> _waypoints() {
    final pts = <LatLng>[];
    final p = _c.position;
    if (p != null) pts.add(LatLng(p.latitude, p.longitude));
    for (final s in _c.stops) {
      final ll = s.latLng;
      if (ll != null) pts.add(ll);
    }
    return pts;
  }

  Future<void> _loadRoute() async {
    final pts = _waypoints();
    final route = pts.length >= 2 ? await OsrmService.route(pts) : null;
    if (!mounted) return;
    setState(() => _route = route);
    _fitToRoute();
  }

  void _fitToRoute() {
    if (!_mapReady || !mounted) return;
    final pts = _route?.points ?? _waypoints();
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      _map.move(pts.first, 15);
      return;
    }
    _map.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(pts),
        padding: const EdgeInsets.fromLTRB(40, 40, 40, 220),
      ),
    );
  }

  Future<void> _recenter() async {
    await _c.refreshPosition();
    final p = _c.position;
    if (!mounted) return;
    if (p != null && _mapReady) {
      _map.move(LatLng(p.latitude, p.longitude), 15);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your location is unavailable. Check that location is turned on.')),
      );
    }
  }

  Future<void> _startNavigation(DeliveryStop stop) async {
    if (stop.latLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("This stop has no map location, so it can't be navigated to.")),
      );
      return;
    }
    if (stop.status == 'assigned') await _c.markInTransit(stop.id);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DriverEnRouteScreen(stop: stop, controller: _c)),
    );
  }

  List<Marker> _markers() {
    final markers = <Marker>[];
    final stops = _c.stops;
    for (var i = 0; i < stops.length; i++) {
      final ll = stops[i].latLng;
      if (ll == null) continue;
      final selected = i == _selected;
      markers.add(
        Marker(
          point: ll,
          width: 48,
          height: 48,
          child: GestureDetector(
            onTap: () => setState(() => _selected = i),
            child: Center(child: StopBadge(index: i, size: selected ? 40 : 32)),
          ),
        ),
      );
    }
    final p = _c.position;
    if (p != null) {
      markers.add(
        Marker(
          point: LatLng(p.latitude, p.longitude),
          width: 26,
          height: 26,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 5)],
            ),
          ),
        ),
      );
    }
    return markers;
  }

  Widget _nextStopCard() {
    final stops = _c.stops;
    if (stops.isEmpty) {
      return _cardShell(
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('No active stops on your route right now.', textAlign: TextAlign.center),
        ),
      );
    }
    final index = _selected < stops.length ? _selected : 0;
    final stop = stops[index];
    return _cardShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => DeliveryDetailsScreen(stop: stop, controller: _c)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(index == 0 ? 'Next Stop:' : 'Selected Stop:',
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      StopBadge(index: index, size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(stop.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                            Text(stop.addressLine,
                                style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: AppColors.textMuted),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () => _startNavigation(stop),
              icon: const Icon(Icons.navigation, size: 18),
              label: const Text('Start Navigation', style: TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardShell({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.driverTheme,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Customer Location'),
          actions: [
            IconButton(icon: const Icon(Icons.my_location), tooltip: 'My location', onPressed: _recenter),
          ],
        ),
        body: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final line = _route?.points ?? _waypoints();
            return Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: _defaultCenter,
                    initialZoom: 13,
                    onMapReady: () {
                      _mapReady = true;
                      _fitToRoute();
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.wackysmart.app',
                    ),
                    if (line.length >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: line,
                            strokeWidth: 5,
                            color: AppColors.primary,
                            borderStrokeWidth: 1.5,
                            borderColor: Colors.white,
                          ),
                        ],
                      ),
                    MarkerLayer(markers: _markers()),
                  ],
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: SafeArea(top: false, child: _nextStopCard()),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
