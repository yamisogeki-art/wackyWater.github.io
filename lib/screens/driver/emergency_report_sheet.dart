import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Map<String, String> emergencyCategories = {
  'vehicle_breakdown': 'Vehicle breakdown',
  'accident': 'Accident',
  'road_blocked': 'Road blocked / flooded',
  'bad_weather': 'Bad weather',
  'customer_unreachable': 'Customer unreachable',
  'safety': 'Safety concern',
  'other': 'Other',
};

/// Opens the emergency report form for the driver.
/// [deliveryRequestId] links the report to the order the driver is on (optional).
Future<void> showEmergencyReportSheet(BuildContext context, {Object? deliveryRequestId}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _EmergencySheet(deliveryRequestId: deliveryRequestId),
  );
  if (sent == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Emergency report sent to the admin.')),
    );
  }
}

class _EmergencySheet extends StatefulWidget {
  final Object? deliveryRequestId;
  const _EmergencySheet({this.deliveryRequestId});

  @override
  State<_EmergencySheet> createState() => _EmergencySheetState();
}

class _EmergencySheetState extends State<_EmergencySheet> {
  String _category = 'vehicle_breakdown';
  final _message = TextEditingController();
  bool _includeLocation = true;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.length < 3) {
      setState(() => _error = 'Please describe what happened.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });

    double? lat;
    double? lng;
    if (_includeLocation) {
      try {
        final enabled = await Geolocator.isLocationServiceEnabled();
        final perm = await Geolocator.checkPermission();
        if (enabled && (perm == LocationPermission.always || perm == LocationPermission.whileInUse)) {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
          ).timeout(const Duration(seconds: 8));
          lat = pos.latitude;
          lng = pos.longitude;
        }
      } catch (_) {
        // The report is still sent without a location.
      }
    }

    final raw = widget.deliveryRequestId;
    final requestId = raw is int ? raw : int.tryParse('${raw ?? ''}');

    try {
      await Supabase.instance.client.from('emergency_reports').insert({
        'category': _category,
        'message': text,
        'delivery_request_id': requestId,
        'latitude': lat,
        'longitude': lng,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not send the report. Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
                SizedBox(width: 8),
                Text('Report an emergency', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'This goes straight to the admin so they can help and warn customers.',
              style: TextStyle(color: Colors.black54, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final entry in emergencyCategories.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: _category == entry.key,
                    selectedColor: Colors.red.shade100,
                    onSelected: (_) => setState(() => _category = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _message,
              maxLines: 4,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'What happened? Do you need help? How long will the delay be?',
                border: OutlineInputBorder(),
              ),
            ),
            CheckboxListTile(
              value: _includeLocation,
              onChanged: _sending ? null : (v) => setState(() => _includeLocation = v ?? true),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Include my current location', style: TextStyle(fontSize: 14)),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send),
                label: const Text('Send to admin', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
