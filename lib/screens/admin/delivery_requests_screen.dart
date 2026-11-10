import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_colors.dart';

class DeliveryRequestsScreen extends StatefulWidget {
  const DeliveryRequestsScreen({super.key});

  @override
  State<DeliveryRequestsScreen> createState() => _DeliveryRequestsScreenState();
}

class _DeliveryRequestsScreenState extends State<DeliveryRequestsScreen> {
  late final Stream<List<Map<String, dynamic>>> _requestsStream;
  List<Map<String, dynamic>> _drivers = [];
  Map<dynamic, Map<String, dynamic>> _addressesCache = {};
  Map<String, Map<String, dynamic>> _customersCache = {};
  bool _isLoadingDetails = false;

  @override
  void initState() {
    super.initState();
    _requestsStream = Supabase.instance.client
        .from('delivery_requests')
        .stream(primaryKey: ['id'])
        .order('requested_at');
    _loadDrivers();
  }

  Future<void> _loadDrivers() async {
    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select('id, full_name, phone')
          .eq('role', 'driver');
      if (mounted) {
        setState(() => _drivers = List<Map<String, dynamic>>.from(response));
      }
    } catch (e) {
      debugPrint('Error loading drivers: $e');
    }
  }

  Future<void> _loadMissingDetails(List<Map<String, dynamic>> requests) async {
    final missingAddrIds = requests
        .map((r) => r['address_id'])
        .where((id) => id != null && !_addressesCache.containsKey(id))
        .toSet()
        .toList();

    if (missingAddrIds.isNotEmpty) {
      try {
        final addrs = await Supabase.instance.client
            .from('customer_addresses')
            .select('id, label, area')
            .inFilter('id', missingAddrIds);
        for (final a in List<Map<String, dynamic>>.from(addrs)) {
          _addressesCache[a['id']] = a;
        }
      } catch (e) {
        debugPrint('Error loading addresses: $e');
      }
    }

    final missingCustIds = requests
        .map((r) => r['customer_id'])
        .whereType<String>()
        .where((id) => !_customersCache.containsKey(id))
        .toSet()
        .toList();

    if (missingCustIds.isNotEmpty) {
      try {
        final custs = await Supabase.instance.client
            .from('profiles')
            .select('id, full_name, phone')
            .inFilter('id', missingCustIds);
        for (final c in List<Map<String, dynamic>>.from(custs)) {
          _customersCache[c['id'] as String] = c;
        }
      } catch (e) {
        debugPrint('Error loading customer details: $e');
      }
    }
  }

  Future<void> _assignDriverToSingleOrder(dynamic requestId, String driverId) async {
    try {
      await Supabase.instance.client.from('delivery_requests').update({
        'driver_id': driverId,
        'status': 'assigned',
      }).eq('id', requestId);

      if (mounted) {
        final driverName = _driverName(driverId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            content: Text('Order assigned to Driver: $driverName'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to assign driver: $e')),
        );
      }
    }
  }

  Future<void> _assignDriverToBarangayGroup(List<Map<String, dynamic>> ordersInBarangay, String driverId) async {
    final ids = ordersInBarangay.map((o) => o['id']).toList();
    if (ids.isEmpty) return;

    try {
      await Supabase.instance.client.from('delivery_requests').update({
        'driver_id': driverId,
        'status': 'assigned',
      }).inFilter('id', ids);

      if (mounted) {
        final driverName = _driverName(driverId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            content: Text('Assigned all ${ids.length} orders in this barangay to Driver: $driverName!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed bulk assignment: $e')),
        );
      }
    }
  }

  String _driverName(String? driverId) {
    if (driverId == null || driverId.isEmpty) return 'Unassigned';
    final match = _drivers.where((d) => d['id'] == driverId);
    if (match.isNotEmpty) {
      final name = match.first['full_name'] as String?;
      if (name != null && name.trim().isNotEmpty) return name;
    }
    return driverId.length > 8 ? driverId.substring(0, 8) : driverId;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Assign Deliveries by Barangay'),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _requestsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !_isLoadingDetails) {
            return const Center(child: CircularProgressIndicator());
          }

          final allRequests = snapshot.data ?? [];
          final openRequests = allRequests.where((r) => r['status'] != 'delivered').toList();

          if (openRequests.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, size: 64, color: AppColors.successGreen),
                  SizedBox(height: 12),
                  Text('No open delivery requests!', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('All customer orders have been completed.', style: TextStyle(color: AppColors.textMuted)),
                ],
              ),
            );
          }

          // Asynchronously fetch missing address/customer info
          _loadMissingDetails(openRequests).then((_) {
            if (mounted && !_isLoadingDetails) {
              setState(() => _isLoadingDetails = true);
            }
          });

          // Group open requests by Barangay / Area
          final Map<String, List<Map<String, dynamic>>> groupedByBarangay = {};
          for (final req in openRequests) {
            final addr = _addressesCache[req['address_id']];
            final area = (addr?['area'] as String?)?.trim();
            final barangayKey = (area != null && area.isNotEmpty) ? area : 'Unassigned Barangay';
            groupedByBarangay.putIfAbsent(barangayKey, () => []).add(req);
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBAE6FD)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Color(0xFF0369A1)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Grouped by Barangay (${groupedByBarangay.keys.length} Areas). Select a driver to assign an entire barangay or individual order.',
                        style: const TextStyle(fontSize: 12.5, color: Color(0xFF0369A1), fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ...groupedByBarangay.entries.map((entry) {
                final barangay = entry.key;
                final orders = entry.value;
                int barangayGallons = 0;
                for (final o in orders) {
                  barangayGallons += (o['gallons_requested'] as num?)?.toInt() ?? 0;
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: const [
                      BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // BARANGAY HEADER & BULK ASSIGNMENT CONTROL
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.location_city, color: Color(0xFF0284C7), size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      barangay,
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0284C7),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${orders.length} ${orders.length == 1 ? 'Order' : 'Orders'} ($barangayGallons Gal)',
                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            // Bulk Driver Assignment for whole Barangay
                            DropdownButtonFormField<String>(
                              decoration: InputDecoration(
                                labelText: 'Bulk Assign Entire $barangay Route',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                filled: true,
                                fillColor: Colors.white,
                                isDense: true,
                              ),
                              items: _drivers
                                  .map((d) => DropdownMenuItem<String>(
                                        value: d['id'] as String,
                                        child: Text(
                                          'Assign all to: ${d['full_name'] ?? (d['id'] as String).substring(0, 8)}',
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                        ),
                                      ))
                                  .toList(),
                              onChanged: (driverId) {
                                if (driverId != null) {
                                  _assignDriverToBarangayGroup(orders, driverId);
                                }
                              },
                            ),
                          ],
                        ),
                      ),

                      // INDIVIDUAL ORDERS IN THIS BARANGAY
                      ...orders.map((req) {
                        final reqId = req['id'];
                        final gallons = req['gallons_requested'];
                        final waterType = (req['water_type'] == 'mineral' ? 'Mineral' : 'Purified');
                        final orderType = (req['order_type'] == 'exchange' ? 'Exchange' : 'Refill');
                        final status = req['status'] as String;
                        final assignedDriverId = req['driver_id'] as String?;

                        final cust = _customersCache[req['customer_id']];
                        final custName = cust?['full_name'] ?? 'Customer';
                        final custPhone = cust?['phone'] ?? '';

                        final addr = _addressesCache[req['address_id']];
                        final addrLabel = addr?['label'] ?? 'Delivery Address';

                        final isAssigned = status == 'assigned' || status == 'in_transit';

                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: const BoxDecoration(
                            border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    custName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isAssigned ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      status.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: isAssigned ? const Color(0xFF15803D) : const Color(0xFFB45309),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$addrLabel · $gallons Gal ($waterType - $orderType)',
                                style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                              ),
                              if (custPhone.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text('Phone: $custPhone', style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                              ],
                              const SizedBox(height: 8),
                              // Single Order Driver Assignment
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      initialValue: assignedDriverId,
                                      decoration: InputDecoration(
                                        labelText: isAssigned ? 'Assigned Driver' : 'Assign Single Order',
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        isDense: true,
                                      ),
                                      items: _drivers
                                          .map((d) => DropdownMenuItem<String>(
                                                value: d['id'] as String,
                                                child: Text(
                                                  d['full_name'] ?? (d['id'] as String).substring(0, 8),
                                                  style: const TextStyle(fontSize: 12.5),
                                                ),
                                              ))
                                          .toList(),
                                      onChanged: (driverId) {
                                        if (driverId != null) {
                                          _assignDriverToSingleOrder(reqId, driverId);
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}
