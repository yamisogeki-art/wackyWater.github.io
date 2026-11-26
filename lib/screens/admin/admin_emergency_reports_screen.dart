import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_colors.dart';
import '../../utils/format.dart';

class AdminEmergencyReportsScreen extends StatefulWidget {
  const AdminEmergencyReportsScreen({super.key});

  @override
  State<AdminEmergencyReportsScreen> createState() => _AdminEmergencyReportsScreenState();
}

class _AdminEmergencyReportsScreenState extends State<AdminEmergencyReportsScreen> {
  late final Stream<List<Map<String, dynamic>>> _reportsStream;

  @override
  void initState() {
    super.initState();
    _reportsStream = Supabase.instance.client
        .from('emergency_reports')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);
  }

  Future<void> _updateStatus(dynamic id, String status) async {
    try {
      await Supabase.instance.client
          .from('emergency_reports')
          .update({'status': status})
          .eq('id', id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Report marked as $status.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update status: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Emergency & Incident Reports'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _reportsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final reports = snapshot.data ?? [];

          if (reports.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_outlined, size: 56, color: Color(0xFF10B981)),
                    SizedBox(height: 12),
                    Text(
                      'No emergency reports recorded.',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B)),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Driver breakdown or accident emergency reports will appear here live.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: reports.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final r = reports[i];
              final status = (r['status'] ?? 'open').toString().toLowerCase();
              final isOpen = status == 'open';
              final dateRaw = r['created_at'];
              DateTime dateVal = DateTime.now();
              if (dateRaw != null) {
                dateVal = DateTime.tryParse(dateRaw.toString()) ?? DateTime.now();
              }

              return Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isOpen ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                                color: isOpen ? Colors.amber.shade800 : const Color(0xFF16A34A),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                r['driver_name'] ?? 'Driver Report',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isOpen ? const Color(0xFFFEF3C7) : const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isOpen ? 'OPEN ALERT' : 'RESOLVED',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isOpen ? const Color(0xFFB45309) : const Color(0xFF15803D),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        r['description'] ?? r['notes'] ?? 'Emergency incident report from driver route.',
                        style: const TextStyle(fontSize: 13.5, color: Color(0xFF334155)),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            formatLongDate(dateVal),
                            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                          ),
                          if (isOpen)
                            TextButton.icon(
                              onPressed: () => _updateStatus(r['id'], 'resolved'),
                              icon: const Icon(Icons.check, size: 16),
                              label: const Text('Mark Resolved'),
                            ),
                        ],
                      ),
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
