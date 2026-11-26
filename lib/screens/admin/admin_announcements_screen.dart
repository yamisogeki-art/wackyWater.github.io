import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin: write announcements that every customer sees in the app
/// (delays, no delivery today, emergencies, general notices).
class AdminAnnouncementsScreen extends StatefulWidget {
  /// Opens the form right away with this kind selected (used from an emergency report).
  final String? prefillKind;
  final int? sourceReportId;
  const AdminAnnouncementsScreen({super.key, this.prefillKind, this.sourceReportId});

  @override
  State<AdminAnnouncementsScreen> createState() => _AdminAnnouncementsScreenState();
}

class _AdminAnnouncementsScreenState extends State<AdminAnnouncementsScreen> {
  late final Stream<List<Map<String, dynamic>>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = Supabase.instance.client
        .from('announcements')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);
    if (widget.prefillKind != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openForm(kind: widget.prefillKind);
      });
    }
  }

  Future<void> _openForm({String? kind}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AnnouncementForm(initialKind: kind ?? 'delay', sourceReportId: widget.sourceReportId),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Announcement published. Customers can see it now.')),
      );
    }
  }

  Future<void> _remove(Map<String, dynamic> a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove announcement?'),
        content: const Text('Customers will no longer see it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    await Supabase.instance.client.from('announcements').update({'is_active': false}).eq('id', a['id']);
  }

  bool _isLive(Map<String, dynamic> a) {
    if (a['is_active'] != true) return false;
    final exp = DateTime.tryParse('${a['expires_at'] ?? ''}');
    return exp == null || exp.isAfter(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: const Text('Announcements')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.campaign_outlined),
        label: const Text('New announcement'),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No announcements yet. Tap "New announcement" to tell customers about a delay or no delivery.',
                    textAlign: TextAlign.center),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final a = items[i];
              final live = _isLive(a);
              final style = announcementStyle('${a['kind']}');
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(style.icon, color: style.color),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('${a['title']}',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: (live ? Colors.green : Colors.grey).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(live ? 'LIVE' : 'ENDED',
                                style: TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w800, color: live ? Colors.green : Colors.grey)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('${a['message']}'),
                      if (live) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => _remove(a),
                            icon: const Icon(Icons.visibility_off_outlined, size: 18),
                            label: const Text('Remove'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Colours and icons shared by the admin list and the customer banner.
({Color color, IconData icon, String label}) announcementStyle(String kind) {
  switch (kind) {
    case 'delay':
      return (color: Colors.orange.shade800, icon: Icons.schedule, label: 'Delivery delay');
    case 'no_delivery':
      return (color: Colors.red.shade700, icon: Icons.block, label: 'No delivery');
    case 'emergency':
      return (color: Colors.red.shade700, icon: Icons.warning_amber_rounded, label: 'Emergency');
    default:
      return (color: Colors.blue.shade700, icon: Icons.info_outline, label: 'Notice');
  }
}

class _AnnouncementForm extends StatefulWidget {
  final String initialKind;
  final int? sourceReportId;
  const _AnnouncementForm({required this.initialKind, this.sourceReportId});

  @override
  State<_AnnouncementForm> createState() => _AnnouncementFormState();
}

class _AnnouncementFormState extends State<_AnnouncementForm> {
  static const _templates = {
    'delay': (
      'Delivery delay',
      'Some deliveries may arrive later than usual today. We apologize for the inconvenience and thank you for your patience.'
    ),
    'no_delivery': (
      'No deliveries today',
      'We are unable to deliver today. Your order will be scheduled for the next available delivery day.'
    ),
    'emergency': (
      'Service notice',
      'An emergency is affecting our deliveries. We will update you as soon as we can.'
    ),
    'info': ('Notice', ''),
  };
  static const _durations = {
    'today': 'Until the end of today',
    '24h': 'For 24 hours',
    '3d': 'For 3 days',
    'manual': 'Until I remove it',
  };

  late String _kind = widget.initialKind;
  late final TextEditingController _title =
      TextEditingController(text: _templates[widget.initialKind]?.$1 ?? '');
  late final TextEditingController _message =
      TextEditingController(text: _templates[widget.initialKind]?.$2 ?? '');
  String _duration = 'today';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _message.dispose();
    super.dispose();
  }

  void _pickKind(String kind) {
    setState(() {
      _kind = kind;
      _title.text = _templates[kind]?.$1 ?? '';
      _message.text = _templates[kind]?.$2 ?? '';
    });
  }

  DateTime? _expiry() {
    final now = DateTime.now();
    switch (_duration) {
      case 'today':
        return DateTime(now.year, now.month, now.day, 23, 59, 59);
      case '24h':
        return now.add(const Duration(hours: 24));
      case '3d':
        return now.add(const Duration(days: 3));
      default:
        return null;
    }
  }

  Future<void> _publish() async {
    final title = _title.text.trim();
    final message = _message.text.trim();
    if (title.length < 3 || message.length < 3) {
      setState(() => _error = 'Please enter a title and a message.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.from('announcements').insert({
        'title': title,
        'message': message,
        'kind': _kind,
        'expires_at': _expiry()?.toUtc().toIso8601String(),
        if (widget.sourceReportId != null) 'source_report_id': widget.sourceReportId,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not publish. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('New announcement', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('Every customer will see this in the app.',
                style: TextStyle(color: Colors.black54, fontSize: 12)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final k in const ['delay', 'no_delivery', 'emergency', 'info'])
                  ChoiceChip(
                    label: Text(announcementStyle(k).label),
                    selected: _kind == k,
                    onSelected: (_) => _pickKind(k),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder(), counterText: ''),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _message,
              maxLines: 4,
              maxLength: 600,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Message (reason for the delay, what customers should do)',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _duration,
              decoration: const InputDecoration(labelText: 'Show for', border: OutlineInputBorder()),
              items: [
                for (final e in _durations.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _duration = v ?? _duration),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ),
            const SizedBox(height: 16),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                onPressed: _saving ? null : _publish,
                icon: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.campaign_outlined),
                label: const Text('Publish to customers', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
