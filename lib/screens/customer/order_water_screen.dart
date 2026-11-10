import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../constants/pricing.dart';
import '../../theme/app_colors.dart';
import 'order_success_screen.dart';
import 'saved_locations_screen.dart';

/// Note on pricing: `delivery_requests` has no price column - the final
/// price is confirmed by whoever completes the delivery (driver, or
/// admin via Daily Transactions), since it must exactly match
/// `water_type`. The amount shown here is a customer-facing estimate
/// computed from the fixed rate card in constants/pricing.dart - it is
/// not written to the database, so there's only ever one source of truth
/// for price.
class OrderWaterScreen extends StatefulWidget {
  const OrderWaterScreen({super.key});

  @override
  State<OrderWaterScreen> createState() => _OrderWaterScreenState();
}

class _OrderWaterScreenState extends State<OrderWaterScreen> {
  int _gallons = 1;
  String _waterType = 'purified'; // 'purified' | 'mineral'
  String _orderType = 'refill'; // 'exchange' | 'refill'
  bool _isLoading = false;
  String _addressLabel = 'Select a delivery location';
  dynamic _selectedAddressId;

  double get _pricePerGallon => pricePerGallonFor(_waterType);

  Future<void> _selectAddress() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const SavedLocationsScreen(isPicker: true)),
    );

    if (result != null) {
      setState(() {
        _addressLabel = '${result['label'] ?? 'Unnamed'} (${result['area'] ?? 'No area set'})';
        _selectedAddressId = result['id'];
      });
    }
  }

  Future<void> _placeOrder() async {
    if (_selectedAddressId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a delivery location first.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;

      final response = await Supabase.instance.client.from('delivery_requests').insert({
        'customer_id': userId,
        'address_id': _selectedAddressId,
        'gallons_requested': _gallons,
        'status': 'pending',
        'water_type': _waterType,
        'order_type': _orderType,
      }).select().single();

      if (mounted) {
        // push (not pushReplacement): this screen is also a bottom-nav tab,
        // and replacing a tab's route would replace the whole home screen.
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OrderSuccessScreen(
              gallons: _gallons,
              waterType: _waterType,
              pricePerGallon: _pricePerGallon,
              estimatedTotal: _gallons * _pricePerGallon,
              orderId: response['id'].toString(),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error placing order: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _typeChip({required bool selected, required String label, required VoidCallback onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.panelGray,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _roundButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: const Color(0xFFCFE0FB), width: 1.5),
        ),
        child: Icon(icon, color: AppColors.primary, size: 20),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Order Water')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Water Type', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _typeChip(
                          selected: _waterType == 'mineral',
                          label: 'Mineral (₱${mineralPricePerGallon.toStringAsFixed(0)}/gal)',
                          onTap: () => setState(() => _waterType = 'mineral'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text('Exchange or Refill', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _typeChip(
                          selected: _orderType == 'exchange',
                          label: 'Exchange container',
                          onTap: () => setState(() => _orderType = 'exchange'),
                        ),
                        const SizedBox(width: 8),
                        _typeChip(
                          selected: _orderType == 'refill',
                          label: 'Refill my container',
                          onTap: () => setState(() => _orderType = 'refill'),
                        ),
                      ],
                    ),
                    if (_orderType == 'exchange') ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8)),
                        child: Text(
                          'No hole, or the hole must be covered, when exchanging your gallon container.',
                          style: TextStyle(fontSize: 11, color: Colors.amber.shade900),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    const Text('Order Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 14),
                    const Text('Gallons', style: TextStyle(color: AppColors.textMuted)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _roundButton(Icons.remove, () => setState(() => _gallons = _gallons > 1 ? _gallons - 1 : 1)),
                          Text('$_gallons', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                          _roundButton(Icons.add, () => setState(() => _gallons++)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Price per Gallon', style: TextStyle(fontSize: 16, color: AppColors.textMuted)),
                        Text(
                          '₱${_pricePerGallon.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                      decoration: BoxDecoration(color: AppColors.successBg, borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total Price',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.successText),
                          ),
                          Text(
                            '₱${(_gallons * _pricePerGallon).toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.successText),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Divider(),
                    const SizedBox(height: 12),
                    const Text('Delivery Address', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            _addressLabel,
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.35,
                              color: _selectedAddressId == null ? Colors.red : Colors.black,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _selectAddress,
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: Size.zero),
                          child: const Text('CHANGE', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: SizedBox(
                height: 52,
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isLoading ? null : _placeOrder,
                  child: _isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('PLACE ORDER', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
