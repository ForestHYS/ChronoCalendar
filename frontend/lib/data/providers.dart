import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_repository.dart';
import 'task_repository.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Override in main()');
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(sharedPreferencesProvider));
});

class AuthNotifier extends ChangeNotifier {
  AuthNotifier(this._repo) {
    _sync();
  }

  final AuthRepository _repo;

  void _sync() {
    _loggedIn = _repo.isLoggedIn;
  }

  bool _loggedIn = false;
  bool get isLoggedIn => _loggedIn;

  Future<void> login(String email, String password) async {
    await _repo.login(email, password);
    _sync();
    notifyListeners();
  }

  Future<void> logout() async {
    await _repo.logout();
    _sync();
    notifyListeners();
  }
}

final authNotifierProvider = ChangeNotifierProvider<AuthNotifier>((ref) {
  return AuthNotifier(ref.watch(authRepositoryProvider));
});

final taskRepositoryProvider = ChangeNotifierProvider<TaskRepository>((ref) {
  return TaskRepository();
});
