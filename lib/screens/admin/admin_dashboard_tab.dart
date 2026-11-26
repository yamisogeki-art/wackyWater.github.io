import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/forecast_service.dart';
import '../../widgets/confirm_logout.dart';
import 'admin_announcements_screen.dart';
import 'admin_drivers_screen.dart';
import 'admin_emergency_reports_screen.dart';

/// How many gallons one delivery trip carries. Used only for the "Estimated Trips" figure.
/// Change it to match your truck.
const double kTripCapacityGallons = 100;

/// Extra water to prepare on top of the forecast ("Recommended Production").
const double kProductionBuffer = 0.05;

const Color _navy = Color(0xFF03223F);
const Color _blue = Color(0xFF1C5FD6);
const Color _titleBlue = Color(0xFF1E40AF);
const Color _pageBg = Color(0xFFF3F6FB);
const Color _line = Color(0xFFE3E8F0);
const Color _ink = Color(0xFF0F172A);
const Color _muted = Color(0xFF64748B);
const Color _green = Color(0xFF15803D);

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
String _md(DateTime d) => '${_months[d.month - 1]} ${d.day}';
String _mdy(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';
String _num(num v) =>
    v.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

class _Pair {
  final DateTime date;
  final double actual;
  final double predicted;
  const _Pair(this.date, this.actual, this.predicted);
  double get error => (actual - predicted).abs();
  double? get ape => actual > 0 ? error / actual * 100 : null;
}

class _DashboardData {
  final ForecastResult forecast;
  final List<Map<String, dynamic>> openOrders;
  final int driverCount;
  final int onlineDrivers;
  _DashboardData(this.forecast, this.openOrders, this.driverCount, this.onlineDrivers);

  late final Map<DateTime, double> actual = {for (final p in forecast.history) _day(p.date): p.gallons};
  late final Map<DateTime, double> predicted = {for (final p in forecast.forecast) _day(p.date): p.gallons};

  DateTime get today => _day(DateTime.now());
  DateTime get tomorrow => today.add(const Duration(days: 1));

  double? get todayForecast => predicted[today];
  double? get tomorrowForecast => predicted[tomorrow];

  /// Past forecasts that can be checked against what was actually sold.
  late final List<_Pair> pairs = () {
    final list = <_Pair>[];
    predicted.forEach((d, p) {
      final a = actual[d];
      if (a != null && !d.isAfter(today)) list.add(_Pair(d, a, p));
    });
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }();

  double? get mae => pairs.isEmpty ? null : pairs.map((p) => p.error).reduce((a, b) => a + b) / pairs.length;
  double? get rmse => pairs.isEmpty
      ? null
      : math.sqrt(pairs.map((p) => p.error * p.error).reduce((a, b) => a + b) / pairs.length);
  double? get mape {
    final apes = pairs.map((p) => p.ape).whereType<double>().toList();
    return apes.isEmpty ? null : apes.reduce((a, b) => a + b) / apes.length;
  }

  double? get accuracy => mape == null ? null : (100 - mape!).clamp(0, 100).toDouble();

  double? get weeklyAverage {
    if (forecast.history.isEmpty) return null;
    final last = forecast.history.length > 7
        ? forecast.history.sublist(forecast.history.length - 7)
        : forecast.history;
    return last.map((p) => p.gallons).reduce((a, b) => a + b) / last.length;
  }

  int get weeklyDays => math.min(7, forecast.history.length);

  /// Gallons so far this month + the weekly average for the days not recorded yet.
  double? get monthProjection {
    final avg = weeklyAverage;
    if (avg == null) return null;
    final now = today;
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final monthRows = forecast.history.where((p) => p.date.year == now.year && p.date.month == now.month);
    final sofar = monthRows.fold<double>(0, (s, p) => s + p.gallons);
    final lastDay = monthRows.isEmpty ? 0 : monthRows.map((p) => p.date.day).reduce(math.max);
    return sofar + avg * (daysInMonth - lastDay);
  }

  String get modelName {
    final v = (forecast.modelVersion ?? '').toLowerCase();
    if (v.contains('lstm')) return 'LSTM';
    if (v.contains('lightgbm')) return 'LightGBM';
    if (v.contains('xgb')) return 'XGBoost';
    return forecast.modelVersion ?? 'Model';
  }

  double get openGallons =>
      openOrders.fold<double>(0, (s, o) => s + ((o['gallons_requested'] as num?)?.toDouble() ?? 0));
  int get openCustomers => openOrders.map((o) => o['customer_id']).toSet().length;
}

/// Admin dashboard: forecast cards, demand chart, delivery plan, accuracy and history.
class AdminDashboardTab extends StatefulWidget {
  /// Switches the bottom tab: 1 Map, 2 Requests, 3 Schedule, 4 Sales, 5 Forecast.
  final ValueChanged<int> onNavigateTab;
  const AdminDashboardTab({super.key, required this.onNavigateTab});

  @override
  State<AdminDashboardTab> createState() => _AdminDashboardTabState();
}

class _AdminDashboardTabState extends State<AdminDashboardTab> {
  final _service = ForecastService();
  final _db = Supabase.instance.client;
  late Future<_DashboardData> _future;
  late final Stream<List<Map<String, dynamic>>> _openAlerts =
      _db.from('emergency_reports').stream(primaryKey: ['id']).eq('status', 'open');
  bool _autoTried = false;
  bool _refreshing = false;
  String? _serverNote;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _future.then(_maybeAutoForecast, onError: (_) {});
  }

  Future<_DashboardData> _load() async {
    final f = await _service.load(historyDays: 45);

    List<Map<String, dynamic>> open = [];
    try {
      open = List<Map<String, dynamic>>.from(await _db
          .from('delivery_requests')
          .select('customer_id, gallons_requested')
          .inFilter('status', ['pending', 'assigned', 'in_transit']));
    } catch (_) {}

    var drivers = 0;
    var online = 0;
    try {
      final d = await _db.from('profiles').select('id').eq('role', 'driver');
      drivers = (d as List).length;
      final cutoff = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
      final locs = await _db.from('driver_locations').select('driver_id, updated_at');
      online = List<Map<String, dynamic>>.from(locs).where((r) {
        final t = DateTime.tryParse('${r['updated_at']}');
        return t != null && t.isAfter(cutoff);
      }).length;
    } catch (_) {}

    return _DashboardData(f, open, drivers, online);
  }

  /// Once per visit: if tomorrow has no forecast yet, ask the server to make one.
  Future<void> _maybeAutoForecast(_DashboardData d) async {
    if (_autoTried) return;
    _autoTried = true;
    if (d.predicted.containsKey(d.tomorrow)) return;
    await _runForecast(silent: true);
  }

  Future<void> _runForecast({bool silent = false}) async {
    if (mounted) setState(() => _refreshing = true);
    try {
      await _service.triggerServerForecast();
      _serverNote = null;
    } catch (e) {
      _serverNote = e.toString().replaceFirst('Exception: ', '').split('\n').first;
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_serverNote!)));
      }
    }
    if (mounted) {
      setState(() {
        _refreshing = false;
        _future = _load();
      });
    }
  }

  Future<void> _reload() async {
    setState(() => _future = _load());
    try {
      await _future;
    } catch (_) {}
  }

  void _go(int tab) {
    Navigator.pop(context);
    widget.onNavigateTab(tab);
  }

  void _push(Widget screen) {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _logout() async {
    if (await confirmLogout(context)) {
      await Supabase.instance.client.auth.signOut();
    }
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      drawer: _drawer(),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: const Border(bottom: BorderSide(color: _line)),
        title: const Text(
          'WACKY WATER DELIVERY\nREFILLING STATION',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, height: 1.2, letterSpacing: 0.3),
        ),
        actions: [
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _openAlerts,
            builder: (context, snap) {
              final open = snap.data?.length ?? 0;
              return IconButton(
                tooltip: 'Emergency reports',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminEmergencyReportsScreen()),
                ),
                icon: Badge(
                  isLabelVisible: open > 0,
                  label: Text('$open'),
                  child: const Icon(Icons.notifications_none_rounded),
                ),
              );
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'refresh') _runForecast();
              if (v == 'logout') _logout();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'refresh', child: Text('Refresh forecast')),
              PopupMenuItem(value: 'logout', child: Text('Log out')),
            ],
            child: const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Row(
                children: [
                  CircleAvatar(radius: 15, backgroundColor: _navy, child: Icon(Icons.person, color: Colors.white, size: 18)),
                  SizedBox(width: 6),
                  Text('Admin', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  Icon(Icons.arrow_drop_down, size: 20),
                ],
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<_DashboardData>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 60),
                  const Icon(Icons.cloud_off, size: 48, color: _muted),
                  const SizedBox(height: 12),
                  Text('${snap.error}'.replaceFirst('Exception: ', ''),
                      textAlign: TextAlign.center, style: const TextStyle(color: _muted)),
                  const SizedBox(height: 16),
                  Center(child: FilledButton(onPressed: _reload, child: const Text('Try again'))),
                ],
              );
            }
            return _content(snap.data!);
          },
        ),
      ),
    );
  }

  Widget _content(_DashboardData d) {
    final today = d.todayForecast;
    final tomorrow = d.tomorrowForecast;
    final ref = today ?? d.actual[d.today] ?? (d.forecast.history.isEmpty ? null : d.forecast.history.last.gallons);
    final refLabel = today != null || d.actual[d.today] != null ? 'vs Today' : 'vs last recorded day';
    final change = (tomorrow != null && ref != null && ref > 0) ? (tomorrow - ref) / ref * 100 : null;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        if (_refreshing) const Padding(padding: EdgeInsets.only(bottom: 10), child: LinearProgressIndicator()),
        if (_serverNote != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFED7AA))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 18, color: Color(0xFFC2410C)),
                const SizedBox(width: 8),
                Expanded(child: Text('Forecast not updated: $_serverNote', style: const TextStyle(fontSize: 12.5, color: Color(0xFF9A3412)))),
              ],
            ),
          ),
        Row(children: [
          Expanded(
            child: _Kpi(
              title: "TODAY'S FORECAST",
              value: today == null ? '—' : _num(today),
              icon: Icons.calendar_month_outlined,
              iconBg: const Color(0xFFE3EBFA),
              iconColor: _blue,
              footer: d.accuracy != null
                  ? _Pill('Accuracy: ${d.accuracy!.round()}%', _green, const Color(0xFFE8F6EC))
                  : const Text('No forecast saved for today', style: TextStyle(fontSize: 11.5, color: _muted)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _Kpi(
              title: "TOMORROW'S FORECAST",
              value: tomorrow == null ? '—' : _num(tomorrow),
              icon: Icons.event_outlined,
              iconBg: const Color(0xFFE3EBFA),
              iconColor: _blue,
              footer: change == null
                  ? const Text('Not available yet', style: TextStyle(fontSize: 11.5, color: _muted))
                  : Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      _Pill('${change >= 0 ? '▲' : '▼'} ${change.abs().toStringAsFixed(1)}%',
                          change >= 0 ? _green : Colors.red.shade700,
                          change >= 0 ? const Color(0xFFE8F6EC) : const Color(0xFFFDECEC)),
                      Text(refLabel, style: const TextStyle(fontSize: 11.5, color: _muted)),
                    ]),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: _Kpi(
              title: 'WEEKLY AVERAGE DEMAND',
              value: d.weeklyAverage == null ? '—' : _num(d.weeklyAverage!),
              icon: Icons.bar_chart_rounded,
              iconBg: const Color(0xFFEDE9FB),
              iconColor: const Color(0xFF6D4AD8),
              footer: Text(d.weeklyDays == 0 ? 'No sales recorded' : 'Last ${d.weeklyDays} Days',
                  style: const TextStyle(fontSize: 11.5, color: _muted)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _Kpi(
              title: 'MONTHLY TOTAL (PROJECTED)',
              value: d.monthProjection == null ? '—' : _num(d.monthProjection!),
              icon: Icons.water_drop_outlined,
              iconBg: const Color(0xFFE3F4E8),
              iconColor: _green,
              footer: const Text('This Month', style: TextStyle(fontSize: 11.5, color: _muted)),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        _chartCard(d),
        const SizedBox(height: 16),
        _planCard(d),
        const SizedBox(height: 16),
        _accuracyCard(d),
        const SizedBox(height: 16),
        _historyCard(d),
        const SizedBox(height: 20),
        Center(
          child: Text('© ${DateTime.now().year} Wacky Water Delivery Refilling Station. All rights reserved.',
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: _muted)),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // ---------------------------------------------------------------- chart

  Widget _chartCard(_DashboardData d) {
    final hist = d.forecast.history;
    Widget body;
    if (hist.isEmpty) {
      body = const SizedBox(height: 160, child: Center(child: Text('No sales history yet.', style: TextStyle(color: _muted))));
    } else {
      final recent = hist.length > 11 ? hist.sublist(hist.length - 11) : hist;
      final start = _day(recent.first.date);
      double x(DateTime dt) => _day(dt).difference(start).inDays.toDouble();

      final actualSpots = [for (final p in recent) FlSpot(x(p.date), p.gallons)];
      final forecastSpots = [
        for (final p in d.forecast.forecast)
          if (!_day(p.date).isBefore(start)) FlSpot(x(p.date), p.gallons),
      ]..sort((a, b) => a.x.compareTo(b.x));

      final all = [...actualSpots, ...forecastSpots];
      final maxX = all.map((s) => s.x).reduce(math.max);
      var minY = all.map((s) => s.y).reduce(math.min);
      var maxY = all.map((s) => s.y).reduce(math.max);
      final pad = math.max(5.0, (maxY - minY) * 0.15);
      minY = math.max(0.0, ((minY - pad) / 10).floorToDouble() * 10);
      maxY = ((maxY + pad) / 10).ceilToDouble() * 10;
      final interval = math.max(1.0, ((maxY - minY) / 5).ceilToDouble());

      LineChartBarData line(List<FlSpot> spots, Color c, {bool dashed = false}) => LineChartBarData(
            spots: spots,
            isCurved: false,
            color: c,
            barWidth: 2,
            dashArray: dashed ? [6, 4] : null,
            dotData: FlDotData(
              show: true,
              getDotPainter: (s, p, b, i) =>
                  FlDotCirclePainter(radius: 3.5, color: Colors.white, strokeWidth: 2, strokeColor: c),
            ),
          );

      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 14, runSpacing: 4, children: [
            const _LegendDot('Actual Demand', _blue, dashed: false),
            _LegendDot('Forecasted Demand (${d.modelName})', _green, dashed: true),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: maxX < 1 ? 1 : maxX,
                minY: minY,
                maxY: maxY,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: interval,
                  getDrawingHorizontalLine: (_) => const FlLine(color: _line, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 34,
                      interval: interval,
                      getTitlesWidget: (v, m) => Text(v.round().toString(), style: const TextStyle(fontSize: 10, color: _muted)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      interval: 2,
                      getTitlesWidget: (v, m) => Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(_md(start.add(Duration(days: v.round()))),
                            style: const TextStyle(fontSize: 10, color: _muted)),
                      ),
                    ),
                  ),
                ),
                lineBarsData: [
                  line(actualSpots, _blue),
                  if (forecastSpots.isNotEmpty) line(forecastSpots, _green, dashed: true),
                ],
              ),
            ),
          ),
          if (forecastSpots.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('The dashed forecast line appears once a forecast has been generated.',
                  style: TextStyle(fontSize: 11.5, color: _muted)),
            ),
        ],
      );
    }
    return _Card(
      title: 'DAILY GALLON DEMAND FORECAST',
      child: body,
    );
  }

  // ---------------------------------------------------------------- operations plan

  Widget _planCard(_DashboardData d) {
    final predicted = d.tomorrowForecast;
    final production = predicted == null ? null : (predicted * (1 + kProductionBuffer)).ceil();
    final trips = d.openGallons <= 0 ? 0 : (d.openGallons / kTripCapacityGallons).ceil();

    Widget row(IconData icon, String label, String value, {bool last = false}) => Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: _line))),
          child: Row(children: [
            Icon(icon, size: 20, color: _navy),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: _ink))),
            Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _ink)),
          ]),
        );

    return _Card(
      title: 'DAILY DELIVERY OPERATION PLAN',
      leadingIcon: Icons.local_shipping_outlined,
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: _line), borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          row(Icons.water_drop, 'Predicted Demand', predicted == null ? '—' : '${_num(predicted)} Gallons'),
          row(Icons.factory_outlined, 'Recommended Production', production == null ? '—' : '${_num(production)} Gallons'),
          row(Icons.groups_outlined, 'Expected Deliveries', '${d.openCustomers} Customers'),
          row(Icons.person_outline, 'Delivery Personnel',
              '${d.driverCount} ${d.driverCount == 1 ? 'Driver' : 'Drivers'} (${d.onlineDrivers} online)'),
          row(Icons.local_shipping_outlined, 'Estimated Trips', '$trips ${trips == 1 ? 'Trip' : 'Trips'}', last: true),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- accuracy + history

  Widget _accuracyCard(_DashboardData d) {
    final mape = d.mape;
    String grade;
    Color gradeColor;
    if (mape == null) {
      grade = 'Not enough data yet';
      gradeColor = _muted;
    } else if (mape < 10) {
      grade = 'Excellent';
      gradeColor = _green;
    } else if (mape < 20) {
      grade = 'Good';
      gradeColor = const Color(0xFF1D4ED8);
    } else {
      grade = 'Needs improvement';
      gradeColor = Colors.orange.shade800;
    }

    Widget row(String label, String value, {bool last = false}) => Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: _line))),
          child: Row(children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
            Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ]),
        );

    return _Card(
      title: 'FORECAST ACCURACY (RECENT DAYS)',
      leadingIcon: Icons.track_changes,
      child: Column(children: [
        Container(
          decoration: BoxDecoration(border: Border.all(color: _line), borderRadius: BorderRadius.circular(10)),
          child: Column(children: [
            row('MAE', d.mae == null ? '—' : d.mae!.toStringAsFixed(2)),
            row('RMSE', d.rmse == null ? '—' : d.rmse!.toStringAsFixed(2)),
            row('MAPE', mape == null ? '—' : '${mape.toStringAsFixed(2)}%', last: true),
          ]),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: gradeColor.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: gradeColor.withValues(alpha: 0.35))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('Model Performance', style: TextStyle(fontWeight: FontWeight.w700, color: gradeColor, fontSize: 13))),
              Text(grade, style: TextStyle(fontWeight: FontWeight.w800, color: gradeColor, fontSize: 13)),
              if (mape != null) ...[const SizedBox(width: 6), Icon(Icons.check_circle, size: 18, color: gradeColor)],
            ]),
            const SizedBox(height: 4),
            Text(
              mape == null
                  ? 'Each day\'s forecast is saved and compared with actual sales the next day.'
                  : 'Based on ${d.pairs.length} day${d.pairs.length == 1 ? '' : 's'} where a saved forecast could be compared with actual sales.',
              style: TextStyle(fontSize: 12, color: gradeColor),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _historyCard(_DashboardData d) {
    final shown = d.pairs.take(5).toList();
    return _Card(
      title: 'FORECAST HISTORY',
      leadingIcon: Icons.history,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (shown.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No past forecasts to compare yet. They will appear here after a forecast date has passed and sales are recorded.',
                style: TextStyle(fontSize: 12.5, color: _muted)),
          )
        else
          _HistoryTable(rows: shown),
        if (d.pairs.length > 5) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
              builder: (_) => DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.8,
                builder: (_, controller) => ListView(
                  controller: controller,
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text('FORECAST HISTORY', style: TextStyle(fontWeight: FontWeight.w800, color: _titleBlue)),
                    const SizedBox(height: 12),
                    _HistoryTable(rows: d.pairs),
                  ],
                ),
              ),
            ),
            child: const Text('View Full History'),
          ),
        ],
      ]),
    );
  }

  // ---------------------------------------------------------------- drawer

  Widget _drawer() {
    Widget item(IconData icon, String label, VoidCallback onTap, {bool selected = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Material(
            color: selected ? _blue : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                child: Row(children: [
                  Icon(icon, color: Colors.white, size: 21),
                  const SizedBox(width: 14),
                  Text(label, style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
        );

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
                    Text('WACKY WATER', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, height: 1.1)),
                    Text('DELIVERY & REFILLING', style: TextStyle(color: Color(0xFF9FB6D6), fontSize: 10, letterSpacing: 0.6)),
                  ]),
                ),
              ]),
            ),
            const Divider(color: Color(0xFF12385C), height: 1),
            const SizedBox(height: 8),
            item(Icons.dashboard_outlined, 'Dashboard', () => Navigator.pop(context), selected: true),
            item(Icons.show_chart, 'Forecasting', () => _go(5)),
            item(Icons.local_shipping_outlined, 'Delivery Operations', () => _go(3)),
            item(Icons.description_outlined, 'Reports', () => _go(4)),
            const Padding(padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16), child: Divider(color: Color(0xFF12385C))),
            item(Icons.badge_outlined, 'Drivers', () => _push(const AdminDriversScreen())),
            item(Icons.warning_amber_rounded, 'Emergency Reports', () => _push(const AdminEmergencyReportsScreen())),
            item(Icons.campaign_outlined, 'Announcements', () => _push(const AdminAnnouncementsScreen())),
            const Spacer(),
            item(Icons.logout, 'Log out', () {
              Navigator.pop(context);
              _logout();
            }),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ small widgets

