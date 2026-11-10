import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/driver_delivery_service.dart';
import '../../services/driver_location_service.dart';
import '../../services/osrm_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import 'delivery_completed_screen.dart';

class DriverEnRouteScreen extends StatefulWidget {
  final DeliveryStop stop;
  final DriverStopsController controller;

  const DriverEnRouteScreen({super.key, required this.stop, required this.controller});

  @override
  State<DriverEnRouteScreen> createState() => _DriverEnRouteScreenState();
}

class _DriverEnRouteScreenState extends State<DriverEnRouteScreen> {
  final MapController _map = MapController();
  bool _mapReady = false;
  bool _loading = true;
  String? _error;
  OsrmRoute? _route;
  Position? _pos;
  StreamSubscription<Position>? _sub;
  String _driverName = 'Driver';

  @override
  void initState() {
    super.initState();
    _fetchDriverName();
    _initMap();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _map.dispose();
    super.dispose();
  }

  Future<void> _fetchDriverName() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final profile = await Supabase.instance.client
            .from('profiles')
            .select('full_name')
            .eq('id', user.id)
            .maybeSingle();
        if (profile != null && profile['full_name'] != null) {
          setState(() => _driverName = profile['full_name']);
        } else if (user.email != null) {
          setState(() => _driverName = user.email!.split('@').first);
        }
      }
    } catch (_) {}
  }

  Future<void> _initMap() async {
    final pos = await DriverLocationService.currentPosition();
    if (!mounted) return;

    final dest = widget.stop.latLng;
    if (dest == null) {
      setState(() {
        _loading = false;
        _error = 'Location coordinates unavailable for this order.';
      });
      return;
    }
    if (pos == null) {
      setState(() {
        _loading = false;
        _error = 'Turn on GPS location services to view the route.';
      });
      return;
    }

    final route = await OsrmService.route([LatLng(pos.latitude, pos.longitude), dest], steps: true);
    if (!mounted) return;

    setState(() {
      _pos = pos;
      _route = route;
      _loading = false;
    });

    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
    ).listen((p) {
      if (mounted) {
        setState(() => _pos = p);
        if (_mapReady) _map.move(LatLng(p.latitude, p.longitude), 16);
      }
    });
  }

  void _startDelivery() async {
    if (widget.stop.status == 'assigned') {
      await widget.controller.markInTransit(widget.stop.id);
    }

    if (!mounted) return;

    // Move to Screen 2: Delivery Complete Confirmation
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => DeliveryCompletedScreen(
          customerName: widget.stop.name,
          location: widget.stop.addressLine,
          gallons: widget.stop.gallons.toDouble(),
          waterType: widget.stop.waterType,
          completedAt: DateTime.now(),
          stop: widget.stop,
          controller: widget.controller,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orderNum = 'DRV-${widget.stop.id}';
    final customerLabel = '${widget.stop.name}, ${widget.stop.addressLine}';

    return Theme(
      data: AppTheme.driverTheme,
      child: Scaffold(
        backgroundColor: const Color(0xFF1E293B),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F172A),
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(
            'Order #$orderNum',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(32),
            child: Container(
              width: double.infinity,
              color: const Color(0xFF1E3A8A),
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              child: const Row(
                children: [
                  Icon(Icons.sync, color: Colors.amber, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'LOCATING REFILL STATION',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Live Map View (Dark / High Contrast styling)
              Expanded(
                child: Stack(
                  children: [
                    if (_loading)
                      const Center(child: CircularProgressIndicator(color: AppColors.primary))
                    else if (_error != null)
                      Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: Colors.white))))
                    else
                      FlutterMap(
                        mapController: _map,
                        options: MapOptions(
                          initialCenter: LatLng(_pos!.latitude, _pos!.longitude),
                          initialZoom: 15,
                          onMapReady: () {
                            _mapReady = true;
                            if (_route != null && _route!.points.isNotEmpty) {
                              _map.fitCamera(
                                CameraFit.bounds(
                                  bounds: LatLngBounds.fromPoints(_route!.points),
                                  padding: const EdgeInsets.all(48),
                                ),
                              );
                            }
                          },
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.wackysmart.app',
                          ),
                          if (_route != null && _route!.points.length >= 2)
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: _route!.points,
                                  strokeWidth: 6,
                                  color: const Color(0xFF2563EB),
                                  borderStrokeWidth: 2,
                                  borderColor: Colors.white,
                                ),
                              ],
                            ),
                          MarkerLayer(
                            markers: [
                              if (widget.stop.latLng != null)
                                Marker(
                                  point: widget.stop.latLng!,
                                  width: 44,
                                  height: 44,
                                  child: const Icon(Icons.location_on, color: Colors.red, size: 42),
                                ),
                              if (_pos != null)
                                Marker(
                                  point: LatLng(_pos!.latitude, _pos!.longitude),
                                  width: 40,
                                  height: 40,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 3),
                                    ),
                                    child: const Icon(Icons.navigation, color: Colors.white, size: 20),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),

                    // Destination Banner Overlay
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.person_pin_circle, color: Color(0xFF38BDF8), size: 24),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                customerLabel,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Bottom Driver Info Card & Action Button
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [
                    BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -3)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Driver Info Card
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.local_shipping_outlined, color: AppColors.primary, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _driverName,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                              ),
                              const Text(
                                'L300 Water Delivery Truck',
                                style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Active',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Action Button: START DELIVERY
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _startDelivery,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E60D5),
                          foregroundColor: Colors.white,
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text(
                          'START DELIVERY',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
