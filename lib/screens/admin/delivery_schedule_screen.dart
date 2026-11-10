import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/forecast_service.dart';

/// Builds today's delivery route from pending customer orders, area by
/// area, so the driver always goes where the real, current demand is -
/// not a forecast guess.
///
/// Priority rules (highest to lowest):
///   1. Area has 3+ pending orders AND hasn't been delivered to in the
///      last 3 days (or ever) - high demand, overdue.
///   2. Area hasn't been delivered to in the last 3 days (or ever),
///      regardless of order count - just overdue.
///   3. Everything else - served recently, normal cycle.
///
/// Orders are pulled area-by-area in that priority order and added to
/// today's route until the running total would exceed 800 gallons (the
/// top of the daily target band). Anything that doesn't fit stays
/// `pending` in `delivery_requests` - it isn't lost, it's automatically
/// reconsidered (and likely bumped to a higher tier, since its area
/// stays "overdue") the next time this screen builds a route.
class DeliveryScheduleScreen extends StatefulWidget {
  const DeliveryScheduleScreen({super.key});

  @override
  State<DeliveryScheduleScreen> createState() => _DeliveryScheduleScreenState();
}

class _DeliveryScheduleScreenState extends State<DeliveryScheduleScreen> {
  static const int _minTargetGallons = 400;
  static const int _maxTargetGallons = 800;
  static const int _manyOrdersThreshold = 3;
  static const int _overdueDays = 3;

  bool _isLoading = true;
  String? _errorMessage;

  List<_RoutedOrder> _todaysRoute = [];
  List<_RoutedOrder> _deferred = [];
  double _todaysTotalGallons = 0;
  List<Map<String, dynamic>> _customers = [];

  double? _predictedGallons;
  String? _modelVersion;

  @override
  void initState() {
    super.initState();
    _buildSchedule();
  }

  Future<void> _loadCustomers() async {
    final response = await Supabase.instance.client
        .from('profiles')
        .select('id, full_name')
        .eq('role', 'customer');
    _customers = List<Map<String, dynamic>>.from(response);
  }

  String _nameFor(String customerId) {
    final match = _customers.where((c) => c['id'] == customerId);
    if (match.isEmpty) return customerId.substring(0, 8);
    final name = match.first['full_name'] as String?;
    return (name != null && name.trim().isNotEmpty) ? name : customerId.substring(0, 8);
  }

  Future<void> _buildSchedule() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _loadCustomers();

      // Load forecast demand if available
      try {
        final forecastRes = await ForecastService().load();
        if (forecastRes.forecast.isNotEmpty) {
          _predictedGallons = forecastRes.forecast.first.gallons;
          _modelVersion = forecastRes.modelVersion;
        }
      } catch (_) {}

      // Pending orders, each carrying its address's area via the FK join.
      final pendingRaw = await Supabase.instance.client
          .from('delivery_requests')
          .select('id, customer_id, address_id, gallons_requested, requested_at, '
              'customer_addresses(area, label)')
          .eq('status', 'pending')
          .order('requested_at');

      // Delivery history, joined through to the area it served, so we can
      // tell how recently each area was actually delivered to.
      final historyRaw = await Supabase.instance.client
          .from('customer_transactions')
          .select('transaction_date, delivery_requests(address_id, customer_addresses(area))');

      final pending = List<Map<String, dynamic>>.from(pendingRaw);
      final history = List<Map<String, dynamic>>.from(historyRaw);

      // Last-served date per area, from delivery-linked transactions only
      // (walk-in/manual transactions aren't tied to a route area).
      final lastServed = <String, DateTime>{};
      for (final row in history) {
        final deliveryRequest = row['delivery_requests'];
        if (deliveryRequest == null) continue;
        final area = deliveryRequest['customer_addresses']?['area'] as String?;
        if (area == null) continue;
        final date = DateTime.tryParse(row['transaction_date'] as String);
        if (date == null) continue;
        if (!lastServed.containsKey(area) || date.isAfter(lastServed[area]!)) {
          lastServed[area] = date;
        }
      }

      // Group pending orders by area.
      final byArea = <String, List<Map<String, dynamic>>>{};
      for (final order in pending) {
        final area = (order['customer_addresses']?['area'] as String?)?.trim();
        final key = (area == null || area.isEmpty) ? 'Unassigned area' : area;
        byArea.putIfAbsent(key, () => []).add(order);
      }

      final today = DateTime.now();
      int daysSince(String area) {
        final last = lastServed[area];
        if (last == null) return 1 << 30; // never served - treat as far overdue
        return today.difference(last).inDays;
      }

      int tierFor(String area, int orderCount) {
        final overdue = daysSince(area) >= _overdueDays;
        if (orderCount >= _manyOrdersThreshold && overdue) return 2;
        if (overdue) return 1;
        return 0;
      }

      // One priority-ordered list: area tier first, then order count
      // within tier, then oldest request first within an area.
      final areaEntries = byArea.entries.toList()
        ..sort((a, b) {
          final tierA = tierFor(a.key, a.value.length);
          final tierB = tierFor(b.key, b.value.length);
          if (tierA != tierB) return tierB.compareTo(tierA);
          return b.value.length.compareTo(a.value.length);
        });

