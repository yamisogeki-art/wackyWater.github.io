import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../utils/validators.dart';

export '../utils/validators.dart';

/// White, thin-bordered text field style used across the mockups
/// (login, household information, driver login).
InputDecoration outlinedField({
  String? hint,
  String? labelText,
  String? suffixText,
  Widget? suffixIcon,
  Widget? prefixIcon,
  double radius = 10,
}) {
  OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    labelText: labelText,
    hintText: hint,
    hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
    suffixText: suffixText,
    suffixStyle: const TextStyle(color: AppColors.textMuted, fontSize: 15),
    suffixIcon: suffixIcon,
    prefixIcon: prefixIcon,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: border(AppColors.border),
    enabledBorder: border(AppColors.border),
    focusedBorder: border(AppColors.primary, 1.5),
    errorBorder: border(Colors.red.shade300),
    focusedErrorBorder: border(Colors.red, 1.5),
    errorMaxLines: 2,
  );
}

/// Small label that sits above a field.
class FieldLabel extends StatelessWidget {
  final String text;
  const FieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF4B5563)),
      ),
    );
  }
}

/// Form input field with integrated error validation handling & input formatters.
class ValidatedFormField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? Function(String?)? validator;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffixIcon;
  final Widget? prefixIcon;
  final ValueChanged<String>? onChanged;

  const ValidatedFormField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.validator,
    this.inputFormatters,
    this.keyboardType,
    this.obscureText = false,
    this.suffixIcon,
    this.prefixIcon,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty) FieldLabel(label),
        TextFormField(
          controller: controller,
          validator: validator,
          inputFormatters: inputFormatters,
          keyboardType: keyboardType,
          obscureText: obscureText,
          onChanged: onChanged,
          decoration: outlinedField(
            hint: hint,
            suffixIcon: suffixIcon,
            prefixIcon: prefixIcon,
          ),
        ),
      ],
    );
  }
}
