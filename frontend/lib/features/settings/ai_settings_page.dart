import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/ui/app_error_dialog.dart';
import '../../core/ui/app_message_dialog.dart';
import '../../data/ai_settings_repository.dart';
import '../../data/providers.dart';
import '../../shared/widgets/app_card.dart';

class AiSettingsPage extends ConsumerStatefulWidget {
  const AiSettingsPage({super.key});

  @override
  ConsumerState<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends ConsumerState<AiSettingsPage> {
  final _agentBaseUrlC = TextEditingController();
  final _agentApiKeyC = TextEditingController();
  final _agentModelC = TextEditingController();
  final _asrBaseUrlC = TextEditingController();
  final _asrApiKeyC = TextEditingController();
  final _asrModelC = TextEditingController();
  final _ttsBaseUrlC = TextEditingController();
  final _ttsApiKeyC = TextEditingController();
  final _ttsModelC = TextEditingController();
  final _ttsVoiceC = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  bool _showAgentKey = false;
  bool _showAsrKey = false;
  bool _showTtsKey = false;
  bool _hasAgentKey = false;
  bool _hasAsrKey = false;
  bool _hasTtsKey = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _agentBaseUrlC.dispose();
    _agentApiKeyC.dispose();
    _agentModelC.dispose();
    _asrBaseUrlC.dispose();
    _asrApiKeyC.dispose();
    _asrModelC.dispose();
    _ttsBaseUrlC.dispose();
    _ttsApiKeyC.dispose();
    _ttsModelC.dispose();
    _ttsVoiceC.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final cfg = await ref.read(aiSettingsRepositoryProvider).fetch();
      _applyConfig(cfg);
    } catch (e) {
      if (mounted) {
        await showAppErrorDialog(context, title: '读取失败', error: e);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyConfig(AiSettings cfg) {
    _agentBaseUrlC.text = cfg.baseUrl;
    _agentModelC.text = cfg.modelName;
    _asrBaseUrlC.text = cfg.asrBaseUrl;
    _asrModelC.text = cfg.asrModel;
    _ttsBaseUrlC.text = cfg.ttsBaseUrl;
    _ttsModelC.text = cfg.ttsModel;
    _ttsVoiceC.text = cfg.ttsVoice;
    _hasAgentKey = cfg.hasApiKey;
    _hasAsrKey = cfg.hasAsrApiKey;
    _hasTtsKey = cfg.hasTtsApiKey;
    _agentApiKeyC.clear();
    _asrApiKeyC.clear();
    _ttsApiKeyC.clear();
  }

  String _normalizeBaseUrl(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    return s.endsWith('/') ? s.substring(0, s.length - 1) : s;
  }

  Future<void> _save(String message) async {
    if (_saving || _testing) return;
    setState(() => _saving = true);
    try {
      final cfg = await ref
          .read(aiSettingsRepositoryProvider)
          .update(
            baseUrl: _normalizeBaseUrl(_agentBaseUrlC.text),
            apiKey: _agentApiKeyC.text.trim().isNotEmpty
                ? _agentApiKeyC.text.trim()
                : null,
            modelName: _agentModelC.text.trim(),
            asrBaseUrl: _normalizeBaseUrl(_asrBaseUrlC.text),
            asrApiKey: _asrApiKeyC.text.trim().isNotEmpty
                ? _asrApiKeyC.text.trim()
                : null,
            asrModel: _asrModelC.text.trim(),
            ttsBaseUrl: _normalizeBaseUrl(_ttsBaseUrlC.text),
            ttsApiKey: _ttsApiKeyC.text.trim().isNotEmpty
                ? _ttsApiKeyC.text.trim()
                : null,
            ttsModel: _ttsModelC.text.trim(),
            ttsVoice: _ttsVoiceC.text.trim(),
          );
      _applyConfig(cfg);
      if (mounted) {
        await showAppMessageDialog(context, title: '已保存', message: message);
      }
    } catch (e) {
      if (mounted) {
        await showAppErrorDialog(context, title: '保存失败', error: e);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clearApiKey(_KeyKind kind) async {
    if (_saving || _testing) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('清除 ${kind.label} API Key'),
        content: Text('确定要清除已保存的 ${kind.label} API Key 吗？'),
        actions: [
          TextButton(onPressed: () => ctx.pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => ctx.pop(true), child: const Text('确定')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(aiSettingsRepositoryProvider);
      final cfg = switch (kind) {
        _KeyKind.agent => await repo.update(apiKey: ''),
        _KeyKind.asr => await repo.update(asrApiKey: ''),
        _KeyKind.tts => await repo.update(ttsApiKey: ''),
      };
      _applyConfig(cfg);
      if (mounted) {
        await showAppMessageDialog(
          context,
          title: '已清除',
          message: '${kind.label} API Key 已移除',
        );
      }
    } catch (e) {
      if (mounted) {
        await showAppErrorDialog(context, title: '操作失败', error: e);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testAgent() async {
    if (_saving || _testing) return;
    setState(() => _testing = true);
    try {
      final msg = await ref
          .read(aiSettingsRepositoryProvider)
          .test(
            baseUrl: _normalizeBaseUrl(_agentBaseUrlC.text),
            apiKey: _agentApiKeyC.text.trim().isNotEmpty
                ? _agentApiKeyC.text.trim()
                : null,
            modelName: _agentModelC.text.trim(),
          );
      if (mounted) {
        await showAppMessageDialog(context, title: '测试成功', message: msg);
      }
    } catch (e) {
      if (mounted) {
        await showAppErrorDialog(context, title: '测试失败', error: e);
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appSettings = ref.watch(appSettingsRepositoryProvider);
    final asrCloud = appSettings.agentAsrProvider == 'cloud';
    final ttsCloud = appSettings.agentTtsProvider == 'cloud';

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('AI 配置'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _InterfaceCard(
                  title: '智能体 Agent',
                  subtitle: '用于任务理解、查询、规划与对话回复。配置保存到服务器，仅对当前账号生效。',
                  children: [
                    _CloudConfigFields(
                      baseUrlController: _agentBaseUrlC,
                      apiKeyController: _agentApiKeyC,
                      modelController: _agentModelC,
                      hasApiKey: _hasAgentKey,
                      showApiKey: _showAgentKey,
                      baseUrlLabel: 'Agent Base URL',
                      apiKeyLabel: 'Agent API Key',
                      modelLabel: 'Agent Model Name',
                      defaultModelHint: 'deepseek-v4-flash',
                      onToggleApiKey: () =>
                          setState(() => _showAgentKey = !_showAgentKey),
                      onSubmitted: () => _save('Agent 配置已更新'),
                    ),
                    _KeyStatusRow(
                      hasKey: _hasAgentKey,
                      label: 'Agent',
                      onClear: _saving
                          ? null
                          : () => _clearApiKey(_KeyKind.agent),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: (_saving || _testing)
                                ? null
                                : _testAgent,
                            child: Text(_testing ? '测试中...' : '测试连接'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: (_saving || _testing)
                                ? null
                                : () => _save('Agent 配置已更新'),
                            child: Text(_saving ? '保存中...' : '保存配置'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _InterfaceCard(
                  title: '语音识别 ASR',
                  subtitle: asrCloud
                      ? '云端模式通过后端代理调用当前账号的 ASR 接口。'
                      : '本地模式使用系统语音识别能力，不需要云端接口配置。',
                  trailing: _VoiceProviderSwitch(
                    value: appSettings.agentAsrProvider,
                    onChanged: (value) => ref
                        .read(appSettingsRepositoryProvider)
                        .setAgentAsrProvider(value),
                  ),
                  children: [
                    if (asrCloud) ...[
                      _CloudConfigFields(
                        baseUrlController: _asrBaseUrlC,
                        apiKeyController: _asrApiKeyC,
                        modelController: _asrModelC,
                        hasApiKey: _hasAsrKey,
                        showApiKey: _showAsrKey,
                        baseUrlLabel: 'ASR Base URL',
                        apiKeyLabel: 'ASR API Key',
                        modelLabel: 'ASR Model Name',
                        defaultModelHint: 'qwen3-asr-flash',
                        onToggleApiKey: () =>
                            setState(() => _showAsrKey = !_showAsrKey),
                        onSubmitted: () => _save('ASR 配置已更新'),
                      ),
                      _KeyStatusRow(
                        hasKey: _hasAsrKey,
                        label: 'ASR',
                        onClear: _saving
                            ? null
                            : () => _clearApiKey(_KeyKind.asr),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: (_saving || _testing)
                            ? null
                            : () => _save('ASR 配置已更新'),
                        child: Text(_saving ? '保存中...' : '保存 ASR 配置'),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                _InterfaceCard(
                  title: '语音合成 TTS',
                  subtitle: ttsCloud
                      ? '云端模式通过后端代理调用当前账号的 TTS 接口。'
                      : '本地模式使用系统语音合成能力，不需要云端接口配置。',
                  trailing: _VoiceProviderSwitch(
                    value: appSettings.agentTtsProvider,
                    onChanged: (value) => ref
                        .read(appSettingsRepositoryProvider)
                        .setAgentTtsProvider(value),
                  ),
                  children: [
                    if (ttsCloud) ...[
                      _CloudConfigFields(
                        baseUrlController: _ttsBaseUrlC,
                        apiKeyController: _ttsApiKeyC,
                        modelController: _ttsModelC,
                        hasApiKey: _hasTtsKey,
                        showApiKey: _showTtsKey,
                        baseUrlLabel: 'TTS Base URL',
                        apiKeyLabel: 'TTS API Key',
                        modelLabel: 'TTS Model Name',
                        defaultModelHint: 'qwen3-tts-flash',
                        onToggleApiKey: () =>
                            setState(() => _showTtsKey = !_showTtsKey),
                        onSubmitted: () => _save('TTS 配置已更新'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _ttsVoiceC,
                        decoration: const InputDecoration(
                          labelText: 'TTS Voice',
                          hintText: 'Cherry',
                        ),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _save('TTS 配置已更新'),
                      ),
                      _KeyStatusRow(
                        hasKey: _hasTtsKey,
                        label: 'TTS',
                        onClear: _saving
                            ? null
                            : () => _clearApiKey(_KeyKind.tts),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: (_saving || _testing)
                            ? null
                            : () => _save('TTS 配置已更新'),
                        child: Text(_saving ? '保存中...' : '保存 TTS 配置'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
    );
  }
}

enum _KeyKind {
  agent('Agent'),
  asr('ASR'),
  tts('TTS');

  const _KeyKind(this.label);
  final String label;
}

class _InterfaceCard extends StatelessWidget {
  const _InterfaceCard({
    required this.title,
    required this.subtitle,
    required this.children,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          if (children.isNotEmpty) ...[const SizedBox(height: 14), ...children],
        ],
      ),
    );
  }
}

class _CloudConfigFields extends StatelessWidget {
  const _CloudConfigFields({
    required this.baseUrlController,
    required this.apiKeyController,
    required this.modelController,
    required this.hasApiKey,
    required this.showApiKey,
    required this.baseUrlLabel,
    required this.apiKeyLabel,
    required this.modelLabel,
    required this.defaultModelHint,
    required this.onToggleApiKey,
    required this.onSubmitted,
  });

  final TextEditingController baseUrlController;
  final TextEditingController apiKeyController;
  final TextEditingController modelController;
  final bool hasApiKey;
  final bool showApiKey;
  final String baseUrlLabel;
  final String apiKeyLabel;
  final String modelLabel;
  final String defaultModelHint;
  final VoidCallback onToggleApiKey;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: baseUrlController,
          decoration: InputDecoration(
            labelText: baseUrlLabel,
            hintText: '例如 https://api.openai.com/v1',
          ),
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: apiKeyController,
          obscureText: !showApiKey,
          decoration: InputDecoration(
            labelText: apiKeyLabel,
            hintText: hasApiKey ? '已保存（留空保持不变）' : '请输入 API Key',
            suffixIcon: IconButton(
              icon: Icon(showApiKey ? Icons.visibility_off : Icons.visibility),
              onPressed: onToggleApiKey,
            ),
          ),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: modelController,
          decoration: InputDecoration(
            labelText: modelLabel,
            hintText: defaultModelHint,
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onSubmitted(),
        ),
      ],
    );
  }
}

class _KeyStatusRow extends StatelessWidget {
  const _KeyStatusRow({
    required this.hasKey,
    required this.label,
    required this.onClear,
  });

  final bool hasKey;
  final String label;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Icon(
            hasKey ? Icons.verified_rounded : Icons.info_outline,
            size: 16,
            color: hasKey ? AppColors.primary : AppColors.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            hasKey ? '已保存 $label API Key' : '未保存 $label API Key',
            style: const TextStyle(
              color: AppColors.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const Spacer(),
          if (hasKey) TextButton(onPressed: onClear, child: const Text('清除')),
        ],
      ),
    );
  }
}

class _VoiceProviderSwitch extends StatelessWidget {
  const _VoiceProviderSwitch({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'local', label: Text('本地')),
        ButtonSegment(value: 'cloud', label: Text('云端')),
      ],
      selected: {value == 'cloud' ? 'cloud' : 'local'},
      onSelectionChanged: (next) => onChanged(next.first),
      showSelectedIcon: false,
    );
  }
}
