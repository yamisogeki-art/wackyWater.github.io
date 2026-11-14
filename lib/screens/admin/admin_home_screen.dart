import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/logout_confirm.dart';
import '../../constants/auth_config.dart';
import '../../services/forecast_service.dart';
import '../../theme/app_colors.dart';
import 'admin_driver_map_screen.dart';
import 'admin_driver_screen.dart';
import 'customer_credit_screen.dart';
import 'daily_transactions_screen.dart';
import 'delivery_requests_screen.dart';
import 'delivery_schedule_screen.dart';
import 'forecast_screen.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      AdminDashboardTab(onNavigateTab: (index) => setState(() => _tabIndex = index)),
      const AdminDriverMapScreen(),
      const DeliveryRequestsScreen(),
      const DeliveryScheduleScreen(),
      const DailyTransactionsScreen(),
      const CustomerCreditScreen(),
      const ForecastScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _tabIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Map'),
          NavigationDestination(icon: Icon(Icons.list_alt_outlined), selectedIcon: Icon(Icons.list_alt), label: 'Requests'),
          NavigationDestination(icon: Icon(Icons.route_outlined), selectedIcon: Icon(Icons.route), label: 'Schedule'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Sales'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'Credit'),
          NavigationDestination(icon: Icon(Icons.show_chart_outlined), selectedIcon: Icon(Icons.show_chart), label: 'Forecast'),
        ],
      ),
    );
  }
}

/// Admin Dashboard tab displaying Demand Forecast summary and Delivery Schedule summary on the home screen.
class AdminDashboardTab extends StatefulWidget {
  final ValueChanged<int> onNavigateTab;
  const AdminDashboardTab({super.key, required this.onNavigateTab});

  @override
  State<AdminDashboardTab> createState() => _AdminDashboardTabState();
}

class _AdminDashboardTabState extends State<AdminDashboardTab> {
  late Future<ForecastResult> _forecastFuture;
  late final Stream<List<Map<String, dynamic>>> _pendingRequestsStream;

  bool _isRefreshingForecast = false;

  @override
  void initState() {
    super.initState();
    _forecastFuture = ForecastService().load();

    _pendingRequestsStream = Supabase.instance.client
        .from('delivery_requests')
        .stream(primaryKey: ['id'])
        .eq('status', 'pending');
  }

