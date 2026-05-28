import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/ui/app_error_dialog.dart';
import '../../core/ui/app_message_dialog.dart';
import '../../data/providers.dart';
import '../../shared/widgets/app_card.dart';

class AiSettingsPage extends ConsumerStatefulWidget {
  const AiSettingsPage({super.key});

  @override
  ConsumerState<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends ConsumerState<AiSettingsPage> {
  final _baseUrlC = TextEditingController();
  final _apiKeyC = TextEditingController();
  final _modelC = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  bool _showKey = false;
  bool _hasKey = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseUrlC.dispose();
    _apiKeyC.dispose();
    _modelC.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(aiSettingsRepositoryProvider);
      final cfg = await repo.fetch();
      _baseUrlC.text = cfg.baseUrl;
      _modelC.text = cfg.modelName;
      _hasKey = cfg.hasApiKey;
    } catch (e) {
      if (mounted) {
        await showAppErrorDialog(context, title: '读取失败', error: e);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _normalizeBaseUrl(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    return s.endsWith('/') ? s.substring(0, s.length - 1) : s;
  }

  Future<void> _save() async {
    if (_saving || _testing) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(aiSettingsRepositoryProvider);
      final baseUrl = _normalizeBaseUrl(_baseUrlC.text);
      final apiKey = _apiKeyC.text.trim();
      final modelName = _modelC.text.trim();
      final cfg = await repo.update(
        baseUrl: baseUrl,
        apiKey: apiKey.isNotEmpty ? apiKey : null,
        modelName: modelName,
      );
      _baseUrlC.text = cfg.baseUrl;
      _modelC.text = cfg.modelName;
      _hasKey = cfg.hasApiKey;
      _apiKeyC.clear();
      if (mounted) {
        await showAppMessageDialog(context, title: '已保存', message: 'AI 配置已更新');
      }
    } catch (e) {
      if (mounted) {
        await showAppErrorDialog(context, title: '保存失败', error: e);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clearApiKey() async {
    if (_saving || _testing) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除 API Key'),
        content: const Text('确定要清除已保存的 API Key 吗？清除后 AI 将无法使用。'),
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
      final cfg = await repo.update(apiKey: '');
      _hasKey = cfg.hasApiKey;
      if (mounted) {
        await showAppMessageDialog(context, title: '已清除', message: 'API Key 已移除');
      }
    } catch (e) {
      if (mounted) {
        await showAppErrorDialog(context, title: '操作失败', error: e);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _test() async {
    if (_saving || _testing) return;
    setState(() => _testing = true);
    try {
      final repo = ref.read(aiSettingsRepositoryProvider);
      final baseUrl = _normalizeBaseUrl(_baseUrlC.text);
      final apiKey = _apiKeyC.text.trim();
      final modelName = _modelC.text.trim();
      final msg = await repo.test(
        baseUrl: baseUrl,
        apiKey: apiKey.isNotEmpty ? apiKey : null,
        modelName: modelName,
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
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('AI 配置'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          TextButton(
            onPressed: (_saving || _testing) ? null : _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                AppCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '自定义 AI 接口',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '配置会保存到服务器，仅对当前账号生效。',
                        style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _baseUrlC,
                        decoration: const InputDecoration(
                          labelText: 'API Base URL',
                          hintText: '例如 https://api.openai.com/v1',
                        ),
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _apiKeyC,
                        obscureText: !_showKey,
                        decoration: InputDecoration(
                          labelText: 'API Key',
                          hintText: _hasKey ? '已保存（留空保持不变）' : '请输入 API Key',
                          suffixIcon: IconButton(
                            icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _showKey = !_showKey),
                          ),
                        ),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _save(),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _modelC,
                        decoration: const InputDecoration(
                          labelText: 'Model',
                          hintText: '留空使用默认模型（例如 gpt-5）',
                        ),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _save(),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            _hasKey ? Icons.verified_rounded : Icons.info_outline,
                            size: 16,
                            color: _hasKey ? AppColors.primary : AppColors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _hasKey ? '已保存 API Key' : '未保存 API Key',
                            style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12),
                          ),
                          const Spacer(),
                          if (_hasKey)
                            TextButton(
                              onPressed: _saving ? null : _clearApiKey,
                              child: const Text('清除'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: (_saving || _testing) ? null : _test,
                              child: Text(_testing ? '测试中...' : '测试连接'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: (_saving || _testing) ? null : _save,
                              child: Text(_saving ? '保存中...' : '保存配置'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
