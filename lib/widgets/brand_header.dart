import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Water-drop logo + "WACKY WATER" wordmark + tagline (login, home).
class BrandHeader extends StatelessWidget {
  final double iconSize;
  final double titleSize;
  const BrandHeader({super.key, this.iconSize = 58, this.titleSize = 28});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF7DD3FC), AppColors.primary],
          ).createShader(rect),
          child: Icon(Icons.water_drop, size: iconSize, color: Colors.white),
        ),
        const SizedBox(height: 4),
        Text(
          'WACKY WATER',
          style: TextStyle(
            fontSize: titleSize,
            fontWeight: FontWeight.w900,
            color: AppColors.primary,
            letterSpacing: 0.5,
          ),
        ),
        const Text(
          'Pure Water, Delivered to You',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      ],
    );
  }
}
