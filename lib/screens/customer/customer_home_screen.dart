import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/order_estimate_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/brand_header.dart';
import '../../widgets/reminder_notification_card.dart';
import 'customer_profile_screen.dart';
import 'household_info_screen.dart';
import 'ml_training_screen.dart';
import 'order_history_screen.dart';
import 'order_water_screen.dart';
import 'saved_locations_screen.dart';
import 'track_order_screen.dart';

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  int _selectedIndex = 0;
  Map<String, dynamic>? _userProfile;
  bool _isLoadingProfile = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final response = await Supabase.instance.client
            .from('profiles')
            .select('full_name')
            .eq('id', user.id)
            .single();
        if (mounted) setState(() => _userProfile = response);
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    } finally {
      if (mounted) setState(() => _isLoadingProfile = false);
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Bottom navigation follows the mockup: Home, Order, History, Profile.
    // Track / Household / Locations / Estimate live on the Home cards and
    // the Profile tab.
    final List<Widget> pages = [
      HomeDashboard(userName: _userProfile?['full_name'], isLoading: _isLoadingProfile),
      const OrderWaterScreen(),
      const OrderHistoryScreen(),
      const CustomerProfileScreen(),
    ];

    return Scaffold(
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textMuted,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.shopping_cart_outlined), activeIcon: Icon(Icons.shopping_cart), label: 'Order'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

class HomeDashboard extends StatefulWidget {
  final String? userName;
  final bool isLoading;
  const HomeDashboard({super.key, this.userName, this.isLoading = false});

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  late final Future<OrderEstimate?> _estimateFuture = OrderEstimateService.compute();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const BrandHeader(iconSize: 60, titleSize: 26),
              const SizedBox(height: 28),
              Text(
                widget.isLoading ? 'Loading...' : 'Welcome Back, ${widget.userName ?? 'Customer'}!',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              FutureBuilder<OrderEstimate?>(
                future: _estimateFuture,
                builder: (context, snapshot) {
                  final estimate = snapshot.data;
                  // Only nudge when the next order is within 3 days (or overdue).
                  if (estimate == null || estimate.daysUntil > 3) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: ReminderNotificationCard(
                      gallons: estimate.gallons,
                      daysUntil: estimate.daysUntil,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const OrderWaterScreen()),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              _buildActionCard(
                context,
                title: 'Request Delivery',
                subtitle: 'Order your water refill now',
                icon: Icons.local_shipping,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OrderWaterScreen())),
              ),
              const SizedBox(height: 16),
              _buildActionCard(
                context,
                title: 'Track My Order',
                subtitle: 'See your driver on the map',
                icon: Icons.pin_drop_outlined,
                color: AppColors.driverAccent,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrackOrderScreen())),
              ),
              const SizedBox(height: 16),
              _buildActionCard(
                context,
                title: 'Household Info',
                subtitle: 'Update your household details',
                icon: Icons.home_work,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HouseholdInfoScreen())),
              ),
              const SizedBox(height: 16),
              _buildActionCard(
                context,
                title: 'Delivery Locations',
                subtitle: 'Manage your saved addresses',
                icon: Icons.location_on_outlined,
                color: Colors.deepPurple,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SavedLocationsScreen())),
              ),
              const SizedBox(height: 16),
              _buildActionCard(
                context,
                title: 'Next Order Estimate',
                subtitle: 'Based on your saved habits',
                icon: Icons.auto_graph,
                color: Colors.green,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MlTrainingScreen())),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    Color color = AppColors.primary,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
