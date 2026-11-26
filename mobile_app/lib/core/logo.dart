import 'package:flutter/material.dart';
import 'theme.dart';

/// Executive Lapis Suites Monogram Mark (strict 3-color Lapis Navy palette)
class LapisLogo extends StatelessWidget {
  final double size;
  final bool isDark;

  const LapisLogo({super.key, this.size = 38, this.isDark = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDark ? C.navy : C.surface,
        borderRadius: BorderRadius.circular(size * 0.24),
        border: Border.all(
          color: isDark ? C.navyBorder : C.border,
          width: 1,
        ),
      ),
      child: Center(
        child: Text(
          'L',
          style: flex(
            size * 0.48,
            color: isDark ? Colors.white : C.navy,
            weight: FontWeight.w700,
            height: 1.0,
            letterSpacing: -0.5,
          ),
        ),
      ),
    );
  }
}
