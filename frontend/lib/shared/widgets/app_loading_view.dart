import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// 全屏或区域内居中加载指示。
class AppLoadingView extends StatelessWidget {
  const AppLoadingView({
    super.key,
    this.message = '加载中…',
    this.fill = true,
  });

  final String message;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final body = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.onSurfaceVariant,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
    if (fill) {
      return ColoredBox(color: AppColors.surface, child: body);
    }
    return body;
  }
}
