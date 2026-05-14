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
  const TaskDetailPage({super.key, this.taskId, this.initialExtra});

  final String? taskId;
  final Object? initialExtra;

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
  /// 新建任务首次保存成功前，返回页面应删除服务端草稿。
  bool _savedNewOnce = false;

  /// 编辑态本地草稿（保存前不写库）；进入编辑时从 [Task] 拷贝。
  List<String>? _draftTagIds;
  DateTime? _draftStartAt;
  DateTime? _draftEndAt;
  DateTime? _draftRemindAt;
  DateTime? _draftDueAt;

  void _initDraftsFromTask(Task t) {
    _draftTagIds = List<String>.from(t.tagIds);
    _draftStartAt = t.startAt;
    _draftEndAt = t.endAt;
    _draftRemindAt = t.remindAt;
    _draftDueAt = t.dueAt;
  }

  void _clearDrafts() {
    _draftTagIds = null;
    _draftStartAt = null;
    _draftEndAt = null;
    _draftRemindAt = null;
    _draftDueAt = null;
  }

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
          _initDraftsFromTask(t0);
          _fillControllers(t0);
          final draft = _readAgentDraft(widget.initialExtra);
          if (draft != null) {
            _applyAgentDraftLocal(draft);
          }
          if (mounted) setState(() {});
        } catch (e) {
          if (!mounted) return;
          await showAppErrorDialog(context, title: '创建失败', error: e);
          if (mounted) context.pop();
        }
      });
    }
  }

  Map<String, dynamic>? _readAgentDraft(Object? extra) {
    if (extra is Map<String, dynamic>) {
      final d = extra['agent_draft'];
      if (d is Map<String, dynamic>) return d;
    }
    return null;
  }

  DateTime? _parseIso(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  /// 将 Agent 草稿写入本地控制器与草稿字段（保存前不调 PATCH）。
  void _applyAgentDraftLocal(Map<String, dynamic> draft) {
    final title = (draft['title'] as String?)?.trim();
    final desc = (draft['description'] as String?)?.trim();
    final startAt = _parseIso(draft['start_at'] as String?);
    final endAt = _parseIso(draft['end_at'] as String?);
    final dueAt = _parseIso(draft['due_at'] as String?);
    final tagIdsRaw = draft['tag_ids'];
    final tagIds = (tagIdsRaw is List)
        ? tagIdsRaw.whereType<String>().toList()
        : <String>[];

    if (title?.isNotEmpty == true) {
      _titleC.text = title!;
    }
    if (desc != null) {
      _descC.text = desc;
    }
    if (startAt != null) _draftStartAt = startAt;
    if (endAt != null) _draftEndAt = endAt;
    if (dueAt != null) _draftDueAt = dueAt;
    if (tagIds.isNotEmpty) {
      _draftTagIds = List<String>.from(tagIds);
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

  /// 将当前编辑区的文本与草稿合并到 [serverT]（用于保存、类型切换、脏检查）。
  Task _composeTaskForSave(Task serverT) {
    final tagIds = _draftTagIds ?? serverT.tagIds;
    var next = serverT.copyWith(
      title: _titleC.text.trim(),
      description: _descC.text,
      tagIds: tagIds,
    );
    switch (serverT.type) {
      case TaskType.block:
        final s = _draftStartAt ?? serverT.startAt;
        final e = _draftEndAt ?? serverT.endAt;
        next = next.copyWith(startAt: s, endAt: e);
        if (_draftRemindAt != null) {
          next = next.copyWith(remindAt: _draftRemindAt, clearRemindAt: false);
        } else if (serverT.remindAt != null) {
          next = next.copyWith(clearRemindAt: true);
        }
        break;
      case TaskType.ddl:
        final d = _draftDueAt ?? serverT.dueAt;
        next = next.copyWith(dueAt: d, clearDueAt: d == null && serverT.dueAt != null);
        if (_draftRemindAt != null) {
          next = next.copyWith(remindAt: _draftRemindAt, clearRemindAt: false);
        } else if (serverT.remindAt != null) {
          next = next.copyWith(clearRemindAt: true);
        }
        break;
      case TaskType.todo:
        final nMin = int.tryParse(_expectedC.text.trim());
        next = next.copyWith(
          expectedMinutes: nMin,
          clearExpectedMinutes: nMin == null,
        );
        if (_draftDueAt != null) {
          next = next.copyWith(dueAt: _draftDueAt, clearDueAt: false);
        } else if (serverT.dueAt != null) {
          next = next.copyWith(clearDueAt: true);
        }
        if (_draftRemindAt != null) {
          next = next.copyWith(remindAt: _draftRemindAt, clearRemindAt: false);
        } else if (serverT.remindAt != null) {
          next = next.copyWith(clearRemindAt: true);
        }
        break;
    }
    return next;
  }

  static bool _dtEq(DateTime? a, DateTime? b) =>
      a?.millisecondsSinceEpoch == b?.millisecondsSinceEpoch;

  static bool _listEq(List<String> a, List<String> b) =>
      Set<String>.from(a) == Set<String>.from(b);

  bool _hasUnsavedChanges(Task t) {
    if (!_editing || _draftTagIds == null) return false;
    final c = _composeTaskForSave(t);
    if (c.title != t.title || c.description != t.description) return true;
    if (!_listEq(c.tagIds, t.tagIds)) return true;
    switch (t.type) {
      case TaskType.block:
        return !_dtEq(c.startAt, t.startAt) ||
            !_dtEq(c.endAt, t.endAt) ||
            !_dtEq(c.remindAt, t.remindAt);
      case TaskType.ddl:
        return !_dtEq(c.dueAt, t.dueAt) || !_dtEq(c.remindAt, t.remindAt);
      case TaskType.todo:
        return c.expectedMinutes != t.expectedMinutes ||
            !_dtEq(c.dueAt, t.dueAt) ||
            !_dtEq(c.remindAt, t.remindAt);
    }
  }

  static bool _blockIntervalsOverlap(DateTime a0, DateTime a1, DateTime b0, DateTime b1) {
    return a0.isBefore(b1) && b0.isBefore(a1);
  }

  /// 与其它进行中的 block 任务时间段是否重叠（不含当前任务）。
  String? _blockTimeOverlapMessage(TaskRepository repo, Task self, DateTime start, DateTime end) {
    final df = DateFormat('yyyy-MM-dd HH:mm');
    for (final o in repo.tasks) {
      if (o.id == self.id || o.type != TaskType.block) continue;
      if (o.status != TaskStatus.active && o.status != TaskStatus.overdue) continue;
      final os = o.startAt;
      final oe = o.endAt;
      if (os == null || oe == null) continue;
      if (_blockIntervalsOverlap(start, end, os, oe)) {
        return '与固定时段任务「${o.title}」重叠（${df.format(os)}–${df.format(oe)}）。请调整本任务的开始与结束时间。';
      }
    }
    return null;
  }

  Future<void> _switchTaskType(TaskRepository repo, Task t, TaskType nextType) async {
    if (t.type == nextType) return;
    final base = (_editing && _draftTagIds != null) ? _composeTaskForSave(t) : t;
    final now = DateTime.now();
    Task n;
    switch (nextType) {
      case TaskType.block:
        n = base.copyWith(
          type: TaskType.block,
          clearDueAt: true,
          clearExpectedMinutes: true,
          subtasks: const [],
          startAt: base.startAt ?? now,
          endAt: base.endAt ?? now.add(const Duration(hours: 1)),
        );
        break;
      case TaskType.ddl:
        n = base.copyWith(
          type: TaskType.ddl,
          clearStartAt: true,
          clearEndAt: true,
          clearExpectedMinutes: true,
          subtasks: const [],
          dueAt: base.dueAt ?? base.endAt ?? now.add(const Duration(days: 1)),
        );
        break;
      case TaskType.todo:
        n = base.copyWith(
          type: TaskType.todo,
          clearStartAt: true,
          clearEndAt: true,
          dueAt: base.dueAt ?? base.endAt ?? base.startAt ?? now.add(const Duration(days: 1)),
          subtasks: base.type == TaskType.todo ? base.subtasks : const [],
        );
        break;
    }
    try {
      final newId = await repo.replaceTaskWithNewType(n);
      if (!mounted) return;
      final tNew = repo.taskById(newId)!;
      setState(() {
        _tid = newId;
        _initDraftsFromTask(tNew);
        _fillControllers(tNew);
      });
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
    final repo = ref.read(taskRepositoryProvider);
    final next = _composeTaskForSave(current);
    if (next.type == TaskType.block) {
      final s = next.startAt;
      final e = next.endAt;
      if (s == null || e == null) {
        if (!mounted) return;
        await showAppErrorDialog(
          context,
          title: '无法保存',
          error: Exception('请设置 block 任务的开始与结束时间'),
        );
        return;
      }
      if (!e.isAfter(s)) {
        if (!mounted) return;
        await showAppErrorDialog(
          context,
          title: '时间无效',
          error: Exception('结束时间必须晚于开始时间'),
        );
        return;
      }
      final overlap = _blockTimeOverlapMessage(repo, current, s, e);
      if (overlap != null) {
        if (!mounted) return;
        await showAppErrorDialog(
          context,
          title: '时间冲突',
          error: Exception(overlap),
        );
        return;
      }
    }
    try {
      await repo.updateTask(next);
      if (!mounted) return;
      setState(() {
        _editing = false;
        _clearDrafts();
        if (widget.taskId == null) _savedNewOnce = true;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存')));
      }
    } catch (e) {
      if (!mounted) return;
      await showAppErrorDialog(context, title: '保存失败', error: e);
    }
  }

  void _enterEditMode(Task t) {
    setState(() {
      _editing = true;
      _initDraftsFromTask(t);
      _fillControllers(t);
    });
  }

  Future<bool> _prepareLeave() async {
    final repo = ref.read(taskRepositoryProvider);
    final tid = _tid;
    if (tid == null) return true;

    final t = repo.taskById(tid);
    if (t == null) return true;

    if (widget.taskId == null && !_savedNewOnce) {
      final dirty = _hasUnsavedChanges(t);
      if (dirty) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('放弃创建？'),
            content: const Text('有未保存的修改，确定放弃并删除该草稿任务？'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('放弃'),
              ),
            ],
          ),
        );
        if (ok != true) return false;
      }
      try {
        await repo.deleteTask(tid);
      } catch (_) {}
      return true;
    }

    if (_editing && _hasUnsavedChanges(t)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('放弃更改？'),
          content: const Text('有未保存的修改，确定离开？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('放弃')),
          ],
        ),
      );
      if (ok != true) return false;
      try {
        await repo.refreshTasks();
      } catch (_) {}
      if (!mounted) return false;
      final t2 = ref.read(taskRepositoryProvider).taskById(tid);
      if (t2 != null) _fillControllers(t2);
      setState(() {
        _editing = false;
        _clearDrafts();
      });
      return true;
    }

    return true;
  }

  Future<void> _onPopInvoked(bool didPop, dynamic result) async {
    if (didPop) return;
    if (!await _prepareLeave()) return;
    if (mounted) context.pop();
  }

  Future<void> _onBackPressed() async {
    if (!await _prepareLeave()) return;
    if (mounted) context.pop();
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        unawaited(_onPopInvoked(didPop, result));
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.taskId == null
              ? '新建任务'
              : (_editing ? '编辑任务' : t.title),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => unawaited(_onBackPressed()),
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
                if (_editing && _draftTagIds != null)
                  _TagEditor(
                    allTags: repo.tags,
                    selectedIds: _draftTagIds!,
                    onChanged: (ids) => setState(() => _draftTagIds = ids),
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
                            _enterEditMode(t);
                          }
                        },
                        child: Text(_editing ? '保存' : '编辑'),
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
    final editing = _editing && _draftTagIds != null;

    Widget readRow(String label, DateTime? value) => _timeRowReadOnly(label, value, df);

    return [
      if (t.type == TaskType.block) ...[
        if (!editing) ...[
          readRow('开始', t.startAt),
          readRow('结束', t.endAt),
          readRow('提醒', t.remindAt),
        ] else ...[
          _timeRowEditable(
            label: '开始',
            value: _draftStartAt ?? t.startAt,
            df: df,
            blockPrimaryHint: true,
            onPick: () async {
              final dt = await _pickDateTime(_draftStartAt ?? t.startAt);
              if (dt != null && mounted) setState(() => _draftStartAt = dt);
            },
          ),
          _timeRowEditable(
            label: '结束',
            value: _draftEndAt ?? t.endAt,
            df: df,
            blockPrimaryHint: true,
            onPick: () async {
              final dt = await _pickDateTime(_draftEndAt ?? t.endAt);
              if (dt != null && mounted) setState(() => _draftEndAt = dt);
            },
          ),
          _timeRowEditable(
            label: '提醒',
            value: _draftRemindAt,
            df: df,
            blockPrimaryHint: false,
            onPick: () async {
              final dt = await _pickDateTime(_draftRemindAt ?? t.remindAt);
              if (dt != null && mounted) setState(() => _draftRemindAt = dt);
            },
            onClear: (t.remindAt != null || _draftRemindAt != null)
                ? () => setState(() => _draftRemindAt = null)
                : null,
          ),
        ],
      ],
      if (t.type == TaskType.ddl) ...[
        if (!editing) ...[
          readRow('截止', t.dueAt),
          readRow('提醒', t.remindAt),
        ] else ...[
          _timeRowEditable(
            label: '截止',
            value: _draftDueAt ?? t.dueAt,
            df: df,
            blockPrimaryHint: false,
            onPick: () async {
              final dt = await _pickDateTime(_draftDueAt ?? t.dueAt);
              if (dt != null && mounted) setState(() => _draftDueAt = dt);
            },
          ),
          _timeRowEditable(
            label: '提醒',
            value: _draftRemindAt,
            df: df,
            blockPrimaryHint: false,
            onPick: () async {
              final dt = await _pickDateTime(_draftRemindAt ?? t.remindAt);
              if (dt != null && mounted) setState(() => _draftRemindAt = dt);
            },
            onClear: (t.remindAt != null || _draftRemindAt != null)
                ? () => setState(() => _draftRemindAt = null)
                : null,
          ),
        ],
      ],
      if (t.type == TaskType.todo) ...[
        if (!editing)
          Text('预计投入：${t.expectedMinutes ?? '—'} 分钟')
        else
          TextField(
            controller: _expectedC,
            decoration: const InputDecoration(labelText: '预计投入（分钟）'),
            keyboardType: TextInputType.number,
          ),
        const SizedBox(height: 8),
        if (!editing) ...[
          readRow('截止', t.dueAt),
          readRow('提醒', t.remindAt),
        ] else ...[
          _timeRowEditable(
            label: '截止',
            value: _draftDueAt ?? t.dueAt,
            df: df,
            blockPrimaryHint: false,
            onPick: () async {
              final dt = await _pickDateTime(_draftDueAt ?? t.dueAt);
              if (dt != null && mounted) setState(() => _draftDueAt = dt);
            },
            onClear: (t.dueAt != null || _draftDueAt != null)
                ? () => setState(() => _draftDueAt = null)
                : null,
          ),
          _timeRowEditable(
            label: '提醒',
            value: _draftRemindAt,
            df: df,
            blockPrimaryHint: false,
            onPick: () async {
              final dt = await _pickDateTime(_draftRemindAt ?? t.remindAt);
              if (dt != null && mounted) setState(() => _draftRemindAt = dt);
            },
            onClear: (t.remindAt != null || _draftRemindAt != null)
                ? () => setState(() => _draftRemindAt = null)
                : null,
          ),
        ],
      ],
    ];
  }

  Widget _timeRowReadOnly(String label, DateTime? value, DateFormat df) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(label, style: const TextStyle(color: AppColors.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value != null ? df.format(value) : '未设置'),
          ),
        ],
      ),
    );
  }

  Widget _timeRowEditable({
    required String label,
    required DateTime? value,
    required DateFormat df,
    required Future<void> Function() onPick,
    required bool blockPrimaryHint,
    VoidCallback? onClear,
  }) {
    final hintColor = AppColors.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(label, style: const TextStyle(color: AppColors.onSurfaceVariant)),
            ),
          ),
          Expanded(
            child: Material(
              color: AppColors.surfaceContainerHigh.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () => unawaited(onPick()),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value != null ? df.format(value) : '未设置',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            blockPrimaryHint ? Icons.edit_calendar_outlined : Icons.touch_app_outlined,
                            size: 15,
                            color: hintColor,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            blockPrimaryHint ? '点击修改时间' : '点击修改',
                            style: TextStyle(fontSize: 12.5, color: hintColor, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (onClear != null) ...[
            const SizedBox(width: 4),
            TextButton(onPressed: onClear, child: const Text('清除')),
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
