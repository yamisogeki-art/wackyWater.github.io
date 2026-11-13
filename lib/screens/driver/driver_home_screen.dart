import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/driver_delivery_service.dart';
import '../../services/driver_location_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/stop_badge.dart';
import 'delivery_details_screen.dart';
import 'driver_history_tab.dart';
import 'driver_profile_tab.dart';
import 'driver_route_screen.dart';
import 'driver_transaction_records_tab.dart';
import 'driver_assign_orders_screen.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  int _currentIndex = 0;
  final _locationService = DriverLocationService();
  final _stops = DriverStopsController();
  bool _isOnline = false;
  bool _isToggling = false;

  @override
  void initState() {
    super.initState();
    _stops.start();
  }

  @override
  void dispose() {
    _locationService.stop();
    _stops.dispose();
    super.dispose();
  }

  Future<void> _toggleOnline(bool goOnline) async {
    setState(() => _isToggling = true);

    if (goOnline) {
      final started = await _locationService.start();
      if (!started && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission is required to go online.')),
        );
      }
      if (mounted) {
        setState(() {
          _isOnline = started;
          _isToggling = false;
        });
      }
    } else {
      await _locationService.stop();
      if (mounted) {
        setState(() {
          _isOnline = false;
          _isToggling = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    await _locationService.stop();
    await Supabase.instance.client.auth.signOut();
  }

  Widget _drawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Wacky Water', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primary)),
                  Text('Delivery Driver Portal', style: TextStyle(color: AppColors.textMuted)),
                ],
              ),
            ),
            const Divider(),
            SwitchListTile(
              title: const Text('Go online', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Share live location with admin & customers'),
              value: _isOnline,
              onChanged: _isToggling ? null : _toggleOnline,
            ),
            const Spacer(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
              onTap: _logout,
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String value, String label, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  Widget _statDivider() => const SizedBox(height: 44, child: VerticalDivider(width: 1, color: AppColors.border));

  Widget _onlinePill() {
    final color = _isOnline ? AppColors.successGreen : AppColors.textMuted;
    return GestureDetector(
      onTap: _isToggling ? null : () => _toggleOnline(!_isOnline),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: _isOnline ? AppColors.successBg : AppColors.panelGray,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(_isOnline ? 'Online' : 'Offline', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard() {
    final total = _stops.totalStops;
    final completed = _stops.completedToday;
    final pending = _stops.stops.length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  "Today's Delivery Route Summary",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                ),
              ),
              _onlinePill(),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _stat('$total', 'Total Assigned', AppColors.textDark),
              _statDivider(),
              _stat('$completed', 'Completed', AppColors.successGreen),
              _statDivider(),
              _stat('$pending', 'Pending', AppColors.primary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _deliveriesList() {
    final stops = _stops.stops;
    final now = DateTime.now();
    final dateStr = '${now.month}/${now.day}/${now.year}';

    if (stops.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: const Column(
          children: [
            Icon(Icons.assignment_outlined, size: 48, color: AppColors.textMuted),
            SizedBox(height: 10),
            Text(
              'No active deliveries assigned today.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
            ),
            SizedBox(height: 4),
            Text(
              'When the admin assigns customer orders by barangay, your daily deliveries will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Assigned Deliveries ($dateStr)',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
            ),
            Text(
              '${stops.length} Pending Stops',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2)),
            ],
          ),
          child: Column(
            children: [
              for (var i = 0; i < stops.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: AppColors.border),
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => DeliveryDetailsScreen(stop: stops[i], controller: _stops)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            StopBadge(index: i, size: 32),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    stops[i].name,
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    stops[i].addressLine,
                                    style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: stops[i].status == 'in_transit' ? const Color(0xFFE0F2FE) : const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                stops[i].status == 'in_transit' ? 'IN TRANSIT' : 'ASSIGNED',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: stops[i].status == 'in_transit' ? const Color(0xFF0369A1) : const Color(0xFFB45309),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${stops[i].gallons} Gal · ${stops[i].waterType == 'mineral' ? 'Mineral' : 'Purified'} (${stops[i].orderType == 'exchange' ? 'Exchange' : 'Refill'})',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                            ),
                            if (stops[i].distanceLabel.isNotEmpty)
                              Text(
                                stops[i].distanceLabel,
                                style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _homeDashboard() {
    if (_stops.loading) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      drawer: _drawer(),
      appBar: AppBar(
        title: const Text('Daily Driver Deliveries'),
        actions: [
          AnimatedBuilder(
            animation: _stops,
            builder: (context, _) => IconButton(
              tooltip: 'Assigned Stops',
              icon: Badge(
                isLabelVisible: _stops.stops.isNotEmpty,
                label: Text('${_stops.stops.length}'),
                child: const Icon(Icons.notifications_none),
              ),
              onPressed: () {
                final n = _stops.stops.length;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(n == 0
                        ? 'No pending assigned deliveries today.'
                        : 'You have $n assigned ${n == 1 ? 'delivery' : 'deliveries'} to complete today.'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _stops.refreshPosition,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            _summaryCard(),
            const SizedBox(height: 20),
            _deliveriesList(),
            const SizedBox(height: 20),
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () => setState(() => _currentIndex = 1),
                icon: const Icon(Icons.map_outlined),
                label: const Text('Start Route Navigation', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bodyForTab() {
    switch (_currentIndex) {
      case 0:
        return _homeDashboard();
      case 1:
        return DriverRouteScreen(controller: _stops);
      case 2:
        return const DriverTransactionRecordsTab();
      case 3:
        return const DriverHistoryTab();
      case 4:
        return const DriverProfileTab();
      default:
        return _homeDashboard();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: AnimatedBuilder(
        animation: _stops,
        builder: (context, _) => _bodyForTab(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        backgroundColor: Colors.white,
        elevation: 8,
        indicatorColor: AppColors.primary.withValues(alpha: 0.12),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: AppColors.primary),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.local_shipping_outlined),
            selectedIcon: Icon(Icons.local_shipping, color: AppColors.primary),
            label: 'Active Route',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long, color: AppColors.primary),
            label: 'Sales Record',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history, color: AppColors.primary),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: AppColors.primary),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
