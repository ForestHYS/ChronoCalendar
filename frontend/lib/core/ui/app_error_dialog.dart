import 'package:flutter/material.dart';

import '../api/api_exception.dart';
import '../theme/app_colors.dart';

/// 将异常转为适合展示的短文案。
String formatErrorForUser(Object error) {
  if (error is ApiException) {
    return error.message;
  }
  final s = error.toString();
  if (s.startsWith('Exception: ')) return s.substring('Exception: '.length);
  if (s.startsWith('ArgumentError: ')) return s.substring('ArgumentError: '.length);
  if (s.startsWith('Invalid argument(s): ')) return s.substring('Invalid argument(s): '.length);
  return s;
}

/// 带图标与圆角的错误提示弹窗（替代底部 SnackBar）。
Future<void> showAppErrorDialog(
  BuildContext context, {
  String title = '操作失败',
  required Object error,
}) {
  final message = formatErrorForUser(error);
  final code = error is ApiException ? error.code : null;

  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: AppColors.surfaceContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadii.card),
                    ),
                    child: const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.onSurface,
                            height: 1.25,
                          ),
                        ),
                        if (code != null && code.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            code,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.onSurfaceVariant,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                message,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('知道了'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
