import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/kyc_service.dart';
import '../../utils/validators.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static const _primary = Color(0xFF0284C7);
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

  int _step = 0; // 0 = account, 1 = ID, 2 = face
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;

  // KYC state
  String _idType = _idTypes.first;
  File? _idImage;
  File? _selfie;
  File? _smileSelfie;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_onPasswordChanged);
  }

  void _onPasswordChanged() => setState(() {});

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
  bool get _hasSpecialChar =>
      _passwordController.text.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));

  bool get _isPasswordStrong =>
      _hasMinLength && _hasUppercase && _hasLowercase && _hasNumber && _hasSpecialChar;

  // ---------------- Step navigation ----------------

  void _nextFromAccount() {
    if (!_formKey.currentState!.validate()) return;
    if (!_isPasswordStrong) {
      setState(() => _errorMessage =
          'Please meet all strong password requirements before continuing.');
      return;
    }
    setState(() {
      _errorMessage = null;
      _step = 1;
    });
  }

  void _nextFromId() {
    if (_idImage == null) {
      setState(() => _errorMessage = 'Please upload a photo of your valid ID.');
      return;
    }
    setState(() {
      _errorMessage = null;
      _step = 2;
    });
  }

  void _back() {
    if (_step == 0) {
      Navigator.pop(context);
    } else {
      setState(() {
        _errorMessage = null;
        _step--;
      });
    }
  }

  // ---------------- KYC capture ----------------

  Future<void> _pickId(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 1920,
      imageQuality: 85,
    );
    if (picked == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final file = File(picked.path);
    final result = await KycService.checkFace(file, FaceChallenge.idPhoto);

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result.ok) {
        _idImage = file;
      } else {
        _idImage = null;
        _errorMessage =
            'We could not find a clear face photo on your ID. Retake it with the whole ID visible and no glare.';
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
      _isLoading = true;
      _errorMessage = null;
    });

    final file = File(picked.path);
    final result = await KycService.checkFace(file, challenge);

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result.ok) {
        if (challenge == FaceChallenge.neutral) {
          _selfie = file;
        } else {
          _smileSelfie = file;
        }
      } else {
        _errorMessage = result.message;
      }
    });
  }

  // ---------------- Register (faces must match the ID) ----------------

  Future<void> _register() async {
    if (_idImage == null || _selfie == null || _smileSelfie == null) {
      setState(() => _errorMessage = 'Please add your ID and both face photos.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // The server compares the neutral face, the smiling face and the ID photo,
    // and only creates the account if all of them show the same person.
    final result = await KycService.registerCustomer(
      fullName: _nameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
      idType: _idType,
      idImage: _idImage!,
      selfie: _selfie!,
      smileSelfie: _smileSelfie!,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!result.ok) {
      setState(() => _errorMessage = result.message);
      return;
    }

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
              'Account Created!',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ],
        ),
        content: const Text(
          'Your face matched your ID. Welcome to Wacky Water! You can log in now.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Color(0xFF475569)),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
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
  }

  // ---------------- UI helpers ----------------

  InputDecoration _fieldDecoration(String label, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: Colors.white,
      suffixIcon: suffix,
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

  Widget _stepIndicator() {
    const labels = ['Account', 'ID', 'Face'];
    return Row(
      children: List.generate(3, (i) {
        final active = i <= _step;
        return Expanded(
          child: Column(
            children: [
              Container(
                height: 4,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: active ? _primary : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                labels[i],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                  color: active ? _primary : const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _photoBox({
    required File? file,
    required String placeholder,
    required IconData icon,
    double height = 180,
  }) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: file != null ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
          width: file != null ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: file != null
          ? Image.file(file, fit: BoxFit.cover, width: double.infinity)
          : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 40, color: const Color(0xFF94A3B8)),
                  const SizedBox(height: 8),
                  Text(placeholder,
                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                ],
              ),
            ),
    );
  }

  Widget _primaryButton(String label, VoidCallback? onPressed) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: _isLoading ? null : onPressed,
        child: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Text(label,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
      ),
    );
  }

  // ---------------- Steps ----------------

  Widget _accountStep() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            inputFormatters: [InputFormatters.lettersOnly],
            decoration: _fieldDecoration('Full name (as shown on your ID)', Icons.person_outline),
            validator: (v) => InputValidators.lettersOnly(v, fieldName: 'Full name'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: _fieldDecoration('Email address', Icons.email_outlined),
            validator: (v) => InputValidators.email(v),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: _fieldDecoration(
              'Password',
              Icons.lock_outline,
              suffix: IconButton(
                icon: Icon(_obscurePassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
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
                  const Text(
                    'Password Strength Requirements:',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                  ),
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
          TextFormField(
            controller: _confirmController,
            obscureText: _obscureConfirmPassword,
            decoration: _fieldDecoration(
              'Confirm password',
              Icons.lock_outline,
              suffix: IconButton(
                icon: Icon(_obscureConfirmPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: () =>
                    setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
            ),
            validator: (v) =>
                v != _passwordController.text ? 'Passwords do not match. Please try again.' : null,
          ),
          if (_errorMessage != null) _errorText(),
          const SizedBox(height: 24),
          _primaryButton('Next: Upload ID', _nextFromAccount),
        ],
      ),
    );
  }

  Widget _idStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Upload a clear photo of a valid government-issued ID. Make sure all four corners are visible, the text is readable, and there is no glare.',
          style: TextStyle(color: Color(0xFF475569), fontSize: 13),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _idType,
          decoration: _fieldDecoration('ID type', Icons.badge_outlined),
          items: _idTypes
              .map((t) => DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: (v) => setState(() => _idType = v ?? _idType),
          isExpanded: true,
        ),
        const SizedBox(height: 16),
        _photoBox(file: _idImage, placeholder: 'No ID photo yet', icon: Icons.credit_card),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : () => _pickId(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Take photo'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : () => _pickId(ImageSource.gallery),
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Upload'),
              ),
            ),
          ],
        ),
        if (_errorMessage != null) _errorText(),
        const SizedBox(height: 24),
        _primaryButton('Next: Face Verification', _nextFromId),
      ],
    );
  }

  Widget _faceStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Take a neutral selfie and a smiling selfie. Your account is created only if both faces match the photo on your ID. Use good lighting, remove glasses/masks/hats, and look straight at the camera.',
          style: TextStyle(color: Color(0xFF475569), fontSize: 13),
        ),
        const SizedBox(height: 16),
        const Text('1. Neutral face',
            style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF334155))),
        const SizedBox(height: 8),
        _photoBox(
            file: _selfie, placeholder: 'Neutral selfie', icon: Icons.face_outlined, height: 160),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _isLoading ? null : () => _captureSelfie(FaceChallenge.neutral),
          icon: const Icon(Icons.photo_camera_front_outlined),
          label: Text(_selfie == null ? 'Take selfie' : 'Retake'),
        ),
        const SizedBox(height: 16),
        const Text('2. Smile',
            style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF334155))),
        const SizedBox(height: 8),
        _photoBox(
            file: _smileSelfie,
            placeholder: 'Smiling selfie',
            icon: Icons.sentiment_satisfied_alt_outlined,
            height: 160),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _isLoading ? null : () => _captureSelfie(FaceChallenge.smile),
          icon: const Icon(Icons.photo_camera_front_outlined),
          label: Text(_smileSelfie == null ? 'Take selfie' : 'Retake'),
        ),
        if (_errorMessage != null) _errorText(),
        const SizedBox(height: 24),
        _primaryButton('Create Account', _register),
      ],
    );
  }

  Widget _errorText() {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Text(
        _errorMessage!,
        style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w500),
        textAlign: TextAlign.center,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['Join Wacky Water', 'Verify Your ID', 'Face Verification'];
    final subtitles = [
      'Create a customer account to order water refills',
      'Step 2 of 3: identity document',
      'Step 3 of 3: confirm it is really you',
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Create Account'),
        leading: BackButton(onPressed: _isLoading ? null : _back),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _stepIndicator(),
                const SizedBox(height: 20),
                const Icon(Icons.water_drop_rounded, size: 56, color: _primary),
                const SizedBox(height: 12),
                Text(
                  titles[_step],
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF0F172A),
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitles[_step],
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: const Color(0xFF64748B)),
                ),
                const SizedBox(height: 24),
                if (_step == 0) _accountStep(),
                if (_step == 1) _idStep(),
                if (_step == 2) _faceStep(),
                const SizedBox(height: 14),
                if (_step == 0)
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
