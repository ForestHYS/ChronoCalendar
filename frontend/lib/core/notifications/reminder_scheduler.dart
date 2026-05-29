import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../data/task_repository.dart';
import '../../domain/models/task.dart';
import '../../domain/models/task_status.dart';
import '../../shared/widgets/reminder_sheet.dart';
import '../router/app_router.dart';
import 'notification_service.dart';

/// 监听 [TaskRepository]：
/// - 为每个未来 `remindAt` 的活跃任务调度系统通知（基于 AlarmManager）。
/// - 在 App 处于前台时维护一个最近一次提醒的 Timer，到点弹出半屏 [ReminderSheet]。
///
/// 登录后由上层启动 [start]，登出时 [stop]。
class ReminderScheduler with WidgetsBindingObserver {
  ReminderScheduler(this._repo, this._notifications);

  final TaskRepository _repo;
  final NotificationService _notifications;

  /// 已为哪些任务调度过系统通知（taskId -> 计划的提醒时间）。
  final Map<String, DateTime> _scheduled = {};

  /// 短时间内已弹出过 sheet 的任务，避免一次提醒重复弹出。
  final Map<String, DateTime> _recentlyShown = {};

  Timer? _foregroundTimer;
  StreamSubscription<String>? _tapSub;
  bool _started = false;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  /// 当前进行中的 `_doSync` future；null 表示空闲。用于单飞合并并发触发。
  Future<void>? _syncing;

  /// 在已有 sync 跑的时候又收到通知 → 标记 dirty，等当前完成后补跑一次。
  bool _syncDirty = false;

  /// 启动：注册 listener、立即做一次同步。
  void start() {
    if (_started) return;
    _started = true;
    debugPrint('[Reminder] scheduler start (tasks=${_repo.tasks.length})');
    WidgetsBinding.instance.addObserver(this);
    _repo.addListener(_onTasksChanged);
    _tapSub = _notifications.onNotificationTapped.listen(_onNotificationTapped);
    _sync();
  }

