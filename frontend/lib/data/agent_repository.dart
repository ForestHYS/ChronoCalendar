import '../core/api/api_client.dart';

class AgentRepository {
  AgentRepository(this._api);

  final ApiClient _api;

  Future<String> createSession() async {
    final data = await _api.request(
      'POST',
      'agent/sessions/',
      body: {},
      auth: true,
    );
    if (data is Map<String, dynamic>) {
      final id = data['id'];
      if (id is String && id.isNotEmpty) return id;
    }
    throw StateError('创建会话失败');
  }

  Future<Map<String, dynamic>> sendMessage({
    required String sessionId,
    required String text,
    Map<String, dynamic>? clientContext,
  }) async {
    final data = await _api.request(
      'POST',
      'agent/sessions/$sessionId/messages/',
      body: {
        'text': text,
        // ignore: use_null_aware_elements
        if (clientContext != null) 'client_context': clientContext,
      },
      auth: true,
    );
    if (data is Map<String, dynamic>) {
      final resp = data['response'];
      if (resp is Map<String, dynamic>) {
        return {
          'response': resp,
          'assistant_message_id': data['assistant_message_id'] as String?,
        };
      }
    }
    throw StateError('发送失败');
  }

  /// 获取当前用户的会话列表（按 updated_at 倒序，最多 20 条）。
  Future<List<Map<String, dynamic>>> getSessions() async {
    final data = await _api.request('GET', 'agent/sessions/', auth: true);
    if (data is List) return data.whereType<Map<String, dynamic>>().toList();
    return [];
  }

  /// 获取指定会话的所有消息（按 created_at 正序）。
  Future<List<Map<String, dynamic>>> getMessages(String sessionId) async {
    final data = await _api.request(
      'GET',
      'agent/sessions/$sessionId/messages/',
      auth: true,
    );
    if (data is List) return data.whereType<Map<String, dynamic>>().toList();
    return [];
  }

  /// 批准高危操作（如删除任务）；返回与消息接口一致的 `response`。
  Future<Map<String, dynamic>> approveApproval(String approvalId) async {
    final data = await _api.request(
      'POST',
      'agent/approvals/$approvalId/approve/',
      body: {},
      auth: true,
    );
    if (data is Map<String, dynamic>) {
      final resp = data['response'];
      if (resp is Map<String, dynamic>) return resp;
    }
    throw StateError('批准失败');
  }

  Future<Map<String, dynamic>> rejectApproval(String approvalId) async {
    final data = await _api.request(
      'POST',
      'agent/approvals/$approvalId/reject/',
      body: {},
      auth: true,
    );
    if (data is Map<String, dynamic>) {
      final resp = data['response'];
      if (resp is Map<String, dynamic>) return resp;
    }
    throw StateError('拒绝失败');
  }

  /// 用户确认长期规划预览后，批量创建所有任务。
  Future<Map<String, dynamic>> confirmPlan(
    List<Map<String, dynamic>> tasks, {
    Map<String, dynamic>? clientContext,
    String? sourceMessageId,
  }) async {
    final data = await _api.request(
      'POST',
      'agent/confirm-plan/',
      body: {
        'tasks': tasks,
        if (clientContext != null) 'client_context': clientContext,
        if (sourceMessageId != null && sourceMessageId.isNotEmpty)
          'source_message_id': sourceMessageId,
      },
      auth: true,
    );
    if (data is Map<String, dynamic>) {
      final resp = data['response'];
      if (resp is Map<String, dynamic>) return resp;
    }
    throw StateError('确认计划失败');
  }
}
