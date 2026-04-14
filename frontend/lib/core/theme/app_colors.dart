import 'package:flutter/material.dart';

/// 与 visual-design.md 对齐的浅色 token。
abstract final class AppColors {
  static const Color primary = Color(0xFF2563EB);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFFDBEAFE);
  static const Color surface = Color(0xFFFAFAFA);
  static const Color surfaceContainer = Color(0xFFFFFFFF);
  static const Color surfaceContainerHigh = Color(0xFFF4F4F5);
  static const Color onSurface = Color(0xFF18181B);
  static const Color onSurfaceVariant = Color(0xFF71717A);
  static const Color outline = Color(0xFFE4E4E7);
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFCA8A04);
  static const Color error = Color(0xFFDC2626);

  static const List<Color> chartTagColors = [
    Color(0xFF3B82F6),
    Color(0xFF06B6D4),
    Color(0xFF8B5CF6),
    Color(0xFFF59E0B),
    Color(0xFFF43F5E),
  ];
}

abstract final class AppRadii {
  static const double card = 12;
  static const double chip = 10;
  static const double sheetTop = 16;
}