  /// 停止：取消监听 + 清空已调度的通知。
  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _repo.removeListener(_onTasksChanged);
    await _tapSub?.cancel();
    _tapSub = null;
    _foregroundTimer?.cancel();
    _foregroundTimer = null;
    // 等飞行中的 _doSync 通过 _started 守卫退出，避免在 cancelAll 之后又写入 _scheduled
    final pending = _syncing;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
    }
    _syncing = null;
    _syncDirty = false;
    _scheduled.clear();
    _recentlyShown.clear();
    await _notifications.cancelAll();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (state == AppLifecycleState.resumed) {
      _maybeShowDuePopups(); // 恢复前台时立即处理已到期的提醒
      _rescheduleForegroundTimer();
    }
  }

  void _onTasksChanged() => _sync();

  /// 通知被点击：弹半屏 [ReminderSheet]（与到点前台触发的行为保持一致）。
  ///
  /// 冷启动（app 进程未启动时点开通知）由 `app.dart` 中读 `launchTaskId` 后
  /// 直接 push 任务详情；这里覆盖的是 app 在后台被点开 / 在前台时点击通知抽屉中
  /// 的旧条目这两种「app 已在运行」的场景。
  void _onNotificationTapped(String taskId) {
    final t = _repo.taskById(taskId);
    if (t == null) return;
    _showSheet(t);
  }

  /// 主同步流程入口：单飞合并并发调用。
  ///
  /// 并发触发（如 bootstrap 批量写入连续多次 notifyListeners）时：
  /// - 第一次启动 [_doSync]
  /// - 期间到来的 sync 请求只标记 dirty
  /// - 第一份完成后，若还活着且 dirty，再跑一次（合并为「当前 + 一次补跑」）
  Future<void> _sync() {
    if (_syncing != null) {
      _syncDirty = true;
      return _syncing!;
    }
    final f = _doSync().whenComplete(() {
      _syncing = null;
      if (_started && _syncDirty) {
        _syncDirty = false;
        _sync();
      }
    });
    _syncing = f;
    return f;
  }

  /// 真正的同步实现。每次 await 后用 `_started` 守卫，避免 [stop] 后再写入状态。
  Future<void> _doSync() async {
    final now = DateTime.now();
    final wanted = <String, DateTime>{};
    final justPast = <Task>[]; // remindAt 在过去 30 秒内、状态仍活跃 → 立即弹 sheet
    int withRemind = 0;
    int skippedStatus = 0;
    int skippedStale = 0;
    for (final t in _repo.tasks) {
      if (t.remindAt == null) continue;
      withRemind++;
      debugPrint('[Reminder]   task=${t.id} title=${t.title} '
          'status=${t.status.name} remindAt=${t.remindAt} '
          '(delta=${t.remindAt!.difference(now).inSeconds}s)');
      if (t.status == TaskStatus.completed ||
          t.status == TaskStatus.cancelled) {
        skippedStatus++;
        continue;
      }
      if (t.remindAt!.isAfter(now)) {
        wanted[t.id] = t.remindAt!;
      } else if (now.difference(t.remindAt!) < const Duration(seconds: 30)) {
        justPast.add(t);
      } else {
        skippedStale++;
      }
    }
    debugPrint('[Reminder] sync: tasks=${_repo.tasks.length} '
        'withRemind=$withRemind future=${wanted.length} '
        'justPast=${justPast.length} skipStatus=$skippedStatus '
        'skipStale=$skippedStale now=$now');

    // 取消已失效（删除 / 完成 / remindAt 变化）的
    final toCancel = <String>[];
    for (final entry in _scheduled.entries) {
      final w = wanted[entry.key];
      if (w == null || w != entry.value) {
        toCancel.add(entry.key);
      }
    }
    for (final id in toCancel) {
      await _notifications.cancelTaskReminder(id);
      if (!_started) return;
      _scheduled.remove(id);
    }

    // 新增/重排
    for (final entry in wanted.entries) {
      final prev = _scheduled[entry.key];
      if (prev != null && prev == entry.value) continue;
      final t = _repo.taskById(entry.key);
      if (t == null) continue;
      await _notifications.scheduleTaskReminder(
        taskId: t.id,
        title: t.title.isEmpty ? '任务提醒' : t.title,
        body: _bodyFor(t),
        when: entry.value,
      );
      if (!_started) return;
      _scheduled[entry.key] = entry.value;
    }

    // 处理「刚刚过去」的：在前台立即弹 sheet（避免「设了一个 1 分钟内的提醒」却没反应的常见困惑）
    if (_started && _lifecycle == AppLifecycleState.resumed) {
      for (final t in justPast) {
        _showSheet(t);
      }
    }

    if (_started) _rescheduleForegroundTimer();
  }

  String _bodyFor(Task t) {
    switch (t.type) {
      case TaskType.block:
        if (t.startAt != null) {
          final h = t.startAt!.hour.toString().padLeft(2, '0');
          final m = t.startAt!.minute.toString().padLeft(2, '0');
          return '时间块即将开始（$h:$m）';
        }
        return '时间块提醒';
      case TaskType.ddl:
        return '截止任务提醒';
      case TaskType.todo:
        return '待办提醒';
    }
  }

  /// 找到最近一次未来提醒，设置一个 Timer；到点尝试弹 sheet。
  void _rescheduleForegroundTimer() {
    _foregroundTimer?.cancel();
    _foregroundTimer = null;
    if (_scheduled.isEmpty) return;
    final now = DateTime.now();
    DateTime? nextAt;
    for (final t in _scheduled.values) {
      if (t.isAfter(now) && (nextAt == null || t.isBefore(nextAt))) {
        nextAt = t;
      }
    }
    if (nextAt == null) return;
    final delta = nextAt.difference(now);
    // 避免 Timer 单次时长过长导致漂移：截断到 6 小时，到时刷新即可。
    // 提前 500ms 触发，给我们机会在前台时取消系统通知，避免与 sheet 重复。
    Duration wait;
    if (delta > const Duration(hours: 6)) {
      wait = const Duration(hours: 6);
    } else {
      wait = delta - const Duration(milliseconds: 500);
      if (wait < Duration.zero) wait = Duration.zero;
    }
    _foregroundTimer = Timer(wait, () {
      _maybeShowDuePopups();
      _rescheduleForegroundTimer();
    });
  }

  /// 检查所有「即将在 1 秒内到期 / 已到期」的提醒，在前台时为每个弹出 sheet。
  /// 过期超过 5 分钟的视为已错过，不再打扰用户（系统通知已在抽屉中提示过）。
  void _maybeShowDuePopups() {
    if (_lifecycle != AppLifecycleState.resumed) return;
    final now = DateTime.now();
    final threshold = now.add(const Duration(seconds: 1));
    final staleBefore = now.subtract(const Duration(minutes: 5));
    final due = <Task>[];
    for (final entry in _scheduled.entries.toList()) {
      if (!entry.value.isAfter(threshold)) {
        if (entry.value.isAfter(staleBefore)) {
          final t = _repo.taskById(entry.key);
          if (t != null) due.add(t);
        }
        _scheduled.remove(entry.key);
      }
    }
    debugPrint('[Reminder] tick: due=${due.length} lifecycle=$_lifecycle');
    for (final t in due) {
      _showSheet(t);
      // 已在前台显示，取消可能已经/将要弹出的系统通知，避免抽屉重复
      _notifications.cancelTaskReminder(t.id);
    }
  }

  void _showSheet(Task task) {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) {
      debugPrint('[Reminder] showSheet: root context is null, skip');
      return;
    }
    // 1 分钟内同一任务不重复弹
    final last = _recentlyShown[task.id];
    final now = DateTime.now();
    if (last != null && now.difference(last) < const Duration(minutes: 1)) {
      debugPrint('[Reminder] showSheet: dedup task=${task.id}');
      return;
    }
    _recentlyShown[task.id] = now;
    debugPrint('[Reminder] showSheet task=${task.id} title=${task.title}');
    // 用 microtask 避开当前帧 build / 通知回调栈
    Future.microtask(() {
      final c = rootNavigatorKey.currentContext;
      if (c == null) return;
      if (!c.mounted) return;
      ReminderSheet.show(c, task);
    });
  }
}
