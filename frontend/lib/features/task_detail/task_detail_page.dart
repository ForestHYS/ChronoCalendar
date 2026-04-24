import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/ui/app_error_dialog.dart';
import '../../data/providers.dart';
import '../../data/task_repository.dart';
import '../../domain/models/tag.dart';
import '../../domain/models/task.dart';
import '../../domain/models/task_status.dart';

class TaskDetailPage extends ConsumerStatefulWidget {
  /// [taskId] 为 `null` 时表示新建：首帧后以 **固定时段（block）** 插入草稿并进入编辑态。
  const TaskDetailPage({super.key, this.taskId});

  final String? taskId;

  @override
  ConsumerState<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends ConsumerState<TaskDetailPage> {
  bool _editing = false;
  late final TextEditingController _titleC = TextEditingController();
  late final TextEditingController _descC = TextEditingController();
  late final TextEditingController _expectedC = TextEditingController();
  /// 新建任务：首帧后创建 block 草稿；已有任务：路由传入 id。
  String? _tid;

  @override
  void initState() {
    super.initState();
    if (widget.taskId != null) {
      _tid = widget.taskId;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        try {
          await ref.read(taskRepositoryProvider).ensureTaskLoaded(widget.taskId!);
          if (!mounted) return;
          final t0 = ref.read(taskRepositoryProvider).taskById(widget.taskId!);
          if (t0 != null) _fillControllers(t0);
          setState(() {});
        } catch (e) {
          if (!mounted) return;
          await showAppErrorDialog(context, title: '加载失败', error: e);
        }
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        try {
          final id = await ref.read(taskRepositoryProvider).createDraftTask(TaskType.block);
          if (!mounted) return;
          setState(() {
            _tid = id;
            _editing = true;
          });
          final t0 = ref.read(taskRepositoryProvider).taskById(id)!;
          _fillControllers(t0);
        } catch (e) {
          if (!mounted) return;
          await showAppErrorDialog(context, title: '创建失败', error: e);
          if (mounted) context.pop();
        }
      });
    }
  }

  @override
  void dispose() {
    _titleC.dispose();
    _descC.dispose();
    _expectedC.dispose();
    super.dispose();
  }

  void _fillControllers(Task t) {
    _titleC.text = t.title;
    _descC.text = t.description;
    _expectedC.text = t.expectedMinutes?.toString() ?? '';
  }

  Future<void> _switchTaskType(TaskRepository repo, Task t, TaskType nextType) async {
    if (t.type == nextType) return;
    final now = DateTime.now();
    Task n;
    switch (nextType) {
      case TaskType.block:
        n = t.copyWith(
          type: TaskType.block,
          clearDueAt: true,
          clearExpectedMinutes: true,
          subtasks: const [],
          startAt: t.startAt ?? now,
          endAt: t.endAt ?? now.add(const Duration(hours: 1)),
        );
        break;
      case TaskType.ddl:
        n = t.copyWith(
          type: TaskType.ddl,
          clearStartAt: true,
          clearEndAt: true,
          clearExpectedMinutes: true,
          subtasks: const [],
          dueAt: t.dueAt ?? t.endAt ?? now.add(const Duration(days: 1)),
        );
        break;
      case TaskType.todo:
        n = t.copyWith(
          type: TaskType.todo,
          clearStartAt: true,
          clearEndAt: true,
          dueAt: t.dueAt ?? t.endAt ?? t.startAt ?? now.add(const Duration(days: 1)),
          subtasks: t.type == TaskType.todo ? t.subtasks : const [],
        );
        break;
    }
    try {
      final newId = await repo.replaceTaskWithNewType(n);
      if (!mounted) return;
      setState(() => _tid = newId);
      _fillControllers(repo.taskById(newId)!);
    } catch (e) {
      if (!mounted) return;
      await showAppErrorDialog(context, title: '切换类型失败', error: e);
    }
  }

  Future<DateTime?> _pickDateTime(DateTime? initial) async {
    final ctx = context;
    final base = initial ?? DateTime.now();
    final d = await showDatePicker(
      context: ctx,
      initialDate: base,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d == null || !ctx.mounted) return null;
    final time = await showTimePicker(
      context: ctx,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (time == null || !ctx.mounted) return null;
    return DateTime(d.year, d.month, d.day, time.hour, time.minute);
  }

  Future<void> _save(Task current) async {
    var next = current.copyWith(
      title: _titleC.text.trim(),
      description: _descC.text,
    );
    if (next.type == TaskType.todo) {
      final n = int.tryParse(_expectedC.text.trim());
      next = next.copyWith(expectedMinutes: n, clearExpectedMinutes: n == null);
    }
    try {
      await ref.read(taskRepositoryProvider).updateTask(next);
      if (!mounted) return;
      setState(() => _editing = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存')));
    } catch (e) {
      if (!mounted) return;
      await showAppErrorDialog(context, title: '保存失败', error: e);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除任务'),
        content: const Text('确定删除该任务？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true && mounted && _tid != null) {
      try {
        await ref.read(taskRepositoryProvider).deleteTask(_tid!);
        if (mounted) context.pop();
      } catch (e) {
        if (mounted) await showAppErrorDialog(context, title: '删除失败', error: e);
      }
    }
  }

  String _statusLabelCn(TaskStatus s) {
    return switch (s) {
      TaskStatus.active => '进行中',
      TaskStatus.completed => '已完成',
      TaskStatus.cancelled => '已取消',
      TaskStatus.overdue => '已逾期',
    };
  }

  void _aiStub() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AI 快捷设置'),
        content: const Text('语音输入与自动生成字段功能开发中（TODO）。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(taskRepositoryProvider);

    if (widget.taskId == null && _tid == null) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          title: const Text('新建任务'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }

    final t = repo.taskById(_tid!);
    if (t == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('任务')),
        body: const Center(child: Text('任务不存在或已删除')),
      );
    }

    final df = DateFormat('yyyy-MM-dd HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.taskId == null
              ? '新建任务'
              : (_editing ? '编辑任务' : t.title),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_editing && widget.taskId == null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Center(
                      child: _TaskTypeToggle(
                        current: t.type,
                        onChanged: (nt) => unawaited(_switchTaskType(repo, t, nt)),
                      ),
                    ),
                  ),
                _typeLabel(t.type),
                const SizedBox(height: 12),
                if (_editing)
                  TextField(
                    controller: _titleC,
                    decoration: const InputDecoration(labelText: '标题'),
                  )
                else
                  Text(t.title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                if (_editing)
                  TextField(
                    controller: _descC,
                    decoration: const InputDecoration(labelText: '描述'),
                    maxLines: 3,
                  )
                else if (t.description.isNotEmpty)
                  Text(t.description, style: const TextStyle(color: AppColors.onSurfaceVariant)),
                const SizedBox(height: 16),
                const Text('标签', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                if (_editing)
                  _TagEditor(
                    allTags: repo.tags,
                    selectedIds: t.tagIds,
                    onChanged: (ids) => unawaited(repo.updateTask(t.copyWith(tagIds: ids))),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: t.tagIds
                        .map((id) => repo.tagById(id))
                        .whereType<Tag>()
                        .map(
                          (tag) => Chip(
                            label: Text(tag.name),
                            backgroundColor: AppColors.surfaceContainerHigh,
                          ),
                        )
                        .toList(),
                  ),
                const SizedBox(height: 20),
                ..._typeFields(context, t, df),
                if (t.type == TaskType.todo) ...[
                  const SizedBox(height: 16),
                  const Text('子任务', style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  ...t.subtasks.map((s) {
                    if (_editing) {
                      return _SubtaskEditRow(
                        key: ValueKey(s.id),
                        taskId: t.id,
                        subtask: s,
                        repo: repo,
                        onChanged: () => setState(() {}),
                      );
                    }
                    return CheckboxListTile(
                      value: s.done,
                      onChanged: null,
                      title: Text(s.title),
                    );
                  }),
                  if (_editing)
                    TextButton.icon(
                      onPressed: () {
                        final ctx = context;
                        unawaited(() async {
                          try {
                            await repo.addSubtask(t.id, '新子任务');
                            if (mounted) setState(() {});
                          } catch (e) {
                            if (!mounted || !ctx.mounted) return;
                            await showAppErrorDialog(ctx, title: '添加失败', error: e);
                          }
                        }());
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('添加子任务'),
                    ),
                ],
                const SizedBox(height: 8),
                Text(
                  '状态：${_statusLabelCn(t.status)} · 专注累计 ${t.focusTotalSeconds ~/ 3600}h${(t.focusTotalSeconds % 3600) ~/ 60}m',
                  style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Material(
            elevation: 8,
            color: AppColors.surfaceContainer,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          if (_editing) {
                            await _save(repo.taskById(t.id)!);
                          } else {
                            _fillControllers(t);
                            setState(() => _editing = true);
                          }
                        },
                        child: Text(_editing ? '保存' : '编辑'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _aiStub,
                        child: const Text('AI 快捷'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextButton(
                        onPressed: _delete,
                        style: TextButton.styleFrom(foregroundColor: AppColors.error),
                        child: const Text('删除'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeLabel(TaskType type) {
    final s = switch (type) {
      TaskType.block => '类型：固定时段（block）',
      TaskType.ddl => '类型：截止日期（ddl）',
      TaskType.todo => '类型：待办（todo）',
    };
    return Text(s, style: const TextStyle(color: AppColors.onSurfaceVariant));
  }

  List<Widget> _typeFields(BuildContext context, Task t, DateFormat df) {
    final fieldContext = context;
    Future<void> update(Task next) async {
      try {
        await ref.read(taskRepositoryProvider).updateTask(next);
        if (mounted) setState(() {});
      } catch (e) {
        if (!mounted || !fieldContext.mounted) return;
        await showAppErrorDialog(fieldContext, title: '更新失败', error: e);
      }
    }

    return [
      if (t.type == TaskType.block) ...[
        _dateRow('开始', t.startAt, df, _editing, () async {
          final dt = await _pickDateTime(t.startAt);
          if (dt != null) await update(t.copyWith(startAt: dt));
        }),
        _dateRow('结束', t.endAt, df, _editing, () async {
          final dt = await _pickDateTime(t.endAt);
          if (dt != null) await update(t.copyWith(endAt: dt));
        }),
        _dateRow('提醒', t.remindAt, df, _editing, () async {
          final dt = await _pickDateTime(t.remindAt);
          if (dt != null) await update(t.copyWith(remindAt: dt));
        }, onClear: t.remindAt != null ? () => update(t.copyWith(clearRemindAt: true)) : null),
      ],
      if (t.type == TaskType.ddl) ...[
        _dateRow('截止', t.dueAt, df, _editing, () async {
          final dt = await _pickDateTime(t.dueAt);
          if (dt != null) await update(t.copyWith(dueAt: dt));
        }),
        _dateRow('提醒', t.remindAt, df, _editing, () async {
          final dt = await _pickDateTime(t.remindAt);
          if (dt != null) await update(t.copyWith(remindAt: dt));
        }, onClear: t.remindAt != null ? () => update(t.copyWith(clearRemindAt: true)) : null),
      ],
      if (t.type == TaskType.todo) ...[
        if (_editing)
          TextField(
            controller: _expectedC,
            decoration: const InputDecoration(labelText: '预计投入（分钟）'),
            keyboardType: TextInputType.number,
          )
        else
          Text('预计投入：${t.expectedMinutes ?? '—'} 分钟'),
        const SizedBox(height: 8),
        _dateRow('截止', t.dueAt, df, _editing, () async {
          final dt = await _pickDateTime(t.dueAt);
          if (dt != null) await update(t.copyWith(dueAt: dt));
        }, onClear: t.dueAt != null ? () => update(t.copyWith(clearDueAt: true)) : null),
        _dateRow('提醒', t.remindAt, df, _editing, () async {
          final dt = await _pickDateTime(t.remindAt);
          if (dt != null) await update(t.copyWith(remindAt: dt));
        }, onClear: t.remindAt != null ? () => update(t.copyWith(clearRemindAt: true)) : null),
      ],
    ];
  }

  Widget _dateRow(
    String label,
    DateTime? value,
    DateFormat df,
    bool editing,
    VoidCallback onPick, {
    VoidCallback? onClear,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(label, style: const TextStyle(color: AppColors.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value != null ? df.format(value) : '未设置'),
          ),
          if (editing) ...[
            TextButton(onPressed: onPick, child: const Text('选择')),
            if (onClear != null) TextButton(onPressed: onClear, child: const Text('清除')),
          ],
        ],
      ),
    );
  }
}

/// 紧凑、非全宽的「任务类型」切换（替代 SegmentedButton 铺满行）。
class _TaskTypeToggle extends StatelessWidget {
  const _TaskTypeToggle({
    required this.current,
    required this.onChanged,
  });

  final TaskType current;
  final ValueChanged<TaskType> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.75)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TaskTypeChip(
              label: '时段',
              icon: Icons.schedule_rounded,
              selected: current == TaskType.block,
              onTap: () => onChanged(TaskType.block),
            ),
            const SizedBox(width: 4),
            _TaskTypeChip(
              label: '截止',
              icon: Icons.flag_outlined,
              selected: current == TaskType.ddl,
              onTap: () => onChanged(TaskType.ddl),
            ),
            const SizedBox(width: 4),
            _TaskTypeChip(
              label: '待办',
              icon: Icons.checklist_rounded,
              selected: current == TaskType.todo,
              onTap: () => onChanged(TaskType.todo),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskTypeChip extends StatelessWidget {
  const _TaskTypeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFF1E40AF);
    final fg = selected ? accent : AppColors.onSurfaceVariant;
    return Material(
      color: selected ? AppColors.primaryContainer.withValues(alpha: 0.95) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TagEditor extends StatelessWidget {
  const _TagEditor({
    required this.allTags,
    required this.selectedIds,
    required this.onChanged,
  });

  final List<Tag> allTags;
  final List<String> selectedIds;
  final void Function(List<String> ids) onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: allTags.map((tag) {
        final sel = selectedIds.contains(tag.id);
        return FilterChip(
          label: Text(tag.name),
          selected: sel,
          onSelected: (v) {
            final next = List<String>.from(selectedIds);
            if (v) {
              if (!next.contains(tag.id)) next.add(tag.id);
            } else {
              next.remove(tag.id);
            }
            onChanged(next);
          },
        );
      }).toList(),
    );
  }
}

class _SubtaskEditRow extends StatefulWidget {
  const _SubtaskEditRow({
    super.key,
    required this.taskId,
    required this.subtask,
    required this.repo,
    required this.onChanged,
  });

  final String taskId;
  final Subtask subtask;
  final TaskRepository repo;
  final VoidCallback onChanged;

  @override
  State<_SubtaskEditRow> createState() => _SubtaskEditRowState();
}

class _SubtaskEditRowState extends State<_SubtaskEditRow> {
  late final TextEditingController _c;
  Timer? _titleDebounce;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.subtask.title);
  }

  @override
  void dispose() {
    _titleDebounce?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Checkbox(
            value: widget.subtask.done,
            onChanged: (v) {
              if (v != null) {
                unawaited(() async {
                  try {
                    await widget.repo.toggleSubtask(widget.taskId, widget.subtask.id, v);
                    if (mounted) widget.onChanged();
                  } catch (_) {}
                }());
              }
            },
          ),
          Expanded(
            child: TextField(
              controller: _c,
              decoration: const InputDecoration(isDense: true),
              onChanged: (v) {
                _titleDebounce?.cancel();
                _titleDebounce = Timer(const Duration(milliseconds: 500), () {
                  if (!mounted) return;
                  unawaited(() async {
                    try {
                      await widget.repo.updateSubtaskTitle(widget.taskId, widget.subtask.id, v);
                    } catch (_) {}
                  }());
                });
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              unawaited(() async {
                try {
                  await widget.repo.removeSubtask(widget.taskId, widget.subtask.id);
                  if (mounted) widget.onChanged();
                } catch (_) {}
              }());
            },
          ),
        ],
      ),
    );
  }
}
