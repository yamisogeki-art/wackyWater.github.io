import 'package:supabase_flutter/supabase_flutter.dart';

/// The delivery fee is charged per gallon and kept in one place in the database
/// (table app_settings, key delivery_fee_per_gallon). The admin can change it
/// from the dashboard menu; the server adds it to every delivered order.
class DeliveryFeeService {
  DeliveryFeeService._();

  static const _key = 'delivery_fee_per_gallon';
  static double? _cached;

  /// Current fee in pesos per gallon (0 if it cannot be loaded).
  static Future<double> fetch({bool refresh = false}) async {
    if (!refresh && _cached != null) return _cached!;
    try {
      final row = await Supabase.instance.client
          .from('app_settings')
          .select('value')
          .eq('key', _key)
          .maybeSingle();
      final v = (row?['value'] as num?)?.toDouble();
      if (v != null) {
        _cached = v;
        return v;
      }
    } catch (_) {}
    return _cached ?? 0;
  }

  /// Admin only.
  static Future<void> save(double pesosPerGallon) async {
    await Supabase.instance.client.from('app_settings').upsert({
      'key': _key,
      'value': pesosPerGallon,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    _cached = pesosPerGallon;
  }
}
