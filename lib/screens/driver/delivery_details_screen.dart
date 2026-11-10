import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../constants/pricing.dart';
import '../../services/driver_delivery_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/stop_badge.dart';
import 'delivery_completed_screen.dart';

/// Delivery Details (driver): who, what, where, plus the "Mark as
/// Delivered" action. Marking a delivery done still records the real sale
/// (order type, quantity, price, paid or credit) in the bottom sheet
/// before showing the "Delivery Completed!" screen.
class DeliveryDetailsScreen extends StatefulWidget {
  final DeliveryStop stop;
  final DriverStopsController controller;

  const DeliveryDetailsScreen({super.key, required this.stop, required this.controller});

  @override
  State<DeliveryDetailsScreen> createState() => _DeliveryDetailsScreenState();
}

class _DeliveryDetailsScreenState extends State<DeliveryDetailsScreen> {
  bool _saving = false;

  DeliveryStop get _stop => widget.stop;

  int get _stopIndex {
    final i = widget.controller.stops.indexWhere((s) => s.id == _stop.id);
    return i < 0 ? 0 : i;
  }

  Future<void> _openCompleteDeliveryForm() async {
    final gallonsController = TextEditingController(text: _stop.gallons.toString());
    String waterType = _stop.waterType;
    String orderType = _stop.orderType;
    String outcome = 'paid'; // 'paid' | 'credit'
    final priceController = TextEditingController(text: pricePerGallonFor(waterType).toStringAsFixed(2));

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Complete delivery', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('Enter the actual delivery data below.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                const SizedBox(height: 16),
                const Text('Water type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'purified', label: Text('Purified')),
                    ButtonSegment(value: 'mineral', label: Text('Mineral')),
                  ],
                  selected: {waterType},
                  onSelectionChanged: (v) => setSheetState(() {
                    waterType = v.first;
                    priceController.text = pricePerGallonFor(waterType).toStringAsFixed(2);
                  }),
                ),
                const SizedBox(height: 12),
                const Text('Order type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'refill', label: Text('Refill')),
                    ButtonSegment(value: 'exchange', label: Text('Exchange')),
                  ],
                  selected: {orderType},
                  onSelectionChanged: (v) => setSheetState(() => orderType = v.first),
                ),
                const SizedBox(height: 16),
                const Text('Place', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 4),
                Text(_stop.addressLine),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: gallonsController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Quantity (gallons)'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: priceController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Price/gal (₱)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Delivered - Paid'),
                        selected: outcome == 'paid',
                        selectedColor: AppColors.statusDelivered,
                        labelStyle: TextStyle(color: outcome == 'paid' ? Colors.white : Colors.black87),
                        showCheckmark: false,
                        onSelected: (_) => setSheetState(() => outcome = 'paid'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Delivered - Credit'),
                        selected: outcome == 'credit',
                        selectedColor: AppColors.statusCredit,
                        labelStyle: TextStyle(color: outcome == 'credit' ? Colors.white : Colors.black87),
                        showCheckmark: false,
                        onSelected: (_) => setSheetState(() => outcome = 'credit'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      final gallons = double.tryParse(gallonsController.text) ?? 0;
                      final price = double.tryParse(priceController.text) ?? pricePerGallonFor(waterType);
                      if (gallons <= 0) return;
                      Navigator.pop(sheetContext);
                      await _completeDelivery(
                        gallons: gallons,
                        pricePerGallon: price,
                        waterType: waterType,
                        orderType: orderType,
                        paidInFull: outcome == 'paid',
                      );
                    },
                    child: const Text('Save & Mark Delivered'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Controllers are intentionally not disposed here: the sheet is still
    // animating out when showModalBottomSheet's future completes.
  }

  Future<void> _completeDelivery({
    required double gallons,
    required double pricePerGallon,
    required String waterType,
    required String orderType,
    required bool paidInFull,
  }) async {
    setState(() => _saving = true);
    final result = await widget.controller.completeDelivery(
      stop: _stop,
      gallons: gallons,
      pricePerGallon: pricePerGallon,
      waterType: waterType,
      orderType: orderType,
      paidInFull: paidInFull,
    );
    if (!mounted) return;
    setState(() => _saving = false);

    if (!result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to record: ${result.error}')));
      return;
    }

    if (result.forecastSyncFailed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Delivery saved, but today's forecast total couldn't be updated."),
        ),
      );
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => DeliveryCompletedScreen(
          customerName: _stop.name,
          location: _stop.addressLine,
          gallons: gallons,
          waterType: waterType,
          completedAt: DateTime.now(),
          stop: _stop,
          controller: widget.controller,
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final requested = _stop.requestedAt;
    final phone = _stop.phone;

    return Theme(
      data: AppTheme.driverTheme,
      child: Scaffold(
        backgroundColor: const Color(0xFFFAFBFD),
        appBar: AppBar(title: const Text('Delivery Details')),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _card(
                      child: Row(
                        children: [
                          StopBadge(index: _stopIndex, size: 34),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_stop.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text(_stop.addressLine, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Order Details', style: TextStyle(fontWeight: FontWeight.w700)),
                          _detailRow('Gallons', '${_stop.gallons}'),
                          _detailRow(
                            'Water',
                            '${_stop.waterType == 'mineral' ? 'Mineral' : 'Purified'} - '
                                '${_stop.orderType == 'exchange' ? 'Exchange container' : 'Refill'}',
                          ),
                          if (requested != null) _detailRow('Ordered On', formatLongDate(requested)),
                        ],
                      ),
                    ),
                    if (phone != null)
                      _card(
                        child: InkWell(
                          onTap: () async {
                            await Clipboard.setData(ClipboardData(text: phone));
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Number copied - paste it in your phone app.')),
                            );
                          },
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Customer Contact', style: TextStyle(fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 8),
                                    Text(phone, style: const TextStyle(fontSize: 15)),
                                  ],
                                ),
                              ),
                              const Icon(Icons.phone, color: AppColors.primary),
                            ],
                          ),
                        ),
                      ),
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Notes', style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          Text(
                            _stop.notes ?? 'No delivery notes.',
                            style: TextStyle(
                              fontSize: 14,
                              color: _stop.notes == null ? AppColors.textMuted : AppColors.textDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _openCompleteDeliveryForm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('Mark as Delivered', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
