import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin screen that rolls up every unpaid `customer_transactions` row per
/// customer into a running credit (utang) total, lets admin collect a
/// payment against it, and prints/shares a receipt for the customer.
class CustomerCreditScreen extends StatefulWidget {
  const CustomerCreditScreen({super.key});

  @override
  State<CustomerCreditScreen> createState() => _CustomerCreditScreenState();
}

class _CustomerCreditScreenState extends State<CustomerCreditScreen> {
  late final Stream<List<Map<String, dynamic>>> _transactionsStream;
  List<Map<String, dynamic>> _customers = [];

  @override
  void initState() {
    super.initState();
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

  String _nameFor(String customerId) {
    final match = _customers.where((c) => c['id'] == customerId);
    if (match.isEmpty) return customerId.substring(0, 8);
    final name = match.first['full_name'] as String?;
    return (name != null && name.trim().isNotEmpty) ? name : customerId.substring(0, 8);
  }

  double _due(Map<String, dynamic> t) =>
      (t['gallons'] as num).toDouble() * (t['price_per_gallon'] as num).toDouble();

  double _balance(Map<String, dynamic> t) => _due(t) - (t['amount_paid'] as num).toDouble();

  Future<void> _collectPayment(String customerId, List<Map<String, dynamic>> unpaidTx) async {
    final totalBalance = unpaidTx.fold<double>(0, (sum, t) => sum + _balance(t));
    final amountController = TextEditingController(text: totalBalance.toStringAsFixed(2));

    final confirmed = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Collect payment - ${_nameFor(customerId)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Outstanding credit: ₱${totalBalance.toStringAsFixed(2)}'),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount received (₱)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, double.tryParse(amountController.text)),
            child: const Text('Apply payment'),
          ),
        ],
      ),
    );

    if (confirmed == null || confirmed <= 0) return;

    // Apply the payment oldest-first across this customer's unpaid
    // transactions, so a partial payment settles the longest-standing
    // credit before the most recent order.
    final sorted = [...unpaidTx]
      ..sort((a, b) =>
          (a['transaction_date'] as String).compareTo(b['transaction_date'] as String));

    var remaining = confirmed;
    for (final t in sorted) {
      if (remaining <= 0) break;
      final balance = _balance(t);
      final applied = remaining >= balance ? balance : remaining;
      final newPaid = (t['amount_paid'] as num).toDouble() + applied;
      final due = _due(t);
      final newStatus = newPaid >= due ? 'paid' : (newPaid > 0 ? 'partial' : 'unpaid');
      await Supabase.instance.client.from('customer_transactions').update({
        'amount_paid': newPaid,
        'status': newStatus,
      }).eq('id', t['id']);
      remaining -= applied;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Applied ₱${confirmed.toStringAsFixed(2)} payment.')),
      );
    }
  }

  Future<void> _printReceipt(String customerId, List<Map<String, dynamic>> unpaidTx) async {
    final name = _nameFor(customerId);
    final totalBalance = unpaidTx.fold<double>(0, (sum, t) => sum + _balance(t));
    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';

    final sorted = [...unpaidTx]
      ..sort((a, b) =>
          (a['transaction_date'] as String).compareTo(b['transaction_date'] as String));

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
              child: pw.Text(
                'WackySmart Water Refilling',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Center(child: pw.Text('Official Receipt', style: const pw.TextStyle(fontSize: 9))),
            pw.SizedBox(height: 8),
            pw.Text('Customer: $name', style: const pw.TextStyle(fontSize: 9)),
            pw.Text('Date: $dateStr', style: const pw.TextStyle(fontSize: 9)),
            pw.Divider(),
            ...sorted.map((t) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('${t['transaction_date']}  ${t['gallons']} gal',
                          style: const pw.TextStyle(fontSize: 8)),
                      pw.Text('P${_balance(t).toStringAsFixed(2)}',
                          style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                )),
            pw.Divider(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Total credit',
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.Text('P${totalBalance.toStringAsFixed(2)}',
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Center(child: pw.Text('Thank you!', style: const pw.TextStyle(fontSize: 8))),
          ],
        ),
      ),
    );

    // Opens the platform print/share sheet - works for an attached
    // receipt printer or for saving/sharing the PDF if no printer is set up.
    await Printing.layoutPdf(onLayout: (format) async => doc.save());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Customer credit')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _transactionsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snapshot.data ?? [];
          final unpaid = all.where((t) => t['status'] != 'paid').toList();

          final byCustomer = <String, List<Map<String, dynamic>>>{};
          for (final t in unpaid) {
            byCustomer.putIfAbsent(t['customer_id'] as String, () => []).add(t);
          }

          final entries = byCustomer.entries.toList()
            ..sort((a, b) {
              final balA = a.value.fold<double>(0, (s, t) => s + _balance(t));
              final balB = b.value.fold<double>(0, (s, t) => s + _balance(t));
              return balB.compareTo(balA);
            });

          if (entries.isEmpty) {
            return const Center(child: Text('No outstanding customer credit.'));
          }

          return ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final customerId = entries[index].key;
              final txs = entries[index].value;
              final balance = txs.fold<double>(0, (s, t) => s + _balance(t));

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_nameFor(customerId),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        '${txs.length} unpaid ${txs.length == 1 ? 'delivery' : 'deliveries'} - '
                        'Balance: ₱${balance.toStringAsFixed(2)}',
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _printReceipt(customerId, txs),
                            icon: const Icon(Icons.print_outlined),
                            label: const Text('Receipt'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: () => _collectPayment(customerId, txs),
                            icon: const Icon(Icons.payments_outlined),
                            label: const Text('Collect payment'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
