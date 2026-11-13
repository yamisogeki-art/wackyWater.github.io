import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_colors.dart';
import '../../widgets/logout_confirm.dart';

/// MotoGuard-style live tracking, applied to delivery operations: every
/// online driver's position, plus a line to wherever they're currently
/// headed (their in-transit delivery's address), all on one map.
class AdminDriverMapScreen extends StatefulWidget {
  const AdminDriverMapScreen({super.key});

  @override
  State<AdminDriverMapScreen> createState() => _AdminDriverMapScreenState();
}

class _AdminDriverMapScreenState extends State<AdminDriverMapScreen> {
  late final Stream<List<Map<String, dynamic>>> _driverLocationsStream;
  late final Stream<List<Map<String, dynamic>>> _inTransitStream;

  static const LatLng _defaultCenter = LatLng(7.6800, 122.4800); // Zamboanga Sibugay area (Tungawan, RT Lim, Ipil)

  List<Map<String, dynamic>> _drivers = [];
  final Map<dynamic, Map<String, dynamic>> _addressCache = {};

  @override
  void initState() {
    super.initState();
    _driverLocationsStream = Supabase.instance.client
        .from('driver_locations')
        .stream(primaryKey: ['driver_id']);
    _inTransitStream = Supabase.instance.client
        .from('delivery_requests')
        .stream(primaryKey: ['id']);
    _loadDrivers();
  }

  Future<void> _loadDrivers() async {
    final response = await Supabase.instance.client
        .from('profiles')
        .select('id, full_name')
        .eq('role', 'driver');
    if (mounted) setState(() => _drivers = List<Map<String, dynamic>>.from(response));
  }

  String _nameFor(String driverId) {
    final match = _drivers.where((d) => d['id'] == driverId);
    if (match.isEmpty) return driverId.substring(0, 6);
    final name = match.first['full_name'] as String?;
    return (name != null && name.trim().isNotEmpty) ? name : driverId.substring(0, 6);
  }

  Future<void> _ensureAddressesLoaded(List<dynamic> addressIds) async {
    final missing = addressIds.where((id) => id != null && !_addressCache.containsKey(id)).toSet().toList();
    if (missing.isEmpty) return;
    final rows = await Supabase.instance.client
        .from('customer_addresses')
        .select('id, label, area, latitude, longitude')
        .inFilter('id', missing);
    if (mounted) {
      setState(() {
        for (final row in List<Map<String, dynamic>>.from(rows)) {
          _addressCache[row['id']] = row;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Driver Tracking'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => logoutWithConfirmation(context),
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _driverLocationsStream,
        builder: (context, locSnapshot) {
          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: _inTransitStream,
            builder: (context, orderSnapshot) {
              if (locSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (locSnapshot.hasError) {
                return Center(child: Text('Error loading locations: ${locSnapshot.error}'));
              }

              final locations = locSnapshot.data ?? [];
              final cutoff = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
              final activeDrivers = locations.where((row) {
                final updatedAt = DateTime.tryParse(row['updated_at']?.toString() ?? '');
                return updatedAt != null && updatedAt.isAfter(cutoff);
              }).toList();

              final inTransit = (orderSnapshot.data ?? [])
                  .where((o) => o['status'] == 'in_transit' && o['driver_id'] != null)
                  .toList();

              _ensureAddressesLoaded(inTransit.map((o) => o['address_id']).toList());

              // Map driver_id -> their active in-transit delivery, so we
              // can draw a line from the driver to where they're headed.
              final activeDeliveryByDriver = <String, Map<String, dynamic>>{
                for (final o in inTransit) o['driver_id'] as String: o,
              };

              return Stack(
                children: [
                  FlutterMap(
                    options: const MapOptions(initialCenter: _defaultCenter, initialZoom: 12),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.wackysmart.app',
                      ),
                      PolylineLayer(
                        polylines: activeDrivers
                            .map((row) {
                              final driverId = row['driver_id'].toString();
                              final delivery = activeDeliveryByDriver[driverId];
                              if (delivery == null) return null;
                              final addr = _addressCache[delivery['address_id']];
                              if (addr == null) return null;
                              return Polyline(
                                points: [
                                  LatLng((row['latitude'] as num).toDouble(), (row['longitude'] as num).toDouble()),
                                  LatLng((addr['latitude'] as num).toDouble(), (addr['longitude'] as num).toDouble()),
                                ],
                                strokeWidth: 3,
                                color: AppColors.driverAccent.withOpacity(0.6),
                              );
                            })
                            .whereType<Polyline>()
                            .toList(),
                      ),
                      MarkerLayer(
                        markers: [
                          // Driver markers
                          ...activeDrivers.map((row) {
                            final lat = (row['latitude'] as num).toDouble();
                            final lng = (row['longitude'] as num).toDouble();
                            final driverId = row['driver_id'].toString();
                            final heading = activeDeliveryByDriver.containsKey(driverId);
                            return Marker(
                              point: LatLng(lat, lng),
                              width: 100,
                              height: 60,
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.black87,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(_nameFor(driverId), style: const TextStyle(color: Colors.white, fontSize: 11)),
                                  ),
                                  Icon(Icons.two_wheeler,
                                      color: heading ? AppColors.driverAccent : Colors.grey, size: 30),
                                ],
                              ),
                            );
                          }),
                          // In-transit destination markers
                          ...inTransit.map((o) {
                            final addr = _addressCache[o['address_id']];
                            if (addr == null) return null;
                            return Marker(
                              point: LatLng((addr['latitude'] as num).toDouble(), (addr['longitude'] as num).toDouble()),
                              width: 32,
                              height: 32,
                              child: const Icon(Icons.location_pin, color: Colors.red, size: 30),
                            );
                          }).whereType<Marker>(),
                        ],
                      ),
                    ],
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${activeDrivers.length} driver(s) online', style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text('${inTransit.length} delivery(ies) in transit', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
