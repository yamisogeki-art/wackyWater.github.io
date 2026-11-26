import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_announcements_screen.dart';

/// Admin: emergency reports sent by drivers. Acknowledge, resolve,
/// and tell customers about the problem with one tap.
class AdminEmergencyReportsScreen extends StatefulWidget {
  const AdminEmergencyReportsScreen({super.key});

  @override
  State<AdminEmergencyReportsScreen> createState() => _AdminEmergencyReportsScreenState();
}

class _AdminEmergencyReportsScreenState extends State<AdminEmergencyReportsScreen> {
  static const _labels = {
    'vehicle_breakdown': 'Vehicle breakdown',
    'accident': 'Accident',
    'road_blocked': 'Road blocked / flooded',
    'bad_weather': 'Bad weather',
    'customer_unreachable': 'Customer unreachable',
    'safety': 'Safety concern',
    'other': 'Other',
  };

  late final Stream<List<Map<String, dynamic>>> _stream;
  Map<String, String> _driverNames = {};

  @override
  void initState() {
    super.initState();
    _stream = Supabase.instance.client
        .from('emergency_reports')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);
    _loadDrivers();
  }

  Future<void> _loadDrivers() async {
    try {
      final rows = await Supabase.instance.client
          .from('profiles')
          .select('id, full_name')
          .eq('role', 'driver');
      if (!mounted) return;
      setState(() {
        _driverNames = {
          for (final r in List<Map<String, dynamic>>.from(rows))
            r['id'] as String: ((r['full_name'] as String?)?.trim().isNotEmpty ?? false)
                ? (r['full_name'] as String).trim()
                : 'Driver',
        };
      });
    } catch (_) {}
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  Future<void> _setStatus(dynamic id, String status, {String? note}) async {
    try {
      await Supabase.instance.client.from('emergency_reports').update({
        'status': status,
        if (status == 'resolved') 'resolved_at': DateTime.now().toUtc().toIso8601String(),
        if (note != null && note.isNotEmpty) 'admin_note': note,
      }).eq('id', id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update: $e')));
      }
    }
  }

  Future<void> _resolve(dynamic id) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Mark as resolved'),
        content: TextField(
          controller: controller,
          maxLines: 2,
          decoration: const InputDecoration(hintText: 'Note (optional): what was done?', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Resolve')),
        ],
      ),
    );
    final note = controller.text.trim();
    controller.dispose();
    if (ok == true) await _setStatus(id, 'resolved', note: note);
  }

  void _notifyCustomers(Map<String, dynamic> r) {
    final category = r['category'] as String? ?? 'other';
    final kind = (category == 'accident' || category == 'safety') ? 'emergency' : 'delay';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminAnnouncementsScreen(
          prefillKind: kind,
          sourceReportId: r['id'] as int?,
        ),
      ),
    );
  }

  Widget _card(Map<String, dynamic> r) {
    final status = r['status'] as String? ?? 'open';
    final category = r['category'] as String? ?? 'other';
    final created = DateTime.tryParse('${r['created_at']}')?.toLocal();
    final lat = (r['latitude'] as num?)?.toDouble();
    final lng = (r['longitude'] as num?)?.toDouble();
    final driver = _driverNames[r['driver_id']] ?? 'Driver';
    final isOpen = status == 'open';
    final color = status == 'resolved'
        ? Colors.green
        : (isOpen ? Colors.red : Colors.orange);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_labels[category] ?? 'Emergency',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                  child: Text(status.toUpperCase(),
                      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('$driver${created == null ? '' : '  -  ${_ago(created)}'}',
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 8),
            Text('${r['message']}'),
            if (r['delivery_request_id'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Order #${r['delivery_request_id']}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ),
            if (lat != null && lng != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Location: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ),
            if ((r['admin_note'] as String?)?.isNotEmpty ?? false)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Admin note: ${r['admin_note']}',
                    style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
              ),
            if (status != 'resolved') ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (isOpen)
                    OutlinedButton(onPressed: () => _setStatus(r['id'], 'acknowledged'), child: const Text('Acknowledge')),
                  FilledButton(onPressed: () => _resolve(r['id']), child: const Text('Resolve')),
                  FilledButton.tonalIcon(
                    onPressed: () => _notifyCustomers(r),
                    icon: const Icon(Icons.campaign_outlined, size: 18),
                    label: const Text('Notify customers'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _list(List<Map<String, dynamic>> items, String empty) {
    if (items.isEmpty) {
      return Center(child: Text(empty, style: const TextStyle(color: Colors.black54)));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [for (final r in items) _card(r)],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Emergency reports'),
          bottom: const TabBar(tabs: [Tab(text: 'Active'), Tab(text: 'Resolved')]),
        ),
        body: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _stream,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text("Couldn't load reports: ${snap.error}"));
            }
            final all = snap.data ?? [];
            final active = all.where((r) => r['status'] != 'resolved').toList();
            final resolved = all.where((r) => r['status'] == 'resolved').toList();
            return TabBarView(children: [
              _list(active, 'No active emergency reports.'),
              _list(resolved, 'Nothing resolved yet.'),
            ]);
          },
        ),
      ),
    );
  }
}
