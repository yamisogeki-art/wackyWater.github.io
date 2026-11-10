import 'package:flutter/material.dart';
import '../../services/driver_delivery_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import 'transaction_record_screen.dart';

class DeliveryCompletedScreen extends StatelessWidget {
  final String customerName;
  final String location;
  final double gallons;
  final String waterType;
  final DateTime completedAt;
  final DeliveryStop? stop;
  final DriverStopsController? controller;

  const DeliveryCompletedScreen({
    super.key,
    required this.customerName,
    this.location = 'Main St, Cagayan de Oro',
    required this.gallons,
    this.waterType = 'purified',
    required this.completedAt,
    this.stop,
    this.controller,
  });

  String get _itemsLabel {
    final qty = gallons % 1 == 0 ? gallons.toInt().toString() : gallons.toStringAsFixed(1);
    final typeStr = waterType == 'mineral' ? 'Mineral Water' : 'Purified Water';
    return '${qty}x 5-Gal $typeStr';
  }

  @override
  Widget build(BuildContext context) {
    final completionTimeStr = formatTime12(completedAt);

    return Theme(
      data: AppTheme.driverTheme,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              // Top Bright Green Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'DELIVERY COMPLETE!',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 1.0,
                  ),
                ),
              ),

              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 20),
                  child: Column(
                    children: [
                      const Spacer(),

                      // Large checkmark badge
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFECFDF5),
                          border: Border.all(color: const Color(0xFF10B981), width: 5),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF10B981).withValues(alpha: 0.2),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.check_rounded, size: 72, color: Color(0xFF10B981)),
                      ),
                      const SizedBox(height: 32),

                      // Summary Details Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.location_on, color: AppColors.primary, size: 22),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Delivered to:',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '$customerName, $location, CDO',
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 14),
                              child: Divider(height: 1, color: Color(0xFFE2E8F0)),
                            ),
                            Row(
                              children: [
                                const Icon(Icons.water_drop, color: AppColors.primary, size: 22),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Items:',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _itemsLabel,
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 14),
                              child: Divider(height: 1, color: Color(0xFFE2E8F0)),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDCFCE7),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.verified, size: 16, color: Color(0xFF16A34A)),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Status: DELIVERED (at $completionTimeStr)',
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF15803D),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const Spacer(),

                      // Action Button: CONFIRM TRANSACTION
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TransactionRecordScreen(
                                  stop: stop,
                                  controller: controller,
                                  customerName: customerName,
                                  location: location,
                                  initialGallons: gallons,
                                  initialWaterType: waterType,
                                ),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            elevation: 2,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text(
                            'CONFIRM TRANSACTION',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
