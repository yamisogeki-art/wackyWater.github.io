import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_colors.dart';

/// Shows the live position of the driver assigned to the customer's
/// active order, the same way MotoGuard shows the owner where their
/// motorcycle is - one marker for the driver (from `driver_locations`,
/// realtime), one for the delivery address, both on one map.
///
/// Only meaningful once an order has moved past "pending" - a driver
/// has to actually be assigned and broadcasting location first.
class TrackOrderScreen extends StatefulWidget {
  const TrackOrderScreen({super.key});

  @override
  State<TrackOrderScreen> createState() => _TrackOrderScreenState();
}

class _TrackOrderScreenState extends State<TrackOrderScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _activeOrder;
  LatLng? _destination;
  Stream<List<Map<String, dynamic>>>? _driverLocationStream;

  @override
  void initState() {
    super.initState();
    _loadActiveOrder();
  }

  Future<void> _loadActiveOrder() async {
    final customerId = Supabase.instance.client.auth.currentUser?.id;
    if (customerId == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final orders = await Supabase.instance.client
          .from('delivery_requests')
          .select('id, status, driver_id, gallons_requested, water_type, '
              'customer_addresses(label, area, latitude, longitude)')
          .eq('customer_id', customerId)
          .inFilter('status', ['assigned', 'in_transit'])
          .order('requested_at', ascending: false)
          .limit(1);

      if (orders.isNotEmpty) {
        final order = orders.first;
        final address = order['customer_addresses'];
        setState(() {
          _activeOrder = order;
          if (address != null) {
            _destination = LatLng(
              (address['latitude'] as num).toDouble(),
              (address['longitude'] as num).toDouble(),
            );
          }
          if (order['driver_id'] != null) {
            _driverLocationStream = Supabase.instance.client
                .from('driver_locations')
                .stream(primaryKey: ['driver_id'])
                .eq('driver_id', order['driver_id'] as String);
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading active order: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Track My Order'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _isLoading = true);
              _loadActiveOrder();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _activeOrder == null
              ? _NoActiveOrder()
              : _buildTrackingView(),
    );
  }

  Widget _buildTrackingView() {
    final status = _activeOrder!['status'] as String;
    final noDriverYet = _driverLocationStream == null;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: AppColors.primaryLight,
          child: Row(
            children: [
              Icon(
                status == 'in_transit' ? Icons.local_shipping : Icons.pending_actions,
                color: AppColors.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status == 'in_transit' ? 'Driver is on the way' : 'Driver assigned',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${_activeOrder!['gallons_requested']} gallons - '
                      '${(_activeOrder!['water_type'] as String?) == 'mineral' ? 'Mineral' : 'Purified'} water',
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: noDriverYet
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Waiting for the driver to start sharing their location.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _driverLocationStream,
                  builder: (context, snapshot) {
                    final rows = snapshot.data ?? [];
                    final driverPoint = rows.isNotEmpty
                        ? LatLng(
                            (rows.first['latitude'] as num).toDouble(),
                            (rows.first['longitude'] as num).toDouble(),
                          )
                        : null;

                    if (driverPoint == null) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            "Driver hasn't shared a location yet - check back shortly.",
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }

                    return FlutterMap(
                      options: MapOptions(
                        initialCenter: driverPoint,
                        initialZoom: 14,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.wackysmart.app',
                        ),
                        MarkerLayer(markers: [
                          Marker(
                            point: driverPoint,
                            width: 50,
                            height: 50,
                            child: const _DriverMarker(),
                          ),
                          if (_destination != null)
                            Marker(
                              point: _destination!,
                              width: 40,
                              height: 40,
                              child: const Icon(Icons.location_pin, color: Colors.red, size: 36),
                            ),
                        ]),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _DriverMarker extends StatelessWidget {
  const _DriverMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.driverAccent,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 6)],
      ),
      child: const Icon(Icons.two_wheeler, color: Colors.white, size: 24),
    );
  }
}

class _NoActiveOrder extends StatelessWidget {
  const _NoActiveOrder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'No active delivery to track',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Once your order is assigned to a driver, you can watch them '
              'on the map here.',
              style: TextStyle(color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
