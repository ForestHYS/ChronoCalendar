import '../core/api/api_client.dart';

class AgentRepository {
  AgentRepository(this._api);

  final ApiClient _api;

  Future<String> createSession() async {
    final data = await _api.request('POST', 'agent/sessions/', body: {}, auth: true);
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
        if (clientContext != null) 'client_context': clientContext,
      },
      auth: true,
    );
    if (data is Map<String, dynamic>) {
      final resp = data['response'];
      if (resp is Map<String, dynamic>) return resp;
    }
    throw StateError('发送失败');
  }
}

