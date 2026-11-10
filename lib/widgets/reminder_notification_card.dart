import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// In-app version of the "Reminder Notification" mockup: shown on the
/// customer home screen when the estimated next-order date is close.
/// (This is an on-screen card, not an OS push notification.)
class ReminderNotificationCard extends StatelessWidget {
  final int gallons;
  final int daysUntil;
  final VoidCallback onTap;

  const ReminderNotificationCard({
    super.key,
    required this.gallons,
    required this.daysUntil,
    required this.onTap,
  });

  String get _message {
    final String when;
    if (daysUntil < 0) {
      when = 'now - you may already be running low';
    } else if (daysUntil == 0) {
      when = 'today';
    } else {
      when = 'within $daysUntil ${daysUntil == 1 ? 'day' : 'days'}';
    }
    return 'Your water supply may run low soon. We predict you will need '
        '$gallons ${gallons == 1 ? 'gallon' : 'gallons'} $when. Order now?';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 0,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.water_drop, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Text('Wacky Water', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const Spacer(),
                  const Text('now', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 10),
              const Text('Reminder', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 2),
              Text(_message, style: const TextStyle(fontSize: 14, height: 1.35)),
            ],
          ),
        ),
      ),
    );
  }
}
