import 'package:flutter/material.dart';

/// Shared design tokens for the app. One brand color, one accent per
/// role, and a small status palette used consistently for order/payment
/// states everywhere.
///
/// The brand blue and the greens below were sampled directly from the
/// thesis mockup screenshots so the app matches them.
class AppColors {
  // Brand
  static const Color primary = Color(0xFF1C5FD6); // sampled from the mockups
  static const Color primaryLight = Color(0xFFE6EFFE);
  static const Color background = Colors.white;
  static const Color surface = Colors.white;
  static const Color textDark = Color(0xFF111827);
  static const Color textMuted = Color(0xFF6B7280);
  static const Color border = Color(0xFFE5E7EB);
  static const Color panelGray = Color(0xFFF3F5F9);

  // Success / confirmation (order placed, delivered, total price box)
  static const Color successGreen = Color(0xFF16A34A);
  static const Color successBg = Color(0xFFEAFBEF);
  static const Color successText = Color(0xFF14532D);

  // Driver navigation banner
  static const Color navGreen = Color(0xFF15804C);

  // Numbered delivery stops: 1st = green, 2nd = orange, 3rd = red, rest = gray
  static const List<Color> _stopColors = [
    Color(0xFF16A34A),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
  ];
  static const Color stopDefault = Color(0xFF9CA3AF);
  static Color stopColor(int index) =>
      index >= 0 && index < _stopColors.length ? _stopColors[index] : stopDefault;

  // Role accents - used for that role's app bar / highlight color
  static const Color customerAccent = primary;
  static const Color driverAccent = Color(0xFFE65100); // still used on live-tracking markers
  static const Color adminAccent = Color(0xFF00695C); // teal - "control room"

  // Status colors, used the same way everywhere a status badge appears
  static const Color statusPending = Color(0xFFF57C00);
  static const Color statusPendingBg = Color(0xFFFFF3E0);
  static const Color statusInTransit = Color(0xFF1976D2);
  static const Color statusInTransitBg = Color(0xFFE3F2FD);
  static const Color statusDelivered = Color(0xFF2E7D32);
  static const Color statusDeliveredBg = Color(0xFFE8F5E9);
  static const Color statusCredit = Color(0xFFC62828);
  static const Color statusCreditBg = Color(0xFFFFEBEE);
}
