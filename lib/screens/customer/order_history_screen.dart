import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../constants/pricing.dart';
import '../../theme/app_colors.dart';
import '../../utils/format.dart';

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  late final Stream<List<Map<String, dynamic>>> _historyStream;
  late final Stream<List<Map<String, dynamic>>> _transactionsStream;

  @override
  void initState() {
    super.initState();
    final userId = Supabase.instance.client.auth.currentUser?.id;
    _historyStream = Supabase.instance.client
        .from('delivery_requests')
        .stream(primaryKey: ['id'])
        .eq('customer_id', userId as Object)
        .order('requested_at', ascending: false);
    // Own transactions only - customers can select their own rows per
    // the "Customers can read their own transactions" RLS policy.
    _transactionsStream = Supabase.instance.client
        .from('customer_transactions')
        .stream(primaryKey: ['id'])
        .eq('customer_id', userId as Object);
  }

  /// (label, text color, background) for the status pill.
  (String, Color, Color) _pill(String status) {
    switch (status) {
      case 'delivered':
        return ('Delivered', AppColors.successGreen, AppColors.successBg);
      case 'in_transit':
        return ('On the way', AppColors.statusInTransit, AppColors.statusInTransitBg);
      case 'assigned':
        return ('Assigned', AppColors.statusInTransit, AppColors.statusInTransitBg);
      default:
        return ('Pending', AppColors.statusPending, AppColors.statusPendingBg);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Order History')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _historyStream,
        builder: (context, orderSnapshot) {
          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: _transactionsStream,
            builder: (context, txSnapshot) {
              if (orderSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final history = orderSnapshot.data ?? [];
              final transactions = txSnapshot.data ?? [];

              // Map delivery_request_id -> its recorded transaction, so a
              // delivered order shows the price admin/driver actually charged.
              final txByOrderId = {
                for (final t in transactions)
                  if (t['delivery_request_id'] != null) t['delivery_request_id']: t,
              };

              if (history.isEmpty) {
                return const Center(child: Text('No order history found.'));
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                itemCount: history.length,
                separatorBuilder: (context, index) => const Divider(height: 1, color: AppColors.border),
                itemBuilder: (context, index) {
                  final order = history[index];
                  final date = DateTime.parse(order['requested_at']).toLocal();
                  final status = order['status'].toString();
                  final gallons = (order['gallons_requested'] as num?) ?? 0;
                  final tx = txByOrderId[order['id']];

                  // Real charged price when a transaction exists; otherwise an
                  // estimate from the rate card (no price is stored on the order).
                  final double price;
                  final bool isEstimate;
                  if (tx != null) {
                    price = (tx['gallons'] as num).toDouble() * (tx['price_per_gallon'] as num).toDouble();
                    isEstimate = false;
                  } else {
                    price = gallons.toDouble() * pricePerGallonFor(order['water_type'] as String?);
                    isEstimate = true;
                  }
                  final (pillLabel, pillFg, pillBg) = _pill(status);

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.water_drop, color: Color(0xFF3B9BF0)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(formatLongDate(date), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              const SizedBox(height: 2),
                              Text(
                                '$gallons ${gallons == 1 ? 'gallon' : 'gallons'}',
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${isEstimate ? 'est. ' : ''}₱${price.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: isEstimate ? 14 : 15,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(color: pillBg, borderRadius: BorderRadius.circular(20)),
                              child: Text(
                                pillLabel,
                                style: TextStyle(color: pillFg, fontSize: 11.5, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
