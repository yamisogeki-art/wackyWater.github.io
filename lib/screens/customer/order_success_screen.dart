import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'order_history_screen.dart';

class OrderSuccessScreen extends StatelessWidget {
  final int gallons;
  final String waterType;
  final double pricePerGallon;
  final double estimatedTotal;
  final String orderId;

  const OrderSuccessScreen({
    super.key,
    required this.gallons,
    required this.waterType,
    required this.pricePerGallon,
    required this.estimatedTotal,
    required this.orderId,
  });

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
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(color: AppColors.successBg, borderRadius: BorderRadius.circular(16)),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: const BoxDecoration(color: AppColors.successGreen, shape: BoxShape.circle),
                            child: const Icon(Icons.check, color: Colors.white, size: 26),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Order Placed Successfully!',
                                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.successText),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Your order has been received.',
                                  style: TextStyle(fontSize: 13, color: Color(0xFF3F7A55)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Text('Order Summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _row('Gallons', '$gallons ${gallons == 1 ? 'gallon' : 'gallons'}'),
                    _row('Water Type', waterType == 'mineral' ? 'Mineral' : 'Purified'),
                    _row('Price per Gallon', '₱${pricePerGallon.toStringAsFixed(2)}'),
                    _row('Total Price', '₱${estimatedTotal.toStringAsFixed(2)}'),
                    _row(
                      'Estimated Delivery',
                      'To be scheduled',
                      note: "(based on your area's route)",
                      isLast: true,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Your final price is confirmed when the order is delivered.',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
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
                  onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const OrderHistoryScreen()),
                  ),
                  child: const Text('VIEW ORDER HISTORY', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {String? note, bool isLast = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: isLast ? null : const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 15, color: AppColors.textMuted)),
          const SizedBox(width: 16),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(value, textAlign: TextAlign.right, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                if (note != null)
                  Text(note, textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
