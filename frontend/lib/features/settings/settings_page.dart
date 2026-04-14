// TODO: 设置账号密码、管理备选标签项（对齐 api /tags）。

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('设置')),
      body: const Center(
        child: Text(
          '设置框架已就绪',
          style: TextStyle(color: AppColors.onSurfaceVariant),
        ),
      ),
    );
  }
}
