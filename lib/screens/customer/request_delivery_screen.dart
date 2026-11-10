import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../constants/pricing.dart';
import '../../utils/validators.dart';

class RequestDeliveryScreen extends StatefulWidget {
  const RequestDeliveryScreen({super.key});

  @override
  State<RequestDeliveryScreen> createState() => _RequestDeliveryScreenState();
}

class _RequestDeliveryScreenState extends State<RequestDeliveryScreen> {
  late final Stream<List<Map<String, dynamic>>> _addressesStream;
  final _gallonsController = TextEditingController(text: '5');
  String? _selectedAddressId;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final customerId = Supabase.instance.client.auth.currentUser?.id;
    _addressesStream = Supabase.instance.client
        .from('customer_addresses')
        .stream(primaryKey: ['id'])
        .eq('customer_id', customerId as Object)
        .order('created_at');
  }

  @override
  void dispose() {
    _gallonsController.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    if (_selectedAddressId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a delivery location first.')),
      );
      return;
    }
    final gallonError = validateGallonInput(_gallonsController.text);
    if (gallonError != null) {
      InputErrorHandler.showErrorSnackBar(context, gallonError);
      return;
    }
    final gallons = int.parse(_gallonsController.text.trim());

    setState(() => _isSubmitting = true);
    final customerId = Supabase.instance.client.auth.currentUser?.id;

    try {
      await Supabase.instance.client.from('delivery_requests').insert({
        'customer_id': customerId,
        'address_id': int.parse(_selectedAddressId!),
        'gallons_requested': gallons,
        'status': 'pending',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Delivery request submitted.')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to submit: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request delivery')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _addressesStream,
        builder: (context, snapshot) {
          final addresses = snapshot.data ?? [];

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (addresses.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Save a delivery location first before requesting a delivery.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Deliver to', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...addresses.map((addr) {
                  final id = addr['id'].toString();
                  return RadioListTile<String>(
                    title: Text(addr['label'] ?? 'Unnamed'),
                    subtitle: Text(
                      '${(addr['latitude'] as num).toStringAsFixed(4)}, '
                      '${(addr['longitude'] as num).toStringAsFixed(4)}',
                    ),
                    value: id,
                    groupValue: _selectedAddressId,
                    onChanged: (v) => setState(() => _selectedAddressId = v),
                  );
                }),
                const SizedBox(height: 16),
                TextField(
                  controller: _gallonsController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [InputFormatters.numbersOnly],
                  decoration: const InputDecoration(
                    labelText: 'Gallons requested',
                    hintText: 'Numbers only e.g. 5',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitRequest,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Submit request'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
