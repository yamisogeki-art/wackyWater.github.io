import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../widgets/logout_confirm.dart';
import 'admin_announcements_screen.dart';
import 'admin_drivers_screen.dart';
import 'admin_emergency_reports_screen.dart';

const Color _navy = Color(0xFF03223F);
const Color _blue = Color(0xFF1C5FD6);

/// Which admin page is showing. The menu changes it; AdminHomeScreen listens.
class AdminNav {
  static const dashboard = 0;
  static const map = 1;
  static const requests = 2;
  static const schedule = 3;
  static const sales = 4;
  static const forecast = 5;

  static final ValueNotifier<int> tab = ValueNotifier<int>(dashboard);
}

/// The navy slide-out menu shown on every admin page.
/// [selected] is the AdminNav.* page that is currently open.
class AdminDrawer extends StatelessWidget {
  final int selected;
  const AdminDrawer({super.key, required this.selected});

  void _goTab(BuildContext context, int tab) {
    Navigator.pop(context); // close the menu
    AdminNav.tab.value = tab;
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String label, VoidCallback onTap, {bool isSelected = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Material(
            color: isSelected ? _blue : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(children: [
                  Icon(icon, color: Colors.white, size: 21),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(label,
                        style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
            ),
          ),
        );

    Widget tabItem(IconData icon, String label, int tab) =>
        item(icon, label, () => _goTab(context, tab), isSelected: selected == tab);

    return Drawer(
      backgroundColor: _navy,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              child: Row(children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(color: _blue, borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.water_drop, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('WACKY WATER',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, height: 1.1)),
                    Text('DELIVERY & REFILLING',
                        style: TextStyle(color: Color(0xFF9FB6D6), fontSize: 10, letterSpacing: 0.6)),
                  ]),
                ),
              ]),
            ),
            const Divider(color: Color(0xFF12385C), height: 1),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  tabItem(Icons.dashboard_outlined, 'Dashboard', AdminNav.dashboard),
                  tabItem(Icons.show_chart, 'Forecasting', AdminNav.forecast),
                  tabItem(Icons.map_outlined, 'Live Driver Map', AdminNav.map),
                  tabItem(Icons.list_alt_outlined, 'Delivery Requests', AdminNav.requests),
                  tabItem(Icons.route_outlined, 'Delivery Schedule', AdminNav.schedule),
                  tabItem(Icons.receipt_long_outlined, 'Sales / Reports', AdminNav.sales),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    child: Divider(color: Color(0xFF12385C)),
                  ),
                  item(Icons.badge_outlined, 'Drivers', () => _push(context, const AdminDriversScreen())),
                  item(Icons.warning_amber_rounded, 'Emergency Reports',
                      () => _push(context, const AdminEmergencyReportsScreen())),
                  item(Icons.campaign_outlined, 'Announcements',
                      () => _push(context, const AdminAnnouncementsScreen())),
                ],
              ),
            ),
            item(Icons.logout, 'Log out', () async {
              Navigator.pop(context);
              if (await confirmLogout(context)) {
                await Supabase.instance.client.auth.signOut();
              }
            }),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
