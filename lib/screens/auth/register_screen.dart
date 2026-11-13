import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../constants/auth_config.dart';
import '../../services/kyc_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/validators.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static const _idTypes = [
    'Philippine National ID (PhilSys)',
    "Driver's License",
    'Passport',
    'UMID',
    'Postal ID',
    "Voter's ID",
    'PRC ID',
  ];

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _picker = ImagePicker();

  int _currentStep = 0; // 0: Account Info, 1: Valid ID Upload, 2: Face Selfies
  bool _isLoading = false;
  bool _isCheckingFace = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;

  // Step 2 & 3 KYC State
  String _idType = _idTypes.first;
  File? _idFile;
  File? _neutralSelfie;
  File? _smileSelfie;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_onPasswordChanged);
  }

  void _onPasswordChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _passwordController.removeListener(_onPasswordChanged);
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  // Password Strength Helpers
  bool get _hasMinLength => _passwordController.text.length >= 8;
  bool get _hasUppercase => _passwordController.text.contains(RegExp(r'[A-Z]'));
  bool get _hasLowercase => _passwordController.text.contains(RegExp(r'[a-z]'));
  bool get _hasNumber => _passwordController.text.contains(RegExp(r'[0-9]'));
  bool get _hasSpecialChar => _passwordController.text.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));

  bool get _isPasswordStrong =>
      _hasMinLength && _hasUppercase && _hasLowercase && _hasNumber && _hasSpecialChar;

  // On-Device Face Detection Checks
  Future<void> _pickIdPhoto(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, maxWidth: 1920, imageQuality: 85);
    if (picked == null) return;

    setState(() {
      _isCheckingFace = true;
      _errorMessage = null;
    });

    final file = File(picked.path);
    final result = await KycService.checkFace(file, FaceChallenge.idPhoto);
    if (!mounted) return;

    setState(() {
      _isCheckingFace = false;
      if (result.ok) {
        _idFile = file;
      } else {
        _idFile = null;
        _errorMessage = 'We could not detect a clear face on your ID. Retake with whole ID visible.';
      }
    });
  }

  Future<void> _captureSelfie(FaceChallenge challenge) async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      maxWidth: 1280,
      imageQuality: 85,
    );
    if (picked == null) return;

    setState(() {
      _isCheckingFace = true;
      _errorMessage = null;
    });

    final file = File(picked.path);
    final result = await KycService.checkFace(file, challenge);
    if (!mounted) return;

    setState(() {
      _isCheckingFace = false;
      if (result.ok) {
        if (challenge == FaceChallenge.neutral) {
          _neutralSelfie = file;
        } else {
          _smileSelfie = file;
        }
      } else {
        _errorMessage = result.message;
      }
    });
  }

  void _nextStep() {
    setState(() => _errorMessage = null);

    if (_currentStep == 0) {
      if (!_formKey.currentState!.validate()) return;
      if (!_isPasswordStrong) {
        setState(() => _errorMessage = 'Please meet all password strength requirements before continuing.');
        return;
      }
      setState(() => _currentStep = 1);
    } else if (_currentStep == 1) {
      if (_idFile == null) {
        setState(() => _errorMessage = 'Please upload a photo of your valid government ID.');
        return;
      }
      setState(() => _currentStep = 2);
    }
  }

  Future<void> _submitRegistration() async {
    if (_idFile == null || _neutralSelfie == null || _smileSelfie == null) {
      setState(() => _errorMessage = 'Please complete your ID photo and both selfies before submitting.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        emailRedirectTo: appRedirectUrl,
        data: {
          'full_name': _nameController.text.trim(),
          'role': 'customer',
        },
      );

      final user = response.user ?? Supabase.instance.client.auth.currentUser;

      if (user != null && response.session != null) {
        // Immediate Upload if session exists
        await KycService.submit(
          userId: user.id,
          idType: _idType,
          idImage: _idFile!,
          selfie: _neutralSelfie!,
          smileSelfie: _smileSelfie!,
        );
      } else {
        // Save locally for upload upon email confirmation login (Flowchart Figure 1)
        await KycService.savePending(
          idType: _idType,
          idImage: _idFile!,
          selfie: _neutralSelfie!,
          smileSelfie: _smileSelfie!,
        );
      }

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Column(
            children: [
              Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 64),
              SizedBox(height: 12),
              Text(
                'Registration Submitted!',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
              ),
            ],
          ),
          content: Text(
            response.session == null
                ? 'Your account and ID verification photos were saved successfully! Please check your email to confirm before logging in.'
                : 'Welcome to Wacky Water! Your account and identity verification have been submitted for review.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Color(0xFF475569)),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.pop(dialogContext);
                  if (mounted) Navigator.pop(context);
                },
                child: const Text(
                  'Continue to Login',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      );
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Registration failed. Please check network connection.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildStepHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _stepIndicator(0, '1. Account'),
          const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
          _stepIndicator(1, '2. Valid ID'),
          const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
          _stepIndicator(2, '3. Selfies'),
        ],
      ),
    );
  }

  Widget _stepIndicator(int step, String label) {
    final active = _currentStep == step;
    final done = _currentStep > step;
    return Row(
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: done
              ? const Color(0xFF10B981)
              : (active ? AppColors.primary : const Color(0xFFCBD5E1)),
          child: done
              ? const Icon(Icons.check, size: 14, color: Colors.white)
              : Text(
                  '${step + 1}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
            color: active ? AppColors.primary : const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildRequirementChip(String label, bool isMet) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          Icon(
            isMet ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 16,
            color: isMet ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isMet ? const Color(0xFF15803D) : const Color(0xFF64748B),
              fontWeight: isMet ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoBox(File? f, String hint, IconData icon, double h) {
    return Container(
      height: h,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: f != null ? const Color(0xFF10B981) : const Color(0xFFCBD5E1),
          width: f != null ? 2 : 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: f != null
          ? Image.file(f, fit: BoxFit.cover, width: double.infinity)
          : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 36, color: const Color(0xFF94A3B8)),
                  const SizedBox(height: 6),
                  Text(hint, style: const TextStyle(color: Color(0xFF64748B), fontSize: 13, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
    );
  }

  Widget _buildStep0AccountInfo() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Full Name
          TextFormField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            inputFormatters: [InputFormatters.lettersOnly],
            decoration: const InputDecoration(
              labelText: 'Full name',
              border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
              prefixIcon: Icon(Icons.person_outline),
              filled: true,
              fillColor: Colors.white,
            ),
            validator: (v) => InputValidators.lettersOnly(v, fieldName: 'Full name'),
          ),
          const SizedBox(height: 16),

          // Email
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email address',
              border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
              prefixIcon: Icon(Icons.email_outlined),
              filled: true,
              fillColor: Colors.white,
            ),
            validator: (v) => InputValidators.email(v),
          ),
          const SizedBox(height: 16),

          // Password
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Password',
              border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
              prefixIcon: const Icon(Icons.lock_outline),
              filled: true,
              fillColor: Colors.white,
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            validator: (v) => InputValidators.password(v),
          ),

          if (_passwordController.text.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Password Strength Requirements:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
                  const SizedBox(height: 4),
                  _buildRequirementChip('At least 8 characters long', _hasMinLength),
                  _buildRequirementChip('Contains uppercase letter (A-Z)', _hasUppercase),
                  _buildRequirementChip('Contains lowercase letter (a-z)', _hasLowercase),
                  _buildRequirementChip('Contains a number (0-9)', _hasNumber),
                  _buildRequirementChip('Contains a special character (!@#\$%)', _hasSpecialChar),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Confirm Password
          TextFormField(
            controller: _confirmController,
            obscureText: _obscureConfirmPassword,
            decoration: InputDecoration(
              labelText: 'Confirm password',
              border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
              prefixIcon: const Icon(Icons.lock_outline),
              filled: true,
              fillColor: Colors.white,
              suffixIcon: IconButton(
                icon: Icon(_obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
            ),
            validator: (v) {
              if (v != _passwordController.text) return 'Passwords do not match. Please try again.';
              return null;
            },
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _nextStep,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Next: Valid ID Photo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward, color: Colors.white, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep1ValidId() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Step 2: Upload Valid Government ID',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
        const SizedBox(height: 4),
        const Text(
          'Select your ID type and photograph your valid government ID. Face must be clearly visible.',
          style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _idType,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Government ID Type',
            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
            filled: true,
            fillColor: Colors.white,
          ),
          items: _idTypes.map((t) => DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) => setState(() => _idType = v ?? _idType),
        ),
        const SizedBox(height: 16),
        _photoBox(_idFile, 'Photograph a valid ID with your face visible', Icons.credit_card, 160),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isCheckingFace ? null : () => _pickIdPhoto(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Take Photo'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isCheckingFace ? null : () => _pickIdPhoto(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Upload'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _currentStep = 0),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isCheckingFace ? null : _nextStep,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Next: Selfies', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                    SizedBox(width: 6),
                    Icon(Icons.arrow_forward, color: Colors.white, size: 18),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStep2Selfies() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Step 3: Verification Selfies',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
        const SizedBox(height: 4),
        const Text(
          'Take a neutral face selfie and a smiling selfie to verify your identity.',
          style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 16),

        // 1. Neutral Face
        const Text('1. Neutral Face Selfie', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 6),
        _photoBox(_neutralSelfie, 'Neutral Face Selfie', Icons.face_outlined, 140),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _isCheckingFace ? null : () => _captureSelfie(FaceChallenge.neutral),
          icon: const Icon(Icons.photo_camera_front_outlined),
          label: Text(_neutralSelfie == null ? 'Take Neutral Selfie' : 'Retake Neutral Selfie'),
        ),

        const SizedBox(height: 16),

        // 2. Smile Selfie
        const Text('2. Smiling Selfie', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 6),
        _photoBox(_smileSelfie, 'Smiling Selfie', Icons.sentiment_satisfied_alt_outlined, 140),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _isCheckingFace ? null : () => _captureSelfie(FaceChallenge.smile),
          icon: const Icon(Icons.photo_camera_front_outlined),
          label: Text(_smileSelfie == null ? 'Take Smiling Selfie' : 'Retake Smiling Selfie'),
        ),

        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _currentStep = 1),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: (_isLoading || _isCheckingFace) ? null : _submitRegistration,
                child: _isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Create Account', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: const Text('Create Account')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.water_drop_rounded, size: 52, color: Color(0xFF0284C7)),
                const SizedBox(height: 8),
                Text(
                  'Join Wacky Water',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF0F172A),
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Customer Account & Identity Verification',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF64748B),
                      ),
                ),
                const SizedBox(height: 16),
                _buildStepHeader(),
                const SizedBox(height: 20),

                if (_isCheckingFace) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 10),
                        Text('Checking photo with face detection...', style: TextStyle(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],

                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                if (_currentStep == 0) _buildStep0AccountInfo(),
                if (_currentStep == 1) _buildStep1ValidId(),
                if (_currentStep == 2) _buildStep2Selfies(),

                const SizedBox(height: 16),
                TextButton(
                  onPressed: _isLoading ? null : () => Navigator.pop(context),
                  child: const Text('Already have an account? Log in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
