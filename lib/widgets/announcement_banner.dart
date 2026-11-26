import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/admin/admin_announcements_screen.dart' show announcementStyle;

/// Shows the admin's live announcements (delays, no delivery, emergencies)
/// to customers. Hides itself when there is nothing to show.
class AnnouncementBanner extends StatefulWidget {
  const AnnouncementBanner({super.key});

  @override
  State<AnnouncementBanner> createState() => _AnnouncementBannerState();
}

class _AnnouncementBannerState extends State<AnnouncementBanner> {
  late final Stream<List<Map<String, dynamic>>> _stream;
  final Set<dynamic> _dismissed = {};

  @override
  void initState() {
    super.initState();
    _stream = Supabase.instance.client
        .from('announcements')
        .stream(primaryKey: ['id'])
        .eq('is_active', true)
        .order('created_at', ascending: false);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snap) {
        final now = DateTime.now();
        final live = (snap.data ?? []).where((a) {
          if (_dismissed.contains(a['id'])) return false;
          final exp = DateTime.tryParse('${a['expires_at'] ?? ''}');
          return exp == null || exp.isAfter(now);
        }).take(3).toList();
        if (live.isEmpty) return const SizedBox.shrink();

        return Column(
          children: [
            for (final a in live)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                decoration: BoxDecoration(
                  color: announcementStyle('${a['kind']}').color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: announcementStyle('${a['kind']}').color.withValues(alpha: 0.5)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(announcementStyle('${a['kind']}').icon, color: announcementStyle('${a['kind']}').color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${a['title']}',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: announcementStyle('${a['kind']}').color)),
                          const SizedBox(height: 2),
                          Text('${a['message']}', style: const TextStyle(fontSize: 13, height: 1.35)),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Dismiss',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _dismissed.add(a['id'])),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
