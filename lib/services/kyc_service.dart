import 'dart:io';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FaceCheckResult {
  final bool ok;
  final String message;
  const FaceCheckResult(this.ok, this.message);
}

enum FaceChallenge { neutral, smile, idPhoto }

class KycService {
  KycService._();

  static final _sb = Supabase.instance.client;
  static const _bucket = 'kyc-documents';
  static const _pendingKey = 'kyc_pending';

  // ---------------------------------------------------------------
  // On-device face checks (ML Kit). Detects faces + basic liveness
  // challenges. It does NOT compare the selfie to the ID photo.
  // ---------------------------------------------------------------
  static Future<FaceCheckResult> checkFace(
      File image,
      FaceChallenge challenge,
      ) async {
    final detector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true, // smile + eyes open probabilities
        performanceMode: FaceDetectorMode.accurate,
        minFaceSize: 0.2,
      ),
    );

    try {
      final faces =
      await detector.processImage(InputImage.fromFile(image));

      if (faces.isEmpty) {
        return const FaceCheckResult(false, 'No face detected. Try again in better light.');
      }
      if (faces.length > 1) {
        return const FaceCheckResult(false, 'Only one face should be in the photo.');
      }

      final face = faces.first;

      // The ID photo is usually small / printed, so skip strict checks.
      if (challenge == FaceChallenge.idPhoto) {
        return const FaceCheckResult(true, 'Face found on ID.');
      }

      final yaw = face.headEulerAngleY ?? 0;
      if (yaw.abs() > 15) {
        return const FaceCheckResult(false, 'Please look straight at the camera.');
      }

      final left = face.leftEyeOpenProbability ?? 1;
      final right = face.rightEyeOpenProbability ?? 1;
      if (left < 0.5 || right < 0.5) {
        return const FaceCheckResult(false, 'Please keep both eyes open.');
      }

      final smile = face.smilingProbability ?? 0;
      if (challenge == FaceChallenge.smile && smile < 0.7) {
        return const FaceCheckResult(false, 'Please give a clear smile.');
      }
      if (challenge == FaceChallenge.neutral && smile > 0.5) {
        return const FaceCheckResult(false, 'Please keep a neutral face for this one.');
      }

      return const FaceCheckResult(true, 'Looks good!');
    } finally {
      await detector.close();
    }
  }

  // ---------------------------------------------------------------
  // Upload to private Supabase Storage + create submission row
  // ---------------------------------------------------------------
  static Future<void> submit({
    required String userId,
    required String idType,
    required File idImage,
    required File selfie,
    required File smileSelfie,
  }) async {
    Future<String> upload(File file, String name) async {
      final path = '$userId/$name.jpg';
      await _sb.storage.from(_bucket).upload(
        path,
        file,
        fileOptions:
        const FileOptions(upsert: true, contentType: 'image/jpeg'),
      );
      return path;
    }

    final idPath = await upload(idImage, 'id');
    final selfiePath = await upload(selfie, 'selfie');
    final smilePath = await upload(smileSelfie, 'selfie_smile');

    await _sb.from('kyc_submissions').upsert({
      'user_id': userId,
      'id_type': idType,
      'id_image_path': idPath,
      'selfie_path': selfiePath,
      'selfie_smile_path': smilePath,
      'status': 'pending',
    });

    // Ask the server to compare the faces. If it fails (offline, AWS not
    // configured yet), the submission simply stays 'pending' for manual review.
    try {
      await _sb.functions.invoke('kyc-verify');
    } catch (_) {}
  }

  // ---------------------------------------------------------------
  // If email confirmation is ON, signUp returns no session, so the
  // upload must wait until the user signs in. Keep the files locally.
  // ---------------------------------------------------------------
  static Future<void> savePending({
    required String idType,
    required File idImage,
    required File selfie,
    required File smileSelfie,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    Future<String> keep(File f, String name) async =>
        (await f.copy(p.join(dir.path, 'kyc_$name.jpg'))).path;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_pendingKey, [
      idType,
      await keep(idImage, 'id'),
      await keep(selfie, 'selfie'),
      await keep(smileSelfie, 'smile'),
    ]);
  }

  /// Call this right after a successful login (e.g. in your auth listener).
  static Future<void> submitPendingIfAny() async {
    final user = _sb.auth.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList(_pendingKey);
    if (data == null || data.length != 4) return;

    await submit(
      userId: user.id,
      idType: data[0],
      idImage: File(data[1]),
      selfie: File(data[2]),
      smileSelfie: File(data[3]),
    );

    for (final path in data.skip(1)) {
      final f = File(path);
      if (await f.exists()) await f.delete();
    }
    await prefs.remove(_pendingKey);
  }
}