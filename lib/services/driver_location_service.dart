import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Streams the signed-in driver's GPS position and upserts it into the
/// `driver_locations` table. Admin's map screen subscribes to that
/// table via Supabase realtime, so every update here shows up live on
/// the admin side within a second or two.
///
/// One row per driver (upsert on driver_id), not a full history log -
/// this is "where is this driver right now", not a trip log. Add a
/// separate `driver_location_history` table later if you need replay.
class DriverLocationService {
  StreamSubscription<Position>? _positionSub;
  bool get isTracking => _positionSub != null;

  Future<bool> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Starts broadcasting location. Call when the driver toggles "online".
  /// Returns false if location permission/service isn't available.
  Future<bool> start() async {
    if (isTracking) return true;

    final granted = await _ensurePermission();
    if (!granted) return false;

    final driverId = Supabase.instance.client.auth.currentUser?.id;
    if (driverId == null) return false;

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 20, // only push an update after moving 20m+
    );

    _positionSub =
        Geolocator.getPositionStream(locationSettings: settings).listen(
      (position) async {
        await Supabase.instance.client.from('driver_locations').upsert({
          'driver_id': driverId,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
      },
    );
    return true;
  }

  /// One-shot "where am I right now" lookup for screens that need the
  /// driver's position (distance to each stop, routing). Asks for location
  /// permission if it hasn't been granted yet. Returns null if location is
  /// off or denied.
  static Future<Position?> currentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
    } catch (_) {
      return null;
    }
  }

  /// Stops broadcasting. Call when the driver toggles "offline" or logs out.
  Future<void> stop() async {
    await _positionSub?.cancel();
    _positionSub = null;
  }
}
