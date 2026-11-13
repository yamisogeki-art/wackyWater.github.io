import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/kyc_service.dart';
import '../../theme/app_colors.dart';

/// Standalone identity verification (ID photo + two selfies) for customers
/// who registered before KYC existed, or whose submission was rejected.
/// Pops with `true` after a successful submission.
class KycSubmitScreen extends StatefulWidget {
  const KycSubmitScreen({super.key});

  @override
  State<KycSubmitScreen> createState() => _KycSubmitScreenState();
}

class _KycSubmitScreenState extends State<KycSubmitScreen> {
  static const _idTypes = [
    'Philippine National ID (PhilSys)',
    "Driver's License",
    'Passport',
    'UMID',
    'Postal ID',
    "Voter's ID",
    'PRC ID',
  ];

  final _picker = ImagePicker();
  String _idType = _idTypes.first;
  File? _id;
  File? _selfie;
  File? _smile;
  bool _busy = false;
  String? _error;

  Future<void> _pickId(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, maxWidth: 1920, imageQuality: 85);
    if (picked == null) return;
    setState(() { _busy = true; _error = null; });
    final file = File(picked.path);
    final result = await KycService.checkFace(file, FaceChallenge.idPhoto);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.ok) {
        _id = file;
      } else {
        _id = null;
        _error = 'We could not find a clear face photo on your ID. Retake it with the whole ID visible and no glare.';
      }
    });
  }

  Future<void> _selfieCapture(FaceChallenge challenge) async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      maxWidth: 1280,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() { _busy = true; _error = null; });
    final file = File(picked.path);
    final result = await KycService.checkFace(file, challenge);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.ok) {
        if (challenge == FaceChallenge.neutral) {
          _selfie = file;
        } else {
          _smile = file;
        }
      } else {
        _error = result.message;
      }
    });
  }

  Future<void> _submit() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || _id == null || _selfie == null || _smile == null) {
      setState(() => _error = 'Please add your ID and both selfies.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await KycService.submit(
        userId: user.id,
        idType: _idType,
        idImage: _id!,
        selfie: _selfie!,
        smileSelfie: _smile!,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Upload failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _photo(File? f, String hint, IconData icon, double h) => Container(
    height: h,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: f != null ? const Color(0xFF10B981) : const Color(0xFFE2E8F0), width: f != null ? 2 : 1),
    ),
    clipBehavior: Clip.antiAlias,
    child: f != null
        ? Image.file(f, fit: BoxFit.cover, width: double.infinity)
        : Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 36, color: const Color(0xFF94A3B8)),
      const SizedBox(height: 6),
      Text(hint, style: const TextStyle(color: Color(0xFF64748B), fontSize: 13)),
    ])),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: const Text('Verify your identity')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text(
              'To order water you need a verified account. Upload a valid government ID and two selfies. Use good lighting and look straight at the camera.',
              style: TextStyle(color: Color(0xFF475569), fontSize: 13),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              value: _idType,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'ID type',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              items: _idTypes.map((t) => DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => setState(() => _idType = v ?? _idType),
            ),
            const SizedBox(height: 16),
            _photo(_id, 'No ID photo yet', Icons.credit_card, 170),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pickId(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined), label: const Text('Take photo'))),
              const SizedBox(width: 12),
              Expanded(child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pickId(ImageSource.gallery),
                  icon: const Icon(Icons.upload_file_outlined), label: const Text('Upload'))),
            ]),
            const SizedBox(height: 20),
            const Text('Neutral face', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _photo(_selfie, 'Neutral selfie', Icons.face_outlined, 150),
            const SizedBox(height: 8),
            OutlinedButton.icon(
                onPressed: _busy ? null : () => _selfieCapture(FaceChallenge.neutral),
                icon: const Icon(Icons.photo_camera_front_outlined),
                label: Text(_selfie == null ? 'Take selfie' : 'Retake')),
            const SizedBox(height: 16),
            const Text('Smile', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _photo(_smile, 'Smiling selfie', Icons.sentiment_satisfied_alt_outlined, 150),
            const SizedBox(height: 8),
            OutlinedButton.icon(
                onPressed: _busy ? null : () => _selfieCapture(FaceChallenge.smile),
                icon: const Icon(Icons.photo_camera_front_outlined),
                label: Text(_smile == null ? 'Take selfie' : 'Retake')),
            if (_error != null) Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(_error!, textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w500)),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('SUBMIT FOR VERIFICATION', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}