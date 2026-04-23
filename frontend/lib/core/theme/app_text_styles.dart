import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 与设计稿对齐的页面级标题（AppBar 与主要区块标题统一）。
abstract final class AppTextStyles {
  static const TextStyle appBarTitle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: AppColors.onSurface,
  );

  static const TextStyle homeSectionTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: AppColors.onSurface,
  );
}
