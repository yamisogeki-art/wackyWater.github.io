import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'driver_location_service.dart';

/// One assigned delivery: the `delivery_requests` row plus the customer's
/// address (and name/phone when the driver is allowed to read them - see
/// supabase_ui_update.sql).
class DeliveryStop {
  final Map<String, dynamic> request;
  final Map<String, dynamic>? address;
  final Map<String, dynamic>? customer;

  /// Straight-line distance from the driver, set when a GPS fix exists.
  double? distanceMeters;

  DeliveryStop({required this.request, this.address, this.customer});

  dynamic get id => request['id'];
  String get status => (request['status'] as String?) ?? 'assigned';
  int get gallons => (request['gallons_requested'] as num?)?.toInt() ?? 0;
  String get waterType => (request['water_type'] as String?) ?? 'purified';
  String get orderType => (request['order_type'] as String?) ?? 'refill';

  String? get notes {
    final n = (request['notes'] as String?)?.trim();
    return (n == null || n.isEmpty) ? null : n;
  }

  String? get phone {
    final p = (customer?['phone'] as String?)?.trim();
    return (p == null || p.isEmpty) ? null : p;
  }

  String get name {
    final n = (customer?['full_name'] as String?)?.trim();
    if (n != null && n.isNotEmpty) return n;
    final label = address?['label'];
    if (label is String && label.isNotEmpty) return label;
    return 'Customer';
  }

  String get addressLine {
    final parts = <String>[];
    final label = address?['label'];
    final area = address?['area'];
    if (label is String && label.isNotEmpty) parts.add(label);
    if (area is String && area.isNotEmpty) parts.add(area);
    return parts.isEmpty ? 'No address on file' : parts.join(', ');
  }

  LatLng? get latLng {
    final lat = address?['latitude'];
    final lng = address?['longitude'];
    if (lat is num && lng is num) return LatLng(lat.toDouble(), lng.toDouble());
    return null;
  }

  DateTime? get requestedAt {
    final v = request['requested_at'];
    return v is String ? DateTime.tryParse(v)?.toLocal() : null;
  }

  String get distanceLabel {
    final m = distanceMeters;
    if (m == null) return '';
    if (m < 1000) return '${(m / 10).round() * 10} m away';
    return '${(m / 1000).toStringAsFixed(1)} km away';
  }
}

class CompletionResult {
  final bool ok;
  final String? error;

  /// The delivery itself was saved, but adding the gallons to the daily
  /// forecast total failed (usually a permissions issue on
  /// `upsert_daily_gallons`).
  final bool forecastSyncFailed;

  const CompletionResult({required this.ok, this.error, this.forecastSyncFailed = false});
}

