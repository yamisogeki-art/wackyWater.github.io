import 'package:supabase_flutter/supabase_flutter.dart';

class OrderEstimate {
  final DateTime nextOrderDate;
  final int gallons;
  const OrderEstimate({required this.nextOrderDate, required this.gallons});

  /// Whole calendar days from today to [nextOrderDate] (negative = overdue).
  int get daysUntil {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(nextOrderDate.year, nextOrderDate.month, nextOrderDate.day);
    return target.difference(today).inDays;
  }
}

/// Per-customer "next order" estimate.
///
/// next order date = last order date + the customer's usual order
/// frequency (or today + frequency if they haven't ordered yet), and the
/// suggested quantity is their usual gallons per order. This is a simple,
/// transparent heuristic computed from the customer's own saved data -
/// the LightGBM/XGBoost model in wackysmart_forecast/ predicts aggregate
/// daily demand for the station, not per-customer dates.
///
/// Returns null if the customer hasn't saved household info yet (or the
/// lookup fails).
class OrderEstimateService {
  static Future<OrderEstimate?> compute() async {
    final customerId = Supabase.instance.client.auth.currentUser?.id;
    if (customerId == null) return null;

    try {
      final household = await Supabase.instance.client
          .from('customer_household_info')
          .select('order_frequency_days, usual_gallons_per_order')
          .eq('customer_id', customerId)
          .maybeSingle();

      if (household == null) return null;

      final frequencyDays = household['order_frequency_days'] as int;
      final gallons = household['usual_gallons_per_order'] as int;

      final lastOrder = await Supabase.instance.client
          .from('delivery_requests')
          .select('requested_at')
          .eq('customer_id', customerId)
          .order('requested_at', ascending: false)
          .limit(1)
          .maybeSingle();

      final baseDate = lastOrder != null
          ? DateTime.parse(lastOrder['requested_at'] as String).toLocal()
          : DateTime.now();

      return OrderEstimate(
        nextOrderDate: baseDate.add(Duration(days: frequencyDays)),
        gallons: gallons,
      );
    } catch (_) {
      return null;
    }
  }
}
