import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_colors.dart';

/// "Assign Orders" (driver): the driver sees every pending, unassigned
/// order grouped by area, ticks the ones they will take, and assigns them
/// to themselves. Assigned orders become the driver's stops (status
/// `assigned`), so they show up in Active Route. Delivering them still
/// requires the camera proof in DeliveryDetailsScreen.
class DriverAssignOrdersScreen extends StatefulWidget {
  /// Called after a successful assignment so the caller can refresh its
  /// stops controller / switch to the Active Route tab.
  final VoidCallback? onAssigned;
  const DriverAssignOrdersScreen({super.key, this.onAssigned});

  @override
  State<DriverAssignOrdersScreen> createState() => _DriverAssignOrdersScreenState();
}

class _DriverAssignOrdersScreenState extends State<DriverAssignOrdersScreen> {
  static const double _dailyCapGallons = 800;

  bool _loading = true;
  bool _assigning = false;
  String? _error;
  List<Map<String, dynamic>> _orders = [];
  Map<String, String> _names = {};
  final Set<dynamic> _selected = {};

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await _db
          .from('delivery_requests')
          .select('id, customer_id, gallons_requested, water_type, order_type, requested_at, '
          'customer_addresses(area, label)')
          .eq('status', 'pending')
          .isFilter('driver_id', null)
          .order('requested_at');

      // Customer names are a nicety; if RLS hides profiles, fall back to the address label.
      final names = <String, String>{};
      try {
        final profiles = await _db.from('profiles').select('id, full_name').eq('role', 'customer');
        for (final p in List<Map<String, dynamic>>.from(profiles)) {
          final n = (p['full_name'] as String?)?.trim();
          if (n != null && n.isNotEmpty) names[p['id'] as String] = n;
        }
      } catch (_) {}

      if (!mounted) return;
      final orders = List<Map<String, dynamic>>.from(raw);
      setState(() {
        _orders = orders;
        _names = names;
        _selected.removeWhere((id) => !orders.any((o) => o['id'] == id));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Couldn't load orders: $e";
        _loading = false;
      });
    }
  }

  double _gallons(Map<String, dynamic> o) => ((o['gallons_requested'] as num?) ?? 0).toDouble();

  double get _selectedGallons =>
      _orders.where((o) => _selected.contains(o['id'])).fold<double>(0, (s, o) => s + _gallons(o));

  String _areaOf(Map<String, dynamic> o) {
    final a = (o['customer_addresses']?['area'] as String?)?.trim();
    return (a == null || a.isEmpty) ? 'Unassigned area' : a;
  }

  String _nameOf(Map<String, dynamic> o) =>
      _names[o['customer_id']] ?? (o['customer_addresses']?['label'] as String?) ?? 'Customer';

  Future<void> _assign() async {
    final me = _db.auth.currentUser?.id;
    if (me == null || _selected.isEmpty) return;

    if (_selectedGallons > _dailyCapGallons) {
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Over the daily target'),
          content: Text(
            'You selected ${_selectedGallons.toStringAsFixed(0)} gal, above the '
                '${_dailyCapGallons.toStringAsFixed(0)}-gallon daily target. Assign anyway?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Assign anyway')),
          ],
        ),
      );
      if (go != true) return;
    }

    final wanted = _selected.length;
    setState(() => _assigning = true);
    try {
      // Re-check pending + unassigned in the UPDATE itself so two drivers
      // can't claim the same order; the returned rows are the ones we won.
      final won = await _db
          .from('delivery_requests')
          .update({'driver_id': me, 'status': 'assigned'})
          .inFilter('id', _selected.toList())
          .eq('status', 'pending')
          .isFilter('driver_id', null)
          .select('id');

      if (!mounted) return;
      final got = (won as List).length;
      final missed = wanted - got;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(missed == 0
            ? '$got order(s) assigned to you. Open Active Route to start.'
            : '$got assigned. $missed were already taken by someone else.'),
      ));
      _selected.clear();
      if (got > 0) widget.onAssigned?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to assign: $e')));
    } finally {
      if (mounted) setState(() => _assigning = false);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final byArea = <String, List<Map<String, dynamic>>>{};
    for (final o in _orders) {
      byArea.putIfAbsent(_areaOf(o), () => []).add(o);
    }
    final areas = byArea.keys.toList()..sort();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Assign Orders'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          : _orders.isEmpty
          ? const Center(child: Text('No unassigned orders right now.'))
          : RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          children: [
            for (final area in areas) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 6),
                child: Text(
                  '$area (${byArea[area]!.length})',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF475569)),
                ),
              ),
              ...byArea[area]!.map((o) {
                final g = _gallons(o);
                final type = o['water_type'] == 'mineral' ? 'Mineral' : 'Purified';
                final kind = o['order_type'] == 'exchange' ? 'Exchange' : 'Refill';
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: CheckboxListTile(
                    value: _selected.contains(o['id']),
                    onChanged: _assigning
                        ? null
                        : (v) => setState(() => v == true ? _selected.add(o['id']) : _selected.remove(o['id'])),
                    title: Text('${_nameOf(o)} - ${g.toStringAsFixed(0)} gal',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('$type - $kind'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                );
              }),
            ],
          ],
        ),
      ),
      bottomNavigationBar: _orders.isEmpty
          ? null
          : SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)]),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_selected.length} selected - ${_selectedGallons.toStringAsFixed(0)} / ${_dailyCapGallons.toStringAsFixed(0)} gal',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _selectedGallons > _dailyCapGallons ? Colors.red : const Color(0xFF1E293B),
                  ),
                ),
              ),
              FilledButton(
                onPressed: (_selected.isEmpty || _assigning) ? null : _assign,
                child: _assigning
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Assign to me'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}