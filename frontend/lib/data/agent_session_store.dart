import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Agent 会话 id 与历史消息本地快照（按登录邮箱隔离）。
class AgentSessionStore {
  AgentSessionStore(this._prefs);

  final SharedPreferences _prefs;

  static String _emailKey(String? email) {
    final e = email?.trim().toLowerCase();
    if (e == null || e.isEmpty) return '_guest';
    return e.replaceAll(RegExp(r'[^a-zA-Z0-9@._-]'), '_');
  }

  String _sessionIdPrefKey(String? email) =>
      'agent_last_session_id_${_emailKey(email)}';

  Future<File> _snapshotFile(String? email) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/agent_chat_${_emailKey(email)}.json');
  }

  Future<String?> getLastSessionId(String? email) async {
    final id = _prefs.getString(_sessionIdPrefKey(email));
    if (id == null || id.isEmpty) return null;
    return id;
  }

  Future<void> setLastSessionId(String? email, String sessionId) async {
    await _prefs.setString(_sessionIdPrefKey(email), sessionId);
  }

  Future<void> clearLastSessionId(String? email) async {
    await _prefs.remove(_sessionIdPrefKey(email));
  }

  /// 读取消息快照；[sessionId] 与存储不一致时返回 null。
  Future<AgentChatSnapshot?> loadSnapshot(String? email) async {
    try {
      final file = await _snapshotFile(email);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      final sid = decoded['session_id'] as String?;
      final raw = decoded['messages'];
      if (sid == null || sid.isEmpty || raw is! List) return null;
      final messages = raw.whereType<Map<String, dynamic>>().toList();
      return AgentChatSnapshot(sessionId: sid, messages: messages);
    } catch (e, st) {
      debugPrint('AgentSessionStore.loadSnapshot failed: $e\n$st');
      return null;
    }
  }

  Future<void> saveSnapshot({
    required String? email,
    required String sessionId,
    required List<Map<String, dynamic>> messages,
  }) async {
    try {
      final file = await _snapshotFile(email);
      final payload = jsonEncode({
        'session_id': sessionId,
        'saved_at': DateTime.now().toIso8601String(),
        'messages': messages,
      });
      await file.writeAsString(payload, flush: true);
      await setLastSessionId(email, sessionId);
    } catch (e, st) {
      debugPrint('AgentSessionStore.saveSnapshot failed: $e\n$st');
    }
  }

  Future<void> clearForUser(String? email) async {
    await clearLastSessionId(email);
    try {
      final file = await _snapshotFile(email);
      if (await file.exists()) await file.delete();
    } catch (e, st) {
      debugPrint('AgentSessionStore.clearForUser failed: $e\n$st');
    }
  }
}

class AgentChatSnapshot {
  const AgentChatSnapshot({
    required this.sessionId,
    required this.messages,
  });

  final String sessionId;
  final List<Map<String, dynamic>> messages;
}
