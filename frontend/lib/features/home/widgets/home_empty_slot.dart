import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// 主页区块空位：与对应任务卡片同高，仅居中一行提示，无图标。
class HomeEmptySlot extends StatelessWidget {
  const HomeEmptySlot.recent({super.key})
      : message = '无最近任务',
        contentHeight = _recentContentHeight;

  const HomeEmptySlot.todo({super.key})
      : message = '无 Todo 事项',
        contentHeight = _todoContentHeight;

  final String message;

  /// 与 [RecentTaskCard] / 收起态 [_TodoExpandTile] 正文区同高（不含 Card 外边距）。
  final double contentHeight;

  /// 标题行 + 间距 + 副标题行（与「专注」按钮行对齐）。
  static const _recentContentHeight = 47.0;

  /// 标题行 + 间距 + 预计时长行（与 Todo 收起态 title 一致）。
  static const _todoContentHeight = 65.0;

  static const _padding = EdgeInsets.fromLTRB(12, 12, 12, 10);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: _padding,
        child: SizedBox(
          height: contentHeight,
          child: Center(
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
