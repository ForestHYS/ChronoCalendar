import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kAutoDeleteCompletedHours = 'auto_delete_completed_hours';
const _kAutoDeleteOverdueHours = 'auto_delete_overdue_hours';
const _kPinnedTodoIds = 'pinned_todo_ids';
const _kHomeTodoShortcutIds = 'home_todo_shortcut_ids';
const _kAgentAutoSpeak = 'agent_auto_speak';

/// 应用级本地偏好（非番茄钟）。
class AppSettingsRepository extends ChangeNotifier {
  AppSettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const maxPinnedTodos = 3;
  static const homeShortcutTodoLimit = 3;

  /// 标记完成后自动删除的延迟（小时）；`0` 表示关闭。
  int get autoDeleteCompletedAfterHours =>
      (_prefs.getInt(_kAutoDeleteCompletedHours) ?? 0).clamp(0, 24 * 365);

  /// 超时后自动删除的延迟（小时，自截止/结束时间起算）；`0` 表示关闭。
  int get autoDeleteOverdueAfterHours =>
      (_prefs.getInt(_kAutoDeleteOverdueHours) ?? 0).clamp(0, 24 * 365);

  List<String> get pinnedTodoIds =>
      List.unmodifiable(_prefs.getStringList(_kPinnedTodoIds) ?? const []);

  /// 主页 Todo 快捷栏展示顺序（最多 [homeShortcutTodoLimit] 个 id）。
  List<String> get homeTodoShortcutIds => List.unmodifiable(
    _prefs.getStringList(_kHomeTodoShortcutIds) ?? const [],
  );

  bool get agentAutoSpeak => _prefs.getBool(_kAgentAutoSpeak) ?? false;

  bool isTodoPinned(String id) => pinnedTodoIds.contains(id);

  bool get canPinMoreTodos => pinnedTodoIds.length < maxPinnedTodos;

  static const autoDeleteOptions = <(int hours, String label)>[
    (0, '关闭'),
    (1, '1 小时'),
    (6, '6 小时'),
    (24, '1 天'),
    (72, '3 天'),
    (168, '7 天'),
    (720, '30 天'),
  ];

  String labelForAutoDeleteHours(int hours) {
    for (final o in autoDeleteOptions) {
      if (o.$1 == hours) return o.$2;
    }
    if (hours <= 0) return '关闭';
    if (hours % 24 == 0) return '${hours ~/ 24} 天';
    return '$hours 小时';
  }

  Future<void> setAutoDeleteCompletedAfterHours(int hours) async {
    await _prefs.setInt(_kAutoDeleteCompletedHours, hours.clamp(0, 24 * 365));
    notifyListeners();
  }

  Future<void> setAutoDeleteOverdueAfterHours(int hours) async {
    await _prefs.setInt(_kAutoDeleteOverdueHours, hours.clamp(0, 24 * 365));
    notifyListeners();
  }

  Future<void> setHomeTodoShortcutIds(List<String> ids) async {
    await _prefs.setStringList(
      _kHomeTodoShortcutIds,
      ids.take(homeShortcutTodoLimit).toList(),
    );
    notifyListeners();
  }

  Future<void> setAgentAutoSpeak(bool enabled) async {
    await _prefs.setBool(_kAgentAutoSpeak, enabled);
    notifyListeners();
  }

  /// 固定 Todo 到主页快捷栏；已满 [maxPinnedTodos] 个时返回 `false`。
  Future<bool> setTodoPinned(String taskId, bool pinned) async {
    var ids = List<String>.from(pinnedTodoIds);
    if (pinned) {
      if (ids.contains(taskId)) return true;
      if (ids.length >= maxPinnedTodos) return false;
      ids.add(taskId);
    } else {
      ids.remove(taskId);
    }
    await _prefs.setStringList(_kPinnedTodoIds, ids);
    notifyListeners();
    return true;
  }
}
