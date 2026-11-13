import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'customer/customer_home_screen.dart';
import 'driver/driver_home_screen.dart';
import 'admin/admin_home_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/logout_confirm.dart';

/// After a successful login, both customer and driver accounts land
/// here first. It looks up the signed-in user's role in the `profiles`
/// table and routes to the matching screen tree - customers never see
/// driver screens and vice versa, even though they went through the
/// exact same login form.
class RoleRouter extends StatefulWidget {
  const RoleRouter({super.key});

  @override
  State<RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends State<RoleRouter> {
  late final Future<String?> _roleFuture;

  @override
  void initState() {
    super.initState();
    _roleFuture = _fetchRole();
  }

  Future<String?> _fetchRole() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return null;

    final response = await Supabase.instance.client
        .from('profiles')
        .select('role')
        .eq('id', userId)
        .single();

    return response['role'] as String?;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _roleFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || snapshot.data == null) {
          // No profile row, or the lookup failed - safest fallback is
          // to sign the user out and send them back to login rather
          // than guess which screen tree they belong on.
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Could not determine your account type.'),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => logoutWithConfirmation(context),
                    child: const Text('Back to login'),
                  ),
                ],
              ),
            ),
          );
        }

        switch (snapshot.data) {
          case 'driver':
            return Theme(data: AppTheme.driverTheme, child: const DriverHomeScreen());
          case 'customer':
            return Theme(data: AppTheme.lightTheme, child: const CustomerHomeScreen());
          case 'admin':
            return Theme(data: AppTheme.adminTheme, child: const AdminHomeScreen());
          default:
            // Unknown role value in the DB - don't silently default
            // to customer, that could expose the wrong screen tree.
            return const Scaffold(
              body: Center(child: Text('Unrecognized account role.')),
            );
        }
      },
    );
  }
}