class _Card extends StatelessWidget {
  final String title;
  final IconData? leadingIcon;
  final Widget child;
  const _Card({required this.title, required this.child, this.leadingIcon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (leadingIcon != null) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFE3EBFA), shape: BoxShape.circle),
              child: Icon(leadingIcon, size: 18, color: _blue),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(child: Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: _titleBlue, letterSpacing: 0.2))),
        ]),
        const SizedBox(height: 14),
        child,
      ]),
    );
  }
}

class _Kpi extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final Widget footer;
  const _Kpi({
    required this.title,
    required this.value,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 148),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: _titleBlue, height: 1.25))),
          const SizedBox(width: 6),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: iconColor),
          ),
        ]),
        const SizedBox(height: 10),
        Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: _ink, height: 1)),
        const SizedBox(height: 2),
        const Text('Gallons', style: TextStyle(fontSize: 14, color: _ink)),
        const SizedBox(height: 8),
        footer,
      ]),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color fg;
  final Color bg;
  const _Pill(this.text, this.fg, this.bg);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg)),
      );
}

class _LegendDot extends StatelessWidget {
  final String label;
  final Color color;
  final bool dashed;
  const _LegendDot(this.label, this.color, {required this.dashed});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 14, height: 2, color: color),
        if (dashed) ...[const SizedBox(width: 2), Container(width: 4, height: 2, color: color)],
        const SizedBox(width: 4),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 2), color: Colors.white),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11, color: _muted)),
      ]);
}

