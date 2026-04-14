import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../data/providers.dart';
import '../../data/task_repository.dart';
import '../../domain/models/tag.dart';
import '../../domain/models/task.dart';

class TaskDetailPage extends ConsumerStatefulWidget {
  const TaskDetailPage({super.key, required this.taskId});

  final String taskId;

  @override
  ConsumerState<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends ConsumerState<TaskDetailPage> {
  bool _editing = false;
  late final TextEditingController _titleC = TextEditingController();
  late final TextEditingController _descC = TextEditingController();
  late final TextEditingController _expectedC = TextEditingController();

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
      next = next.copyWith(expectedMinutes: n);
    }
    ref.read(taskRepositoryProvider).updateTask(next);
    setState(() => _editing = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存')));
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
    if (ok == true && mounted) {
      ref.read(taskRepositoryProvider).deleteTask(widget.taskId);
      context.pop();
    }
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
    final t = repo.taskById(widget.taskId);
    if (t == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('任务')),
        body: const Center(child: Text('任务不存在或已删除')),
      );
    }

    final df = DateFormat('yyyy-MM-dd HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? '编辑任务' : t.title),
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
                    onChanged: (ids) => repo.updateTask(t.copyWith(tagIds: ids)),
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
                        repo.addSubtask(t.id, '新子任务');
                        setState(() {});
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('添加子任务'),
                    ),
                ],
                const SizedBox(height: 8),
                Text(
                  '状态：${t.status.name} · 专注累计 ${t.focusTotalSeconds ~/ 3600}h${(t.focusTotalSeconds % 3600) ~/ 60}m',
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
                            await _save(repo.taskById(widget.taskId)!);
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
    Future<void> update(Task next) {
      ref.read(taskRepositoryProvider).updateTask(next);
      setState(() {});
      return Future.value();
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

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.subtask.title);
  }

  @override
  void dispose() {
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
                widget.repo.toggleSubtask(widget.taskId, widget.subtask.id, v);
                widget.onChanged();
              }
            },
          ),
          Expanded(
            child: TextField(
              controller: _c,
              decoration: const InputDecoration(isDense: true),
              onChanged: (v) => widget.repo.updateSubtaskTitle(widget.taskId, widget.subtask.id, v),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              widget.repo.removeSubtask(widget.taskId, widget.subtask.id);
              widget.onChanged();
            },
          ),
        ],
      ),
    );
  }
}
