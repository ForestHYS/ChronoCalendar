import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/models/tag.dart';
import '../../../domain/models/task.dart';
import '../../../domain/models/task_status.dart';
import 'task_filter_state.dart';

/// 弹出筛选/排序底部面板。返回 `null` 表示用户关闭未应用，否则返回新的状态。
Future<TaskFilterState?> showTaskFilterSortSheet({
  required BuildContext context,
  required TaskFilterState current,
  required TaskType? category,
  required List<Tag> availableTags,
}) {
  return showModalBottomSheet<TaskFilterState>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.sheetTop)),
    ),
    builder: (ctx) => _FilterSortSheet(
      initial: current,
      category: category,
      tags: availableTags,
    ),
  );
}

class _FilterSortSheet extends StatefulWidget {
  const _FilterSortSheet({
    required this.initial,
    required this.category,
    required this.tags,
  });

  final TaskFilterState initial;
  final TaskType? category;
  final List<Tag> tags;

  @override
  State<_FilterSortSheet> createState() => _FilterSortSheetState();
}

class _FilterSortSheetState extends State<_FilterSortSheet> {
  late TaskFilterState _state;

  @override
  void initState() {
    super.initState();
    _state = widget.initial.copy();
  }

  void _toggleStatus(TaskStatus s) {
    setState(() {
      if (_state.statuses.contains(s)) {
        _state.statuses.remove(s);
      } else {
        _state.statuses.add(s);
      }
    });
  }

  void _toggleTag(String id) {
    setState(() {
      if (_state.tagIds.contains(id)) {
        _state.tagIds.remove(id);
      } else {
        _state.tagIds.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sortOptions = sortOptionsFor(widget.category);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxH = MediaQuery.sizeOf(context).height * 0.78;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '筛选 / 排序',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  children: [
                    const _SectionTitle('排序'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in sortOptions)
                          _FilterChip(
                            label: s.label,
                            selected: _state.sort == s,
                            onTap: () => setState(() => _state.sort = s),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const _SectionTitle('状态'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final entry in _statusOptions)
                          _FilterChip(
                            label: entry.$2,
                            selected: _state.statuses.contains(entry.$1),
                            onTap: () => _toggleStatus(entry.$1),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const _SectionTitle('标签'),
                    if (widget.tags.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          '暂无标签，可在「设置 - 标签管理」添加',
                          style: TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
                        ),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final tag in widget.tags)
                            _FilterChip(
                              label: tag.name,
                              dotColor: tag.color,
                              selected: _state.tagIds.contains(tag.id),
                              onTap: () => _toggleTag(tag.id),
                            ),
                        ],
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() {
                          _state = TaskFilterState();
                        }),
                        child: const Text('重置'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(_state),
                        child: const Text('应用'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _statusOptions = <(TaskStatus, String)>[
  (TaskStatus.active, '进行中'),
  (TaskStatus.overdue, '超时'),
  (TaskStatus.completed, '已完成'),
  (TaskStatus.cancelled, '已取消'),
];

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.onSurface,
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.dotColor,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.chip),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryContainer : AppColors.surfaceContainerHigh,
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.outline,
          ),
          borderRadius: BorderRadius.circular(AppRadii.chip),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dotColor != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? AppColors.primary : AppColors.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
