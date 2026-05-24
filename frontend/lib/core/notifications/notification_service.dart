import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// 单例：封装本地通知（基于 AlarmManager 的精确闹钟）。
///
/// 仅 Android 端做了完整适配（权限、receiver、精确闹钟）。其他端会无操作降级。
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// 首次 [init] 调用返回的 Future，并发的后续调用都 await 这个，避免重复初始化。
  Future<void>? _initFuture;

  /// 真正初始化完成后才置为 true。其他方法据此判定是否可安全调用 plugin。
  bool _ready = false;

  /// 通知被点击时回调（携带任务 id）。
  final StreamController<String> _tapStream =
      StreamController<String>.broadcast();
  Stream<String> get onNotificationTapped => _tapStream.stream;

  /// 启动时的「冷启动负载」：通过点击通知打开 app 时，第一帧可读取。
  String? launchTaskId;

  static const _channelId = 'task_reminder';
  static const _channelName = '任务提醒';
  static const _channelDesc = '任务到达设定提醒时间时的通知';

  /// 在 `main()` 中 `runApp` 之前调用。并发/重复调用安全（共享同一个 Future）。
  Future<void> init() => _initFuture ??= _doInit();

  Future<void> _doInit() async {
    tzdata.initializeTimeZones();
    // 应用 locale 为 zh_CN，默认使用上海时区；如需精准 DST 可后续接入 flutter_native_timezone。
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    } catch (e) {
      // 时区库缺失时退化使用 UTC，仍可调度但展示时间可能偏差
      debugPrint('[Notif] setLocalLocation failed: $e');
    }
    debugPrint('[Notif] init begin, tz=${tz.local.name}');

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _handleResponse,
      onDidReceiveBackgroundNotificationResponse:
          _handleBackgroundResponseEntry,
    );

    // 创建通知渠道（Android 8+）
    final androidImpl =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      await androidImpl.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDesc,
          importance: Importance.high,
        ),
      );
    }

    // 读取冷启动负载（用户从通知点开 app 时）
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp ?? false) {
      launchTaskId = details?.notificationResponse?.payload;
    }
    _ready = true;
    debugPrint('[Notif] init done');
  }

  /// 申请运行时权限：通知（Android 13+）+ 精确闹钟（Android 12+）。
  /// 在用户首次进入需要提醒的页面时调用（例如首次启用提醒、登录后）。
  Future<bool> requestPermissions() async {
    if (!_ready) return false;
    bool granted = true;

    // Android 13+ POST_NOTIFICATIONS
    final notif = await Permission.notification.status;
    if (!notif.isGranted) {
      final r = await Permission.notification.request();
      granted = granted && r.isGranted;
    }

    final androidImpl =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      // 部分 OEM 上 plugin 侧也会再次申请通知权限
      await androidImpl.requestNotificationsPermission();
      // 精确闹钟（Android 12 / API 31+）
      try {
        await androidImpl.requestExactAlarmsPermission();
      } catch (_) {
        // 旧设备无此能力，忽略
      }
    }

    return granted;
  }

  /// 调度（或重置）某任务的提醒通知。已存在则覆盖。
  /// [when] 必须为未来时间，否则方法直接返回不调度。
  Future<void> scheduleTaskReminder({
    required String taskId,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    if (!_ready) {
      debugPrint('[Notif] schedule skipped: not initialized ($taskId)');
      return;
    }
    final now = DateTime.now();
    if (!when.isAfter(now)) {
      debugPrint('[Notif] schedule skipped: when in past ($taskId, when=$when, now=$now)');
      return;
    }

    final id = _idFromTaskId(taskId);
    final tzWhen = tz.TZDateTime.from(when, tz.local);
    debugPrint('[Notif] schedule task=$taskId id=$id at=$tzWhen (delta=${when.difference(now).inSeconds}s)');

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
    );
    const details = NotificationDetails(android: androidDetails);

    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tzWhen,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: taskId,
      );
      debugPrint('[Notif] schedule ok (exact) task=$taskId');
    } catch (e) {
      // 精确闹钟未授权时降级为非精确调度（仍能在大致时间触发）
      debugPrint('[Notif] schedule exact failed: $e -> retry inexact');
      try {
        await _plugin.zonedSchedule(
          id,
          title,
          body,
          tzWhen,
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: taskId,
        );
        debugPrint('[Notif] schedule ok (inexact) task=$taskId');
      } catch (e2) {
        debugPrint('[Notif] schedule inexact failed: $e2');
      }
    }
  }

  /// 取消某任务的提醒。
  Future<void> cancelTaskReminder(String taskId) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(_idFromTaskId(taskId));
    } catch (e) {
      debugPrint('[Notif] cancel($taskId) failed: $e');
    }
  }

  /// 取消全部（登出时调用）。
  Future<void> cancelAll() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('[Notif] cancelAll failed: $e');
    }
  }

  void _handleResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      _tapStream.add(payload);
    }
  }

  static int _idFromTaskId(String id) {
    // 通知 id 需要 32-bit 正整数。
    return id.hashCode & 0x7fffffff;
  }
}

/// 后台回调必须是顶层/静态函数。当前不做处理（点击会带 payload，app 启动后再消费）。
@pragma('vm:entry-point')
void _handleBackgroundResponseEntry(NotificationResponse response) {
  // no-op
}
