// TODO: 日/周/月三个视图、切换动画、与任务数据联动。

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class CalendarPage extends StatelessWidget {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('日历')),
      body: const Center(
        child: Text(
          '日历框架已就绪',
          style: TextStyle(color: AppColors.onSurfaceVariant),
        ),
      ),
    );
  }
}
