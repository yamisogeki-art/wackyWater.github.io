import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../utils/format.dart';
import 'household_info_screen.dart';
import 'order_water_screen.dart';

class PredictionResultScreen extends StatelessWidget {
  final DateTime? nextOrderDate;
  final int? recommendedGallons;

  const PredictionResultScreen({
    super.key,
    required this.nextOrderDate,
    required this.recommendedGallons,
  });

  @override
  Widget build(BuildContext context) {
    final hasEstimate = nextOrderDate != null && recommendedGallons != null;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Prediction Result')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
          child: hasEstimate ? _buildResult(context) : _buildNoData(context),
        ),
      ),
    );
  }

  Widget _buildNoData(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(color: Colors.orange[50], shape: BoxShape.circle),
          child: const Icon(Icons.info_outline, size: 50, color: Colors.orange),
        ),
        const SizedBox(height: 28),
        const Text(
          'Save your household information first',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text(
          "We need your usual order frequency and gallons per order "
          "to predict when you'll need your next delivery.",
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textMuted),
        ),
        const SizedBox(height: 28),
        ElevatedButton(
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const HouseholdInfoScreen()),
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('ADD HOUSEHOLD INFO', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _buildResult(BuildContext context) {
    final days = _daysUntil(nextOrderDate!);
    return Column(
      children: [
        const Spacer(),
        Container(
          width: 110,
          height: 110,
          decoration: const BoxDecoration(color: Color(0xFFEEF1F6), shape: BoxShape.circle),
          child: const Icon(Icons.calendar_month, size: 54, color: AppColors.primary),
        ),
        const SizedBox(height: 26),
        const Text(
          'Your next order is predicted on',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: AppColors.textMuted),
        ),
        const SizedBox(height: 10),
        Text(
          formatLongDate(nextOrderDate!),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
        ),
        Text(
          _relativeLabel(days),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, color: AppColors.successGreen, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 32),
        const Text(
          'Recommended Quantity',
          style: TextStyle(fontSize: 15, color: AppColors.primary, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          '$recommendedGallons ${recommendedGallons == 1 ? 'gallon' : 'gallons'}',
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 32),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.panelGray, borderRadius: BorderRadius.circular(12)),
          child: const Text(
            'This prediction is based on your past order history and usage pattern.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.4),
          ),
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const OrderWaterScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('ORDER NOW', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  int _daysUntil(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(date.year, date.month, date.day).difference(today).inDays;
  }

  String _relativeLabel(int days) {
    if (days < 0) return '(overdue)';
    if (days == 0) return '(today)';
    if (days == 1) return '(tomorrow)';
    return '(In $days days)';
  }
}
