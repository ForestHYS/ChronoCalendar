// TODO: 全屏计时器、锁定屏幕交互、白噪音预设、结束按钮；杀后台结束逻辑。

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class PomodoroPage extends StatelessWidget {
  const PomodoroPage({super.key, this.taskId});

  final String? taskId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('番茄钟')),
      body: Center(
        child: Text(
          taskId != null ? '任务 $taskId · 番茄钟占位' : '番茄钟占位',
          style: const TextStyle(color: AppColors.onSurfaceVariant),
        ),
      ),
    );
  }
}