  Future<void> _refreshForecast() async {
    setState(() {
      _isRefreshingForecast = true;
    });
    try {
      final updated = await ForecastService().triggerServerForecast();
      if (mounted) {
        setState(() {
          _forecastFuture = Future.value(updated);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _forecastFuture = ForecastService().load();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Server forecast refresh: ${e.toString().replaceFirst('Exception: ', '')}'),
            backgroundColor: Colors.orange.shade800,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingForecast = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Wacky Water Admin', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text('Dashboard & Demand Overview', style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              if (await confirmLogout(context)) {
                await Supabase.instance.client.auth.signOut();
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. DEMAND FORECAST CARD
              _buildForecastCard(),

              const SizedBox(height: 16),

              // 2. TODAY'S DELIVERY SCHEDULE SUMMARY CARD
              _buildDeliveryScheduleCard(),

              const SizedBox(height: 16),

              // 3. QUICK ACCESS GRID
              const Text(
                'Quick Management',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildQuickCard(
                      title: 'Driver Map',
                      subtitle: 'Live GPS locations',
                      icon: Icons.map_outlined,
                      color: const Color(0xFF0284C7),
                      onTap: () => widget.onNavigateTab(1),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildQuickCard(
                      title: 'Requests',
                      subtitle: 'Customer orders',
                      icon: Icons.list_alt_outlined,
                      color: const Color(0xFFD97706),
                      onTap: () => widget.onNavigateTab(2),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildQuickCard(
                      title: 'Transactions',
                      subtitle: 'Recorded sales',
                      icon: Icons.receipt_long_outlined,
                      color: const Color(0xFF16A34A),
                      onTap: () => widget.onNavigateTab(4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildQuickCard(
                      title: 'Credit Wallet',
                      subtitle: 'Customer balances',
                      icon: Icons.account_balance_wallet_outlined,
                      color: const Color(0xFF9333EA),
                      onTap: () => widget.onNavigateTab(5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildQuickCard(
                      title: 'Drivers',
                      subtitle: 'Create driver accounts',
                      icon: Icons.person_add_alt_1_outlined,
                      color: const Color(0xFF0D9488),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AdminDriversScreen()),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(child: SizedBox()),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForecastCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x330284C7), blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: FutureBuilder<ForecastResult>(
        future: _forecastFuture,
        builder: (context, snapshot) {
          final res = snapshot.data;
          final latest = res != null && res.forecast.isNotEmpty ? res.forecast.first : null;
          final predictedGallons = latest?.gallons.round();
          final forecastDate = latest != null
              ? '${latest.date.year}-${latest.date.month.toString().padLeft(2, '0')}-${latest.date.day.toString().padLeft(2, '0')}'
              : 'N/A';
          final modelVer = res?.modelVersion ?? 'LightGBM v1';
          final sevenDayTotal = res != null ? res.forecast.take(7).fold<double>(0.0, (s, p) => s + p.gallons).round() : 0;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.show_chart, color: Colors.white, size: 24),
                      SizedBox(width: 8),
                      Text(
                        'Demand Forecasting',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: _isRefreshingForecast || snapshot.connectionState == ConnectionState.waiting
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                        : const Icon(Icons.refresh, color: Colors.white),
                    onPressed: _isRefreshingForecast ? null : _refreshForecast,
                    tooltip: 'Run server forecast',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    predictedGallons != null ? '$predictedGallons' : '---',
                    style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'gallons predicted',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                latest != null
                    ? 'Target Date: $forecastDate · 7-Day Total: $sevenDayTotal gal · Model: $modelVer'
                    : 'Model: $modelVer · Server: ${resolvedApiBaseUrl.contains('https') ? 'HTTPS Production' : 'Local Dev'}',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
              if (res != null && res.isOfflineCache) ...[
                const SizedBox(height: 6),
                const Text(
                  '⚡ Showing offline cached data',
                  style: TextStyle(color: Color(0xFFFDE68A), fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ],
              if (snapshot.hasError) ...[
                const SizedBox(height: 8),
                Text(
                  'Error loading forecast: ${snapshot.error}',
                  style: const TextStyle(color: Color(0xFFFECACA), fontSize: 12),
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF0369A1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: () => widget.onNavigateTab(6),
                  icon: const Icon(Icons.auto_graph, size: 18),
                  label: const Text('View Detailed Forecast & Analytics', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDeliveryScheduleCard() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _pendingRequestsStream,
      builder: (context, snapshot) {
        final pending = snapshot.data ?? [];
        int totalPendingGallons = 0;
        for (final req in pending) {
          totalPendingGallons += (req['gallons_requested'] as num?)?.toInt() ?? 0;
        }

        final pendingCount = pending.length;
        final targetMetPercent = (totalPendingGallons / 800.0 * 100).clamp(0.0, 100.0);

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [
              BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.route, color: AppColors.primary, size: 24),
                      SizedBox(width: 8),
                      Text(
                        "Today's Delivery Schedule",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2FE),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$pendingCount Orders',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0369A1)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total Scheduled Volume', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                      const SizedBox(height: 2),
                      Text(
                        '$totalPendingGallons Gal',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Daily Capacity (800 gal)', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                      const SizedBox(height: 2),
                      Text(
                        '${targetMetPercent.toStringAsFixed(0)}% Capacity',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF10B981)),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: targetMetPercent / 100.0,
                  minHeight: 8,
                  backgroundColor: const Color(0xFFE2E8F0),
                  color: const Color(0xFF0284C7),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0284C7),
                    side: const BorderSide(color: Color(0xFF0284C7)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: () => widget.onNavigateTab(3),
                  icon: const Icon(Icons.alt_route, size: 18),
                  label: const Text('Open Full Delivery Schedule & Route', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A))),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
          ],
        ),
      ),
    );
  }
}