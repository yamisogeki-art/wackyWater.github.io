import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/auth_config.dart';

class DemandPoint {
  final DateTime date;
  final double gallons;
  const DemandPoint(this.date, this.gallons);
}

class ForecastResult {
  final List<DemandPoint> history;
  final List<DemandPoint> forecast;
  final String? modelVersion;
  final bool isOfflineCache;
  final DateTime? cachedAt;

  const ForecastResult(
    this.history,
    this.forecast,
    this.modelVersion, {
    this.isOfflineCache = false,
    this.cachedAt,
  });
}

class ForecastService {
  final _db = Supabase.instance.client;
  static const String _cacheKey = 'cached_forecast_result_v1';
  static const String _cacheTimestampKey = 'cached_forecast_timestamp_v1';

  /// Loads history and forecast data. First attempts live query from Supabase.
  /// If offline or network error, loads from local disk cache so screen isn't blank.
  Future<ForecastResult> load({int historyDays = 30}) async {
    try {
      final h = await _db
          .from('sales_daily')
          .select('sale_date,total_gallons')
          .order('sale_date', ascending: false)
          .limit(historyDays)
          .timeout(const Duration(seconds: 8));

      final f = await _db
          .from('forecasts')
          .select('forecast_date,predicted_gallons,model_version')
          .order('forecast_date')
          .timeout(const Duration(seconds: 8));

      DateTime d(dynamic v) => DateTime.parse(v as String);

      final history = h.reversed
          .map((r) => DemandPoint(d(r['sale_date']), (r['total_gallons'] as num).toDouble()))
          .toList();
      final forecast = f
          .map((r) => DemandPoint(d(r['forecast_date']), (r['predicted_gallons'] as num).toDouble()))
          .toList();

      final modelVer = f.isEmpty ? null : f.first['model_version'] as String?;
      final result = ForecastResult(history, forecast, modelVer);

      // Save to cache asynchronously for offline fallback
      _saveToCache(result);

      return result;
    } catch (e) {
      debugPrint('ForecastService.load error ($e), attempting offline cache...');
      final cached = await _loadFromCache();
      if (cached != null) {
        return cached;
      }
      throw Exception(
        'Unable to load demand forecast.\n'
        'Network error: $e\n'
        'Please check your internet connection and try again.',
      );
    }
  }

  /// Triggers a fresh ML model forecast generation on the FastAPI backend server.
  /// Sends X-API-Key header, enforces HTTPS base URL, handles timeouts and rate limits.
  Future<ForecastResult> triggerServerForecast() async {
    final targetUrl = '$resolvedApiBaseUrl/forecast';
    final uri = Uri.parse(targetUrl);

    try {
      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'X-API-Key': forecastApiKey,
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        // Forecast generated successfully and written to Supabase; load fresh results
        return await load();
      } else if (response.statusCode == 401) {
        throw Exception('Server Authentication Failed (HTTP 401): Invalid API Key.');
      } else if (response.statusCode == 429) {
        throw Exception('Rate limit exceeded (HTTP 429): Server busy. Please wait a minute before retrying.');
      } else {
        throw Exception('Server Error (${response.statusCode}): ${response.body}');
      }
    } on TimeoutException {
      throw Exception(
        'Connection timed out reaching forecast server at:\n$targetUrl\n\n'
        'Suggestions:\n'
        '• Ensure backend server is deployed and running on HTTPS (e.g. Render/Railway)\n'
        '• Verify API_BASE_URL build config',
      );
    } on SocketException catch (se) {
      throw Exception(
        'Network unreachable ($targetUrl).\n'
        'Socket error: ${se.message}.\n'
        'Check device Wi-Fi/Cellular data connection.',
      );
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Unexpected error triggering server forecast: $e');
    }
  }

  Future<void> _saveToCache(ForecastResult result) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonMap = {
        'modelVersion': result.modelVersion,
        'history': result.history
            .map((h) => {
                  'date': h.date.toIso8601String(),
                  'gallons': h.gallons,
                })
            .toList(),
        'forecast': result.forecast
            .map((f) => {
                  'date': f.date.toIso8601String(),
                  'gallons': f.gallons,
                })
            .toList(),
      };
      await prefs.setString(_cacheKey, jsonEncode(jsonMap));
      await prefs.setString(_cacheTimestampKey, DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('Failed to save forecast cache: $e');
    }
  }

  Future<ForecastResult?> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_cacheKey);
      final tsStr = prefs.getString(_cacheTimestampKey);
      if (jsonStr == null) return null;

      final jsonMap = jsonDecode(jsonStr) as Map<String, dynamic>;
      final modelVersion = jsonMap['modelVersion'] as String?;
      final cachedAt = tsStr != null ? DateTime.tryParse(tsStr) : null;

      final historyList = (jsonMap['history'] as List? ?? []).map((item) {
        return DemandPoint(
          DateTime.parse(item['date'] as String),
          (item['gallons'] as num).toDouble(),
        );
      }).toList();

      final forecastList = (jsonMap['forecast'] as List? ?? []).map((item) {
        return DemandPoint(
          DateTime.parse(item['date'] as String),
          (item['gallons'] as num).toDouble(),
        );
      }).toList();

      return ForecastResult(
        historyList,
        forecastList,
        modelVersion,
        isOfflineCache: true,
        cachedAt: cachedAt,
      );
    } catch (e) {
      debugPrint('Failed to load forecast cache: $e');
      return null;
    }
  }
}
