import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/models/tag.dart';
import '../../domain/models/task.dart';
import 'tag_chip.dart';

class TaskRowUpcoming extends StatelessWidget {
  const TaskRowUpcoming({
    super.key,
    required this.task,
    required this.subtitle,
    required this.tag,
    required this.onTap,
    required this.onFocus,
    required this.onComplete,
    this.showComplete = true,
  });

  final Task task;
  final String subtitle;
  final Tag? tag;
  final VoidCallback onTap;
  final VoidCallback onFocus;
  final VoidCallback onComplete;
  final bool showComplete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: AppColors.onSurface,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                    if (tag != null) ...[
                      const SizedBox(height: 8),
                      TagChip(tag: tag!, compact: true),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(onPressed: onFocus, child: const Text('专注')),
                  if (showComplete)
                    TextButton(
                      onPressed: onComplete,
                      style: TextButton.styleFrom(foregroundColor: AppColors.success),
                      child: const Text('完成'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
