import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_colors.dart';
import '../../utils/format.dart';
import 'transaction_record_screen.dart';

class DriverTransactionRecordsTab extends StatefulWidget {
  const DriverTransactionRecordsTab({super.key});

  @override
  State<DriverTransactionRecordsTab> createState() => _DriverTransactionRecordsTabState();
}

class _DriverTransactionRecordsTabState extends State<DriverTransactionRecordsTab> {
  late final Stream<List<Map<String, dynamic>>> _transactionsStream;

  @override
  void initState() {
    super.initState();
    // Query transactions arranged by date from latest to oldest
    _transactionsStream = Supabase.instance.client
        .from('customer_transactions')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);
  }

  Widget _summaryStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Transaction Records'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _transactionsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final rawTransactions = snapshot.data ?? [];

          // Compute Totals
          double totalGallons = 0;
          double totalMoney = 0;
          double totalCOD = 0;
          double totalGCash = 0;

          for (final tx in rawTransactions) {
            final gal = (tx['gallons'] as num?)?.toDouble() ?? 0.0;
            final price = (tx['price_per_gallon'] as num?)?.toDouble() ?? 180.0;
            final paid = (tx['amount_paid'] as num?)?.toDouble() ?? (gal * price);

            totalGallons += gal;
            totalMoney += paid;

            final note = (tx['notes'] ?? '').toString().toLowerCase();
            final paymentMethod = (tx['payment_method'] ?? '').toString().toLowerCase();

            if (note.contains('gcash') || paymentMethod.contains('gcash')) {
              totalGCash += paid;
            } else {
              // Defaults to COD or cash
              totalCOD += paid;
            }
          }

          return Column(
            children: [
              // SUMMARY HEADER
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'DELIVERY & COLLECTION SUMMARY',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B), letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _summaryStatCard(
                            title: 'Delivered Gallons',
                            value: '${totalGallons % 1 == 0 ? totalGallons.toInt() : totalGallons.toStringAsFixed(1)} Gal',
                            icon: Icons.water_drop_outlined,
                            color: const Color(0xFF0284C7),
                            bgColor: const Color(0xFFF0F9FF),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _summaryStatCard(
                            title: 'Total Collection',
                            value: '₱${totalMoney.toStringAsFixed(2)}',
                            icon: Icons.monetization_on_outlined,
                            color: const Color(0xFF16A34A),
                            bgColor: const Color(0xFFF0FDF4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _summaryStatCard(
                            title: 'COD Total',
                            value: '₱${totalCOD.toStringAsFixed(2)}',
                            icon: Icons.payments_outlined,
                            color: const Color(0xFFD97706),
                            bgColor: const Color(0xFFFFFBEB),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _summaryStatCard(
                            title: 'GCash Total',
                            value: '₱${totalGCash.toStringAsFixed(2)}',
                            icon: Icons.account_balance_wallet_outlined,
                            color: const Color(0xFF2563EB),
                            bgColor: const Color(0xFFEFF6FF),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // TRANSACTIONS LIST (Arranged from latest to oldest)
              Expanded(
                child: rawTransactions.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.receipt_long_outlined, size: 48, color: Color(0xFF94A3B8)),
                            SizedBox(height: 12),
                            Text(
                              'No transactions recorded yet.',
                              style: TextStyle(color: Color(0xFF64748B), fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: rawTransactions.length,
                        itemBuilder: (context, index) {
                          final tx = rawTransactions[index];
                          final gal = (tx['gallons'] as num?)?.toDouble() ?? 0.0;
                          final price = (tx['price_per_gallon'] as num?)?.toDouble() ?? 180.0;
                          final total = gal * price;
                          final status = (tx['status'] ?? 'paid').toString();
                          final isPaid = status == 'paid';
                          final dateRaw = tx['transaction_date'] ?? tx['created_at'];
                          DateTime dateVal = DateTime.now();
                          if (dateRaw != null) {
                            dateVal = DateTime.tryParse(dateRaw.toString()) ?? DateTime.now();
                          }

                          final note = (tx['notes'] ?? '').toString();
                          final isGCash = note.toLowerCase().contains('gcash');
                          final paymentMethod = isGCash ? 'GCash' : 'Cash on Delivery (COD)';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.02),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Top row: Customer Name & Price
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        tx['customer_name'] ?? tx['customer_id']?.toString().substring(0, 8) ?? 'Customer',
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF1E293B)),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      '₱${total.toStringAsFixed(2)}',
                                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF0F172A)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),

                                // Location
                                Row(
                                  children: [
                                    const Icon(Icons.location_on_outlined, size: 14, color: Color(0xFF64748B)),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        tx['address_line'] ?? tx['area'] ?? 'Tungawan, Zamboanga Sibugay',
                                        style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),

                                // Quantity & Water type
                                Text(
                                  'Quantity: ${gal % 1 == 0 ? gal.toInt() : gal.toStringAsFixed(1)} Gal (${tx['water_type'] == 'mineral' ? 'Mineral' : 'Purified Water'})',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                                ),
                                const SizedBox(height: 10),
                                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                const SizedBox(height: 10),

                                // Bottom row: Status badge, Payment Method, and Date
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        // Status Pill (Paid or Credit)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: isPaid ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            isPaid ? 'Paid' : 'Credit',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: isPaid ? const Color(0xFF15803D) : const Color(0xFFB45309),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        // Payment Method Badge
                                        Text(
                                          paymentMethod,
                                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      '${formatLongDate(dateVal)} - ${formatTime12(dateVal)}',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text('New Record', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TransactionRecordScreen()),
          );
        },
      ),
    );
  }
}
