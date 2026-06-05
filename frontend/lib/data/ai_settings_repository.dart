import '../core/api/api_client.dart';

const _defaultAgentBaseUrl = 'https://api.deepseek.com/';
const _defaultAgentModel = 'deepseek-v4-flash';
const _defaultAsrModel = 'qwen3-asr-flash';
const _defaultTtsModel = 'qwen3-tts-flash';
const _defaultTtsVoice = 'Cherry';

class AiSettings {
  const AiSettings({
    required this.baseUrl,
    required this.hasApiKey,
    required this.modelName,
    required this.asrBaseUrl,
    required this.hasAsrApiKey,
    required this.asrModel,
    required this.ttsBaseUrl,
    required this.hasTtsApiKey,
    required this.ttsModel,
    required this.ttsVoice,
  });

  final String baseUrl;
  final bool hasApiKey;
  final String modelName;
  final String asrBaseUrl;
  final bool hasAsrApiKey;
  final String asrModel;
  final String ttsBaseUrl;
  final bool hasTtsApiKey;
  final String ttsModel;
  final String ttsVoice;
}

class AiSettingsRepository {
  AiSettingsRepository(this._api);

  final ApiClient _api;

  Future<AiSettings> fetch() async {
    final data = await _api.request('GET', 'agent/llm-config/', auth: true);
    if (data is Map<String, dynamic>) {
      final baseUrl = data['base_url'] as String? ?? _defaultAgentBaseUrl;
      final hasApiKey = data['has_api_key'] == true;
      final modelName = data['model_name'] as String? ?? _defaultAgentModel;
      final asrBaseUrl = data['asr_base_url'] as String? ?? '';
      final hasAsrApiKey = data['has_asr_api_key'] == true;
      final asrModel = data['asr_model'] as String? ?? _defaultAsrModel;
      final ttsBaseUrl = data['tts_base_url'] as String? ?? '';
      final hasTtsApiKey = data['has_tts_api_key'] == true;
      final ttsModel = data['tts_model'] as String? ?? _defaultTtsModel;
      final ttsVoice = data['tts_voice'] as String? ?? _defaultTtsVoice;
      return AiSettings(
        baseUrl: baseUrl,
        hasApiKey: hasApiKey,
        modelName: modelName,
        asrBaseUrl: asrBaseUrl,
        hasAsrApiKey: hasAsrApiKey,
        asrModel: asrModel,
        ttsBaseUrl: ttsBaseUrl,
        hasTtsApiKey: hasTtsApiKey,
        ttsModel: ttsModel,
        ttsVoice: ttsVoice,
      );
    }
    return const AiSettings(
      baseUrl: _defaultAgentBaseUrl,
      hasApiKey: false,
      modelName: _defaultAgentModel,
      asrBaseUrl: '',
      hasAsrApiKey: false,
      asrModel: _defaultAsrModel,
      ttsBaseUrl: '',
      hasTtsApiKey: false,
      ttsModel: _defaultTtsModel,
      ttsVoice: _defaultTtsVoice,
    );
  }

  Future<AiSettings> update({
    String? baseUrl,
    String? apiKey,
    String? modelName,
    String? asrBaseUrl,
    String? asrApiKey,
    String? asrModel,
    String? ttsBaseUrl,
    String? ttsApiKey,
    String? ttsModel,
    String? ttsVoice,
  }) async {
    final body = <String, dynamic>{};
    if (baseUrl != null) body['base_url'] = baseUrl;
    if (apiKey != null) body['api_key'] = apiKey;
    if (modelName != null) body['model_name'] = modelName;
    if (asrBaseUrl != null) body['asr_base_url'] = asrBaseUrl;
    if (asrApiKey != null) body['asr_api_key'] = asrApiKey;
    if (asrModel != null) body['asr_model'] = asrModel;
    if (ttsBaseUrl != null) body['tts_base_url'] = ttsBaseUrl;
    if (ttsApiKey != null) body['tts_api_key'] = ttsApiKey;
    if (ttsModel != null) body['tts_model'] = ttsModel;
    if (ttsVoice != null) body['tts_voice'] = ttsVoice;
    final data = await _api.request(
      'PATCH',
      'agent/llm-config/',
      body: body,
      auth: true,
    );
    if (data is Map<String, dynamic>) {
      final nextBaseUrl = data['base_url'] as String? ?? _defaultAgentBaseUrl;
      final hasApiKey = data['has_api_key'] == true;
      final nextModelName = data['model_name'] as String? ?? _defaultAgentModel;
      final nextAsrBaseUrl = data['asr_base_url'] as String? ?? '';
      final hasAsrApiKey = data['has_asr_api_key'] == true;
      final nextAsrModel = data['asr_model'] as String? ?? _defaultAsrModel;
      final nextTtsBaseUrl = data['tts_base_url'] as String? ?? '';
      final hasTtsApiKey = data['has_tts_api_key'] == true;
      final nextTtsModel = data['tts_model'] as String? ?? _defaultTtsModel;
      final nextTtsVoice = data['tts_voice'] as String? ?? _defaultTtsVoice;
      return AiSettings(
        baseUrl: nextBaseUrl,
        hasApiKey: hasApiKey,
        modelName: nextModelName,
        asrBaseUrl: nextAsrBaseUrl,
        hasAsrApiKey: hasAsrApiKey,
        asrModel: nextAsrModel,
        ttsBaseUrl: nextTtsBaseUrl,
        hasTtsApiKey: hasTtsApiKey,
        ttsModel: nextTtsModel,
        ttsVoice: nextTtsVoice,
      );
    }
    return const AiSettings(
      baseUrl: _defaultAgentBaseUrl,
      hasApiKey: false,
      modelName: _defaultAgentModel,
      asrBaseUrl: '',
      hasAsrApiKey: false,
      asrModel: _defaultAsrModel,
      ttsBaseUrl: '',
      hasTtsApiKey: false,
      ttsModel: _defaultTtsModel,
      ttsVoice: _defaultTtsVoice,
    );
  }

  Future<String> test({
    String? baseUrl,
    String? apiKey,
    String? modelName,
  }) async {
    final body = <String, dynamic>{};
    if (baseUrl != null) body['base_url'] = baseUrl;
    if (apiKey != null) body['api_key'] = apiKey;
    if (modelName != null) body['model_name'] = modelName;
    final data = await _api.request(
      'POST',
      'agent/llm-test/',
      body: body,
      auth: true,
    );
    if (data is Map<String, dynamic>) {
      final msg = data['message'] as String?;
      if (msg != null && msg.isNotEmpty) return msg;
    }
    return '连接成功';
  }
}