      final prioritized = <_RoutedOrder>[];
      for (final entry in areaEntries) {
        final area = entry.key;
        final orders = [...entry.value]
          ..sort((a, b) => (a['requested_at'] as String).compareTo(b['requested_at'] as String));
        final tier = tierFor(area, orders.length);
        for (final order in orders) {
          prioritized.add(_RoutedOrder(
            id: order['id'],
            customerId: order['customer_id'] as String,
            area: area,
            gallons: (order['gallons_requested'] as num).toDouble(),
            tier: tier,
            daysSinceAreaServed: daysSince(area),
            orderCountInArea: orders.length,
          ));
        }
      }

      // Fill today's route up to the target ceiling; overflow is deferred.
      final route = <_RoutedOrder>[];
      final deferred = <_RoutedOrder>[];
      var cumulative = 0.0;
      for (final order in prioritized) {
        if (cumulative + order.gallons <= _maxTargetGallons) {
          route.add(order);
          cumulative += order.gallons;
        } else {
          deferred.add(order);
        }
      }

      if (mounted) {
        setState(() {
          _todaysRoute = route;
          _deferred = deferred;
          _todaysTotalGallons = cumulative;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to build schedule: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _markDelivered(_RoutedOrder order) async {
    await Supabase.instance.client
        .from('delivery_requests')
        .update({'status': 'delivered'}).eq('id', order.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marked delivered - record payment in Transactions.')),
      );
    }
    _buildSchedule();
  }

  String _tierLabel(int tier) {
    switch (tier) {
      case 2:
        return 'High priority - many orders, overdue';
      case 1:
        return 'Priority - overdue for delivery';
      default:
        return 'Normal cycle';
    }
  }

  Color _tierColor(int tier) {
    switch (tier) {
      case 2:
        return Colors.red.shade50;
      case 1:
        return Colors.amber.shade50;
      default:
        return Colors.grey.shade100;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery schedule'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _buildSchedule,
            tooltip: 'Rebuild schedule',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(child: Text(_errorMessage!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _TargetGauge(
                      total: _todaysTotalGallons,
                      min: _minTargetGallons.toDouble(),
                      max: _maxTargetGallons.toDouble(),
                      predicted: _predictedGallons,
                      modelVersion: _modelVersion,
                    ),
                    const SizedBox(height: 20),
                    Text("Today's route (${_todaysRoute.length} stops)",
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    if (_todaysRoute.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('No pending orders to route right now.'),
                      )
                    else
                      ..._todaysRoute.map((o) => Card(
                            color: _tierColor(o.tier),
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              title: Text('${_nameFor(o.customerId)} - ${o.gallons.toStringAsFixed(0)} gal'),
                              subtitle: Text(
                                '${o.area} - ${_tierLabel(o.tier)}\n'
                                '${o.orderCountInArea} order(s) in area - '
                                '${o.daysSinceAreaServed > 1000 ? 'never served' : '${o.daysSinceAreaServed}d since last delivery'}',
                              ),
                              isThreeLine: true,
                              trailing: FilledButton(
                                onPressed: () => _markDelivered(o),
                                child: const Text('Delivered'),
                              ),
                            ),
                          )),
                    if (_deferred.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text('Deferred to next schedule (${_deferred.length})',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const Text(
                        "Over today's 800-gallon target - stays pending and will be "
                        're-prioritized automatically next time the route is built.',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      ..._deferred.map((o) => Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              leading: const Icon(Icons.schedule_outlined),
                              title: Text('${_nameFor(o.customerId)} - ${o.gallons.toStringAsFixed(0)} gal'),
                              subtitle: Text(o.area),
                            ),
                          )),
                    ],
                  ],
                ),
    );
  }
}

class _RoutedOrder {
  final dynamic id;
  final String customerId;
  final String area;
  final double gallons;
  final int tier;
  final int daysSinceAreaServed;
  final int orderCountInArea;

  _RoutedOrder({
    required this.id,
    required this.customerId,
    required this.area,
    required this.gallons,
    required this.tier,
    required this.daysSinceAreaServed,
    required this.orderCountInArea,
  });
}

class _TargetGauge extends StatelessWidget {
  final double total;
  final double min;
  final double max;
  final double? predicted;
  final String? modelVersion;

  const _TargetGauge({
    required this.total,
    required this.min,
    required this.max,
    this.predicted,
    this.modelVersion,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = (total / max).clamp(0.0, 1.0);
    final belowMin = total < min;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    "Today's planned volume: ${total.toStringAsFixed(0)} gal",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                Text(
                  'Target ${min.toStringAsFixed(0)}-${max.toStringAsFixed(0)} gal',
                  style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            if (predicted != null) ...[
              const SizedBox(height: 4),
              Text(
                'Predicted demand: ${predicted!.toStringAsFixed(0)} gal (${modelVersion ?? 'LightGBM'})',
                style: TextStyle(fontSize: 12, color: Colors.blue.shade700, fontWeight: FontWeight.w500),
              ),
            ],
            const SizedBox(height: 10),
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 14,
                    backgroundColor: Colors.grey.shade200,
                    color: belowMin ? Colors.orange : Colors.green,
                  ),
                ),
                Positioned(
                  left: (min / max) * (MediaQuery.of(context).size.width - 64),
                  child: Container(width: 2, height: 14, color: Colors.black45),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (belowMin)
              const Text(
                'Below target - not enough pending orders right now.',
                style: TextStyle(color: Colors.orange, fontSize: 12),
              )
            else
              const Text(
                'Within target range.',
                style: TextStyle(color: Colors.green, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }
}
