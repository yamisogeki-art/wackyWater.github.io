import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/auth/login_screen.dart';
import 'screens/role_router.dart';
import 'theme/app_theme.dart';

// Supabase project credentials
const String supabaseUrl = 'https://hsrsuuyqqtyqeutcvorp.supabase.co';
const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhzcnN1dXlxcXR5cWV1dGN2b3JwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODgwODQ4NzcsImV4cCI6MjEwMzY2MDg3N30.4S81Zzktm9RTD_HvqWT8LXXdBrtK4Znt3sa60uvLGYc';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  runApp(const WackySmartApp());
}

class WackySmartApp extends StatelessWidget {
  const WackySmartApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wacky Water',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      // AuthGate handles the logic of showing Login or the App Home
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    // Listen to auth changes and rebuild UI (shows login or home automatically)
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;

    if (session == null) {
      return const LoginScreen();
    }

    // Logged in => Route to correct screen based on role (Customer/Admin/Driver)
    return const RoleRouter();
  }
}
