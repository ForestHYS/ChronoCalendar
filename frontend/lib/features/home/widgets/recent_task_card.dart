import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/models/tag.dart';
import '../../../domain/models/task.dart';
import 'title_with_tags_row.dart';

/// 主页「最近任务」条目：左滑完成、标题右侧标签带、圆角「专注」按钮。
class RecentTaskCard extends StatelessWidget {
  const RecentTaskCard({
    super.key,
    required this.task,
    required this.tags,
    required this.subtitle,
    required this.onTap,
    required this.onFocus,
    required this.onDismissedComplete,
  });

  final Task task;
  final List<Tag> tags;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback onFocus;
  final VoidCallback onDismissedComplete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('recent_${task.id}'),
      direction: DismissDirection.endToStart,
      movementDuration: const Duration(milliseconds: 340),
      resizeDuration: const Duration(milliseconds: 340),
      dismissThresholds: const {DismissDirection.endToStart: 0.32},
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
      ),
      secondaryBackground: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.success,
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Icon(Icons.check_rounded, color: Colors.white, size: 26),
            SizedBox(width: 6),
            Text(
              '完成',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      confirmDismiss: (direction) async => direction == DismissDirection.endToStart,
      onDismissed: (_) => onDismissedComplete(),
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TitleWithTagsRow(
                            title: task.title,
                            tags: tags,
                            titleStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppColors.onSurface,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Align(
                      alignment: Alignment.center,
                      child: OutlinedButton(
                        onPressed: onFocus,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary, width: 1),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          minimumSize: const Size(0, 36),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('专注', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
