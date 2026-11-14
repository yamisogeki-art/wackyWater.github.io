import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_colors.dart';

/// Admin: see all driver accounts and create new ones.
/// Creating a driver calls the `create-driver` Edge Function, which checks
/// that the caller is an admin, creates a confirmed login, and sets the role
/// to "driver".
class AdminDriversScreen extends StatefulWidget {
  const AdminDriversScreen({super.key});

  @override
  State<AdminDriversScreen> createState() => _AdminDriversScreenState();
}

class _AdminDriversScreenState extends State<AdminDriversScreen> {
  late Future<List<Map<String, dynamic>>> _drivers = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await Supabase.instance.client
        .from('profiles')
        .select('id, full_name, phone')
        .eq('role', 'driver')
        .order('full_name');
    return List<Map<String, dynamic>>.from(rows);
  }

  void _reload() => setState(() => _drivers = _load());

  Future<void> _openCreate() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _CreateDriverSheet(),
    );
    if (created == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Drivers'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _reload)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add driver'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _drivers,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text("Couldn't load drivers: ${snap.error}"));
          }
          final drivers = snap.data ?? [];
          if (drivers.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No driver accounts yet. Tap "Add driver" to create one.',
                    textAlign: TextAlign.center),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: drivers.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final d = drivers[i];
              final name = (d['full_name'] as String?)?.trim();
              final phone = d['phone'] as String?;
              final shown = (name == null || name.isEmpty) ? 'Driver' : name;
              return Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFE0F2FE),
                    child: Text(shown[0].toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                  ),
                  title: Text(shown, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(phone == null || phone.isEmpty ? 'No phone number' : phone),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _CreateDriverSheet extends StatefulWidget {
  const _CreateDriverSheet();

  @override
  State<_CreateDriverSheet> createState() => _CreateDriverSheetState();
}

class _CreateDriverSheetState extends State<_CreateDriverSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _hide = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client.functions.invoke('create-driver', body: {
        'full_name': _name.text.trim(),
        'email': _email.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'password': _password.text,
      });
      if (res.status >= 200 && res.status < 300) {
        if (!mounted) return;
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Driver account created for ${_email.text.trim()}. Share the password with the driver.')),
        );
      } else {
        setState(() => _error = _messageFrom(res.data));
      }
    } on FunctionException catch (e) {
      setState(() => _error = _messageFrom(e.details));
    } catch (e) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _messageFrom(dynamic data) {
    if (data is Map && data['error'] != null) return data['error'].toString();
    if (data is String && data.isNotEmpty) return data;
    return 'Could not create the driver account.';
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
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('New driver account',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text('The driver can log in right away with this email and password.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Full name', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter the driver\'s name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email address', border: OutlineInputBorder()),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return 'Enter an email address';
                  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)) return 'Enter a valid email address';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    labelText: 'Phone number (optional)', hintText: '09171234567', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: _hide,
                decoration: InputDecoration(
                  labelText: 'Password (at least 6 characters)',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_hide ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _hide = !_hide),
                  ),
                ),
                validator: (v) => (v == null || v.length < 6) ? 'At least 6 characters' : null,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w500)),
                ),
              const SizedBox(height: 16),
              SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Create driver account', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}