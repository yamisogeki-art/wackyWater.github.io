import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


/// Admin screen for recording the day's water sales.
///
/// Delivered orders that haven't been turned into a transaction yet are
/// shown first ("Delivered orders to record") - these are real, already-
/// confirmed sales from the delivery flow, so they take priority over
/// anything typed in from scratch. Below that, admin can add a manual
/// transaction for a walk-in / cash sale, picking the customer from the
/// stored `profiles` list instead of retyping their details.
class DailyTransactionsScreen extends StatefulWidget {
  const DailyTransactionsScreen({super.key});

  @override
  State<DailyTransactionsScreen> createState() => _DailyTransactionsScreenState();
}

class _DailyTransactionsScreenState extends State<DailyTransactionsScreen> {
  static const double _purifiedPrice = 180.0;
  static const double _mineralPrice = 20.0;

  double _priceFor(String waterType) => waterType == 'mineral' ? _mineralPrice : _purifiedPrice;

  late final Stream<List<Map<String, dynamic>>> _ordersStream;
  late final Stream<List<Map<String, dynamic>>> _transactionsStream;
  List<Map<String, dynamic>> _customers = [];

  @override
  void initState() {
    super.initState();
    _ordersStream = Supabase.instance.client
        .from('delivery_requests')
        .stream(primaryKey: ['id'])
        .order('requested_at', ascending: false);
    _transactionsStream = Supabase.instance.client
        .from('customer_transactions')
        .stream(primaryKey: ['id'])
        .order('transaction_date', ascending: false);
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    final response = await Supabase.instance.client
        .from('profiles')
        .select('id, full_name')
        .eq('role', 'customer');
    if (mounted) {
      setState(() => _customers = List<Map<String, dynamic>>.from(response));
    }
  }

  String _todayStr() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  String _nameFor(String customerId) {
    final match = _customers.where((c) => c['id'] == customerId);
    if (match.isEmpty) return customerId.substring(0, 8);
    final name = match.first['full_name'] as String?;
    return (name != null && name.trim().isNotEmpty) ? name : customerId.substring(0, 8);
  }

  Future<void> _recordFromOrder(Map<String, dynamic> order, double pricePerGallon) async {
    final gallons = (order['gallons_requested'] as num).toDouble();
    final waterType = (order['water_type'] as String?) ?? 'purified';
    await Supabase.instance.client.from('customer_transactions').insert({
      'customer_id': order['customer_id'],
      'delivery_request_id': order['id'],
      'transaction_date': _todayStr(),
      'gallons': gallons,
      'price_per_gallon': pricePerGallon,
      'water_type': waterType,
      'amount_paid': 0,
      'status': 'unpaid',
    });
    await _syncDailyAggregate(gallons);
  }

