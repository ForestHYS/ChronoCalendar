import 'package:shared_preferences/shared_preferences.dart';

const _kFocusSec = 'pomodoro_focus_seconds';
const _kRestSec = 'pomodoro_rest_seconds';
const _kWake = 'pomodoro_wakelock';

/// 番茄钟偏好（本地 SharedPreferences，后续可对接 API）。
class PomodoroSettingsRepository {
  PomodoroSettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const int defaultFocusSeconds = 25 * 60;
  static const int defaultRestSeconds = 5 * 60;

  int get focusSeconds => (_prefs.getInt(_kFocusSec) ?? defaultFocusSeconds).clamp(60, 180 * 60);

  int get restSeconds => (_prefs.getInt(_kRestSec) ?? defaultRestSeconds).clamp(60, 120 * 60);

  bool get wakelockWhileRunning => _prefs.getBool(_kWake) ?? true;

  Future<void> setFocusSeconds(int v) async {
    await _prefs.setInt(_kFocusSec, v.clamp(60, 180 * 60));
  }

  Future<void> setRestSeconds(int v) async {
    await _prefs.setInt(_kRestSec, v.clamp(60, 120 * 60));
  }

  Future<void> setWakelockWhileRunning(bool v) async {
    await _prefs.setBool(_kWake, v);
  }
}
