import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/service_areas.dart';
import '../../utils/validators.dart';

class SavedLocationsScreen extends StatefulWidget {
  final bool isPicker;
  const SavedLocationsScreen({super.key, this.isPicker = false});

  @override
  State<SavedLocationsScreen> createState() => _SavedLocationsScreenState();
}

class _SavedLocationsScreenState extends State<SavedLocationsScreen> {
  // Zamboanga Sibugay center coordinates covering Tungawan, R.T. Lim, and Ipil
  static const LatLng _defaultCenter = LatLng(7.6800, 122.4800);

  final _mapController = MapController();
  final _labelController = TextEditingController();
  String? _selectedArea;
  LatLng? _pickedPoint;
  bool _isSaving = false;

  late final Stream<List<Map<String, dynamic>>> _savedAddressesStream;

  @override
  void initState() {
    super.initState();
    final customerId = Supabase.instance.client.auth.currentUser?.id;
    _savedAddressesStream = Supabase.instance.client
        .from('customer_addresses')
        .stream(primaryKey: ['id'])
        .eq('customer_id', customerId as Object)
        .order('created_at');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _useCurrentLocation();
    });
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enable GPS / Location services on your device.')),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission was denied. Please allow location access.')),
          );
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Locating current position...'),
            duration: Duration(milliseconds: 1200),
          ),
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final point = LatLng(position.latitude, position.longitude);
      if (mounted) {
        setState(() => _pickedPoint = point);
        _mapController.move(point, 16);
        _detectArea(point);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF10B981),
            content: Text('Pinned to your current GPS location!'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error getting current location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not fetch GPS location: $e')),
        );
      }
    }
  }

  // ---- Automatically find the barangay for the pinned point ----
  int _detectToken = 0;
  String? _areaHint;

  String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'\(.*?\)'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\b(barangay|brgy)\b'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Matches names returned by the map service against the app's service areas.
  String? _matchArea(List<String> candidates) {
    for (final c in candidates) {
      final nc = _norm(c);
      if (nc.isEmpty) continue;
      for (final area in serviceableAreas) {
        if (_norm(area.toString()) == nc) return area.toString();
      }
    }
    for (final c in candidates) {
      final nc = _norm(c);
      if (nc.length < 4) continue;
      for (final area in serviceableAreas) {
        final na = _norm(area.toString());
        if (na.length >= 4 && (na.contains(nc) || nc.contains(na))) return area.toString();
      }
    }
    return null;
  }

  Future<void> _detectArea(LatLng point) async {
    final token = ++_detectToken;
    setState(() => _areaHint = 'Detecting barangay...');

    String? matched;
    String? foundName;
    try {
      final client = HttpClient()
        ..userAgent = 'com.wackysmart.app'
        ..connectionTimeout = const Duration(seconds: 8);
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': point.latitude.toString(),
        'lon': point.longitude.toString(),
        'zoom': '16',
        'addressdetails': '1',
        'accept-language': 'en',
      });
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(const Duration(seconds: 10));
      final body = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode == 200) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        final address = (data['address'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
        const keys = ['suburb', 'village', 'neighbourhood', 'quarter', 'hamlet', 'city_district', 'residential'];
        final candidates = <String>[
          for (final k in keys)
            if (address[k] is String) address[k] as String,
        ];
        foundName = candidates.isEmpty ? null : candidates.first;
        matched = _matchArea(candidates);
      }
    } catch (e) {
      debugPrint('Barangay lookup failed: $e');
    }

    // Ignore the result if the user already moved the pin again.
    if (!mounted || token != _detectToken) return;
    setState(() {
      if (matched != null) {
        _selectedArea = matched;
        _areaHint = 'Detected from your pinned location';
      } else if (foundName != null) {
        _areaHint = 'Detected "$foundName", which is not in the service list. Please choose your barangay.';
      } else {
        _areaHint = "Couldn't detect the barangay. Please choose it from the list.";
      }
    });
  }

  Future<void> _saveLocation() async {
    if (_pickedPoint == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tap the map or use current location first.')),
      );
      return;
    }
    final labelError = InputValidators.alphanumeric(_labelController.text, fieldName: 'Location label');
    if (labelError != null) {
      InputErrorHandler.showErrorSnackBar(context, labelError);
      return;
    }
    if (_selectedArea == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select the barangay so delivery routing can group it.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    final customerId = Supabase.instance.client.auth.currentUser?.id;

    try {
      await Supabase.instance.client.from('customer_addresses').insert({
        'customer_id': customerId,
        'label': _labelController.text.trim(),
        'area': _selectedArea,
        'latitude': _pickedPoint!.latitude,
        'longitude': _pickedPoint!.longitude,
      });
      _labelController.clear();
      setState(() {
        _pickedPoint = null;
        _selectedArea = null;
        _areaHint = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteLocation(dynamic id) async {
    await Supabase.instance.client.from('customer_addresses').delete().eq('id', id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.isPicker ? 'Select delivery location' : 'Delivery locations')),
      body: Column(
        children: [
          SizedBox(
            height: 260,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _defaultCenter,
                    initialZoom: 10.8,
                    onTap: (tapPosition, point) {
                      setState(() => _pickedPoint = point);
                      _detectArea(point);
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.wackysmart.app',
                    ),
                    if (_pickedPoint != null)
                      MarkerLayer(markers: [
                        Marker(
                          point: _pickedPoint!,
                          width: 40,
                          height: 40,
                          child: const Icon(Icons.location_pin, color: Colors.red, size: 36),
                        ),
                      ]),
                  ],
                ),
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: FloatingActionButton.small(
                    heroTag: 'current-location',
                    onPressed: _useCurrentLocation,
                    child: const Icon(Icons.my_location),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: DropdownButtonFormField<String>(
              key: ValueKey(_selectedArea ?? ''),
              initialValue: _selectedArea,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Area / Barangay',
                border: const OutlineInputBorder(),
                isDense: true,
                helperText: _areaHint,
                helperMaxLines: 2,
              ),
              items: serviceableAreas
                  .map((area) => DropdownMenuItem(value: area, child: Text(area)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedArea = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _labelController,
                    inputFormatters: [InputFormatters.alphanumeric],
                    decoration: const InputDecoration(
                      labelText: 'Label (e.g. Home, Store 1)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isSaving ? null : _saveLocation,
                  child: _isSaving
                      ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Text('Save'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _savedAddressesStream,
              builder: (context, snapshot) {
                final addresses = snapshot.data ?? [];
                if (addresses.isEmpty) {
                  return const Center(child: Text('No saved locations yet.'));
                }
                return ListView.builder(
                  itemCount: addresses.length,
                  itemBuilder: (context, index) {
                    final addr = addresses[index];
                    return ListTile(
                      leading: const Icon(Icons.location_on_outlined),
                      title: Text(addr['label'] ?? 'Unnamed'),
                      subtitle: Text(addr['area'] ?? 'No area set'),
                      onTap: () {
                        if (widget.isPicker) {
                          Navigator.pop(context, addr);
                        } else {
                          final lat = (addr['latitude'] as num?)?.toDouble();
                          final lng = (addr['longitude'] as num?)?.toDouble();
                          if (lat != null && lng != null) {
                            final point = LatLng(lat, lng);
                            setState(() {
                              _pickedPoint = point;
                              _selectedArea = addr['area']?.toString();
                            });
                            _mapController.move(point, 16);
                          }
                        }
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteLocation(addr['id']),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}