  /// Adds this delivery's gallons into today's `daily_transactions` row
  /// (creating it if it doesn't exist yet). That table is what the real
  /// LightGBM/XGBoost forecast model reads from (see
  /// wackysmart_forecast/backend/main.py) - without this, recorded
  /// deliveries would never actually reach the forecasting pipeline, and
  /// the model would keep predicting off old seeded history forever.
  Future<void> _syncDailyAggregate(double gallons) async {
    try {
      await Supabase.instance.client.rpc('upsert_daily_gallons', params: {
        'p_date': _todayStr(),
        'p_gallons': gallons,
      });
    } catch (e) {
      // Don't block the transaction record on this - surface it, but
      // the customer_transactions row (the source of truth for
      // billing/credit) is already saved either way.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Recorded, but forecast data sync failed: $e')),
        );
      }
    }
  }

  Future<void> _recordManual({
    required String customerId,
    required double gallons,
    required double pricePerGallon,
    required double amountPaid,
    required String waterType,
  }) async {
    final due = gallons * pricePerGallon;
    final status = amountPaid <= 0 ? 'unpaid' : (amountPaid < due ? 'partial' : 'paid');
    await Supabase.instance.client.from('customer_transactions').insert({
      'customer_id': customerId,
      'transaction_date': _todayStr(),
      'gallons': gallons,
      'price_per_gallon': pricePerGallon,
      'water_type': waterType,
      'amount_paid': amountPaid,
      'status': status,
    });
    await _syncDailyAggregate(gallons);
  }

  Future<void> _promptRecordFromOrder(Map<String, dynamic> order) async {
    final waterType = (order['water_type'] as String?) ?? 'purified';
    final priceController = TextEditingController(text: _priceFor(waterType).toStringAsFixed(2));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record transaction'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${order['gallons_requested']} gallons delivered - '
                '${waterType == 'mineral' ? 'Mineral' : 'Purified'} water'),
            Text('Customer: ${_nameFor(order['customer_id'] as String)}'),
            const SizedBox(height: 12),
            TextField(
              controller: priceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Price per gallon (₱)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (confirmed == true) {
      final price = double.tryParse(priceController.text) ?? _priceFor(waterType);
      await _recordFromOrder(order, price);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Transaction recorded.')));
      }
    }
  }

  Future<void> _openManualEntryDialog() async {
    if (_customers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No customers found in profiles yet.')),
      );
      return;
    }
    String selectedCustomerId = _customers.first['id'] as String;
    String waterType = 'purified';
    final gallonsController = TextEditingController();
    final priceController = TextEditingController(text: _priceFor(waterType).toStringAsFixed(2));
    final paidController = TextEditingController(text: '0');

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Add transaction'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedCustomerId,
                  decoration: const InputDecoration(
                    labelText: 'Customer',
                    border: OutlineInputBorder(),
                  ),
                  items: _customers
                      .map((c) => DropdownMenuItem<String>(
                            value: c['id'] as String,
                            child: Text(_nameFor(c['id'] as String)),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDialogState(() => selectedCustomerId = v);
                  },
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'purified', label: Text('Purified')),
                    ButtonSegment(value: 'mineral', label: Text('Mineral')),
                  ],
                  selected: {waterType},
                  onSelectionChanged: (v) => setDialogState(() {
                    waterType = v.first;
                    priceController.text = _priceFor(waterType).toStringAsFixed(2);
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: gallonsController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Gallons',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Price per gallon (₱)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: paidController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Amount paid now (₱)',
                    border: OutlineInputBorder(),
                    helperText: 'Leave as 0 to add the full amount to their credit',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final gallons = double.tryParse(gallonsController.text) ?? 0;
                if (gallons <= 0) return;
                final price = double.tryParse(priceController.text) ?? _priceFor(waterType);
                final paid = double.tryParse(paidController.text) ?? 0;
                await _recordManual(
                  customerId: selectedCustomerId,
                  gallons: gallons,
                  pricePerGallon: price,
                  amountPaid: paid,
                  waterType: waterType,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daily transactions')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openManualEntryDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add transaction'),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _ordersStream,
        builder: (context, orderSnapshot) {
          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: _transactionsStream,
            builder: (context, txSnapshot) {
              if (orderSnapshot.connectionState == ConnectionState.waiting ||
                  txSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final transactions = txSnapshot.data ?? [];
              final recordedOrderIds = transactions
                  .where((t) => t['delivery_request_id'] != null)
                  .map((t) => t['delivery_request_id'])
                  .toSet();

              // Delivered orders with no matching transaction row yet -
              // these are shown first since they're confirmed sales that
              // still need to be reconciled into today's record.
              final pendingOrders = (orderSnapshot.data ?? [])
                  .where((o) =>
                      o['status'] == 'delivered' && !recordedOrderIds.contains(o['id']))
                  .toList();

              final todayTx =
                  transactions.where((t) => t['transaction_date'] == _todayStr()).toList();

              return ListView(
                padding: const EdgeInsets.only(bottom: 96, top: 8),
                children: [
                  if (pendingOrders.isNotEmpty) ...[
                    const _SectionHeader('Delivered orders to record'),
                    ...pendingOrders.map((order) => Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          color: Colors.amber.shade50,
                          child: ListTile(
                            leading: const Icon(Icons.local_shipping_outlined),
                            title: Text(
                                '${order['gallons_requested']} gallons - order #${order['id']}'),
                            subtitle: Text(_nameFor(order['customer_id'] as String)),
                            trailing: FilledButton(
                              onPressed: () => _promptRecordFromOrder(order),
                              child: const Text('Record'),
                            ),
                          ),
                        )),
                  ],
                  _SectionHeader("Today's recorded transactions"),
                  if (todayTx.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text('No transactions recorded yet today.'),
                    )
                  else
                    ...todayTx.map((t) {
                      final due =
                          (t['gallons'] as num).toDouble() * (t['price_per_gallon'] as num).toDouble();
                      final paid = (t['amount_paid'] as num).toDouble();
                      final status = t['status'] as String;
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: ListTile(
                          leading: Icon(
                            status == 'paid' ? Icons.check_circle : Icons.pending_outlined,
                            color: status == 'paid' ? Colors.green : Colors.orange,
                          ),
                          title: Text(
                              '${_nameFor(t['customer_id'] as String)} - ${t['gallons']} gal @ ₱${t['price_per_gallon']}'),
                          subtitle: Text(
                              'Due ₱${due.toStringAsFixed(2)} - paid ₱${paid.toStringAsFixed(2)} ($status)'),
                        ),
                      );
                    }),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}
