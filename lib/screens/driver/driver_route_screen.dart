import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  // Orders this driver delivered TODAY (shown as checkmark pins). Cleared every day.
  List<_DeliveredPin> _delivered = [];
  String _lastStopIds = '';
  Timer? _midnightTimer;
  Timer? _refreshTimer;

  DriverStopsController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onControllerChanged);
    _signature = _signatureOf();
    _lastStopIds = _c.stops.map((s) => s.id).join(',');
    _loadRoute();
    _loadDelivered();
    _scheduleMidnightReset();
    _refreshTimer = Timer.periodic(const Duration(seconds: 45), (_) => _loadDelivered());
  }

  @override
  void dispose() {
    _c.removeListener(_onControllerChanged);
    _midnightTimer?.cancel();
    _refreshTimer?.cancel();
    _map.dispose();
    super.dispose();
  }

  String _signatureOf() {
    final p = _c.position;
    final pos = p == null ? '-' : '${p.latitude.toStringAsFixed(3)},${p.longitude.toStringAsFixed(3)}';
    return '${_c.stops.map((s) => s.id).join(',')}|$pos';
  }

  void _onControllerChanged() {
    final ids = _c.stops.map((s) => s.id).join(',');
    if (ids != _lastStopIds) {
      _lastStopIds = ids;
      _loadDelivered();
    }
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

  // ---- Daily checkmarks: orders this driver delivered today ----

  DateTime _startOfToday() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  Future<void> _loadDelivered() async {
    final me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null) return;
    try {
      final rows = await Supabase.instance.client
          .from('delivery_requests')
          .select('id, delivered_at, customer_addresses(label, latitude, longitude)')
          .eq('driver_id', me) // only this driver's own deliveries
          .eq('status', 'delivered')
          .gte('delivered_at', _startOfToday().toUtc().toIso8601String())
          .order('delivered_at', ascending: false);

      final pins = <_DeliveredPin>[];
      for (final r in List<Map<String, dynamic>>.from(rows)) {
        final a = r['customer_addresses'];
        final lat = (a is Map ? a['latitude'] : null) as num?;
        final lng = (a is Map ? a['longitude'] : null) as num?;
        if (lat == null || lng == null) continue;
        pins.add(_DeliveredPin(
          id: r['id'].toString(),
          label: ((a as Map)['label'] as String?) ?? 'Delivered',
          point: LatLng(lat.toDouble(), lng.toDouble()),
        ));
      }
      if (mounted) setState(() => _delivered = pins);
    } catch (e) {
      debugPrint('Could not load delivered pins: $e');
    }
  }

  /// At midnight: clear yesterday's checkmarks and show the new day's assigned orders.
  void _scheduleMidnightReset() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    _midnightTimer = Timer(nextMidnight.difference(now) + const Duration(seconds: 2), () async {
      if (!mounted) return;
      setState(() {
        _delivered = [];
        _selected = 0;
      });
      await _c.refreshPosition();
      await _loadDelivered();
      await _loadRoute();
      _scheduleMidnightReset();
    });
  }

  Future<void> _confirmDelivered(DeliveryStop stop) async {
    if (stop.status == 'assigned') await _c.markInTransit(stop.id);
    if (!mounted) return;
    // Opens the camera right away; the order is only marked delivered after the photo.
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DeliveryDetailsScreen(stop: stop, controller: _c, autoStartDelivered: true),
      ),
    );
    _loadDelivered();
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
    final deliveredIds = _delivered.map((d) => d.id).toSet();
    for (var i = 0; i < stops.length; i++) {
      final ll = stops[i].latLng;
      if (ll == null) continue;
      if (deliveredIds.contains(stops[i].id.toString())) continue;
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
    for (final d in _delivered) {
      markers.add(
        Marker(
          point: d.point,
          width: 44,
          height: 44,
          child: Tooltip(
            message: d.label,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF16A34A),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 5)],
              ),
              child: const Icon(Icons.check, color: Colors.white, size: 24),
            ),
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
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            _delivered.isEmpty
                ? 'No active stops on your route right now.'
                : 'All assigned orders are delivered today (${_delivered.length}).',
            textAlign: TextAlign.center,
          ),
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
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => DeliveryDetailsScreen(stop: stop, controller: _c)),
              );
              _loadDelivered();
            },
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
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () => _startNavigation(stop),
                    icon: const Icon(Icons.navigation, size: 18),
                    label: const Text('Navigate', style: TextStyle(fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () => _confirmDelivered(stop),
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: const Text('Delivered', style: TextStyle(fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
            ],
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
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8)],
                    ),
                    child: Text(
                      'To deliver: ${_c.stops.where((s) => !_delivered.any((d) => d.id == s.id.toString())).length}'
                      '   Delivered today: ${_delivered.length}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
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

class _DeliveredPin {
  final String id;
  final String label;
  final LatLng point;
  const _DeliveredPin({required this.id, required this.label, required this.point});
}
