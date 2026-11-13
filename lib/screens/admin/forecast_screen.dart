import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../constants/auth_config.dart';
import '../../services/forecast_service.dart';
import '../../widgets/logout_confirm.dart';

class ForecastScreen extends StatefulWidget {
  const ForecastScreen({super.key});

  @override
  State<ForecastScreen> createState() => _ForecastScreenState();
}

class _ForecastScreenState extends State<ForecastScreen> {
  late Future<ForecastResult> _forecastFuture;
  bool _isGenerating = false;
  String? _serverError;

  @override
  void initState() {
    super.initState();
    _loadForecast();
  }

  void _loadForecast() {
    _forecastFuture = ForecastService().load();
  }

  Future<void> _handleRefresh() async {
    setState(() {
      _serverError = null;
      _loadForecast();
    });
    await _forecastFuture;
  }

  Future<void> _runNewForecastServer() async {
    setState(() {
      _isGenerating = true;
      _serverError = null;
    });

    try {
      final updatedResult = await ForecastService().triggerServerForecast();
      if (!mounted) return;
      setState(() {
        _forecastFuture = Future.value(updatedResult);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ New forecast generated successfully by LightGBM server!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final errorMsg = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _serverError = errorMsg;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Forecast generation failed: $errorMsg'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: _runNewForecastServer,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Demand forecast'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isGenerating ? null : _handleRefresh,
            tooltip: 'Reload forecast',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => logoutWithConfirmation(context),
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        child: FutureBuilder<ForecastResult>(
          future: _forecastFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && !_isGenerating) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError && !snapshot.hasData) {
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.wifi_off_rounded, color: Colors.orange, size: 54),
                      const SizedBox(height: 16),
                      const Text(
                        'Connection Error',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        snapshot.error.toString().replaceFirst('Exception: ', ''),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _handleRefresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry Connection'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final res = snapshot.data;
            if (res == null || (res.history.isEmpty && res.forecast.isEmpty)) {
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 40),
                      const Icon(Icons.show_chart, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text(
                        'No forecast yet',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Server endpoint: $resolvedApiBaseUrl/forecast',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                      if (_serverError != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Text(
                            _serverError!,
                            style: TextStyle(color: Colors.red.shade800, fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          backgroundColor: const Color(0xFF0284C7),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _isGenerating ? null : _runNewForecastServer,
                        icon: _isGenerating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.flash_on),
                        label: Text(_isGenerating ? 'Running LightGBM Model...' : 'Run new forecast'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final modelVersion = res.modelVersion ?? 'LightGBM v1';
            final tomorrowForecast = res.forecast.isNotEmpty ? res.forecast.first.gallons : 0.0;
            final sevenDayTotal = res.forecast.take(7).fold<double>(0.0, (sum, p) => sum + p.gallons);

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16.0),
              children: [
                // Offline Mode Banner if serving from local cache
                if (res.isOfflineCache) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.offline_bolt, color: Colors.amber.shade800, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Offline Mode: Displaying cached forecast'
                            '${res.cachedAt != null ? ' (Saved: ${_formatShortDate(res.cachedAt!)})' : ''}.',
                            style: TextStyle(fontSize: 12, color: Colors.amber.shade900, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Server Status / Model Info Card
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.memory, color: Colors.blue.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Model: $modelVersion',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: resolvedApiBaseUrl.startsWith('https') ? Colors.green.shade100 : Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              resolvedApiBaseUrl.startsWith('https') ? 'HTTPS Secure' : 'HTTP Dev',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: resolvedApiBaseUrl.startsWith('https') ? Colors.green.shade800 : Colors.orange.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Backend: $resolvedApiBaseUrl',
                        style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // KPI Cards
                Row(
                  children: [
                    Expanded(
                      child: _buildKpiCard(
                        title: "Tomorrow's Forecast",
                        value: res.forecast.isNotEmpty ? '${tomorrowForecast.round()} gal' : 'N/A',
                        subtitle: res.forecast.isNotEmpty
                            ? '${res.forecast.first.date.month}/${res.forecast.first.date.day}'
                            : 'No data',
                        color: const Color(0xFF0284C7),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildKpiCard(
                        title: '7-Day Total',
                        value: '${sevenDayTotal.round()} gal',
                        subtitle: '${res.forecast.length} forecast days',
                        color: const Color(0xFF16A34A),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Chart Card
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Demand History & Forecast',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                modelVersion,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _buildLegendItem(color: const Color(0xFF0284C7), label: 'Actual', isDashed: false),
                            const SizedBox(width: 16),
                            _buildLegendItem(color: const Color(0xFFF59E0B), label: 'Forecast', isDashed: true),
                            const SizedBox(width: 16),
                            _buildLegendItem(color: Colors.redAccent, label: 'Min (400 gal)', isDashed: true),
                          ],
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 260,
                          child: res.history.isEmpty && res.forecast.isEmpty
                              ? const Center(child: Text('No chart data'))
                              : _buildChart(res),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                if (_serverError != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(
                      _serverError!,
                      style: TextStyle(color: Colors.red.shade800, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Run New Forecast Button
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isGenerating ? null : _runNewForecastServer,
                  icon: _isGenerating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(_isGenerating ? 'Running LightGBM Model on Server...' : 'Run new forecast'),
                ),

                const SizedBox(height: 20),

                // Detailed Forecast Breakdown
                if (res.forecast.isNotEmpty) ...[
                  Text(
                    'Upcoming Forecast Days',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: res.forecast.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = res.forecast[index];
                        final dateStr = '${item.date.year}-${item.date.month.toString().padLeft(2, '0')}-${item.date.day.toString().padLeft(2, '0')}';
                        final isAboveMin = item.gallons >= 400;

                        return ListTile(
                          dense: true,
                          title: Text(
                            dateStr,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text('Model: $modelVersion'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${item.gallons.round()} gal',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: isAboveMin ? Colors.green.shade700 : Colors.orange.shade700,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                isAboveMin ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                                color: isAboveMin ? Colors.green : Colors.orange,
                                size: 18,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildChart(ForecastResult res) {
    final base = res.history.isNotEmpty ? res.history.first.date : (res.forecast.isNotEmpty ? res.forecast.first.date : DateTime.now());
    double x(DateTime t) => t.difference(base).inDays.toDouble();

    final actualSpots = res.history.map((p) => FlSpot(x(p.date), p.gallons)).toList();

    final forecastSpots = [
      if (res.history.isNotEmpty) FlSpot(x(res.history.last.date), res.history.last.gallons),
      ...res.forecast.map((p) => FlSpot(x(p.date), p.gallons)),
    ];

    double maxY = 500;
    for (final p in [...res.history, ...res.forecast]) {
      if (p.gallons > maxY) maxY = p.gallons;
    }
    maxY = (maxY * 1.15).clamp(500.0, 5000.0);

    return LineChart(
      LineChartData(
        minY: 350,
        maxY: maxY,
        lineBarsData: [
          if (actualSpots.isNotEmpty)
            LineChartBarData(
              spots: actualSpots,
              isCurved: false,
              barWidth: 2,
              color: const Color(0xFF0284C7),
              dotData: const FlDotData(show: false),
            ),
          if (forecastSpots.isNotEmpty)
            LineChartBarData(
              spots: forecastSpots,
              isCurved: false,
              barWidth: 2,
              color: const Color(0xFFF59E0B),
              dashArray: [6, 4],
              dotData: const FlDotData(show: false),
            ),
        ],
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: 400,
              dashArray: [2, 4],
              color: Colors.redAccent.withValues(alpha: 0.8),
              strokeWidth: 1.5,
            ),
          ],
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.grey.withValues(alpha: 0.15),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                if (value % 100 != 0 && value != 350) return const SizedBox.shrink();
                return Text(
                  '${value.toInt()}',
                  style: const TextStyle(color: Colors.grey, fontSize: 10),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 5,
              getTitlesWidget: (value, meta) {
                final date = base.add(Duration(days: value.toInt()));
                return Padding(
                  padding: const EdgeInsets.only(top: 6.0),
                  child: Text(
                    '${date.month}/${date.day}',
                    style: const TextStyle(color: Colors.grey, fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(
            bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
            left: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
          ),
        ),
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildLegendItem({required Color color, required String label, required bool isDashed}) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500)),
      ],
    );
  }

  String _formatShortDate(DateTime dt) {
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
