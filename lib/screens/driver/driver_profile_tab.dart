import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/driver_location_service.dart';
import '../../theme/app_colors.dart';

class DriverProfileTab extends StatefulWidget {
  const DriverProfileTab({super.key});

  @override
  State<DriverProfileTab> createState() => _DriverProfileTabState();
}

class _DriverProfileTabState extends State<DriverProfileTab> {
  final _locationService = DriverLocationService();
  String? _fullName;
  String? _phone;
  bool _isOnline = false;
  bool _isLoading = true;

  String? get _email => Supabase.instance.client.auth.currentUser?.email;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('full_name, phone')
          .eq('id', user.id)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _fullName = row?['full_name'] as String?;
          _phone = row?['phone'] as String?;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleOnline(bool value) async {
    if (value) {
      final ok = await _locationService.start();
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission is required to go online.')),
        );
      }
      if (mounted) setState(() => _isOnline = ok);
    } else {
      await _locationService.stop();
      if (mounted) setState(() => _isOnline = false);
    }
  }

  Future<void> _logout() async {
    await _locationService.stop();
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final driverName = (_fullName != null && _fullName!.trim().isNotEmpty)
        ? _fullName!
        : (_email != null ? _email!.split('@').first : 'Driver');

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Driver Profile'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: const Color(0xFFEFF6FF),
                    child: Text(
                      driverName[0].toUpperCase(),
                      style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: AppColors.primary),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    driverName,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  ),
                  if (_email != null) ...[
                    const SizedBox(height: 2),
                    Text(_email!, style: const TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                  ],
                  const SizedBox(height: 20),

                  // Online status toggle card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _isOnline ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.my_location,
                                color: _isOnline ? const Color(0xFF16A34A) : Colors.grey,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _isOnline ? 'Online & Location Active' : 'Offline',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                ),
                                const Text(
                                  'Share live position with dispatch',
                                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Switch(
                          value: _isOnline,
                          activeTrackColor: const Color(0xFF16A34A),
                          onChanged: _toggleOnline,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Vehicle Info Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.local_shipping_outlined, color: AppColors.primary, size: 24),
                        SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Assigned Vehicle', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                              SizedBox(height: 2),
                              Text('L300 Water Delivery Truck', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Phone number card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.phone_outlined, color: AppColors.primary, size: 24),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Contact Phone', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                              const SizedBox(height: 2),
                              Text(
                                _phone ?? 'No phone set',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Sign Out Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: _logout,
                      icon: const Icon(Icons.logout, color: Colors.red),
                      label: const Text('LOGOUT', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.red)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
