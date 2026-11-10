import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reusable input validators with user-friendly error prompts.
class InputValidators {
  /// Ensures field is not empty or whitespace only.
  static String? required(String? value, {String fieldName = 'This field'}) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required. Please try again.';
    }
    return null;
  }

  /// Validates letters and spaces only (alphabetic).
  static String? lettersOnly(String? value, {String fieldName = 'This field'}) {
    final req = required(value, fieldName: fieldName);
    if (req != null) return req;

    final trimmed = value!.trim();
    final regex = RegExp(r'^[a-zA-Z\s]+$');
    if (!regex.hasMatch(trimmed)) {
      return '$fieldName must contain letters only. Please try again.';
    }
    return null;
  }

  /// Validates numbers only (digits).
  static String? numbersOnly(String? value, {String fieldName = 'This field'}) {
    final req = required(value, fieldName: fieldName);
    if (req != null) return req;

    final trimmed = value!.trim();
    final regex = RegExp(r'^[0-9]+$');
    if (!regex.hasMatch(trimmed)) {
      return '$fieldName must contain numbers only. Please try again.';
    }
    return null;
  }

  /// Validates letters and numbers only (alphanumeric), with optional spaces.
  static String? alphanumeric(
    String? value, {
    String fieldName = 'This field',
    bool allowSpaces = true,
  }) {
    final req = required(value, fieldName: fieldName);
    if (req != null) return req;

    final trimmed = value!.trim();
    final pattern = allowSpaces ? r'^[a-zA-Z0-9\s]+$' : r'^[a-zA-Z0-9]+$';
    final regex = RegExp(pattern);
    if (!regex.hasMatch(trimmed)) {
      return '$fieldName must contain letters and numbers only. Please try again.';
    }
    return null;
  }

  /// Validates numeric / decimal values.
  static String? decimalNumber(
    String? value, {
    String fieldName = 'This field',
    double? min,
    double? max,
  }) {
    final req = required(value, fieldName: fieldName);
    if (req != null) return req;

    final trimmed = value!.trim();
    final parsed = double.tryParse(trimmed);
    if (parsed == null) {
      return 'Please enter a valid number for $fieldName. Please try again.';
    }

    if (min != null && parsed < min) {
      return '$fieldName must be at least $min. Please try again.';
    }

    if (max != null && parsed > max) {
      return '$fieldName cannot exceed $max. Please try again.';
    }

    return null;
  }

  /// Validates standard email address format.
  static String? email(String? value) {
    final req = required(value, fieldName: 'Email address');
    if (req != null) return req;

    final trimmed = value!.trim();
    final regex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    if (!regex.hasMatch(trimmed)) {
      return 'Please enter a valid email address (e.g. user@example.com). Please try again.';
    }
    return null;
  }

  /// Validates phone numbers (10 to 13 digits, optional + prefix).
  static String? phone(String? value) {
    final req = required(value, fieldName: 'Phone number');
    if (req != null) return req;

    final trimmed = value!.trim();
    final regex = RegExp(r'^\+?[0-9]{10,13}$');
    if (!regex.hasMatch(trimmed)) {
      return 'Please enter a valid phone number (10-13 digits). Please try again.';
    }
    return null;
  }

  /// Validates minimum character length.
  static String? minLength(
    String? value,
    int min, {
    String fieldName = 'This field',
  }) {
    if (value == null || value.trim().length < min) {
      return '$fieldName must be at least $min characters long. Please try again.';
    }
    return null;
  }

  /// Validates maximum character length.
  static String? maxLength(
    String? value,
    int max, {
    String fieldName = 'This field',
  }) {
    if (value != null && value.trim().length > max) {
      return '$fieldName cannot exceed $max characters. Please try again.';
    }
    return null;
  }

  /// Validates password strength (min 8 chars, 1 uppercase, 1 lowercase, 1 number, 1 special char).
  static String? password(String? value) {
    final req = required(value, fieldName: 'Password');
    if (req != null) return req;

    if (value!.length < 8) {
      return 'Password must be at least 8 characters long. Please try again.';
    }
    if (!value.contains(RegExp(r'[A-Z]'))) {
      return 'Password must contain at least one uppercase letter (A-Z). Please try again.';
    }
    if (!value.contains(RegExp(r'[a-z]'))) {
      return 'Password must contain at least one lowercase letter (a-z). Please try again.';
    }
    if (!value.contains(RegExp(r'[0-9]'))) {
      return 'Password must contain at least one number (0-9). Please try again.';
    }
    if (!value.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
      return 'Password must contain at least one special character (!@#\$%). Please try again.';
    }
    return null;
  }

  /// Combines multiple validator functions in sequence.
  static String? Function(String?) combine(
    List<String? Function(String?)> validators,
  ) {
    return (String? value) {
      for (final validator in validators) {
        final error = validator(value);
        if (error != null) return error;
      }
      return null;
    };
  }
}

/// Helper input formatters to enforce letter-only, number-only, or alphanumeric typing.
class InputFormatters {
  /// Denies non-letter characters (allows letters A-Z, a-z and spaces).
  static TextInputFormatter get lettersOnly =>
      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]'));

  /// Denies non-digit characters (allows digits 0-9).
  static TextInputFormatter get numbersOnly =>
      FilteringTextInputFormatter.digitsOnly;

  /// Denies non-alphanumeric characters (allows letters, numbers, spaces).
  static TextInputFormatter get alphanumeric =>
      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\s]'));

  /// Allows decimal numbers (digits and single decimal point).
  static TextInputFormatter get decimal =>
      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'));
}

/// General App & Form Error Handler for showing alerts and retry prompts.
class InputErrorHandler {
  /// Displays a SnackBar with an error message and a retry action.
  static void showErrorSnackBar(
    BuildContext context,
    String message, {
    VoidCallback? onRetry,
  }) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: Text(
          message,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        ),
        action: onRetry != null
            ? SnackBarAction(
                label: 'TRY AGAIN',
                textColor: Colors.yellowAccent,
                onPressed: onRetry,
              )
            : SnackBarAction(
                label: 'OK',
                textColor: Colors.white,
                onPressed: () {},
              ),
      ),
    );
  }

  /// Displays a retry alert dialog when user input or operations fail.
  static Future<void> showRetryDialog(
    BuildContext context, {
    String title = 'Input Error',
    required String message,
    VoidCallback? onRetry,
  }) async {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(fontSize: 14, color: Color(0xFF334155)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(dialogContext);
              if (onRetry != null) onRetry();
            },
            child: const Text('Try Again', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// Transforms raw exceptions into readable error prompt strings.
  static String parseError(dynamic error) {
    if (error == null) return 'An error occurred. Please try again.';
    final str = error.toString();
    if (str.contains('network') || str.contains('SocketException')) {
      return 'Network error detected. Please check your connection and try again.';
    }
    if (str.contains('Invalid input')) {
      return 'Invalid input format. Please try again.';
    }
    return str.replaceAll('Exception: ', '');
  }
}
