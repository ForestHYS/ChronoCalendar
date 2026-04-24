import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api/api_client.dart';
import 'auth_repository.dart';
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
}

final authNotifierProvider = ChangeNotifierProvider<AuthNotifier>((ref) {
  return AuthNotifier(
    ref.watch(authRepositoryProvider),
    ref.watch(taskRepositoryProvider),
  );
});