class _HistoryTable extends StatelessWidget {
  final List<_Pair> rows;
  const _HistoryTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    const head = TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: _ink);
    const cell = TextStyle(fontSize: 11.5, color: _ink);
    Widget c(String t, TextStyle s, {TextAlign a = TextAlign.center}) =>
        Padding(padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4), child: Text(t, style: s, textAlign: a));

    return Container(
      decoration: BoxDecoration(border: Border.all(color: _line), borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: Table(
        columnWidths: const {0: FlexColumnWidth(2.1), 1: FlexColumnWidth(1.4), 2: FlexColumnWidth(1.5), 3: FlexColumnWidth(1.1), 4: FlexColumnWidth(1.3)},
        border: const TableBorder(horizontalInside: BorderSide(color: _line)),
        children: [
          TableRow(
            decoration: const BoxDecoration(color: Color(0xFFF1F5F9)),
            children: [c('Date', head), c('Actual', head), c('Predicted', head), c('Error', head), c('APE (%)', head)],
          ),
          for (final r in rows)
            TableRow(children: [
              c(_mdy(r.date), cell),
              c(_num(r.actual), cell),
              c(_num(r.predicted), cell),
              c(r.error.toStringAsFixed(0), cell),
              c(r.ape == null ? '-' : '${r.ape!.toStringAsFixed(2)}%', cell),
            ]),
        ],
      ),
    );
  }
}
