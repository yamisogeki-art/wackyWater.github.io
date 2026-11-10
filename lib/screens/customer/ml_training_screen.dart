import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/order_estimate_service.dart';
import '../../theme/app_colors.dart';
import 'prediction_result_screen.dart';

/// "LightGBM Model Training" screen from the mockup: a short progress
/// animation, then the prediction result.
///
/// Implementation note: the animation is presentation only. The estimate
/// itself comes from OrderEstimateService (last order date + the
/// customer's saved order frequency); the real LightGBM/XGBoost model in
/// wackysmart_forecast/ forecasts aggregate daily demand for the whole
/// station and isn't run per customer from this screen.
class MlTrainingScreen extends StatefulWidget {
  const MlTrainingScreen({super.key});

  @override
  State<MlTrainingScreen> createState() => _MlTrainingScreenState();
}

class _MlTrainingScreenState extends State<MlTrainingScreen> {
  double _progress = 0.0;
  Timer? _timer;
  late final Future<OrderEstimate?> _estimateFuture;

  @override
  void initState() {
    super.initState();
    _estimateFuture = OrderEstimateService.compute();
    _startProgressAnimation();
  }

  void _startProgressAnimation() {
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _progress = (_progress + 0.04).clamp(0.0, 1.0);
      });
      if (_progress >= 1.0) {
        timer.cancel();
        _goToResult();
      }
    });
  }

  Future<void> _goToResult() async {
    final estimate = await _estimateFuture;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PredictionResultScreen(
          nextOrderDate: estimate?.nextOrderDate,
          recommendedGallons: estimate?.gallons,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('LightGBM Model Training')),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 140,
              height: 140,
              decoration: const BoxDecoration(color: AppColors.primaryLight, shape: BoxShape.circle),
              child: const Icon(Icons.account_tree, size: 68, color: AppColors.primary),
            ),
            const SizedBox(height: 32),
            const Text(
              'Training LightGBM Model...',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Building gradient-boosted decision trees from your order history and usage patterns.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, height: 1.4),
            ),
            const SizedBox(height: 32),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 8,
                backgroundColor: AppColors.primaryLight,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${(_progress * 100).toInt()}%',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primary),
            ),
            const SizedBox(height: 20),
            const Text(
              'This may take a few moments.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
