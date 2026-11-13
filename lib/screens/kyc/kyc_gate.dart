import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_colors.dart';
import 'kyc_submit_screen.dart';

/// Set to false to let everyone order without verification (e.g. while
/// testing, or while existing customers are being verified).
const bool kRequireKyc = true;

/// Shows [child] only when the signed-in customer's KYC is approved.
/// Otherwise shows the matching status: not submitted, in review, or rejected.
class KycGate extends StatefulWidget {
  final Widget child;
  const KycGate({super.key, required this.child});

  @override
  State<KycGate> createState() => _KycGateState();
}

class _KycGateState extends State<KycGate> {
  late Future<Map<String, dynamic>?> _future = _load();

  Future<Map<String, dynamic>?> _load() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return null;
    return Supabase.instance.client
        .from('kyc_submissions')
        .select('status, review_note')
        .eq('user_id', uid)
        .maybeSingle();
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _openSubmit() async {
    final done = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const KycSubmitScreen()),
    );
    if (done == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    if (!kRequireKyc) return widget.child;

    return FutureBuilder<Map<String, dynamic>?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return _view(
            icon: Icons.error_outline,
            color: Colors.red,
            title: "Couldn't check your verification",
            text: 'Check your connection and try again.',
            button: 'Try again',
            onPressed: _reload,
          );
        }

        final row = snap.data;
        final status = row?['status'] as String?;

        if (status == 'approved') return widget.child;

        if (status == 'pending') {
          return _view(
            icon: Icons.hourglass_top,
            color: Colors.orange,
            title: 'Verification in review',
            text: "We're checking your ID and photos. You'll be able to order once you're approved.",
            button: 'Check again',
            onPressed: _reload,
          );
        }

        if (status == 'rejected') {
          final note = (row?['review_note'] as String?)?.trim();
          return _view(
            icon: Icons.cancel_outlined,
            color: Colors.red,
            title: 'Verification not approved',
            text: (note == null || note.isEmpty)
                ? 'We could not match your photos to your ID. Please try again with clearer photos.'
                : note,
            button: 'Submit again',
            onPressed: _openSubmit,
          );
        }

        return _view(
          icon: Icons.verified_user_outlined,
          color: AppColors.primary,
          title: 'Verify your identity',
          text: 'To order water, please verify your account with a valid ID and a quick selfie.',
          button: 'Start verification',
          onPressed: _openSubmit,
        );
      },
    );
  }

  Widget _view({
    required IconData icon,
    required Color color,
    required String title,
    required String text,
    required String button,
    required VoidCallback onPressed,
  }) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Order Water')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Icon(icon, size: 50, color: color),
              ),
              const SizedBox(height: 24),
              Text(title, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text(text, textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textMuted, height: 1.4)),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: onPressed,
                  child: Text(button, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}