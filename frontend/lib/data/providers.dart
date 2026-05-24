import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api/api_client.dart';
import '../core/notifications/notification_service.dart';
import '../core/notifications/reminder_scheduler.dart';
import 'auth_repository.dart';
import 'agent_repository.dart';
import 'pomodoro_settings_repository.dart';
import 'task_repository.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Override in main()');
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref.watch(sharedPreferencesProvider));
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(sharedPreferencesProvider), ref.watch(apiClientProvider));
});

final pomodoroSettingsRepositoryProvider = Provider<PomodoroSettingsRepository>((ref) {
  return PomodoroSettingsRepository(ref.watch(sharedPreferencesProvider));
});

final taskRepositoryProvider = ChangeNotifierProvider<TaskRepository>((ref) {
  return TaskRepository(ref.watch(apiClientProvider));
});

final agentRepositoryProvider = Provider<AgentRepository>((ref) {
  return AgentRepository(ref.watch(apiClientProvider));
});

/// 全局唯一的提醒调度器。由 [CalendarApp] 在登录态变化时 start/stop。
///
/// 必须用 `ref.read` 而非 `ref.watch`：[taskRepositoryProvider] 是
/// `ChangeNotifierProvider`，每次 repo `notifyListeners()` 都会让 watch 它的 provider
/// 重建。一旦重建，旧 scheduler 被 dispose（listener 被摘掉），新 scheduler 从未
/// 调用过 `start()`，整个调度链就此断掉。
final reminderSchedulerProvider = Provider<ReminderScheduler>((ref) {
  final scheduler = ReminderScheduler(
    ref.read(taskRepositoryProvider),
    NotificationService.instance,
  );
  ref.onDispose(() {
    // onDispose 是同步回调，stop() 是 async；不能 await，必须主动接住异常，
    // 否则 stop 内部 await 链路上任何抛出都会变成未处理的异步错误。
    scheduler.stop().then(
      (_) {},
      onError: (Object e, StackTrace st) {
        debugPrint('reminderScheduler.stop() failed in onDispose: $e\n$st');
      },
    );
  });
  return scheduler;
});

class AuthNotifier extends ChangeNotifier {
  AuthNotifier(this._repo, this._taskRepo) {
    _sync();
  }

  final AuthRepository _repo;
  final TaskRepository _taskRepo;

  void _sync() {
    _loggedIn = _repo.isLoggedIn;
  }

  bool _loggedIn = false;
  bool get isLoggedIn => _loggedIn;

  Future<void> login(String email, String password) async {
    await _repo.login(email, password);
    _sync();
    notifyListeners();
    try {
      await _taskRepo.bootstrap();
    } catch (e) {
      _taskRepo.clearLocalCache();
      await _repo.logout();
      _sync();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> register({
    required String email,
    required String password,
    String? name,
  }) async {
    await _repo.register(email: email, password: password, name: name);
    _sync();
    notifyListeners();
    try {
      await _taskRepo.bootstrap();
    } catch (e) {
      _taskRepo.clearLocalCache();
      await _repo.logout();
      _sync();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> logout() async {
    _taskRepo.clearLocalCache();
    await _repo.logout();
    _sync();
    notifyListeners();
  }

  Future<void> updateNickname(String nickname) async {
    await _repo.updateNickname(nickname);
  }

  Future<void> changePassword({required String current, required String next}) async {
    await _repo.changePassword(current: current, next: next);
  }
}

/// 昵称等资料变更后递增，供设置页刷新展示（不触发 GoRouter 重建）。
final profileRefreshProvider = StateProvider<int>((ref) => 0);

/// 底栏 Tab 切换方向：1 向右切（索引增大），−1 向左切。
final shellNavDirectionProvider = StateProvider<int>((ref) => 1);

final authNotifierProvider = ChangeNotifierProvider<AuthNotifier>((ref) {
  return AuthNotifier(
    ref.watch(authRepositoryProvider),
    // 必须用 read：若 watch TaskRepository，clearLocalCache() 会 notifyListeners，
    // Riverpod 会 dispose 本 AuthNotifier，异步 logout 末尾再 notifyListeners 会崩溃。
    ref.read(taskRepositoryProvider),
  );
});
