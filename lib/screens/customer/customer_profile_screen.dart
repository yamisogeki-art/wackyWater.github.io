import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_colors.dart';
import '../../utils/validators.dart';
import 'household_info_screen.dart';
import 'saved_locations_screen.dart';
import 'track_order_screen.dart';

/// "Profile" tab from the mockup's bottom navigation: who's signed in,
/// shortcuts to household info / saved locations / order tracking, the
/// contact number drivers see, and logout.
class CustomerProfileScreen extends StatefulWidget {
  const CustomerProfileScreen({super.key});

  @override
  State<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends State<CustomerProfileScreen> {
  String? _fullName;
  String? _phone;
  bool _isLoading = true;

  String? get _email => Supabase.instance.client.auth.currentUser?.email;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _isLoading = false);
      return;
    }
    Map<String, dynamic>? row;
    try {
      row = await Supabase.instance.client.from('profiles').select('full_name, phone').eq('id', userId).single();
    } catch (_) {
      // `phone` column may not exist yet (see supabase_ui_update.sql).
      try {
        row = await Supabase.instance.client.from('profiles').select('full_name').eq('id', userId).single();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _fullName = row?['full_name'] as String?;
      _phone = row?['phone'] as String?;
      _isLoading = false;
    });
  }

  Future<void> _editPhone() async {
    final controller = TextEditingController(text: _phone ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Contact number'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          autofocus: true,
          decoration: const InputDecoration(hintText: '09171234567'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;

    final phoneVal = value.isEmpty ? null : value;

    try {
      await Supabase.instance.client.rpc('set_my_phone', params: {'p_phone': phoneVal});
      if (mounted) {
        setState(() => _phone = phoneVal);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contact number saved successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save contact number: $e')),
        );
      }
    }
  }

  Widget _tile({required IconData icon, required String title, String? subtitle, required VoidCallback onTap}) {
    return Card(
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: AppColors.primary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = (_fullName == null || _fullName!.trim().isEmpty) ? 'Customer' : _fullName!.trim();

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 38,
                    backgroundColor: AppColors.primaryLight,
                    child: Text(
                      name[0].toUpperCase(),
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(child: Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                if (_email != null)
                  Center(child: Text(_email!, style: const TextStyle(color: AppColors.textMuted))),
                const SizedBox(height: 24),
                _tile(
                  icon: Icons.home_work_outlined,
                  title: 'Household Information',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HouseholdInfoScreen())),
                ),
                _tile(
                  icon: Icons.location_on_outlined,
                  title: 'Delivery Locations',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SavedLocationsScreen())),
                ),
                _tile(
                  icon: Icons.pin_drop_outlined,
                  title: 'Track My Order',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrackOrderScreen())),
                ),
                _tile(
                  icon: Icons.phone_outlined,
                  title: 'Contact Number',
                  subtitle: _phone ?? 'Add a number so your driver can reach you',
                  onTap: _editPhone,
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () => Supabase.instance.client.auth.signOut(),
                  icon: const Icon(Icons.logout),
                  label: const Text('LOGOUT'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],
            ),
    );
  }
}
