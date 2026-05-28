import '../core/api/api_client.dart';

class AiSettings {
  const AiSettings({
    required this.baseUrl,
    required this.hasApiKey,
    required this.modelName,
  });

  final String baseUrl;
  final bool hasApiKey;
  final String modelName;
}

class AiSettingsRepository {
  AiSettingsRepository(this._api);

  final ApiClient _api;

  Future<AiSettings> fetch() async {
    final data = await _api.request('GET', 'agent/llm-config/', auth: true);
    if (data is Map<String, dynamic>) {
      final baseUrl = data['base_url'] as String? ?? '';
      final hasApiKey = data['has_api_key'] == true;
      final modelName = data['model_name'] as String? ?? '';
      return AiSettings(baseUrl: baseUrl, hasApiKey: hasApiKey, modelName: modelName);
    }
    return const AiSettings(baseUrl: '', hasApiKey: false, modelName: '');
  }

  Future<AiSettings> update({String? baseUrl, String? apiKey, String? modelName}) async {
    final body = <String, dynamic>{};
    if (baseUrl != null) body['base_url'] = baseUrl;
    if (apiKey != null) body['api_key'] = apiKey;
    if (modelName != null) body['model_name'] = modelName;
    final data = await _api.request('PATCH', 'agent/llm-config/', body: body, auth: true);
    if (data is Map<String, dynamic>) {
      final nextBaseUrl = data['base_url'] as String? ?? '';
      final hasApiKey = data['has_api_key'] == true;
      final nextModelName = data['model_name'] as String? ?? '';
      return AiSettings(baseUrl: nextBaseUrl, hasApiKey: hasApiKey, modelName: nextModelName);
    }
    return const AiSettings(baseUrl: '', hasApiKey: false, modelName: '');
  }

  Future<String> test({String? baseUrl, String? apiKey, String? modelName}) async {
    final body = <String, dynamic>{};
    if (baseUrl != null) body['base_url'] = baseUrl;
    if (apiKey != null) body['api_key'] = apiKey;
    if (modelName != null) body['model_name'] = modelName;
    final data = await _api.request('POST', 'agent/llm-test/', body: body, auth: true);
    if (data is Map<String, dynamic>) {
      final msg = data['message'] as String?;
      if (msg != null && msg.isNotEmpty) return msg;
    }
    return '连接成功';
  }
}