/// Live list of the signed-in driver's active stops, shared by the
/// dashboard, the map, navigation and delivery-details screens so they
/// all agree (and only fetch addresses/customers once).
class DriverStopsController extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;

  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  final Map<dynamic, Map<String, dynamic>> _addresses = {};
  final Map<String, Map<String, dynamic>> _customers = {};
  final Set<String> _customerLookupDone = {};
  final Set<dynamic> _sessionCompleted = {};
  List<Map<String, dynamic>> _rows = [];
  bool _disposed = false;

  bool loading = true;
  Position? position;

  /// Active (not yet delivered) stops, nearest first once a GPS fix exists.
  List<DeliveryStop> stops = [];

  /// Deliveries this driver finished today.
  int completedToday = 0;

  int get totalStops => stops.length + completedToday;

  void start() {
    final driverId = _client.auth.currentUser?.id;
    if (driverId == null) {
      loading = false;
      _notify();
      return;
    }
    _sub = _client
        .from('delivery_requests')
        .stream(primaryKey: ['id'])
        .eq('driver_id', driverId)
        .order('requested_at')
        .listen(_onRows, onError: (Object e) {
      debugPrint('Driver stops stream error: $e');
      loading = false;
      _notify();
    });
    refreshPosition();
  }

  Future<void> _onRows(List<Map<String, dynamic>> rows) async {
    _rows = rows;
    await _loadMissing(rows.where((r) => r['status'] != 'delivered').toList());
    _rebuild();
    loading = false;
    _notify();
  }

  /// `.stream()` only returns raw columns - no embedded joins - so
  /// addresses and customers are fetched separately and merged by id.
  Future<void> _loadMissing(List<Map<String, dynamic>> active) async {
    final missingAddresses = active
        .map((r) => r['address_id'])
        .where((id) => id != null && !_addresses.containsKey(id))
        .toSet()
        .toList();
    if (missingAddresses.isNotEmpty) {
      try {
        final rows = await _client
            .from('customer_addresses')
            .select('id, label, area, latitude, longitude')
            .inFilter('id', missingAddresses);
        for (final row in List<Map<String, dynamic>>.from(rows)) {
          _addresses[row['id']] = row;
        }
      } catch (e) {
        debugPrint('Could not load addresses: $e');
      }
    }

    final missingCustomers = active
        .map((r) => r['customer_id'])
        .whereType<String>()
        .where((id) => !_customerLookupDone.contains(id))
        .toSet()
        .toList();
    if (missingCustomers.isNotEmpty) {
      _customerLookupDone.addAll(missingCustomers);
      List<dynamic> rows = const [];
      try {
        rows = await _client.from('profiles').select('id, full_name, phone').inFilter('id', missingCustomers);
      } catch (_) {
        // `phone` column may not exist yet, or the driver-read policy isn't
        // installed - fall back to whatever we're allowed to read.
        try {
          rows = await _client.from('profiles').select('id, full_name').inFilter('id', missingCustomers);
        } catch (e) {
          debugPrint('Could not load customer names: $e');
        }
      }
      for (final row in rows) {
        final m = Map<String, dynamic>.from(row as Map);
        _customers[m['id'] as String] = m;
      }
    }
  }

  void _rebuild() {
    final active = _rows
        .where((r) => r['status'] != 'delivered')
        .map((r) => DeliveryStop(
              request: r,
              address: _addresses[r['address_id']],
              customer: _customers[r['customer_id']],
            ))
        .toList();

    final pos = position;
    if (pos != null) {
      for (final s in active) {
        final p = s.latLng;
        s.distanceMeters = p == null
            ? null
            : Geolocator.distanceBetween(pos.latitude, pos.longitude, p.latitude, p.longitude);
      }
      active.sort((a, b) => (a.distanceMeters ?? double.infinity).compareTo(b.distanceMeters ?? double.infinity));
    }
    stops = active;

    completedToday = _rows
        .where((r) =>
            r['status'] == 'delivered' && (_sessionCompleted.contains(r['id']) || _isToday(r['delivered_at'])))
        .length;
  }

  bool _isToday(dynamic value) {
    if (value is! String) return false;
    final d = DateTime.tryParse(value)?.toLocal();
    if (d == null) return false;
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  Future<void> refreshPosition() async {
    final p = await DriverLocationService.currentPosition();
    if (p == null || _disposed) return;
    position = p;
    _rebuild();
    _notify();
  }

  /// assigned -> in_transit (called when the driver starts navigating).
  Future<void> markInTransit(dynamic requestId) async {
    try {
      await _client.from('delivery_requests').update({'status': 'in_transit'}).eq('id', requestId);
    } catch (e) {
      debugPrint('Could not mark in transit: $e');
    }
  }

  /// Completing a stop does three things in one action:
  ///   1. Inserts the sale into `customer_transactions` (paid or credit)
  ///   2. Marks the `delivery_requests` row `delivered`
  ///   3. Syncs the gallons into today's `daily_transactions` aggregate
  ///      via `upsert_daily_gallons`, so the forecast model sees it too
  Future<CompletionResult> completeDelivery({
    required DeliveryStop stop,
    required double gallons,
    required double pricePerGallon,
    required String waterType,
    required String orderType,
    required bool paidInFull,
  }) async {
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    try {
      await _client.from('customer_transactions').insert({
        'customer_id': stop.request['customer_id'],
        'delivery_request_id': stop.id,
        'transaction_date': dateStr,
        'gallons': gallons,
        'price_per_gallon': pricePerGallon,
        'water_type': waterType,
        'amount_paid': paidInFull ? gallons * pricePerGallon : 0,
        'status': paidInFull ? 'paid' : 'unpaid',
      });

      final update = {
        'status': 'delivered',
        'water_type': waterType,
        'order_type': orderType,
      };
      try {
        await _client
            .from('delivery_requests')
            .update({...update, 'delivered_at': now.toUtc().toIso8601String()}).eq('id', stop.id);
      } on PostgrestException {
        // `delivered_at` column not added yet (supabase_ui_update.sql) -
        // still mark the delivery as done.
        await _client.from('delivery_requests').update(update).eq('id', stop.id);
      }
    } catch (e) {
      return CompletionResult(ok: false, error: '$e');
    }

    _sessionCompleted.add(stop.id);
    _rebuild();
    _notify();

    var forecastSyncFailed = false;
    try {
      await _client.rpc('upsert_daily_gallons', params: {'p_date': dateStr, 'p_gallons': gallons});
    } catch (e) {
      debugPrint('upsert_daily_gallons failed: $e');
      forecastSyncFailed = true;
    }

    return CompletionResult(ok: true, forecastSyncFailed: forecastSyncFailed);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }
}
