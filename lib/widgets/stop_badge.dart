import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Numbered circle for a delivery stop: 1 = green, 2 = orange, 3 = red,
/// everything after = gray (same colors on the list and the map).
class StopBadge extends StatelessWidget {
  final int index; // zero-based
  final double size;
  const StopBadge({super.key, required this.index, this.size = 32});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.stopColor(index),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Text(
        '${index + 1}',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.42),
      ),
    );
  }
}
