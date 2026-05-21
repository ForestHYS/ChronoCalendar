import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// 标签可选色板（任务编辑、标签管理共用）。
abstract final class TagColorPalette {
  static const int maxNameLength = 20;

  static List<Color> get colors => [
        ...AppColors.chartTagColors,
        const Color(0xFF10B981),
        const Color(0xFFEC4899),
        const Color(0xFF78716C),
        const Color(0xFF0EA5E9),
        const Color(0xFFA855F7),
        AppColors.primary,
        AppColors.success,
        AppColors.warning,
        AppColors.error,
      ];
}
